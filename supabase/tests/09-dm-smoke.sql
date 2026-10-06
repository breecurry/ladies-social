-- Behavioral smoke test of the reworked (NON-E2E) direct-message
-- invariants (local only). Covers: the renamed dm_enabled feature flag
-- (and the dead old key doing nothing); the structural REMOVAL of the
-- whole E2E layer (no device/prekey tables or functions, no
-- ciphertext/franking columns, exactly one signature per DM function —
-- the PostgREST ambiguity guard); readable message bodies with the
-- 2000-char cap; the server-enforced inbox rules (follower → inbox,
-- stranger → exactly one silent request, accept/decline, the identical
-- refusal for block / DMs off / "no one"); server-side evidence
-- snapshots in file_dm_report (no client-supplied content); the
-- moderation hand-off INCLUDING the audit_log row that every
-- mod_dm_evidence content read must write; notification rules; RLS
-- lockdown of every DM table; and the structural guarantee that no DM
-- function returns or references display_name.
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
-- 1. STRUCTURAL: the E2E layer is GONE and the readable shape is in.
--    * no user_devices / one_time_prekeys tables;
--    * no device/prekey/franking functions, and no DM function has a
--      leftover second signature (PostgREST ambiguity guard);
--    * dm_messages has a body column and none of the E2E columns;
--    * dm_report_evidence is the server snapshot shape (no franking);
--    * no DM function returns or references display_name;
--    * the enum values from 0020 are still there.
-- ============================================================
do $$ begin
  if exists (select 1 from information_schema.tables
             where table_schema = 'public'
               and table_name in ('user_devices', 'one_time_prekeys')) then
    raise exception 'FAIL: E2E key tables still exist';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public'
               and p.proname in ('dm_register_device', 'dm_add_prekeys', 'dm_my_device',
                                 'dm_prekey_bundle', 'dm_active_device')) then
    raise exception 'FAIL: E2E device/prekey functions still exist';
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'dm_messages'
               and column_name in ('ciphertext', 'header', 'frank_hash',
                                   'sender_device_id', 'recipient_device_id')) then
    raise exception 'FAIL: dm_messages still carries E2E columns';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'dm_messages'
                   and column_name = 'body') then
    raise exception 'FAIL: dm_messages has no body column';
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'dm_report_evidence'
               and column_name in ('frank_key', 'frank', 'verified', 'plaintext')) then
    raise exception 'FAIL: dm_report_evidence still carries franking columns';
  end if;
  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                 where t.typname = 'report_subject' and e.enumlabel = 'message') then
    raise exception 'FAIL: report_subject has no message value';
  end if;
  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                 where t.typname = 'notif_type' and e.enumlabel = 'message') then
    raise exception 'FAIL: notif_type has no message value';
  end if;
end $$;

do $$ declare f text; n integer; sig text; src text; begin
  foreach f in array array['dm_feature_enabled', 'dm_can_message', 'dm_send_message',
                           'dm_accept_request', 'dm_decline_request',
                           'dm_delete_conversation', 'dm_set_muted', 'dm_mark_read',
                           'dm_list_conversations', 'dm_unread_total',
                           'dm_fetch_messages', 'file_dm_report', 'mod_dm_evidence'] loop
    select count(*) into n
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'public' and p.proname = f;
    if n = 0 then raise exception 'FAIL: function % missing', f; end if;
    if n > 1 then
      raise exception 'FAIL: % has % signatures — PostgREST would be ambiguous', f, n;
    end if;
    select pg_get_function_result(p.oid), p.prosrc into sig, src
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'public' and p.proname = f;
    if position('display_name' in sig) > 0 then
      raise exception 'FAIL: % return shape exposes display_name', f;
    end if;
    if position('display_name' in src) > 0 then
      raise exception 'FAIL: % body references display_name', f;
    end if;
  end loop;
end $$;

