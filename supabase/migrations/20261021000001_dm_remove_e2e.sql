-- ============================================================
-- 0029 — Direct messages rework: REMOVE end-to-end encryption.
--
-- Owner decision (2026-10-09, final): DMs are NOT end-to-end
-- encrypted. The platform owner CAN read message content, members are
-- told so plainly and up front, and messages may be disclosed to
-- authorities in matters involving trafficking or sexual exploitation
-- (including of minors). This supersedes the E2E design that 0020
-- (20261011000001_direct_messages.sql) built.
--
-- What this migration does:
--   1. Renames the feature flag: app_config key 'dm_e2e_enabled' →
--      'dm_enabled'. The row is DELIBERATELY NOT inserted — the
--      feature ships dark and the Owner flips it.
--   2. Drops the whole cryptographic layer at the database: device
--      registration, prekey storage and the franking machinery.
--      user_devices and one_time_prekeys (created empty in 0007,
--      populated by 0020) are dropped — nothing outside DMs ever used
--      them, and the one-device-per-account limitation dies with them.
--   3. Reshapes dm_messages to hold a readable body (text, 1-2000
--      chars) instead of header/ciphertext/frank_hash.
--   4. Reshapes dm_report_evidence: evidence is now a SERVER-SIDE
--      snapshot of the reported messages taken inside file_dm_report()
--      — the reporter selects which messages, the server copies them.
--      No client-supplied plaintext, no franking keys, no "verified"
--      flag (a server copy cannot be fabricated). The table stays a
--      separate snapshot because evidence must survive the message
--      rows (accounts and conversations cascade-delete; moderation
--      records have retention obligations).
--   5. HARDENS ACCESS in place of E2E — this is the mitigation the
--      owner is relying on:
--        * RLS stays on every DM table with ZERO direct-read policies
--          on content tables; members reach their own conversations
--          only through the SECURITY DEFINER functions (pinned
--          search_path), which verify participation.
--        * Owner/moderator access to message content exists ONLY
--          through mod_dm_evidence(), and EVERY call writes an
--          audit_log row recording who read whose messages and when.
--          Access is accountable, never invisible.
--
-- Forward-only and idempotent: safe against the live database and
-- safe to re-run. The reshape of dm_messages / dm_report_evidence is
-- guarded by a column check, so a re-run AFTER launch never touches
-- member data (verified: both tables hold 0 rows today, 2026-10-05).
--
-- 🚨 IDENTITY RULE (0013 header, upheld): no function here ever
-- SELECTs display_name. Every DM surface identifies members by
-- @handle only.
--
-- 🚨 INBOX RULES (locked owner decisions) are unchanged and still
-- enforced below the app in dm_route() / dm_send_message():
--   * Main inbox receives only from people the recipient follows.
--   * Everyone else gets EXACTLY ONE silent message request.
--   * Block, DMs off, and "no one" raise the IDENTICAL refusal.
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- 1. The feature flag: 'dm_e2e_enabled' was a lie once E2E left the
--    design, so the key is now 'dm_enabled'. Remove any old row
--    (there are none on live today); never insert the new one here.
-- ------------------------------------------------------------
delete from app_config where key = 'dm_e2e_enabled';

create or replace function dm_feature_enabled() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(
    (select value from app_config where key = 'dm_enabled') = 'true'::jsonb,
    false)
$$;

-- Internal guard. Not granted to any app role. (Body unchanged; kept
-- here so the comment tells the truth about what "enabled" now means:
-- readable-by-the-platform DMs, disclosed as such in the UI.)
create or replace function assert_dm_enabled() returns void
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if not dm_feature_enabled() then
    raise exception 'Direct messages are not available.';
  end if;
end $$;

-- ------------------------------------------------------------
-- 2. Drop the cryptographic layer: every function that existed to
--    serve device keys, prekeys or franking, plus every function
--    whose shape changes below. Explicit signature-qualified drops —
--    a leftover second signature makes PostgREST ambiguous.
-- ------------------------------------------------------------
drop function if exists dm_register_device(text, bytea, bytea, bytea, bytea[]);
drop function if exists dm_add_prekeys(bytea[]);
drop function if exists dm_my_device();
drop function if exists dm_prekey_bundle(uuid);
drop function if exists dm_active_device(uuid);
drop function if exists dm_send_message(uuid, uuid, jsonb, bytea, bytea);
drop function if exists dm_fetch_messages(uuid, bigint, integer);
drop function if exists dm_list_conversations(boolean);
drop function if exists file_dm_report(uuid, report_reason, text, jsonb);
drop function if exists mod_dm_evidence(uuid);

