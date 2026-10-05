-- ============================================================
-- 0020 — Direct messages (Phase 2C): end-to-end encrypted, text-only,
-- 1:1 only. The server stores CIPHERTEXT ONLY and can never read a
-- message body. Design: docs/design-phase2c-direct-messages.md.
--
-- Forward-only and idempotent: safe against the live database
-- (0001-0019 applied, real accounts present) and safe to re-run.
--
-- 🚨 FEATURE FLAG (dm_e2e_enabled): every member-facing function in
-- this migration refuses unless app_config holds the row
--   key = 'dm_e2e_enabled', value = 'true'::jsonb
-- which is DELIBERATELY NOT inserted here. The member-facing DM
-- feature stays unreachable — in the UI (env DM_E2E_ENABLED) AND at
-- the database (this flag) — until the external crypto audit passes
-- and the Owner flips it. There is NO readable-by-anyone fallback:
-- off means the surfaces do not exist, not that messages travel
-- unencrypted.
--
-- 🚨 E2E INVARIANTS, enforced structurally here:
--   * dm_messages carries ciphertext (bytea), a ratchet header of
--     public values, and a franking commitment hash. There is no
--     plaintext column and no function that could return one.
--   * The ONLY plaintext the database ever holds is report evidence
--     in dm_report_evidence, written exclusively inside
--     file_dm_report() from content the REPORTER's own device chose
--     to attach, with the franking commitment verified server-side
--     (pgcrypto HMAC) so the reporter cannot fabricate and the sender
--     cannot deny.
--   * The franking construction is the HMAC-key scheme (Grubbs, Lu &
--     Ristenpart, CRYPTO 2017), never raw AES-GCM — raw AES-GCM
--     franking is broken ("invisible salamanders", Dodis et al. 2018):
--       frank = HMAC-SHA256(K_frank, 'hersciety-dm-frank-v1' \n
--               sender_uuid \n recipient_uuid \n plaintext)
--       ciphertext = AEAD(message_key, K_frank || plaintext)
--       server stores sha256(frank) per message.
--
-- 🚨 IDENTITY RULE (0013 header, upheld): no function here ever
-- SELECTs display_name. Every DM surface — inbox, thread, requests,
-- notifications, report evidence — identifies every member by @handle
-- only.
--
-- 🚨 INBOX RULES (locked owner decisions), enforced here, below the
-- app, so no UI bug and no hand-crafted RPC call can cross them:
--   * Main inbox receives only from people the recipient follows.
--   * Everyone else gets EXACTLY ONE message request (silent, never
--     notified, no second message until accepted). Declining a
--     request keeps the conversation row so the one-request cap
--     survives; a sender can never earn a second request by any path.
--   * Settings: who may send a request (everyone / followed / no
--     one) + a global DM off switch — checked in dm_send_message AND
--     in dm_prekey_bundle so prekeys cannot be farmed as an oracle.
--   * A blocked person can send nothing, and every refusal (block,
--     DMs off, "no one") raises the IDENTICAL message, so a block is
--     indistinguishable from the other refusals to the blocked party.
--
-- The empty user_devices and one_time_prekeys tables from 0007 are
-- finally populated here (device registration + prekey bundles), as
-- that migration promised. This migration also locks them down with
-- RLS, which 0007 did not need while they were empty.
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- 1. Enum additions and new enums (guarded for idempotency).
--    The new values are referenced only inside plpgsql bodies below,
--    never in DML in this file, so adding them in the same
--    transaction is safe.
-- ------------------------------------------------------------
alter type report_subject add value if not exists 'message';
alter type notif_type     add value if not exists 'message';

do $$ begin
  if not exists (select 1 from pg_type where typname = 'dm_conversation_state') then
    create type dm_conversation_state as enum ('request', 'accepted');
  end if;
  if not exists (select 1 from pg_type where typname = 'dm_request_policy') then
    create type dm_request_policy as enum ('everyone', 'followed', 'no_one');
  end if;
end $$;

-- ------------------------------------------------------------
-- 2. The feature flag, read server-side.
-- ------------------------------------------------------------
create or replace function dm_feature_enabled() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(
    (select value from app_config where key = 'dm_e2e_enabled') = 'true'::jsonb,
    false)
$$;

-- Internal guard. Not granted to any app role.
create or replace function assert_dm_enabled() returns void
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if not dm_feature_enabled() then
    raise exception 'Direct messages are not available.';
  end if;
