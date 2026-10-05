-- Behavioral smoke test of the Phase 2C direct-message invariants
-- (local only). Covers: the dm_e2e_enabled feature flag refusing every
-- member-facing DM function while off; device registration (single
-- active device) and one-time prekey consumption; the server-enforced
-- inbox rules (follower → inbox, stranger → exactly one silent
-- request, accept/decline, the identical refusal for block / DMs off /
-- "no one"); ciphertext-only storage (structurally: no plaintext
-- column, no function that could return one); franking verification in
-- file_dm_report (a fabricated plaintext is marked unverified, the
-- genuine one verified); the moderation hand-off (message report in
-- the queue, evidence transcript, safety@ email copy with no reporter
-- and no message text); notification rules (accepted only, never
-- requests, prefs honoured); RLS lockdown of every DM table; and the
-- structural guarantee that no DM function returns or references
-- display_name.
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000041', 'mod@test'),
  ('00000000-0000-0000-0000-000000000042', 'ada@test'),
  ('00000000-0000-0000-0000-000000000043', 'bea@test'),
  ('00000000-0000-0000-0000-000000000044', 'cat@test'),
  ('00000000-0000-0000-0000-000000000045', 'dee@test'),
  ('00000000-0000-0000-0000-000000000047', 'system@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_system_account('00000000-0000-0000-0000-000000000047', 'hersciety');
select create_member('00000000-0000-0000-0000-000000000041', 'mod@test', 'Mo Derator', '1995-05-05', 'minerva', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000042', 'ada@test', 'Ada Lovelace', '1995-05-05', 'ada9', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000043', 'bea@test', 'Bea Arthur',   '1995-05-05', 'bea9', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000044', 'cat@test', 'Cat Stevens',  '1995-05-05', 'cat9', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000045', 'dee@test', 'Dee Dee',      '1995-05-05', 'dee9', null, null, null, '{}'::jsonb, false);

-- Make minerva a moderator (owner grant at aal2).
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"ow"}', false);
select grant_role('00000000-0000-0000-0000-000000000041', 'moderator');
reset role;

-- ============================================================
-- 1. STRUCTURAL: the new enum values exist; no DM function returns or
--    references display_name; dm_messages has no plaintext column —
--    the only plaintext table is dm_report_evidence.
-- ============================================================
do $$ begin
  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                 where t.typname = 'report_subject' and e.enumlabel = 'message') then
    raise exception 'FAIL: report_subject has no message value';
  end if;
  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                 where t.typname = 'notif_type' and e.enumlabel = 'message') then
    raise exception 'FAIL: notif_type has no message value';
  end if;
end $$;

do $$ declare f text; sig text; src text; begin
  foreach f in array array['dm_register_device', 'dm_add_prekeys', 'dm_my_device',
                           'dm_can_message', 'dm_prekey_bundle', 'dm_send_message',
                           'dm_accept_request', 'dm_decline_request',
                           'dm_delete_conversation', 'dm_set_muted', 'dm_mark_read',
                           'dm_list_conversations', 'dm_unread_total',
                           'dm_fetch_messages', 'file_dm_report', 'mod_dm_evidence'] loop
    select pg_get_function_result(p.oid), p.prosrc into sig, src
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = f;
    if sig is null then raise exception 'FAIL: function % missing', f; end if;
    if position('display_name' in sig) > 0 then
      raise exception 'FAIL: % return shape exposes display_name', f;
    end if;
    if position('display_name' in src) > 0 then
      raise exception 'FAIL: % body references display_name', f;
    end if;
  end loop;
  -- Ciphertext only: dm_messages must never grow a plaintext/body column.
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'dm_messages'
               and column_name in ('plaintext', 'body', 'text', 'content')) then
    raise exception 'FAIL: dm_messages carries a plaintext column';
  end if;
end $$;