-- ------------------------------------------------------------
-- 3. Reshape dm_messages: a readable body instead of
--    header/ciphertext/frank_hash. Guarded: the drop happens only
--    while the old (ciphertext) shape exists, so a re-run after
--    launch cannot destroy messages. Live today: 0 rows.
-- ------------------------------------------------------------
do $$ begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'dm_messages'
               and column_name = 'ciphertext') then
    drop table dm_messages;
  end if;
end $$;

create table if not exists dm_messages (
  id              bigint generated always as identity primary key,
  conversation_id uuid not null references dm_conversations (id) on delete cascade,
  sender_id       uuid not null references profiles (user_id),
  body            text not null check (char_length(body) between 1 and 2000),
  sent_at         timestamptz not null default now()
);
create index if not exists idx_dm_messages_conv on dm_messages (conversation_id, id);

alter table dm_messages enable row level security;
revoke all on dm_messages from anon, authenticated, service_role;

-- ------------------------------------------------------------
-- 4. Drop the key-material tables. Created empty by 0007 "for when
--    E2E ships", populated by 0020, and used by nothing else in the
--    schema (verified: the only references were the DM functions
--    dropped above and the old dm_messages device columns). With them
--    goes the one-device-per-account limitation — phone + laptop now
--    simply work, because there are no per-device keys to manage.
-- ------------------------------------------------------------
drop table if exists one_time_prekeys;
drop table if exists user_devices;

-- ------------------------------------------------------------
-- 5. Reshape dm_report_evidence: a server-side snapshot, no franking.
--    Same guard pattern as dm_messages. Live today: 0 rows.
--    message_id is deliberately NOT a foreign key: the snapshot must
--    survive the message (and the conversation, and the accounts)
--    being deleted — it is subject to preservation obligations.
-- ------------------------------------------------------------
do $$ begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'dm_report_evidence'
               and column_name = 'frank_key') then
    drop table dm_report_evidence;
  end if;
end $$;

create table if not exists dm_report_evidence (
  id           bigint generated always as identity primary key,
  report_id    uuid not null references reports (id) on delete cascade,
  message_id   bigint not null,
  sender_id    uuid not null references profiles (user_id),
  recipient_id uuid not null references profiles (user_id),
  body         text not null check (char_length(body) <= 2000),
  sent_at      timestamptz not null,
  created_at   timestamptz not null default now()
);
create index if not exists idx_dm_evidence_report on dm_report_evidence (report_id);

alter table dm_report_evidence enable row level security;
revoke all on dm_report_evidence from anon, authenticated, service_role;

-- ------------------------------------------------------------
-- 6. Sending. All the inbox and permission rules live HERE, below
--    the app, exactly as before — minus devices and franking.
-- ------------------------------------------------------------
create or replace function dm_send_message(
  p_recipient uuid,
  p_body text
) returns table (message_id bigint, conversation_id uuid,
                 conversation_state dm_conversation_state, sent_at timestamptz)
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me   uuid := auth.uid();
  v_conv dm_conversations%rowtype;
  v_route text;
  v_id   bigint;
  v_now  timestamptz := now();
