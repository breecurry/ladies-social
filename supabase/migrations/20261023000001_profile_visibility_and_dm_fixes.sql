-- ============================================================
-- 20261023000001 — Profile visibility for enforced accounts + two DM fixes.
--
-- Forward-only and idempotent: safe against the live database and safe
-- to re-run. No RPC signature changes anywhere in this file — every
-- function below is redefined with CREATE OR REPLACE at its existing
-- signature, so grants persist and PostgREST stays unambiguous.
--
-- What this migration fixes:
--
--   1. PROFILES_READ — the published-promise violation (QA suite 20).
--      The Community Guidelines promise: "For the duration of your
--      suspension, your account and your content are removed from the
--      platform. Nobody can see your profile or your posts." Posts were
--      correctly hidden; the PROFILE ROW was not — the old policy
--      excluded only status = 'deleted', so any active member could
--      still read a suspended or banned member's handle, bio,
--      founding-member badge and join date, indefinitely. On this
--      platform that means a banned stalker's account stays
--      identifiable by URL after enforcement. Closed here: an ordinary
--      member now reads only 'active' / 'restricted' profiles (which
--      also stops showing self-deactivated departures to the
--      membership). The member herself still reads her OWN row in any
--      state, and staff (ts_reviewer and above) still read suspended /
--      banned rows — the moderation console's case page links to
--      /u/<handle> for the accused, the ban route verifies the typed
--      handle against a profiles read, and the Owner's roles surfaces
--      resolve handles for role holders who may themselves be
--      suspended or banned. All of those go through a USER-SCOPED
--      client and therefore through this policy. internal.blocked_by()
--      behaviour is preserved exactly as it was, for staff included.
--
--   2. DM_SEND_MESSAGE — blank-message guard (QA suite 19, finding 2).
--      The old guard was char_length(btrim(p_body)) < 1; single-
--      argument btrim() strips ONLY ASCII spaces, so a body of pure
--      newlines or tabs passed and was stored as a visually blank
--      message. The guard now requires at least one non-whitespace
--      character (regex \S, which covers space, tab, newline, CR, FF,
--      VT). Everything else in the function is byte-identical to
--      20261021000001.
--
--   3. FILE_DM_REPORT — duplicate evidence ids (QA suite 19, finding 3).
--      The old loop snapshotted every element of p_message_ids with no
--      de-duplication, and dm_report_evidence had no unique constraint
--      on (report_id, message_id): the same message could be copied
--      into evidence several times, inflating the evidence count and
--      the "messages" volume mod_dm_evidence writes to the audit log —
--      a figure we promise members is accurate. The loop now iterates
--      DISTINCT ids, and a unique index backstops the function.
--      Refusal semantics are unchanged and apply to the RAW input:
--      0 ids, more than 10 ids, or any id outside the conversation
--      still voids the WHOLE report and writes nothing.
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- 1. profiles_read: enforcement-aware visibility.
--    Branches, in order:
--      - never a 'deleted' row, for anyone (unchanged);
--      - the member always reads her OWN row, in any state — she needs
--        to understand her own standing while suspended (unchanged);
--      - any other reader must be an active member not blocked by the
--        profile owner (both unchanged), AND the profile must be in
--        good standing ('active'/'restricted') UNLESS the reader holds
--        a staff role (ts_reviewer and above). The staff branch sits
--        INSIDE the is_active_member()/blocked_by conjunction on
--        purpose: a suspended staff member gets no staff view, and
--        blocked_by applies to staff exactly as it did before this
--        migration.
-- ------------------------------------------------------------
drop policy if exists profiles_read on profiles;
create policy profiles_read on profiles for select
  using (
    status <> 'deleted'
    and (
      user_id = auth.uid()
      or (
        is_active_member()
        and not internal.blocked_by(profiles.user_id)
        and (status in ('active', 'restricted') or is_reviewer_or_above())
      )
    )
  );

comment on policy profiles_read on profiles is
  'Published promise (Community Guidelines): a suspended or banned member''s profile is removed from the platform. Ordinary members read only active/restricted profiles; the member reads her own row in any non-deleted state; staff (ts_reviewer+) read suspended/banned rows for moderation. blocked_by applies to every non-self reader, staff included.';

-- ------------------------------------------------------------
-- 2. dm_send_message: whitespace-aware blank guard. Identical to the
--    20261021000001 definition except the p_body guard (see header).
--    Same signature — CREATE OR REPLACE, grants persist.
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
  -- A body must contain at least one NON-WHITESPACE character. The old
  -- btrim(p_body) check stripped only ASCII spaces, so newlines-only
  -- and tabs-only bodies passed as visually blank messages.
  if p_body is null or p_body !~ '\S' or char_length(p_body) > 2000 then
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
-- 3a. De-duplicate any evidence rows that predate the constraint
--     (live today: zero rows — this is belt-and-braces so the unique
--     index below can never fail to build), keeping the earliest row.
-- ------------------------------------------------------------
delete from dm_report_evidence a
using dm_report_evidence b
where a.report_id = b.report_id
  and a.message_id = b.message_id
  and a.id > b.id;

create unique index if not exists uq_dm_evidence_report_message
  on dm_report_evidence (report_id, message_id);

-- ------------------------------------------------------------
-- 3b. file_dm_report: snapshot DISTINCT message ids. Identical to the
--     20261021000001 definition except the evidence loop iterates
--     `select distinct unnest(...)` instead of the raw array. The
--     refusal checks still look at the RAW input: an 11-id report is
--     refused even if it contains only 2 distinct real ids.
--     Same signature — CREATE OR REPLACE, grants persist.
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

  -- Snapshot each selected message server-side, ONCE per distinct id —
  -- the same message listed twice must not inflate the evidence count
  -- or the volume mod_dm_evidence later audits. Every id must be a
  -- real message of THIS conversation — anything else voids the whole
  -- report rather than quietly thinning the evidence.
  for v_mid in select distinct u.mid from unnest(p_message_ids) as u(mid) loop
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