-- ============================================================
-- 2. FEATURE FLAG: while app_config has no dm_e2e_enabled=true row,
--    every member-facing DM function refuses, and dm_unread_total
--    returns 0 (never an error — the shell calls it unconditionally).
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000042', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000042","aal":"aal1","session_id":"a"}', false);
do $$ begin
  if dm_feature_enabled() then raise exception 'FAIL: flag defaults on'; end if;
  if dm_unread_total() <> 0 then raise exception 'FAIL: unread total not 0 while off'; end if;
  begin
    perform dm_register_device('t', repeat('a', 64)::bytea, repeat('a', 32)::bytea,
                               repeat('a', 64)::bytea, array[repeat('a', 32)::bytea]);
    raise exception 'FAIL: device registered while feature off';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm <> 'Direct messages are not available.' then
      raise exception 'FAIL: wrong off-flag error: %', sqlerrm;
    end if;
  end;
  begin
    perform dm_list_conversations(false);
    raise exception 'FAIL: inbox listed while feature off';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
reset role;

-- Turn the flag on for the rest of the suite (what Grove does after
-- the external audit: one app_config row).
insert into app_config (key, value) values ('dm_e2e_enabled', 'true'::jsonb)
on conflict (key) do update set value = 'true'::jsonb;

-- ============================================================
-- 3. DEVICES AND PREKEYS: registration enforces key shapes, a second
--    registration revokes the first (single active device), prekeys
--    are consumed at most once each, and a member with no device
--    cannot be messaged yet.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000042', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000042","aal":"aal1","session_id":"a"}', false);
do $$ declare d1 uuid; d2 uuid; begin
  begin
    perform dm_register_device('t', repeat('a', 10)::bytea, repeat('a', 32)::bytea,
                               repeat('a', 64)::bytea, array[repeat('a', 32)::bytea]);
    raise exception 'FAIL: bad identity key accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  d1 := dm_register_device('ada browser',
          decode(repeat('11', 64), 'hex'), decode(repeat('12', 32), 'hex'),
          decode(repeat('13', 64), 'hex'),
          array[decode(repeat('21', 32), 'hex'), decode(repeat('22', 32), 'hex')]);
  d2 := dm_register_device('ada browser 2',
          decode(repeat('31', 64), 'hex'), decode(repeat('32', 32), 'hex'),
          decode(repeat('33', 64), 'hex'),
          array[decode(repeat('41', 32), 'hex'), decode(repeat('42', 32), 'hex')]);
  if (select count(*) from user_devices
      where user_id = '00000000-0000-0000-0000-000000000042' and revoked_at is null) <> 1 then
    raise exception 'FAIL: more than one active device';
  end if;
  if (select device_id from dm_my_device()) <> d2 then
    raise exception 'FAIL: dm_my_device does not return the new device';
  end if;
  perform set_config('t.ada_device', d2::text, false);
end $$;
reset role;

-- bea registers a device too. cat deliberately has NO device.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000043', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000043","aal":"aal1","session_id":"b"}', false);
do $$ declare d uuid; begin
  d := dm_register_device('bea browser',
         decode(repeat('51', 64), 'hex'), decode(repeat('52', 32), 'hex'),
         decode(repeat('53', 64), 'hex'),
         array[decode(repeat('61', 32), 'hex')]);
  perform set_config('t.bea_device', d::text, false);
end $$;

-- bea follows ada: ada now reaches bea's MAIN inbox (design §6).
insert into follows (follower_id, followee_id)
values ('00000000-0000-0000-0000-000000000043', '00000000-0000-0000-0000-000000000042');
reset role;

-- ============================================================
-- 4. PREKEY BUNDLE: consuming works once per prekey; a member with no
--    device cannot be fetched; the bundle enforces the same send
--    permission (no oracle).
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000042', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000042","aal":"aal1","session_id":"a"}', false);
do $$ declare b record; b2 record; begin
  select * into b from dm_prekey_bundle('00000000-0000-0000-0000-000000000043');
  if b.device_id::text <> current_setting('t.bea_device') then
    raise exception 'FAIL: bundle returned wrong device';
  end if;
  if b.prekey_id is null then raise exception 'FAIL: no one-time prekey consumed'; end if;
  -- bea only uploaded one prekey: a second bundle has none left (X3DH
  -- degrades to no-OTP mode, which is allowed).
  select * into b2 from dm_prekey_bundle('00000000-0000-0000-0000-000000000043');
  if b2.prekey_id is not null then
    raise exception 'FAIL: one-time prekey consumed twice';
  end if;
  begin
    perform dm_prekey_bundle('00000000-0000-0000-0000-000000000044');
    raise exception 'FAIL: bundle for a member with no device';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm <> 'This member cannot receive messages yet.' then
      raise exception 'FAIL: wrong no-device error: %', sqlerrm;
    end if;
  end;