begin
  perform assert_dm_enabled();
  if v_me is null then raise exception 'Not signed in.'; end if;
  if not exists (select 1 from profiles where user_id = v_me and status in ('active', 'restricted')) then
    raise exception 'Your account cannot send messages right now.';
  end if;
  if p_body is null or char_length(btrim(p_body)) < 1 or char_length(p_body) > 2000 then
    raise exception 'Messages are limited to 2000 characters.';
  end if;

  v_route := dm_route(v_me, p_recipient);
  if v_route = 'none' then
    -- One refusal for block, DMs off, and "no one": indistinguishable.
    raise exception 'You can no longer message this account.';
  end if;

  select * into v_conv from dm_conversations c
   where c.member_low = least(v_me, p_recipient)
     and c.member_high = greatest(v_me, p_recipient)
   for update;

  if not found then
    insert into dm_conversations (member_low, member_high, initiator_id, state,
                                  accepted_at, last_message_at)
    values (least(v_me, p_recipient), greatest(v_me, p_recipient), v_me,
            case when v_route = 'inbox' then 'accepted'::dm_conversation_state
                 else 'request'::dm_conversation_state end,
            case when v_route = 'inbox' then v_now end,
            v_now)
    returning * into v_conv;
    insert into dm_participant_state (conversation_id, user_id)
    values (v_conv.id, v_me), (v_conv.id, p_recipient)
    on conflict do nothing;
  else
    if v_conv.state = 'request' then
      if v_conv.initiator_id = v_me then
        -- EXACTLY ONE message until accepted. The conversation row is
        -- created with its first message, so any further send while
        -- still a request is the second message.
        raise exception 'You can send one message until they accept.';
      else
        raise exception 'Accept the request before replying.';
      end if;
    end if;
    update dm_conversations set last_message_at = v_now where id = v_conv.id;
  end if;

  insert into dm_messages (conversation_id, sender_id, body, sent_at)
  values (v_conv.id, v_me, p_body, v_now)
  returning id into v_id;

  -- A new message brings a conversation back for someone who deleted
  -- it (only the new messages: cleared_before stays).
  update dm_participant_state ps set hidden = false
   where ps.conversation_id = v_conv.id and ps.hidden;

  -- Notification: ACCEPTED conversations only — a message request is
  -- silent by design, always. No content, no body: the row says only
  -- that @handle sent a message. Honors the member's per-type pref,
  -- her per-conversation mute, and her account-level mute of the
  -- sender. One unread notification per sender at a time.
  if v_conv.state = 'accepted'
     and not exists (select 1 from dm_participant_state ps
                     where ps.conversation_id = v_conv.id
                       and ps.user_id = p_recipient and ps.muted)
     and not exists (select 1 from mutes m
                     where m.muter_id = p_recipient and m.muted_id = v_me)
     and notif_enabled(p_recipient, 'message')
     and not exists (select 1 from notifications n
                     where n.user_id = p_recipient and n.actor_id = v_me
                       and n.type = 'message' and n.read_at is null) then
    insert into notifications (user_id, actor_id, type)
    values (p_recipient, v_me, 'message');
  end if;

  return query select v_id, v_conv.id, v_conv.state, v_now;
end $$;

-- ------------------------------------------------------------
-- 7. Reads. @handle only, always. A member reads only conversations
--    she participates in — the functions verify participation, and
--    the tables grant no direct read to anyone.
-- ------------------------------------------------------------

-- The inbox. Now that the server can read messages, each row carries
-- an honest preview of the last visible message (the member's own
-- "delete for me" horizon applies to the preview too).
create or replace function dm_list_conversations(p_requests boolean default false)
returns table (
  conversation_id uuid,
  correspondent_id uuid,
  correspondent_handle text,
  state dm_conversation_state,
  is_initiator boolean,
  muted boolean,
  cleared_before timestamptz,
  last_message_at timestamptz,
  unread_count bigint,
  my_last_read_at timestamptz,
  peer_read_at timestamptz,
  last_body text,
  last_sender_id uuid
)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_me uuid := auth.uid();
begin
  perform assert_dm_enabled();
  if v_me is null then raise exception 'Not signed in.'; end if;
  return query
  select c.id,
         o.user_id,
         pr.handle::text,
         c.state,
         c.initiator_id = v_me,
         ps.muted,
         ps.cleared_before,
         c.last_message_at,
         (select count(*) from dm_messages m
          where m.conversation_id = c.id
            and m.sender_id <> v_me
            and m.sent_at > coalesce(ps.last_read_at, '-infinity'::timestamptz)
            and m.sent_at > coalesce(ps.cleared_before, '-infinity'::timestamptz)),
         ps.last_read_at,
         case when c.state = 'accepted'
                   and coalesce(os.read_receipts, false)
              then ops.last_read_at end,
         (select left(m.body, 160) from dm_messages m
          where m.conversation_id = c.id
            and m.sent_at > coalesce(ps.cleared_before, '-infinity'::timestamptz)
          order by m.id desc limit 1),
         (select m.sender_id from dm_messages m
          where m.conversation_id = c.id
            and m.sent_at > coalesce(ps.cleared_before, '-infinity'::timestamptz)
          order by m.id desc limit 1)
  from dm_conversations c
  join dm_participant_state ps on ps.conversation_id = c.id and ps.user_id = v_me
  join lateral (select case when c.member_low = v_me then c.member_high else c.member_low end as user_id) o on true
  join profiles pr on pr.user_id = o.user_id
  left join dm_participant_state ops on ops.conversation_id = c.id and ops.user_id = o.user_id
  left join dm_settings os on os.user_id = o.user_id
  where v_me in (c.member_low, c.member_high)
    and not ps.hidden
    and case when p_requests
             then c.state = 'request' and c.initiator_id <> v_me
             else c.state = 'accepted' or c.initiator_id = v_me
        end
  order by c.last_message_at desc
  limit 100;
end $$;