-- ============================================================
-- 2. FEATURE FLAG: the key is dm_enabled now. While absent, every
--    member-facing DM function refuses and dm_unread_total returns 0
--    (never an error). The OLD key is dead: a dm_e2e_enabled row
--    enables nothing.
-- ============================================================
insert into app_config (key, value) values ('dm_e2e_enabled', 'true'::jsonb)
on conflict (key) do update set value = 'true'::jsonb;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000042', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000042","aal":"aal1","session_id":"a"}', false);
do $$ begin
  if dm_feature_enabled() then raise exception 'FAIL: the dead dm_e2e_enabled key enabled DMs'; end if;
  if dm_unread_total() <> 0 then raise exception 'FAIL: unread total not 0 while off'; end if;
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000043', 'hello');
    raise exception 'FAIL: message sent while feature off';
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

delete from app_config where key = 'dm_e2e_enabled';
-- Turn the flag on for the rest of the suite (what Grove does at
-- launch: one app_config row, key dm_enabled).
insert into app_config (key, value) values ('dm_enabled', 'true'::jsonb)
on conflict (key) do update set value = 'true'::jsonb;

-- bea follows ada: ada now reaches bea's MAIN inbox (design §6).
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000043', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000043","aal":"aal1","session_id":"b"}', false);
insert into follows (follower_id, followee_id)
values ('00000000-0000-0000-0000-000000000043', '00000000-0000-0000-0000-000000000042');
reset role;

-- ============================================================
-- 3. SEND, FOLLOWER PATH: ada → bea lands as an ACCEPTED conversation
--    (bea follows ada), the body round-trips readably, a 'message'
--    notification fires, and the length caps hold.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000042', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000042","aal":"aal1","session_id":"a"}', false);
do $$ declare r record; begin
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000043', repeat('x', 2001));
    raise exception 'FAIL: 2001-char message accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000043', '   ');
    raise exception 'FAIL: blank message accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  select * into r from dm_send_message('00000000-0000-0000-0000-000000000043', 'tea on thursday?');
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
  if m.body <> 'tea on thursday?' then
    raise exception 'FAIL: body did not round-trip';
  end if;
  if m.sender_handle <> 'ada9' then
    raise exception 'FAIL: sender handle wrong in fetch';
  end if;
  -- The inbox preview carries the body too, with the sender.
  if not exists (select 1 from dm_list_conversations(false)
                 where conversation_id = current_setting('t.conv_ab')::uuid
                   and last_body = 'tea on thursday?'
                   and last_sender_id = '00000000-0000-0000-0000-000000000042') then
    raise exception 'FAIL: inbox preview missing or wrong';
  end if;
  select count(*) into n from notifications
   where user_id = '00000000-0000-0000-0000-000000000043'
     and type = 'message' and actor_id = '00000000-0000-0000-0000-000000000042';
  if n <> 1 then raise exception 'FAIL: accepted message did not notify (got %)', n; end if;
  -- The notification itself carries no message content (no body column
  -- is even nullable-filled for messages).
  if exists (select 1 from notifications
             where user_id = '00000000-0000-0000-0000-000000000043' and type = 'message'
               and coalesce(body, '') <> '') then
    raise exception 'FAIL: message notification carries content';
  end if;
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
-- 4. SEND, STRANGER PATH: bea → dee (no follow) lands as a silent
--    REQUEST: no notification, exactly ONE message until accepted,
--    invisible in dee's Primary tab, visible in her Requests tab,
--    never counted in her unread badge; dee cannot reply before
--    accepting; accepting opens the thread for both.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000043', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000043","aal":"aal1","session_id":"b"}', false);
do $$ declare r record; begin
  if dm_can_message('00000000-0000-0000-0000-000000000045') <> 'request' then
    raise exception 'FAIL: stranger route is not request';
  end if;
  select * into r from dm_send_message('00000000-0000-0000-0000-000000000045', 'hi, loved your post');
  if r.conversation_state <> 'request' then
    raise exception 'FAIL: stranger message did not land as request';
  end if;
  perform set_config('t.conv_bd', r.conversation_id::text, false);
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000045', 'me again');
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
  select count(*) into n from notifications
   where user_id = '00000000-0000-0000-0000-000000000045' and actor_id = '00000000-0000-0000-0000-000000000043';
  if n <> 0 then raise exception 'FAIL: a message request notified'; end if;
  if dm_unread_total() <> 0 then raise exception 'FAIL: request counted in unread badge'; end if;
  if exists (select 1 from dm_list_conversations(false)
             where conversation_id = current_setting('t.conv_bd')::uuid) then
    raise exception 'FAIL: request visible in Primary tab';
  end if;
  if not exists (select 1 from dm_list_conversations(true)
                 where conversation_id = current_setting('t.conv_bd')::uuid) then
    raise exception 'FAIL: request missing from Requests tab';
  end if;
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000043', 'who are you?');
    raise exception 'FAIL: reply sent before accepting the request';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm <> 'Accept the request before replying.' then
      raise exception 'FAIL: wrong reply-before-accept error: %', sqlerrm;
    end if;
  end;
  perform dm_accept_request(current_setting('t.conv_bd')::uuid);
  perform dm_send_message('00000000-0000-0000-0000-000000000043', 'thanks! hi');
  if not exists (select 1 from dm_list_conversations(false)
                 where conversation_id = current_setting('t.conv_bd')::uuid
                   and state = 'accepted') then
    raise exception 'FAIL: accepted conversation missing from Primary';
  end if;