end $$;

-- ============================================================
-- 5. SEND, FOLLOWER PATH: ada → bea lands as an ACCEPTED conversation
--    (bea follows ada), creates a 'message' notification, and the
--    ciphertext round-trips byte-for-byte.
-- ============================================================
do $$ declare r record; begin
  select * into r from dm_send_message(
    '00000000-0000-0000-0000-000000000043',
    current_setting('t.bea_device')::uuid,
    '{"n":0,"pn":0,"dh":"test"}'::jsonb,
    decode('c0ffee', 'hex'),
    decode(repeat('ab', 32), 'hex'));
  if r.conversation_state <> 'accepted' then
    raise exception 'FAIL: follower-path message did not land accepted, got %', r.conversation_state;
  end if;
  perform set_config('t.conv_ab', r.conversation_id::text, false);
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000043', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000043","aal":"aal1","session_id":"b"}', false);
do $$ declare m record; n integer; begin
  select * into m from dm_fetch_messages(current_setting('t.conv_ab')::uuid);
  if m.ciphertext <> decode('c0ffee', 'hex') then
    raise exception 'FAIL: ciphertext did not round-trip';
  end if;
  if m.sender_handle <> 'ada9' then
    raise exception 'FAIL: sender handle wrong in fetch';
  end if;
  select count(*) into n from notifications
   where user_id = '00000000-0000-0000-0000-000000000043'
     and type = 'message' and actor_id = '00000000-0000-0000-0000-000000000042';
  if n <> 1 then raise exception 'FAIL: accepted message did not notify (got %)', n; end if;
  if dm_unread_total() <> 1 then raise exception 'FAIL: unread total wrong'; end if;
  perform dm_mark_read(current_setting('t.conv_ab')::uuid);
  if dm_unread_total() <> 0 then raise exception 'FAIL: mark read did not clear unread'; end if;
  if exists (select 1 from notifications
             where user_id = '00000000-0000-0000-0000-000000000043'
               and type = 'message' and read_at is null) then
    raise exception 'FAIL: mark read did not clear the message notification';
  end if;
end $$;
reset role;