-- Messages of one conversation, readable body, ascending by id. The
-- caller's own "delete for me" horizon applies.
create or replace function dm_fetch_messages(
  p_conversation uuid,
  p_after_id bigint default null,
  p_limit integer default 100
) returns table (
  id bigint,
  sender_id uuid,
  sender_handle text,
  body text,
  sent_at timestamptz
)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me uuid := auth.uid();
  v_cleared timestamptz;
begin
  perform assert_dm_enabled();
  if v_me is null then raise exception 'Not signed in.'; end if;
  select ps.cleared_before into v_cleared
  from dm_participant_state ps
  join dm_conversations c on c.id = ps.conversation_id
  where ps.conversation_id = p_conversation and ps.user_id = v_me
    and v_me in (c.member_low, c.member_high);
  if not found then
    raise exception 'That conversation is unavailable.';
  end if;
  return query
  select m.id, m.sender_id, pr.handle::text, m.body, m.sent_at
  from dm_messages m
  join profiles pr on pr.user_id = m.sender_id
  where m.conversation_id = p_conversation
    and (v_cleared is null or m.sent_at > v_cleared)
    and (p_after_id is null or m.id > p_after_id)
  order by m.id
  limit least(greatest(coalesce(p_limit, 100), 1), 200);
end $$;

-- ------------------------------------------------------------
-- 8. Reporting a DM. The reporter selects which messages (1-10); the
--    SERVER copies them into the evidence snapshot — nothing the
--    reporter types can end up presented as the other member's words.
--    Same duplicate guard, hourly cap, staff routing, safety@ email
--    copy, and audit shape as file_report().
-- ------------------------------------------------------------
create or replace function file_dm_report(
  p_conversation uuid,
  p_reason report_reason,
  p_details text default null,
  p_message_ids bigint[] default null
) returns uuid
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me       uuid := auth.uid();
  v_conv     dm_conversations%rowtype;
  v_accused  uuid;
  v_handle   text;
  v_routing  report_routing := 'standard';
  v_status   report_status := 'open';
  v_id       uuid;
  v_msg      dm_messages%rowtype;
  v_mid      bigint;
  v_recipient uuid;
begin
  perform assert_dm_enabled();
  if v_me is null then raise exception 'Not signed in.'; end if;
  if not exists (select 1 from profiles where user_id = v_me and status in ('active', 'restricted')) then
    raise exception 'Your account cannot file reports right now.';
  end if;
  if p_details is not null and char_length(p_details) > 2000 then
    raise exception 'Details are limited to 2000 characters.';
  end if;
  select * into v_conv from dm_conversations
   where id = p_conversation and v_me in (member_low, member_high);
  if not found then
    raise exception 'That conversation is unavailable.';
  end if;
  v_accused := case when v_conv.member_low = v_me then v_conv.member_high else v_conv.member_low end;

  if p_message_ids is null
     or array_length(p_message_ids, 1) is null
     or array_length(p_message_ids, 1) > 10 then
    raise exception 'Select between 1 and 10 messages to report.';
  end if;

  -- Same guards as file_report (0018): duplicate + hourly cap.
  if exists (select 1 from reports r
             where r.reporter_id = v_me
               and r.subject_user_id = v_accused
               and r.reason = p_reason
               and r.created_at > now() - interval '24 hours') then
    raise exception 'You have already reported this recently, and that report is with our team. There is no need to send it again.';
  end if;
  if (select count(*) from reports r
      where r.reporter_id = v_me
        and r.created_at > now() - interval '1 hour') >= 10 then
    raise exception 'You have filed several reports in the last hour, and they are all safely with our team. Please wait a little while before filing another.';
  end if;

  if exists (select 1 from role_assignments
             where user_id = v_accused
               and role in ('owner', 'admin', 'moderator', 'ts_reviewer')
               and revoked_at is null) then
    v_routing := 'admin_only';
  end if;
  if p_reason = 'csam' then
    v_status := 'escalated';
  end if;

  insert into reports (reporter_id, subject_type, subject_post_id, subject_user_id,
                       reason, details, routing, status)
  values (v_me, 'message', null, v_accused, p_reason,
          nullif(btrim(coalesce(p_details, '')), ''), v_routing, v_status)
  returning id into v_id;

  -- Snapshot each selected message server-side. Every id must be a
  -- real message of THIS conversation — anything else voids the whole
  -- report rather than quietly thinning the evidence.
  foreach v_mid in array p_message_ids loop
    select m.* into v_msg from dm_messages m
     where m.id = v_mid and m.conversation_id = p_conversation;
    if not found then
      raise exception 'Invalid report evidence.';
    end if;
    v_recipient := case when v_msg.sender_id = v_conv.member_low
                        then v_conv.member_high else v_conv.member_low end;
    insert into dm_report_evidence
      (report_id, message_id, sender_id, recipient_id, body, sent_at)
    values
      (v_id, v_msg.id, v_msg.sender_id, v_recipient, v_msg.body, v_msg.sent_at);
  end loop;

  -- The second traceable copy (owner decision, 0018): case reference
  -- and category only — no reporter, no message text, no names.
  select pr.handle::text into v_handle from profiles pr where pr.user_id = v_accused;
  insert into safety_email_outbox (report_id, recipient, subject, body)
  values (
    v_id,
    'safety@unitedfeminist.com',
    'Hersciety report ' || left(v_id::text, 8) || ' — ' || p_reason::text,
    'A report was filed on Hersciety.' || E'\n\n'
      || 'Case reference: ' || v_id::text || E'\n'
      || 'Filed at: ' || to_char(now() at time zone 'utc', 'YYYY-MM-DD HH24:MI:SS') || ' UTC' || E'\n'
      || 'Reason: ' || p_reason::text || E'\n'
      || 'Subject: direct messages from @' || coalesce(v_handle, 'unknown') || E'\n\n'
      || 'Full details are in the moderation console. This copy exists so every report '
      || 'is traceable in two places. It intentionally names no reporter and carries no '
      || 'report text.'
  );

  perform append_audit('report.filed', 'report', v_id::text,
                       jsonb_build_object('reason', p_reason));
  return v_id;