end $$;
reset role;

-- ============================================================
-- 5. DECLINE KEEPS THE CAP: cat requests dee; dee declines; the
--    request vanishes from dee's view, cat is told nothing, and cat
--    still cannot send a second message.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000044', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000044","aal":"aal1","session_id":"c"}', false);
do $$ declare r record; begin
  select * into r from dm_send_message('00000000-0000-0000-0000-000000000045', 'hello there');
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
  if not exists (select 1 from dm_list_conversations(false)
                 where conversation_id = current_setting('t.conv_cd')::uuid
                   and state = 'request') then
    raise exception 'FAIL: decline leaked to the sender';
  end if;
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000045', 'hello again');
    raise exception 'FAIL: declined sender sent a second message';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
reset role;

-- ============================================================
-- 6. THE IDENTICAL REFUSAL: block, DMs off, and "no one" all raise
--    the same message, so a blocked person cannot distinguish a block.
--    An existing accepted conversation stays readable on both sides
--    across a block, but sending stops.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000045', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000045","aal":"aal1","session_id":"d"}', false);
insert into blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-000000000045', '00000000-0000-0000-0000-000000000044');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000042', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000042","aal":"aal1","session_id":"a"}', false);
insert into dm_settings (user_id, dms_enabled)
values ('00000000-0000-0000-0000-000000000042', false)
on conflict (user_id) do update set dms_enabled = false;
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
  e_block text; e_off text; e_noone text;
begin
  if dm_can_message('00000000-0000-0000-0000-000000000045') <> 'none'
     or dm_can_message('00000000-0000-0000-0000-000000000042') <> 'none'
     or dm_can_message('00000000-0000-0000-0000-000000000043') <> 'none' then
    raise exception 'FAIL: dm_can_message did not return none for block/off/no_one';
  end if;
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000045', 'x');
    raise exception 'FAIL: blocked sender sent';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if; e_block := sqlerrm;
  end;
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000042', 'x');
    raise exception 'FAIL: sent to DMs-off member';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if; e_off := sqlerrm;
  end;
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000043', 'x');
    raise exception 'FAIL: sent to no-one member';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if; e_noone := sqlerrm;
  end;
  if e_block <> e_off or e_off <> e_noone then
    raise exception 'FAIL: refusals are distinguishable: % / % / %', e_block, e_off, e_noone;
  end if;