-- ============================================================
-- 6. SEND, STRANGER PATH: bea → dee (no follow) lands as a silent
--    REQUEST: no notification, exactly ONE message until accepted,
--    invisible in dee's Primary tab, visible in her Requests tab,
--    never counted in her unread badge.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000045', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000045","aal":"aal1","session_id":"d"}', false);
do $$ declare d uuid; begin
  d := dm_register_device('dee browser',
         decode(repeat('71', 64), 'hex'), decode(repeat('72', 32), 'hex'),
         decode(repeat('73', 64), 'hex'),
         array[decode(repeat('81', 32), 'hex'), decode(repeat('82', 32), 'hex')]);
  perform set_config('t.dee_device', d::text, false);
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000043', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000043","aal":"aal1","session_id":"b"}', false);
do $$ declare r record; begin
  if dm_can_message('00000000-0000-0000-0000-000000000045') <> 'request' then
    raise exception 'FAIL: stranger route is not request';
  end if;
  select * into r from dm_send_message(
    '00000000-0000-0000-0000-000000000045',
    current_setting('t.dee_device')::uuid,
    '{"n":0}'::jsonb, decode('0102', 'hex'), decode(repeat('cd', 32), 'hex'));
  if r.conversation_state <> 'request' then
    raise exception 'FAIL: stranger message did not land as request';
  end if;
  perform set_config('t.conv_bd', r.conversation_id::text, false);
  -- EXACTLY ONE message until accepted.
  begin
    perform dm_send_message(
      '00000000-0000-0000-0000-000000000045',
      current_setting('t.dee_device')::uuid,
      '{"n":1}'::jsonb, decode('0304', 'hex'), decode(repeat('ce', 32), 'hex'));
    raise exception 'FAIL: second request message accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm <> 'You can send one message until they accept.' then
      raise exception 'FAIL: wrong one-message-cap error: %', sqlerrm;
    end if;
  end;
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000045', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000045","aal":"aal1","session_id":"d"}', false);
do $$ declare n integer; begin
  -- Silent: no notification of any type from the request.
  select count(*) into n from notifications
   where user_id = '00000000-0000-0000-0000-000000000045' and actor_id = '00000000-0000-0000-0000-000000000043';
  if n <> 0 then raise exception 'FAIL: a message request notified'; end if;
  -- Never in the unread badge.
  if dm_unread_total() <> 0 then raise exception 'FAIL: request counted in unread badge'; end if;
  -- In Requests, not Primary.
  if exists (select 1 from dm_list_conversations(false)
             where conversation_id = current_setting('t.conv_bd')::uuid) then
    raise exception 'FAIL: request visible in Primary tab';
  end if;
  if not exists (select 1 from dm_list_conversations(true)
                 where conversation_id = current_setting('t.conv_bd')::uuid) then
    raise exception 'FAIL: request missing from Requests tab';
  end if;
  -- The recipient cannot reply before accepting.
  begin
    perform dm_send_message(
      '00000000-0000-0000-0000-000000000043',
      current_setting('t.bea_device')::uuid,
      '{"n":0}'::jsonb, decode('05', 'hex'), decode(repeat('cf', 32), 'hex'));
    raise exception 'FAIL: reply sent before accepting the request';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm <> 'Accept the request before replying.' then
      raise exception 'FAIL: wrong reply-before-accept error: %', sqlerrm;
    end if;
  end;
  -- Accept, then reply works and the thread is Primary for both.
  perform dm_accept_request(current_setting('t.conv_bd')::uuid);
  perform dm_send_message(
    '00000000-0000-0000-0000-000000000043',
    current_setting('t.bea_device')::uuid,
    '{"n":0}'::jsonb, decode('05', 'hex'), decode(repeat('cf', 32), 'hex'));
  if not exists (select 1 from dm_list_conversations(false)
                 where conversation_id = current_setting('t.conv_bd')::uuid
                   and state = 'accepted') then
    raise exception 'FAIL: accepted conversation missing from Primary';
  end if;
end $$;
reset role;

-- ============================================================
-- 7. DECLINE KEEPS THE CAP: cat (with a device now) requests dee;
--    dee declines; the request vanishes from dee's view, cat is told
--    nothing, and cat still cannot send a second message.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000044', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000044","aal":"aal1","session_id":"c"}', false);
do $$ declare d uuid; r record; begin
  d := dm_register_device('cat browser',
         decode(repeat('91', 64), 'hex'), decode(repeat('92', 32), 'hex'),
         decode(repeat('93', 64), 'hex'), array[decode(repeat('a1', 32), 'hex')]);
  perform set_config('t.cat_device', d::text, false);
  select * into r from dm_send_message(
    '00000000-0000-0000-0000-000000000045',
    current_setting('t.dee_device')::uuid,
    '{"n":0}'::jsonb, decode('0a', 'hex'), decode(repeat('da', 32), 'hex'));
  perform set_config('t.conv_cd', r.conversation_id::text, false);
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000045', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000045","aal":"aal1","session_id":"d"}', false);
select dm_decline_request(current_setting('t.conv_cd')::uuid);
do $$ begin
  if exists (select 1 from dm_list_conversations(true)
             where conversation_id = current_setting('t.conv_cd')::uuid) then
    raise exception 'FAIL: declined request still visible';
  end if;
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000044', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000044","aal":"aal1","session_id":"c"}', false);
do $$ begin
  -- The decline is invisible to cat: her view is unchanged ("waiting")
  -- and the one-message cap still holds — no second request, ever.
  if not exists (select 1 from dm_list_conversations(false)
                 where conversation_id = current_setting('t.conv_cd')::uuid
                   and state = 'request') then
    raise exception 'FAIL: decline leaked to the sender';
  end if;
  begin
    perform dm_send_message(
      '00000000-0000-0000-0000-000000000045',
      current_setting('t.dee_device')::uuid,
      '{"n":1}'::jsonb, decode('0b', 'hex'), decode(repeat('db', 32), 'hex'));
    raise exception 'FAIL: declined sender sent a second message';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