end $$;

-- ------------------------------------------------------------
-- 9. The console's view of DM evidence — THE ONLY PATH by which the
--    owner or a moderator reads message content through the app, and
--    it is never silent: every call writes an audit_log row naming
--    the reader, the accused whose messages were read, and the
--    volume. Access is accountable, not invisible. (Volatile, not
--    stable: it writes the audit row.)
-- ------------------------------------------------------------
create or replace function mod_dm_evidence(p_target uuid)
returns table (
  report_id uuid,
  reason report_reason,
  report_status report_status,
  reported_at timestamptz,
  message_id bigint,
  sender_handle text,
  body text,
  sent_at timestamptz
)
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_reports integer;
  v_messages integer;
begin
  if mod_actor_tier() < 0 then
    raise exception 'You do not have permission to view this case.';
  end if;
  select count(distinct r.id), count(*) into v_reports, v_messages
  from reports r
  join dm_report_evidence e on e.report_id = r.id
  where r.subject_user_id = p_target
    and r.subject_type = 'message'
    and mod_report_visible(r.routing, r.subject_user_id);
  if v_messages > 0 then
    perform append_audit('dm.content_read', 'user', p_target::text,
                         jsonb_build_object('surface', 'mod_dm_evidence',
                                            'reports', v_reports,
                                            'messages', v_messages));
  end if;
  return query
  select r.id, r.reason, r.status, r.created_at,
         e.message_id, pr.handle::text, e.body, e.sent_at
  from reports r
  join dm_report_evidence e on e.report_id = r.id
  join profiles pr on pr.user_id = e.sender_id
  where r.subject_user_id = p_target
    and r.subject_type = 'message'
    and mod_report_visible(r.routing, r.subject_user_id)
  order by r.created_at desc, e.sent_at, e.id
  limit 200;
end $$;

-- ------------------------------------------------------------
-- 10. EXECUTE lockdown for every function created above. (Dropped
--     functions took their grants with them; untouched functions —
--     dm_route, dm_can_message, dm_accept_request, dm_decline_request,
--     dm_delete_conversation, dm_set_muted, dm_mark_read,
--     dm_unread_total — keep the 0020 grants.)
-- ------------------------------------------------------------
revoke execute on function assert_dm_enabled()                               from public, anon, authenticated, service_role;
revoke execute on function dm_feature_enabled()                              from public, anon, service_role;
revoke execute on function dm_send_message(uuid, text)                       from public, anon, service_role;
revoke execute on function dm_list_conversations(boolean)                    from public, anon, service_role;
revoke execute on function dm_fetch_messages(uuid, bigint, integer)          from public, anon, service_role;
revoke execute on function file_dm_report(uuid, report_reason, text, bigint[]) from public, anon, service_role;
revoke execute on function mod_dm_evidence(uuid)                             from public, anon, service_role;

grant execute on function dm_feature_enabled()                               to authenticated;
grant execute on function dm_send_message(uuid, text)                        to authenticated;
grant execute on function dm_list_conversations(boolean)                     to authenticated;
grant execute on function dm_fetch_messages(uuid, bigint, integer)           to authenticated;
grant execute on function file_dm_report(uuid, report_reason, text, bigint[]) to authenticated;
grant execute on function mod_dm_evidence(uuid)                              to authenticated;