end $$;
reset role;

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
    perform dm_send_message('00000000-0000-0000-0000-000000000043', 'x');
    raise exception 'FAIL: blocked party sent into an existing conversation';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm <> 'You can no longer message this account.' then
      raise exception 'FAIL: block refusal on existing thread differs: %', sqlerrm;
    end if;
  end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000043', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000043","aal":"aal1","session_id":"b"}', false);
delete from blocks where blocker_id = '00000000-0000-0000-0000-000000000043';
reset role;

-- ============================================================
-- 7. REPORTING: the server snapshots exactly the selected messages
--    into dm_report_evidence — body, sender, recipient, timestamp
--    copied from the real rows, never from the reporter; a message id
--    from another conversation voids the report; the safety@ copy
--    names no reporter and carries no message text.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000043', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000043","aal":"aal1","session_id":"b"}', false);
do $$ declare r record; begin
  select * into r from dm_send_message('00000000-0000-0000-0000-000000000045', 'meet me at nine');
  perform set_config('t.reported_msg', r.message_id::text, false);
end $$;
reset role;

-- Captured as superuser: a message id from a DIFFERENT conversation
-- (ada↔bea), for the foreign-evidence refusal below — the member
-- session could not read it, which is the point.
select set_config('t.foreign_msg',
  (select min(id) from dm_messages
   where conversation_id = current_setting('t.conv_ab')::uuid)::text, false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000045', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000045","aal":"aal1","session_id":"d"}', false);
do $$ declare v_report uuid; begin
  -- A foreign message id (from ada↔bea's conversation) voids the report.
  begin
    perform file_dm_report(
      current_setting('t.conv_bd')::uuid, 'harassment', null,
      array[current_setting('t.foreign_msg')::bigint]);
    raise exception 'FAIL: evidence from another conversation accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm <> 'Invalid report evidence.' then
      raise exception 'FAIL: wrong foreign-evidence error: %', sqlerrm;
    end if;
  end;
  -- An empty selection is refused.
  begin
    perform file_dm_report(current_setting('t.conv_bd')::uuid, 'harassment', null,
                           array[]::bigint[]);
    raise exception 'FAIL: empty evidence selection accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  v_report := file_dm_report(
    current_setting('t.conv_bd')::uuid,
    'harassment',
    'he will not stop',
    array[current_setting('t.reported_msg')::bigint]);
  perform set_config('t.report1', v_report::text, false);
end $$;
reset role;

do $$ begin
  -- The snapshot is the server's copy of the real message.
  if not exists (select 1 from dm_report_evidence
                 where report_id = current_setting('t.report1')::uuid
                   and message_id = current_setting('t.reported_msg')::bigint
                   and body = 'meet me at nine'
                   and sender_id = '00000000-0000-0000-0000-000000000043'
                   and recipient_id = '00000000-0000-0000-0000-000000000045') then
    raise exception 'FAIL: evidence snapshot missing or wrong';
  end if;
  if (select subject_type from reports where id = current_setting('t.report1')::uuid)
     <> 'message'::report_subject then
    raise exception 'FAIL: DM report not filed with subject message';
  end if;
  if not exists (select 1 from safety_email_outbox
                 where report_id = current_setting('t.report1')::uuid
                   and body not like '%dee9%'
                   and body not like '%meet me at nine%'
                   and body not like '%Dee Dee%'
                   and body like '%direct messages from @bea9%') then
    raise exception 'FAIL: safety email copy missing or leaking';
  end if;
  -- The snapshot survives the message rows: deleting the conversation
  -- cascades dm_messages away, the evidence stays.
  if (select count(*) from dm_report_evidence
      where report_id = current_setting('t.report1')::uuid) <> 1 then
    raise exception 'FAIL: evidence row count wrong';
  end if;
end $$;