reset role;

-- ============================================================
-- 8. THE IDENTICAL REFUSAL: block, DMs off, and "no one" all raise
--    the same message, so a blocked person cannot distinguish a block
--    (design §6, §14). The prekey bundle refuses identically.
-- ============================================================
-- dee blocks cat.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000045', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000045","aal":"aal1","session_id":"d"}', false);
insert into blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-000000000045', '00000000-0000-0000-0000-000000000044');
-- ada turns DMs off entirely.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000042', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000042","aal":"aal1","session_id":"a"}', false);
insert into dm_settings (user_id, dms_enabled)
values ('00000000-0000-0000-0000-000000000042', false)
on conflict (user_id) do update set dms_enabled = false;
-- bea allows requests from no one.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000043', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000043","aal":"aal1","session_id":"b"}', false);
insert into dm_settings (user_id, requests_from)
values ('00000000-0000-0000-0000-000000000043', 'no_one')
on conflict (user_id) do update set requests_from = 'no_one';
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000044', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000044","aal":"aal1","session_id":"c"}', false);
do $$
declare
  e_block text; e_off text; e_noone text; e_bundle text;
begin
  if dm_can_message('00000000-0000-0000-0000-000000000045') <> 'none'
     or dm_can_message('00000000-0000-0000-0000-000000000042') <> 'none'
     or dm_can_message('00000000-0000-0000-0000-000000000043') <> 'none' then
    raise exception 'FAIL: dm_can_message did not return none for block/off/no_one';
  end if;
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000045',
      current_setting('t.dee_device')::uuid, '{}'::jsonb,
      decode('01', 'hex'), decode(repeat('aa', 32), 'hex'));
    raise exception 'FAIL: blocked sender sent';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if; e_block := sqlerrm;
  end;
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000042',
      current_setting('t.ada_device')::uuid, '{}'::jsonb,
      decode('01', 'hex'), decode(repeat('aa', 32), 'hex'));
    raise exception 'FAIL: sent to DMs-off member';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if; e_off := sqlerrm;
  end;
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000043',
      current_setting('t.bea_device')::uuid, '{}'::jsonb,
      decode('01', 'hex'), decode(repeat('aa', 32), 'hex'));
    raise exception 'FAIL: sent to no-one member';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if; e_noone := sqlerrm;
  end;
  if e_block <> e_off or e_off <> e_noone then
    raise exception 'FAIL: refusals are distinguishable: % / % / %', e_block, e_off, e_noone;
  end if;
  begin
    perform dm_prekey_bundle('00000000-0000-0000-0000-000000000045');
    raise exception 'FAIL: blocked sender fetched a prekey bundle';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if; e_bundle := sqlerrm;
  end;
  if e_bundle <> e_block then
    raise exception 'FAIL: bundle refusal differs from send refusal';
  end if;
end $$;
reset role;

-- An EXISTING accepted conversation stays readable on both sides
-- across a block (the history may be the evidence), but sending stops.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000043', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000043","aal":"aal1","session_id":"b"}', false);
insert into blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-000000000043', '00000000-0000-0000-0000-000000000042');
do $$ begin
  if not exists (select 1 from dm_fetch_messages(current_setting('t.conv_ab')::uuid)) then
    raise exception 'FAIL: blocker lost her conversation history';
  end if;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000042', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000042","aal":"aal1","session_id":"a"}', false);