end $$;

-- ------------------------------------------------------------
-- 3. Lock down the 0007 key tables now that they carry real keys.
--    A member may read her OWN device rows (the client checks which
--    device is active); nobody reads anyone else's directly — peers
--    get public keys only through dm_prekey_bundle(), which enforces
--    the same permission checks as sending. One-time prekeys are
--    reachable by no app role at all.
-- ------------------------------------------------------------
alter table user_devices     enable row level security;
alter table one_time_prekeys enable row level security;

drop policy if exists user_devices_own_read on user_devices;
create policy user_devices_own_read on user_devices for select
  using (user_id = auth.uid());

revoke all on user_devices     from anon, authenticated, service_role;
revoke all on one_time_prekeys from anon, authenticated, service_role;
grant select on user_devices to authenticated;

-- ------------------------------------------------------------
-- 4. Tables.
-- ------------------------------------------------------------

-- One row per member pair. member_low < member_high (uuid order)
-- makes the pair unique regardless of who started it. The row is
-- permanent once created: 'request' rows in particular are never
-- deleted, because the row itself IS the one-request-per-person cap.
create table if not exists dm_conversations (
  id              uuid primary key default gen_random_uuid(),
  member_low      uuid not null references profiles (user_id) on delete cascade,
  member_high     uuid not null references profiles (user_id) on delete cascade,
  initiator_id    uuid not null references profiles (user_id),
  state           dm_conversation_state not null default 'request',
  accepted_at     timestamptz,
  created_at      timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  check (member_low < member_high),
  check (initiator_id = member_low or initiator_id = member_high),
  unique (member_low, member_high)
);
create index if not exists idx_dm_conversations_low  on dm_conversations (member_low,  last_message_at desc);
create index if not exists idx_dm_conversations_high on dm_conversations (member_high, last_message_at desc);

-- Per-participant view state. hidden + cleared_before implement
-- "delete for me" honestly: the other side keeps her copy, and the
-- server keeps (unreadable) ciphertext until account deletion.
create table if not exists dm_participant_state (
  conversation_id uuid not null references dm_conversations (id) on delete cascade,
  user_id         uuid not null references profiles (user_id) on delete cascade,
  muted           boolean not null default false,
  hidden          boolean not null default false,
  cleared_before  timestamptz,
  last_read_at    timestamptz,
  primary key (conversation_id, user_id)
);

-- Messages: ciphertext only. header holds the Double Ratchet public
-- header (and, on session-opening messages, the X3DH init values) —
-- public keys and counters, never secrets. frank_hash is
-- sha256(frank), the franking commitment.
create table if not exists dm_messages (
  id                  bigint generated always as identity primary key,
  conversation_id     uuid not null references dm_conversations (id) on delete cascade,
  sender_id           uuid not null references profiles (user_id),
  sender_device_id    uuid not null references user_devices (id),
  recipient_device_id uuid not null references user_devices (id),
  header              jsonb not null,
  ciphertext          bytea not null check (octet_length(ciphertext) between 1 and 16384),
  frank_hash          bytea not null check (octet_length(frank_hash) = 32),
  sent_at             timestamptz not null default now(),
  check (pg_column_size(header) <= 4096)
);
create index if not exists idx_dm_messages_conv on dm_messages (conversation_id, id);

-- Messages settings (design §7). Absent row = the safe defaults.
-- "Who can message you" is structurally People-you-follow and is not
-- a column: it cannot be loosened.
create table if not exists dm_settings (
  user_id       uuid primary key references profiles (user_id) on delete cascade,
  requests_from dm_request_policy not null default 'everyone',
  dms_enabled   boolean not null default true,
  read_receipts boolean not null default false,
  updated_at    timestamptz not null default now()
);

-- Report evidence: the ONLY plaintext in the database, attached by
-- the reporter's own device inside file_dm_report(), franking-checked
-- at write time. message_id is deliberately NOT a foreign key: the
-- evidence must survive the message (and the conversation) being
-- deleted — it is subject to preservation obligations.
create table if not exists dm_report_evidence (
  id          bigint generated always as identity primary key,
  report_id   uuid not null references reports (id) on delete cascade,
  message_id  bigint not null,
  sender_id   uuid not null references profiles (user_id),
  recipient_id uuid not null references profiles (user_id),
  plaintext   text not null check (char_length(plaintext) <= 4000),
  frank_key   bytea not null check (octet_length(frank_key) = 32),
  frank       bytea not null check (octet_length(frank) = 32),
  verified    boolean not null,
  sent_at     timestamptz not null,
  created_at  timestamptz not null default now()
);
create index if not exists idx_dm_evidence_report on dm_report_evidence (report_id);