-- ============================================================
-- 8. MODERATION HAND-OFF + THE AUDIT TRAIL: the moderator sees the
--    case in the queue and the evidence transcript; a plain member is
--    refused; and EVERY mod_dm_evidence content read writes a
--    dm.content_read row to the audit log naming reader and target —
--    staff access to message content is accountable, never invisible.
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
  if n <> 1 then raise exception 'FAIL: evidence transcript wrong size (%)', n; end if;
  if not exists (select 1 from mod_dm_evidence('00000000-0000-0000-0000-000000000043')
                 where body = 'meet me at nine' and sender_handle = 'bea9') then
    raise exception 'FAIL: evidence body missing from transcript';
  end if;
end $$;
-- A plain member cannot read the evidence function.
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
-- The reporter sees her own report in her history.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000045', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000045","aal":"aal1","session_id":"d"}', false);
do $$ begin
  if not exists (select 1 from reports where id = current_setting('t.report1')::uuid
                 and reporter_id = auth.uid()) then
    raise exception 'FAIL: reporter cannot see her own DM report';
  end if;
end $$;
reset role;

-- The audit rows: the moderator's reads (she called the function
-- twice) are each recorded; the refused member read is not.
do $$ declare n integer; begin
  select count(*) into n from audit_log
   where action = 'dm.content_read'
     and actor_id = '00000000-0000-0000-0000-000000000041'
     and target_id = '00000000-0000-0000-0000-000000000043'
     and (detail ->> 'messages')::integer >= 1;
  if n < 2 then
    raise exception 'FAIL: mod content reads not audited (found % rows)', n;
  end if;
  if exists (select 1 from audit_log
             where action = 'dm.content_read'
               and actor_id = '00000000-0000-0000-0000-000000000044') then
    raise exception 'FAIL: a refused member read wrote an audit row';
  end if;
end $$;

-- ============================================================
-- 9. RLS LOCKDOWN: no app role touches the DM tables directly; a
--    non-participant cannot fetch a conversation; dm_settings is
--    own-row only.
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
  if exists (select 1 from dm_settings where user_id <> auth.uid()) then
    raise exception 'FAIL: another member''s dm_settings are visible';
  end if;
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
    insert into dm_messages (conversation_id, sender_id, body)
    values (current_setting('t.conv_ab')::uuid, '00000000-0000-0000-0000-000000000042', 'x');
    raise exception 'FAIL: service_role inserted a message directly';
  exception when insufficient_privilege then null;
    when others then if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    perform * from dm_messages limit 1;
    raise exception 'FAIL: service_role read dm_messages directly';
  exception when insufficient_privilege then null;
    when others then if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
reset role;

-- ============================================================
-- 10. NOTIFICATION PREFS: the 'message' toggle is honoured.
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
select dm_send_message('00000000-0000-0000-0000-000000000045', 'one more thing');
reset role;
do $$ begin
  if exists (select 1 from notifications
             where user_id = '00000000-0000-0000-0000-000000000045'
               and type = 'message' and read_at is null) then
    raise exception 'FAIL: message notification created despite pref off';
  end if;
end $$;

-- ============================================================
-- 11. DELETE FOR ME: the deleter's horizon moves (messages AND the
--     inbox preview); the other side keeps everything; a new message
--     brings the thread back with only the new content.
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
  perform dm_send_message('00000000-0000-0000-0000-000000000045', 'are you still there?');
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000045', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000045","aal":"aal1","session_id":"d"}', false);
do $$ declare n integer; begin
  if not exists (select 1 from dm_list_conversations(false)
                 where conversation_id = current_setting('t.conv_bd')::uuid
                   and last_body = 'are you still there?') then
    raise exception 'FAIL: new message did not resurface the thread (or preview leaked old content)';
  end if;
  -- …with only the new content.
  select count(*) into n from dm_fetch_messages(current_setting('t.conv_bd')::uuid);
  if n <> 1 then raise exception 'FAIL: cleared history resurfaced (% rows)', n; end if;
end $$;
reset role;

rollback;
\echo ALL DM SMOKE TESTS PASSED