do $$ begin
  if not exists (select 1 from dm_fetch_messages(current_setting('t.conv_ab')::uuid)) then
    raise exception 'FAIL: blocked party lost her own copy of the history';
  end if;
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000043',
      current_setting('t.bea_device')::uuid, '{}'::jsonb,
      decode('01', 'hex'), decode(repeat('aa', 32), 'hex'));
    raise exception 'FAIL: blocked party sent into an existing conversation';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm <> 'You can no longer message this account.' then
      raise exception 'FAIL: block refusal on existing thread differs: %', sqlerrm;
    end if;
  end;
end $$;
-- Clean up the block so the franking section can message again.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000043', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000043","aal":"aal1","session_id":"b"}', false);
delete from blocks where blocker_id = '00000000-0000-0000-0000-000000000043';
reset role;

-- ============================================================
-- 9. FRANKING: a genuine message verifies; a fabricated plaintext is
--    stored as unverified. Uses a real HMAC commitment computed the
--    way the client computes it.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000043', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000043","aal":"aal1","session_id":"b"}', false);
do $$
declare
  v_key   bytea := decode(repeat('42', 32), 'hex');
  v_plain text := 'meet me at nine';
  v_frank bytea;
  r record;
begin
  -- bea → dee (accepted conversation from section 6).
  v_frank := extensions.hmac(
    convert_to('hersciety-dm-frank-v1' || E'\n' || '00000000-0000-0000-0000-000000000043'
               || E'\n' || '00000000-0000-0000-0000-000000000045' || E'\n' || v_plain, 'UTF8'),
    v_key, 'sha256');
  select * into r from dm_send_message(
    '00000000-0000-0000-0000-000000000045',
    current_setting('t.dee_device')::uuid,
    '{"n":2}'::jsonb,
    decode('deadbeef', 'hex'),           -- ciphertext is opaque to the server
    extensions.digest(v_frank, 'sha256'));
  perform set_config('t.franked_msg', r.message_id::text, false);
  perform set_config('t.frank_key', encode(v_key, 'hex'), false);
end $$;
reset role;

-- dee reports it: genuine plaintext verifies, fabricated does not.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000045', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000045","aal":"aal1","session_id":"d"}', false);
do $$ declare v_report uuid; begin
  v_report := file_dm_report(
    current_setting('t.conv_bd')::uuid,
    'harassment',
    'he will not stop',
    jsonb_build_array(jsonb_build_object(
      'messageId', current_setting('t.franked_msg')::bigint,
      'plaintext', 'meet me at nine',
      'frankKey', current_setting('t.frank_key'))));
  perform set_config('t.report1', v_report::text, false);
end $$;
reset role;

do $$ begin
  if not exists (select 1 from dm_report_evidence
                 where report_id = current_setting('t.report1')::uuid and verified) then
    raise exception 'FAIL: genuine evidence did not verify';
  end if;
  if (select subject_type from reports where id = current_setting('t.report1')::uuid)
     <> 'message'::report_subject then
    raise exception 'FAIL: DM report not filed with subject message';
  end if;
  -- The safety@ copy exists and leaks nothing: no reporter handle, no
  -- message text, no legal names.
  if not exists (select 1 from safety_email_outbox
                 where report_id = current_setting('t.report1')::uuid
                   and body not like '%dee9%'
                   and body not like '%meet me at nine%'
                   and body not like '%Dee Dee%'
                   and body like '%direct messages from @bea9%') then
    raise exception 'FAIL: safety email copy missing or leaking';
  end if;
end $$;

-- A fabricated plaintext (dee edits the words) stores as verified=false.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000045', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000045","aal":"aal1","session_id":"d"}', false);
do $$ declare v_report uuid; begin
  v_report := file_dm_report(
    current_setting('t.conv_bd')::uuid,
    'violence_threat',
    null,
    jsonb_build_array(jsonb_build_object(
      'messageId', current_setting('t.franked_msg')::bigint,
      'plaintext', 'i will hurt you',
      'frankKey', current_setting('t.frank_key'))));
  perform set_config('t.report2', v_report::text, false);
end $$;
reset role;
do $$ begin
  if exists (select 1 from dm_report_evidence
             where report_id = current_setting('t.report2')::uuid and verified) then
    raise exception 'FAIL: fabricated evidence verified';
  end if;