-- ------------------------------------------------------------
-- 5. RLS + privilege lockdown. Zero-policy tables are reachable only
--    through the SECURITY DEFINER functions below (the moderation
--    tables' pattern). dm_settings is own-row, like
--    notification_prefs.
-- ------------------------------------------------------------
alter table dm_conversations     enable row level security;
alter table dm_participant_state enable row level security;
alter table dm_messages          enable row level security;
alter table dm_settings          enable row level security;
alter table dm_report_evidence   enable row level security;

revoke all on dm_conversations     from anon, authenticated, service_role;
revoke all on dm_participant_state from anon, authenticated, service_role;
revoke all on dm_messages          from anon, authenticated, service_role;
revoke all on dm_report_evidence   from anon, authenticated, service_role;

revoke all on dm_settings from anon, service_role;
revoke all on dm_settings from authenticated;
grant select, insert, update on dm_settings to authenticated;
drop policy if exists dm_settings_own_read on dm_settings;
create policy dm_settings_own_read on dm_settings for select
  using (user_id = auth.uid());
drop policy if exists dm_settings_own_insert on dm_settings;
create policy dm_settings_own_insert on dm_settings for insert
  with check (user_id = auth.uid() and is_active_member());
drop policy if exists dm_settings_own_update on dm_settings;
create policy dm_settings_own_update on dm_settings for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ------------------------------------------------------------
-- 6. Internal helpers.
-- ------------------------------------------------------------

-- The caller's active (unrevoked) device, or NULL.
create or replace function dm_active_device(p_user uuid) returns uuid
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select d.id from user_devices d
  where d.user_id = p_user and d.revoked_at is null
  order by d.created_at desc
  limit 1
$$;

-- Can p_sender place a message with p_recipient, and where does it
-- land? Returns 'inbox' | 'request' | 'none'. Every 'none' is
-- deliberately indistinguishable to the sender: block, DMs off, and
-- "no one" all look the same.
create or replace function dm_route(p_sender uuid, p_recipient uuid) returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_conv   dm_conversations%rowtype;
  v_policy dm_request_policy;
  v_enabled boolean;
begin
  if p_sender is null or p_recipient is null or p_sender = p_recipient then
    return 'none';
  end if;
  if not exists (select 1 from profiles
                 where user_id = p_recipient
                   and status in ('active', 'restricted')
                   and not is_system) then
    return 'none';
  end if;
  if blocked_either(p_sender, p_recipient) then
    return 'none';
  end if;
  select coalesce(s.dms_enabled, true), coalesce(s.requests_from, 'everyone')
    into v_enabled, v_policy
  from (select 1) one
  left join dm_settings s on s.user_id = p_recipient;
  if not v_enabled then
    return 'none';
  end if;

  select * into v_conv from dm_conversations
   where member_low = least(p_sender, p_recipient)
     and member_high = greatest(p_sender, p_recipient);
  if found and v_conv.state = 'accepted' then
    return 'inbox';
  end if;

  -- The recipient following the sender is the affirmative act that
  -- opens the main inbox (design §6).
  if exists (select 1 from follows
             where follower_id = p_recipient and followee_id = p_sender) then
    return 'inbox';
  end if;

  if v_policy = 'no_one' then
    return 'none';
  end if;
  if v_policy = 'followed' then
    -- Recipient does not follow the sender (checked above), so no.
    return 'none';
  end if;
  return 'request';
end $$;

-- ------------------------------------------------------------
-- 7. Device registration and prekeys (the 0007 tables, finally used).
--    One active device per account in this release: registering a new
--    device revokes the old one. A new device cannot read old
--    messages — that is the honest E2E trade, told to the member in
--    the UI, never papered over with a server-readable backup.
-- ------------------------------------------------------------
create or replace function dm_register_device(
  p_device_name text,
  p_identity_key bytea,
  p_signed_prekey bytea,
  p_signed_prekey_sig bytea,
  p_prekeys bytea[]
) returns uuid
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me uuid := auth.uid();
  v_id uuid;
  v_pk bytea;
  v_count integer := 0;
begin
  perform assert_dm_enabled();
  if v_me is null then raise exception 'Not signed in.'; end if;
  if not exists (select 1 from profiles where user_id = v_me and status in ('active', 'restricted')) then
    raise exception 'Your account cannot use messages right now.';
  end if;
  if p_identity_key is null or octet_length(p_identity_key) <> 64 then
    raise exception 'Invalid identity key.';
  end if;
  if p_signed_prekey is null or octet_length(p_signed_prekey) <> 32
     or p_signed_prekey_sig is null or octet_length(p_signed_prekey_sig) <> 64 then
    raise exception 'Invalid signed prekey.';
  end if;
  if p_prekeys is null or array_length(p_prekeys, 1) is null
     or array_length(p_prekeys, 1) > 200 then
    raise exception 'Between 1 and 200 one-time prekeys are required.';
  end if;

  update user_devices set revoked_at = now()
   where user_id = v_me and revoked_at is null;

  insert into user_devices (user_id, device_name, identity_key_pub,
                            signed_prekey_pub, signed_prekey_sig)
  values (v_me, left(coalesce(p_device_name, 'Browser'), 80),
          p_identity_key, p_signed_prekey, p_signed_prekey_sig)
  returning id into v_id;

  foreach v_pk in array p_prekeys loop
    if v_pk is null or octet_length(v_pk) <> 32 then
      raise exception 'Invalid one-time prekey.';
    end if;
    insert into one_time_prekeys (device_id, prekey_pub) values (v_id, v_pk);
    v_count := v_count + 1;
  end loop;

  -- Key material is public keys, but the audit records only the fact.
  perform append_audit('dm.device_registered', 'user', v_me::text,
                       jsonb_build_object('prekeys', v_count));
  return v_id;
end $$;

-- Replenish one-time prekeys on the caller's active device.
create or replace function dm_add_prekeys(p_prekeys bytea[]) returns integer
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me uuid := auth.uid();
  v_device uuid;
  v_pk bytea;
  v_have integer;
  v_added integer := 0;
begin
  perform assert_dm_enabled();
  if v_me is null then raise exception 'Not signed in.'; end if;
  v_device := dm_active_device(v_me);
  if v_device is null then
    raise exception 'No active device. Register a device first.';
  end if;
  if p_prekeys is null or array_length(p_prekeys, 1) is null
     or array_length(p_prekeys, 1) > 200 then
    raise exception 'Between 1 and 200 one-time prekeys are required.';
  end if;
  select count(*) into v_have from one_time_prekeys
   where device_id = v_device and consumed_at is null;
  foreach v_pk in array p_prekeys loop
    exit when v_have + v_added >= 200;
    if v_pk is null or octet_length(v_pk) <> 32 then
      raise exception 'Invalid one-time prekey.';
    end if;
    insert into one_time_prekeys (device_id, prekey_pub) values (v_device, v_pk);
    v_added := v_added + 1;
  end loop;
  return v_added;
end $$;

-- The caller's own active device, so the client can tell whether its
-- locally held keys are still current.
create or replace function dm_my_device()
returns table (device_id uuid, identity_key bytea, created_at timestamptz, prekeys_remaining bigint)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select d.id, d.identity_key_pub, d.created_at,
         (select count(*) from one_time_prekeys k
          where k.device_id = d.id and k.consumed_at is null)
  from user_devices d
  where d.user_id = auth.uid() and d.revoked_at is null
  order by d.created_at desc
  limit 1
$$;

-- Where would a message from the caller to p_user land? For the
-- recipient picker's honesty ("this will arrive as a request").
create or replace function dm_can_message(p_user uuid) returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  perform assert_dm_enabled();
  if auth.uid() is null then raise exception 'Not signed in.'; end if;
  if not exists (select 1 from profiles where user_id = auth.uid() and status in ('active', 'restricted')) then
    return 'none';
  end if;
  return dm_route(auth.uid(), p_user);
end $$;

-- A prekey bundle for starting a session with p_user. Enforces the
-- SAME permission rules as sending, so it cannot be used as an
-- oracle, and atomically consumes one one-time prekey.
create or replace function dm_prekey_bundle(p_user uuid)
returns table (
  device_id uuid,
  identity_key bytea,
  signed_prekey bytea,
  signed_prekey_sig bytea,
  prekey_id bigint,
  prekey bytea
)
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me uuid := auth.uid();
  v_device user_devices%rowtype;
  v_prekey_id bigint;
  v_prekey bytea;
begin
  perform assert_dm_enabled();
  if v_me is null then raise exception 'Not signed in.'; end if;
  if dm_route(v_me, p_user) = 'none' then
    raise exception 'You can no longer message this account.';
  end if;
  select d.* into v_device from user_devices d
   where d.user_id = p_user and d.revoked_at is null
   order by d.created_at desc limit 1;
  if not found then
    raise exception 'This member cannot receive messages yet.';
  end if;
  update one_time_prekeys k
     set consumed_at = now()
   where k.id = (select k2.id from one_time_prekeys k2
                 where k2.device_id = v_device.id and k2.consumed_at is null
                 order by k2.id
                 for update skip locked
                 limit 1)
   returning k.id, k.prekey_pub into v_prekey_id, v_prekey;
  return query select v_device.id, v_device.identity_key_pub,
                      v_device.signed_prekey_pub, v_device.signed_prekey_sig,
                      v_prekey_id, v_prekey;
end $$;

-- ------------------------------------------------------------
-- 8. Sending. All the inbox and permission rules live HERE, below
--    the app. The client never decides routing.
-- ------------------------------------------------------------
create or replace function dm_send_message(
  p_recipient uuid,
  p_recipient_device uuid,
  p_header jsonb,
  p_ciphertext bytea,
  p_frank_hash bytea
) returns table (message_id bigint, conversation_id uuid,
                 conversation_state dm_conversation_state, sent_at timestamptz)
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me        uuid := auth.uid();
  v_my_device uuid;
  v_conv      dm_conversations%rowtype;
  v_route     text;
  v_id        bigint;
  v_now       timestamptz := now();
begin
  perform assert_dm_enabled();
  if v_me is null then raise exception 'Not signed in.'; end if;
  if not exists (select 1 from profiles where user_id = v_me and status in ('active', 'restricted')) then
    raise exception 'Your account cannot send messages right now.';
  end if;
  v_my_device := dm_active_device(v_me);
  if v_my_device is null then
    raise exception 'No active device. Register a device first.';
  end if;
  if p_ciphertext is null or octet_length(p_ciphertext) < 1 or octet_length(p_ciphertext) > 16384 then
    raise exception 'Message cannot be sent.';
  end if;
  if p_frank_hash is null or octet_length(p_frank_hash) <> 32 then
    raise exception 'Message cannot be sent.';
  end if;
  if p_header is null or pg_column_size(p_header) > 4096 then
    raise exception 'Message cannot be sent.';
  end if;

  v_route := dm_route(v_me, p_recipient);
  if v_route = 'none' then
    -- One refusal for block, DMs off, and "no one": indistinguishable.
    raise exception 'You can no longer message this account.';
  end if;

  -- The recipient device must still be the recipient's active device;
  -- a stale one means her security code changed and the client must
  -- fetch a fresh bundle. Distinct, retryable error.
  if p_recipient_device is null
     or p_recipient_device <> dm_active_device(p_recipient) then
    raise exception 'RECIPIENT_DEVICE_CHANGED';
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
        -- EXACTLY ONE message until accepted (design §6). The
        -- conversation row is created with its first message, so any
        -- further send while still a request is the second message.
        raise exception 'You can send one message until they accept.';
      else
        raise exception 'Accept the request before replying.';
      end if;
    end if;
    -- An accepted conversation a follower-path sender can always use.
    update dm_conversations set last_message_at = v_now where id = v_conv.id;
  end if;

  insert into dm_messages (conversation_id, sender_id, sender_device_id,
                           recipient_device_id, header, ciphertext, frank_hash, sent_at)
  values (v_conv.id, v_me, v_my_device, p_recipient_device,
          p_header, p_ciphertext, p_frank_hash, v_now)
  returning id into v_id;

  -- A new message brings a conversation back for someone who deleted
  -- it (only the new messages: cleared_before stays).
  update dm_participant_state ps set hidden = false
   where ps.conversation_id = v_conv.id and ps.hidden;

  -- Notification: ACCEPTED conversations only — a message request is
  -- silent by design, always (design §6, §16). No content, no body:
  -- the row says only that @handle sent a message. Honors the member's
  -- per-type pref, her per-conversation mute, and her account-level
  -- mute of the sender. One unread notification per sender at a time.
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
-- 9. Requests: accept / decline. Declining hides the request from
--    the recipient but keeps the row — the sender is told nothing,
--    sees no state change, and can never send a second request.
-- ------------------------------------------------------------
create or replace function dm_accept_request(p_conversation uuid) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me uuid := auth.uid();
  v_conv dm_conversations%rowtype;
begin
  perform assert_dm_enabled();
  if v_me is null then raise exception 'Not signed in.'; end if;
  select * into v_conv from dm_conversations
   where id = p_conversation
     and v_me in (member_low, member_high)
   for update;
  if not found or v_conv.state <> 'request' or v_conv.initiator_id = v_me then
    raise exception 'That request is unavailable.';
  end if;
  if blocked_either(v_conv.member_low, v_conv.member_high) then
    raise exception 'That request is unavailable.';
  end if;
  update dm_conversations set state = 'accepted', accepted_at = now()
   where id = p_conversation;
  update dm_participant_state set hidden = false
   where conversation_id = p_conversation and user_id = v_me;
end $$;

create or replace function dm_decline_request(p_conversation uuid) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me uuid := auth.uid();
  v_conv dm_conversations%rowtype;
begin
  perform assert_dm_enabled();
  if v_me is null then raise exception 'Not signed in.'; end if;
  select * into v_conv from dm_conversations
   where id = p_conversation
     and v_me in (member_low, member_high);
  if not found or v_conv.state <> 'request' or v_conv.initiator_id = v_me then
    raise exception 'That request is unavailable.';
  end if;
  update dm_participant_state
     set hidden = true, cleared_before = now(), last_read_at = now()
   where conversation_id = p_conversation and user_id = v_me;
end $$;

-- ------------------------------------------------------------
-- 10. Per-conversation state: delete (for me), mute, mark read.
-- ------------------------------------------------------------
create or replace function dm_delete_conversation(p_conversation uuid) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_me uuid := auth.uid();
begin
  perform assert_dm_enabled();
  if v_me is null then raise exception 'Not signed in.'; end if;
  update dm_participant_state ps
     set hidden = true, cleared_before = now(), last_read_at = now()
   where ps.conversation_id = p_conversation and ps.user_id = v_me
     and exists (select 1 from dm_conversations c
                 where c.id = p_conversation and v_me in (c.member_low, c.member_high));
  if not found then
    raise exception 'That conversation is unavailable.';
  end if;
end $$;

create or replace function dm_set_muted(p_conversation uuid, p_muted boolean) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_me uuid := auth.uid();
begin
  perform assert_dm_enabled();
  if v_me is null then raise exception 'Not signed in.'; end if;
  update dm_participant_state ps
     set muted = coalesce(p_muted, false)
   where ps.conversation_id = p_conversation and ps.user_id = v_me;
  if not found then
    raise exception 'That conversation is unavailable.';
  end if;
end $$;

create or replace function dm_mark_read(p_conversation uuid) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me uuid := auth.uid();
  v_other uuid;
begin
  perform assert_dm_enabled();
  if v_me is null then raise exception 'Not signed in.'; end if;
  select case when member_low = v_me then member_high else member_low end
    into v_other
  from dm_conversations
   where id = p_conversation and v_me in (member_low, member_high);
  if v_other is null then
    raise exception 'That conversation is unavailable.';
  end if;
  update dm_participant_state
     set last_read_at = now()
   where conversation_id = p_conversation and user_id = v_me;
  update notifications
     set read_at = now()
   where user_id = v_me and actor_id = v_other and type = 'message' and read_at is null;
end $$;

-- ------------------------------------------------------------
-- 11. Reads. @handle only, always.
-- ------------------------------------------------------------

-- The inbox. p_requests=false → Primary (accepted conversations plus
-- the caller's own pending outgoing request); p_requests=true → the
-- Requests tab (silent incoming requests). No message content: the
-- preview is decrypted on the member's device from her local store.
-- Both sides keep their copy of an existing conversation across a
-- block (design §14: the history may be exactly the evidence the
-- blocker needs to report), so the only visibility predicate is
-- participant-and-not-hidden.
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
  peer_read_at timestamptz
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
              then ops.last_read_at end
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

-- The Messages badge: unread ACCEPTED conversations only. Requests
-- never count anywhere (design §6, §16). Returns 0 — never an error —
-- when the feature is off, so the shell can call it unconditionally.
create or replace function dm_unread_total() returns bigint
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null or not dm_feature_enabled() then
    return 0;
  end if;
  return (
    select count(*)
    from dm_conversations c
    join dm_participant_state ps on ps.conversation_id = c.id and ps.user_id = v_me
    where v_me in (c.member_low, c.member_high)
      and c.state = 'accepted'
      and not ps.hidden
      and not ps.muted
      and exists (select 1 from dm_messages m
                  where m.conversation_id = c.id
                    and m.sender_id <> v_me
                    and m.sent_at > coalesce(ps.last_read_at, '-infinity'::timestamptz)
                    and m.sent_at > coalesce(ps.cleared_before, '-infinity'::timestamptz))
  );
end $$;

-- Messages of one conversation, ciphertext only, ascending by id.
-- The caller's own "delete for me" horizon applies.
create or replace function dm_fetch_messages(
  p_conversation uuid,
  p_after_id bigint default null,
  p_limit integer default 100
) returns table (
  id bigint,
  sender_id uuid,
  sender_handle text,
  sender_device_id uuid,
  recipient_device_id uuid,
  header jsonb,
  ciphertext bytea,
  frank_hash bytea,
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
  select m.id, m.sender_id, pr.handle::text, m.sender_device_id,
         m.recipient_device_id, m.header, m.ciphertext, m.frank_hash, m.sent_at
  from dm_messages m
  join profiles pr on pr.user_id = m.sender_id
  where m.conversation_id = p_conversation
    and (v_cleared is null or m.sent_at > v_cleared)
    and (p_after_id is null or m.id > p_after_id)
  order by m.id
  limit least(greatest(coalesce(p_limit, 100), 1), 200);
end $$;

-- ------------------------------------------------------------
-- 12. Reporting a DM: client-side report-with-evidence plus franking
--     verification. The reporter's device attaches the plaintext and
--     per-message franking keys for exactly the messages she chose;
--     the server verifies each against its stored commitment. The
--     same duplicate guard, hourly cap, staff routing, safety@ email
--     copy, and audit shape as file_report().
--     p_evidence: jsonb array of
--       {"messageId": <bigint>, "plaintext": <text>, "frankKey": <hex>}
-- ------------------------------------------------------------
create or replace function file_dm_report(
  p_conversation uuid,
  p_reason report_reason,
  p_details text default null,
  p_evidence jsonb default '[]'::jsonb
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
  v_item     jsonb;
  v_msg      dm_messages%rowtype;
  v_plain    text;
  v_key      bytea;
  v_frank    bytea;
  v_verified boolean;
  v_count    integer := 0;
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

  if jsonb_typeof(coalesce(p_evidence, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_evidence, '[]'::jsonb)) < 1
     or jsonb_array_length(p_evidence) > 10 then
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

  -- Verify and store each attached message. verified=false rows are
  -- kept and shown honestly as the reporter's unverified claim.
  for v_item in select * from jsonb_array_elements(p_evidence) loop
    v_plain := v_item ->> 'plaintext';
    if v_plain is null or char_length(v_plain) < 1 or char_length(v_plain) > 4000 then
      raise exception 'Invalid report evidence.';
    end if;
    begin
      v_key := decode(v_item ->> 'frankKey', 'hex');
    exception when others then
      raise exception 'Invalid report evidence.';
    end;
    if v_key is null or octet_length(v_key) <> 32 then
      raise exception 'Invalid report evidence.';
    end if;
    select m.* into v_msg from dm_messages m
     where m.id = (v_item ->> 'messageId')::bigint
       and m.conversation_id = p_conversation;
    if not found then
      raise exception 'Invalid report evidence.';
    end if;
    v_recipient := case when v_msg.sender_id = v_conv.member_low
                        then v_conv.member_high else v_conv.member_low end;
    v_frank := extensions.hmac(
      convert_to('hersciety-dm-frank-v1' || E'\n' || v_msg.sender_id::text
                 || E'\n' || v_recipient::text || E'\n' || v_plain, 'UTF8'),
      v_key, 'sha256');
    v_verified := extensions.digest(v_frank, 'sha256') = v_msg.frank_hash;
    insert into dm_report_evidence
      (report_id, message_id, sender_id, recipient_id, plaintext,
       frank_key, frank, verified, sent_at)
    values
      (v_id, v_msg.id, v_msg.sender_id, v_recipient, v_plain,
       v_key, v_frank, v_verified, v_msg.sent_at);
    v_count := v_count + 1;
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

-- The console's view of DM evidence: a read-only transcript of
-- exactly what the reporter attached, per report, with the franking
-- verdict. @handle only. Visibility mirrors the reports queue.
create or replace function mod_dm_evidence(p_target uuid)
returns table (
  report_id uuid,
  reason report_reason,
  report_status report_status,
  reported_at timestamptz,
  message_id bigint,
  sender_handle text,
  plaintext text,
  verified boolean,
  sent_at timestamptz
)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if mod_actor_tier() < 0 then
    raise exception 'You do not have permission to view this case.';
  end if;
  return query
  select r.id, r.reason, r.status, r.created_at,
         e.message_id, pr.handle::text, e.plaintext, e.verified, e.sent_at
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
-- 13. EXECUTE lockdown. Internal helpers get no app-role grants;
--     member functions go to authenticated (each re-checks inside);
--     nothing is for anon or service_role.
-- ------------------------------------------------------------
revoke execute on function assert_dm_enabled()                                   from public, anon, authenticated, service_role;
revoke execute on function dm_active_device(uuid)                                from public, anon, authenticated, service_role;
revoke execute on function dm_route(uuid, uuid)                                  from public, anon, authenticated, service_role;

revoke execute on function dm_feature_enabled()                                  from public, anon, service_role;
revoke execute on function dm_register_device(text, bytea, bytea, bytea, bytea[]) from public, anon, service_role;
revoke execute on function dm_add_prekeys(bytea[])                               from public, anon, service_role;
revoke execute on function dm_my_device()                                        from public, anon, service_role;
revoke execute on function dm_can_message(uuid)                                  from public, anon, service_role;
revoke execute on function dm_prekey_bundle(uuid)                                from public, anon, service_role;
revoke execute on function dm_send_message(uuid, uuid, jsonb, bytea, bytea)      from public, anon, service_role;
revoke execute on function dm_accept_request(uuid)                               from public, anon, service_role;
revoke execute on function dm_decline_request(uuid)                              from public, anon, service_role;
revoke execute on function dm_delete_conversation(uuid)                          from public, anon, service_role;
revoke execute on function dm_set_muted(uuid, boolean)                           from public, anon, service_role;
revoke execute on function dm_mark_read(uuid)                                    from public, anon, service_role;
revoke execute on function dm_list_conversations(boolean)                        from public, anon, service_role;
revoke execute on function dm_unread_total()                                     from public, anon, service_role;
revoke execute on function dm_fetch_messages(uuid, bigint, integer)              from public, anon, service_role;
revoke execute on function file_dm_report(uuid, report_reason, text, jsonb)      from public, anon, service_role;
revoke execute on function mod_dm_evidence(uuid)                                 from public, anon, service_role;

grant execute on function dm_feature_enabled()                                   to authenticated;
grant execute on function dm_register_device(text, bytea, bytea, bytea, bytea[]) to authenticated;
grant execute on function dm_add_prekeys(bytea[])                                to authenticated;
grant execute on function dm_my_device()                                         to authenticated;
grant execute on function dm_can_message(uuid)                                   to authenticated;
grant execute on function dm_prekey_bundle(uuid)                                 to authenticated;
grant execute on function dm_send_message(uuid, uuid, jsonb, bytea, bytea)       to authenticated;
grant execute on function dm_accept_request(uuid)                                to authenticated;
grant execute on function dm_decline_request(uuid)                               to authenticated;
grant execute on function dm_delete_conversation(uuid)                           to authenticated;
grant execute on function dm_set_muted(uuid, boolean)                            to authenticated;
grant execute on function dm_mark_read(uuid)                                     to authenticated;
grant execute on function dm_list_conversations(boolean)                         to authenticated;
grant execute on function dm_unread_total()                                      to authenticated;
grant execute on function dm_fetch_messages(uuid, bigint, integer)               to authenticated;
grant execute on function file_dm_report(uuid, report_reason, text, jsonb)       to authenticated;
grant execute on function mod_dm_evidence(uuid)                                  to authenticated;