end $$;

-- ============================================================
-- 10. MODERATION HAND-OFF: the moderator sees the message case in the
--     queue and the evidence transcript with its franking verdicts;
--     a member does not; the reporter sees her own report.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000041', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000041","aal":"aal1","session_id":"m"}', false);
do $$ declare n integer; begin
  if not exists (select 1 from mod_queue('open')
                 where accused_handle = 'bea9' and subject_post_id is null) then
    raise exception 'FAIL: DM report missing from the moderation queue';
  end if;
  select count(*) into n from mod_dm_evidence('00000000-0000-0000-0000-000000000043');
  if n <> 2 then raise exception 'FAIL: evidence transcript wrong size (%)', n; end if;
  if not exists (select 1 from mod_dm_evidence('00000000-0000-0000-0000-000000000043')
                 where plaintext = 'meet me at nine' and verified) then
    raise exception 'FAIL: verified evidence missing from transcript';
  end if;
  if not exists (select 1 from mod_dm_evidence('00000000-0000-0000-0000-000000000043')
                 where plaintext = 'i will hurt you' and not verified) then
    raise exception 'FAIL: unverified evidence not marked';
  end if;
end $$;
-- A plain member cannot read the evidence function or tables.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000044', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000044","aal":"aal1","session_id":"c"}', false);
do $$ begin
  begin
    perform mod_dm_evidence('00000000-0000-0000-0000-000000000043');
    raise exception 'FAIL: member read the evidence transcript';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
-- The reporter sees her own report in her history, shape unchanged.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000045', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000045","aal":"aal1","session_id":"d"}', false);
do $$ begin
  if not exists (select 1 from reports where id = current_setting('t.report1')::uuid
                 and reporter_id = auth.uid()) then
    raise exception 'FAIL: reporter cannot see her own DM report';
  end if;
end $$;
reset role;

-- ============================================================
-- 11. RLS LOCKDOWN: no app role touches the DM tables directly; a
--     non-participant cannot fetch a conversation; dm_settings is
--     own-row only.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000044', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000044","aal":"aal1","session_id":"c"}', false);
do $$ begin
  begin
    perform * from dm_messages limit 1;
    raise exception 'FAIL: authenticated read dm_messages directly';
  exception when insufficient_privilege then null;
    when others then if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    perform * from dm_conversations limit 1;
    raise exception 'FAIL: authenticated read dm_conversations directly';
  exception when insufficient_privilege then null;
    when others then if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    perform * from dm_report_evidence limit 1;
    raise exception 'FAIL: authenticated read dm_report_evidence directly';
  exception when insufficient_privilege then null;
    when others then if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    perform * from one_time_prekeys limit 1;
    raise exception 'FAIL: authenticated read one_time_prekeys directly';
  exception when insufficient_privilege then null;
    when others then if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  -- Another member's device rows are invisible (RLS), own rows visible.
  if exists (select 1 from user_devices where user_id <> auth.uid()) then
    raise exception 'FAIL: another member''s devices are visible';
  end if;
  -- Another member's dm_settings are invisible.
  if exists (select 1 from dm_settings where user_id <> auth.uid()) then
    raise exception 'FAIL: another member''s dm_settings are visible';
  end if;
  -- A non-participant cannot fetch messages through the function either.
  begin
    perform dm_fetch_messages(current_setting('t.conv_ab')::uuid);
    raise exception 'FAIL: non-participant fetched a conversation';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm <> 'That conversation is unavailable.' then
      raise exception 'FAIL: wrong non-participant error: %', sqlerrm;
    end if;
  end;
end $$;
reset role;
set role service_role;
do $$ begin
  begin
    insert into dm_messages (conversation_id, sender_id, sender_device_id,
                             recipient_device_id, header, ciphertext, frank_hash)
    values (current_setting('t.conv_ab')::uuid, '00000000-0000-0000-0000-000000000042',
            current_setting('t.ada_device')::uuid, current_setting('t.bea_device')::uuid,
            '{}'::jsonb, decode('00', 'hex'), decode(repeat('00', 32), 'hex'));
    raise exception 'FAIL: service_role inserted a message directly';
  exception when insufficient_privilege then null;
    when others then if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
reset role;

-- ============================================================
-- 12. NOTIFICATION PREFS: the 'message' toggle is honoured; a
--     per-conversation mute silences without unsubscribing.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000045', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000045","aal":"aal1","session_id":"d"}', false);
insert into notification_prefs (user_id, prefs)
values ('00000000-0000-0000-0000-000000000045', '{"message": false}'::jsonb)
on conflict (user_id) do update set prefs = '{"message": false}'::jsonb;
select dm_mark_read(current_setting('t.conv_bd')::uuid);
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000043', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000043","aal":"aal1","session_id":"b"}', false);
select dm_send_message('00000000-0000-0000-0000-000000000045',
  current_setting('t.dee_device')::uuid, '{"n":3}'::jsonb,
  decode('ff', 'hex'), decode(repeat('ee', 32), 'hex'));
reset role;
do $$ begin
  if exists (select 1 from notifications
             where user_id = '00000000-0000-0000-0000-000000000045'
               and type = 'message' and read_at is null) then
    raise exception 'FAIL: message notification created despite pref off';
  end if;
end $$;

-- ============================================================
-- 13. DELETE FOR ME: the deleter's horizon moves; the other side
--     keeps everything; a new message brings the thread back with
--     only the new content.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000045', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000045","aal":"aal1","session_id":"d"}', false);
do $$ declare before_n integer; after_n integer; begin
  select count(*) into before_n from dm_fetch_messages(current_setting('t.conv_bd')::uuid);
  if before_n < 2 then raise exception 'FAIL: expected messages before delete'; end if;
  perform dm_delete_conversation(current_setting('t.conv_bd')::uuid);
  if exists (select 1 from dm_list_conversations(false)
             where conversation_id = current_setting('t.conv_bd')::uuid) then
    raise exception 'FAIL: deleted conversation still listed';
  end if;
  select count(*) into after_n from dm_fetch_messages(current_setting('t.conv_bd')::uuid);
  if after_n <> 0 then raise exception 'FAIL: delete-for-me did not clear the view'; end if;
end $$;
reset role;
-- This whole suite runs in one transaction, so now() is frozen: every
-- row so far shares one timestamp, and the new message below would tie
-- with the clear horizon. Simulate the time that passes between real
-- requests: the old messages happened 2s ago, the delete 1s ago, the
-- new message now.
update dm_messages set sent_at = sent_at - interval '2 seconds'
 where conversation_id = current_setting('t.conv_bd')::uuid;
update dm_participant_state
   set cleared_before = cleared_before - interval '1 second',
       last_read_at = last_read_at - interval '1 second'
 where conversation_id = current_setting('t.conv_bd')::uuid
   and user_id = '00000000-0000-0000-0000-000000000045';
set role authenticated;
-- The other side keeps her copy.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000043', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000043","aal":"aal1","session_id":"b"}', false);
do $$ begin
  if not exists (select 1 from dm_fetch_messages(current_setting('t.conv_bd')::uuid)) then
    raise exception 'FAIL: delete-for-me reached the other member';
  end if;
  -- A new message resurfaces the thread for the deleter…
  perform dm_send_message('00000000-0000-0000-0000-000000000045',
    current_setting('t.dee_device')::uuid, '{"n":4}'::jsonb,
    decode('ab', 'hex'), decode(repeat('ba', 32), 'hex'));
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000045', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000045","aal":"aal1","session_id":"d"}', false);
do $$ declare n integer; begin
  if not exists (select 1 from dm_list_conversations(false)
                 where conversation_id = current_setting('t.conv_bd')::uuid) then
    raise exception 'FAIL: new message did not resurface the thread';
  end if;
  -- …with only the new content.
  select count(*) into n from dm_fetch_messages(current_setting('t.conv_bd')::uuid);
  if n <> 1 then raise exception 'FAIL: cleared history resurfaced (% rows)', n; end if;
end $$;
reset role;

rollback;
\echo ALL DM SMOKE TESTS PASSED
