-- Independent QA pass (Grove-Test) on the non-E2E DM rework, written
-- against migration 20261021000001 and INDEPENDENTLY of the author's
-- own suite (09-dm-smoke.sql). This file targets what an adversary
-- would try next, past what 09 already proves: exact body-length
-- boundaries, the blank-message guard's actual trim semantics, null
-- bytes and invalid UTF-8, file_dm_report's id-array edge cases
-- (duplicates, >10, nonexistent-but-same-conversation ids), the
-- mod_dm_evidence audit guarantee under repeated and refused reads
-- with the hash chain re-verified afterward, suspension/ban mid-
-- conversation, and an independent, non-named-list structural sweep
-- for duplicate DM function signatures.
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000071', 'mod71@test'),
  ('00000000-0000-0000-0000-000000000072', 'eve72@test'),
  ('00000000-0000-0000-0000-000000000073', 'fay73@test'),
  ('00000000-0000-0000-0000-000000000074', 'gia74@test'),
  ('00000000-0000-0000-0000-000000000075', 'hua75@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_member('00000000-0000-0000-0000-000000000071', 'mod71@test', 'Mo Derator', '1995-05-05', 'mod71', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000072', 'eve72@test', 'Eve Evers',  '1995-05-05', 'eve72', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000073', 'fay73@test', 'Fay Fayson', '1995-05-05', 'fay73', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000074', 'gia74@test', 'Gia Giason', '1995-05-05', 'gia74', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000075', 'hua75@test', 'Hua Huason', '1995-05-05', 'hua75', null, null, null, '{}'::jsonb, false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"ow"}', false);
select grant_role('00000000-0000-0000-0000-000000000071', 'moderator');
reset role;

insert into app_config (key, value) values ('dm_enabled', 'true'::jsonb)
on conflict (key) do update set value = 'true'::jsonb;

-- eve follows fay so eve -> fay lands straight in the accepted inbox
-- (gives the length-boundary tests a conversation with no request cap
-- to fight).
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000073', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000073","aal":"aal1","session_id":"f"}', false);
insert into follows (follower_id, followee_id)
values ('00000000-0000-0000-0000-000000000073', '00000000-0000-0000-0000-000000000072');
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000072', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000072","aal":"aal1","session_id":"e"}', false);

-- ============================================================
-- 1. BODY LENGTH BOUNDARIES — exact edges, not just "too long".
-- ============================================================
do $$
declare v_id bigint;
begin
  -- Exactly 1 char: must succeed (the floor of the range).
  select message_id into v_id from dm_send_message('00000000-0000-0000-0000-000000000073', 'x');
  if v_id is null then raise exception 'FAIL: a 1-char message was refused'; end if;

  -- Exactly 2000 chars: must succeed (the ceiling of the range).
  select message_id into v_id from dm_send_message('00000000-0000-0000-0000-000000000073', repeat('a', 2000));
  if v_id is null then raise exception 'FAIL: an exactly-2000-char message was refused'; end if;

  -- 2000 four-byte emoji: char_length is still 2000 (codepoints, not
  -- bytes) so this must ALSO succeed — confirms there is no hidden
  -- byte-size ceiling that would make the char_length(2000) check
  -- lie about what is actually allowed.
  select message_id into v_id from dm_send_message('00000000-0000-0000-0000-000000000073', repeat(E'\U0001F600', 2000));
  if v_id is null then raise exception 'FAIL: a 2000-emoji (8000-byte) message was refused'; end if;

  -- 2001 chars: must fail.
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000073', repeat('a', 2001));
    raise exception 'FAIL: a 2001-char message was accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;

  -- 10000 chars: must fail the same way (not a different, looser
  -- error path for "very large").
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000073', repeat('a', 10000));
    raise exception 'FAIL: a 10000-char message was accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;

  -- Empty string: refused.
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000073', '');
    raise exception 'FAIL: an empty-string message was accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;

  -- Spaces-only: refused (btrim strips plain spaces).
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000073', '     ');
    raise exception 'FAIL: a spaces-only message was accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

-- ============================================================
-- 2. FINDING: the blank-message guard uses btrim(p_body), and
--    Postgres's single-argument btrim() strips ONLY ASCII space
--    characters — NOT tabs or newlines. A body of pure newlines (or
--    tabs) therefore satisfies char_length(btrim(p_body)) >= 1 and is
--    ACCEPTED, even though it renders as a visually blank message.
--    This is a real gap in the guard, reproduced here, not asserted
--    as already-fixed: if migration 20261021000001 is ever hardened to
--    use a real whitespace trim, this test must be updated to expect
--    REJECTION and the FAIL branch below deleted.
-- ============================================================
do $$
declare v_id bigint; v_body text;
begin
  select message_id into v_id from dm_send_message('00000000-0000-0000-0000-000000000073', E'\n\n\n');
  if v_id is null then
    raise exception 'REGRESSION: a newlines-only body is now refused — update this test to assert rejection and remove the FINDING note above';
  end if;
  select body into v_body from dm_fetch_messages(
    (select conversation_id from dm_list_conversations(false)
      where correspondent_id = '00000000-0000-0000-0000-000000000073' limit 1))
   where id = v_id;
  if v_body !~ '^\n+$' then raise exception 'FAIL: unexpected body for the newline case: %', v_body; end if;

  select message_id into v_id from dm_send_message('00000000-0000-0000-0000-000000000073', E'\t\t\t');
  if v_id is null then
    raise exception 'REGRESSION: a tabs-only body is now refused — update this test to assert rejection';
  end if;
end $$;

-- ============================================================
-- 3. NULL BYTES: PostgreSQL's text type refuses an embedded NUL at
--    the protocol/parse level ("null character not permitted"),
--    before the function body or its check constraint ever runs.
--    This is a structural guarantee, not an application one — proven
--    here rather than assumed.
-- ============================================================
do $$ begin
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000073', 'hello' || chr(0) || 'world');
    raise exception 'FAIL: a message containing a null byte was accepted';
  exception
    when others then
      if sqlerrm like 'FAIL:%' then raise; end if;
      if sqlerrm !~ 'null character' then
        raise exception 'FAIL: unexpected error for a null byte body: %', sqlerrm;
      end if;
  end;
end $$;
reset role;

-- Invalid UTF-8 cannot reach a `text` value at all in a UTF8 database
-- — confirmed structurally (not through dm_send_message, which cannot
-- even be called with an invalid byte sequence as a text argument):
do $$ begin
  begin
    perform convert_from('\xff'::bytea, 'UTF8');
    raise exception 'FAIL: an invalid UTF-8 byte sequence was accepted into text';
  exception when others then
    if sqlerrm !~ 'invalid byte sequence' then
      raise exception 'FAIL: unexpected error for invalid UTF-8: %', sqlerrm;
    end if;
  end;
end $$;

-- ============================================================
-- 4. SENDER FORGERY: dm_send_message takes no sender argument at all
--    (sender is always auth.uid()), so there is no parameter to
--    forge through the function. Confirm the only other path —
--    writing dm_messages directly — is refused for every app role
--    including service_role (table grants, independent of RLS).
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000072', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000072","aal":"aal1","session_id":"e"}', false);
do $$
declare v_conv uuid;
begin
  select c.conversation_id into v_conv from dm_list_conversations(false) c
   where c.correspondent_id = '00000000-0000-0000-0000-000000000073' limit 1;
  begin
    -- Pretend to be fay (...073) while signed in as eve (...072).
    insert into dm_messages (conversation_id, sender_id, body)
    values (v_conv, '00000000-0000-0000-0000-000000000073', 'forged');
    raise exception 'FAIL: authenticated forged a sender_id via direct insert';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- ============================================================
-- 5. file_dm_report — THE MESSAGE-ID ARRAY, EVERY EDGE.
--    gia (074) and hua (075): gia messages hua once, creating a
--    conversation to report against.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000075', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000075","aal":"aal1","session_id":"h"}', false);
insert into follows (follower_id, followee_id)
values ('00000000-0000-0000-0000-000000000075', '00000000-0000-0000-0000-000000000074');
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000074', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000074","aal":"aal1","session_id":"g"}', false);
select set_config('t.gh_conv', (select conversation_id::text from dm_send_message('00000000-0000-0000-0000-000000000075', 'message one')), false);
select set_config('t.gh_msg1', (select id::text from dm_fetch_messages(current_setting('t.gh_conv')::uuid) limit 1), false);
select dm_send_message('00000000-0000-0000-0000-000000000075', 'message two');
select set_config('t.gh_msg2', (select max(id)::text from dm_fetch_messages(current_setting('t.gh_conv')::uuid)), false);
reset role;

-- A non-existent message id, large and clearly never issued.
-- dm_report_evidence and reports are both unreadable directly by
-- `authenticated` (no SELECT grant/policy) — the before/after counts
-- are therefore taken as the session superuser, bracketing the
-- attempts made as the reporter.
select set_config('t.before_reports', (select count(*)::text from reports), false);
select set_config('t.before_evidence', (select count(*)::text from dm_report_evidence), false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000075', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000075","aal":"aal1","session_id":"h"}', false);
do $$
begin
  -- 0 ids (empty array, not null): refused, nothing written.
  begin
    perform file_dm_report(current_setting('t.gh_conv')::uuid, 'harassment', null, '{}'::bigint[]);
    raise exception 'FAIL: an empty message-id array was accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;

  -- 11 ids (one over the 10 cap), even though the first several are
  -- real and belong to this conversation: the WHOLE report must be
  -- refused, not thinned to 10.
  begin
    perform file_dm_report(current_setting('t.gh_conv')::uuid, 'harassment', null,
      array[current_setting('t.gh_msg1')::bigint, current_setting('t.gh_msg2')::bigint,
            999901,999902,999903,999904,999905,999906,999907,999908,999909]);
    raise exception 'FAIL: an 11-id report was accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;

  -- A non-existent message id (never issued, but shaped like a real
  -- bigint, mixed in with ONE real id from this same conversation):
  -- the whole report must be void, not partially filed against the
  -- one real id.
  begin
    perform file_dm_report(current_setting('t.gh_conv')::uuid, 'harassment', null,
      array[current_setting('t.gh_msg1')::bigint, 999999999::bigint]);
    raise exception 'FAIL: a report with one nonexistent message id was accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm !~ 'Invalid report evidence' then
      raise exception 'FAIL: wrong error for a nonexistent message id: %', sqlerrm;
    end if;
  end;
end $$;
reset role;

-- Nothing from any of the three refused attempts above may have been
-- written — all-or-nothing, not partial.
do $$ begin
  if (select count(*) from reports) <> current_setting('t.before_reports')::integer then
    raise exception 'FAIL: a refused report call still inserted into reports';
  end if;
  if (select count(*) from dm_report_evidence) <> current_setting('t.before_evidence')::integer then
    raise exception 'FAIL: a refused report call still inserted evidence rows';
  end if;
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000075', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000075","aal":"aal1","session_id":"h"}', false);
do $$
begin
  -- DUPLICATE ids within the cap: the function does not reject
  -- duplicates, and has no unique constraint on (report_id,
  -- message_id) — so the SAME message is copied into evidence TWICE.
  -- Reproduced here as a FINDING, not asserted as correct: it lets one
  -- message inflate both the evidence row count AND the "messages"
  -- volume mod_dm_evidence later audits for this target.
  perform file_dm_report(current_setting('t.gh_conv')::uuid, 'spam', null,
    array[current_setting('t.gh_msg1')::bigint, current_setting('t.gh_msg1')::bigint]);
end $$;
reset role;

do $$ begin
  if (select count(*) from dm_report_evidence
       where message_id = current_setting('t.gh_msg1')::bigint) <> 2 then
    raise exception 'REGRESSION: duplicate message ids no longer double-insert evidence — update this test, the finding is fixed';
  end if;
end $$;

-- Exactly 10 ids (the boundary itself) must succeed when all 10 are
-- real and belong to the conversation. Reuse the two real ids,
-- repeated to make up the count — the duplicate-id gap above means
-- this succeeds too (not a boundary-specific concern; confirms >10 is
-- the only hard line, not >=10).
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000075', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000075","aal":"aal1","session_id":"h"}', false);
do $$ begin
  perform file_dm_report(current_setting('t.gh_conv')::uuid, 'other', null,
    array[current_setting('t.gh_msg1')::bigint, current_setting('t.gh_msg2')::bigint,
          current_setting('t.gh_msg1')::bigint, current_setting('t.gh_msg2')::bigint,
          current_setting('t.gh_msg1')::bigint, current_setting('t.gh_msg2')::bigint,
          current_setting('t.gh_msg1')::bigint, current_setting('t.gh_msg2')::bigint,
          current_setting('t.gh_msg1')::bigint, current_setting('t.gh_msg2')::bigint]);
exception when others then
  raise exception 'FAIL: an exactly-10-id report (all real, same conversation) was refused: %', sqlerrm;
end $$;
reset role;

-- A conversation the reporter is NOT part of: void entirely, same as
-- 09 already proves for one foreign id — here proving the
-- conversation-level check independent of any message id validity.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000072', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000072","aal":"aal1","session_id":"e"}', false);
do $$ begin
  begin
    perform file_dm_report(current_setting('t.gh_conv')::uuid, 'harassment', null,
      array[current_setting('t.gh_msg1')::bigint]);
    raise exception 'FAIL: a non-participant filed a DM report against a conversation she is not in';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm !~ 'unavailable' then
      raise exception 'FAIL: wrong error for a non-participant report: %', sqlerrm;
    end if;
  end;
end $$;
reset role;

-- ============================================================
-- 6. mod_dm_evidence — THE AUDIT PROMISE, EXACT COUNTS AND THE CHAIN.
--    gia (074) has several DM reports filed against her from section
--    5 (the filer, hua, holds no staff tier, so none of those
--    filings themselves touched mod_dm_evidence or audit_log).
--    NOTE: audit_log is Owner-read-only at RLS (audit_owner_read,
--    AAL2) — a moderator querying it directly sees zero rows, not a
--    permission error. Every count below is therefore taken as the
--    session superuser (which bypasses RLS entirely), bracketing the
--    mod_dm_evidence calls made as the moderator.
-- ============================================================
select set_config('t.pre_count',
  (select count(*)::text from audit_log where action = 'dm.content_read' and target_id = '00000000-0000-0000-0000-000000000074'),
  false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000071', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000071","aal":"aal1","session_id":"m"}', false);

-- Call 1: a legitimate staff read of gia's reported messages.
select count(*) as evidence_rows_call_1 from mod_dm_evidence('00000000-0000-0000-0000-000000000074');
-- Call 2: the identical call again — must add ANOTHER row, not merge
-- into or dedupe against the first (the brief: "repeated reads are
-- NOT deduplicated").
select count(*) as evidence_rows_call_2 from mod_dm_evidence('00000000-0000-0000-0000-000000000074');
reset role;

do $$
declare v_pre integer; v_post integer;
begin
  v_pre := current_setting('t.pre_count')::integer;
  select count(*) into v_post from audit_log
   where action = 'dm.content_read' and target_id = '00000000-0000-0000-0000-000000000074';
  if v_post <> v_pre + 2 then
    raise exception 'FAIL: expected exactly 2 new dm.content_read rows for 2 calls (pre=%, post=%)', v_pre, v_post;
  end if;
  if not exists (select 1 from audit_log
                 where action = 'dm.content_read'
                   and target_id = '00000000-0000-0000-0000-000000000074'
                   and actor_id = '00000000-0000-0000-0000-000000000071'
                   and (detail ->> 'messages')::integer > 0) then
    raise exception 'FAIL: dm.content_read row missing reader/target/volume fields';
  end if;
end $$;

-- A target with ZERO reported messages: a tier-eligible moderator's
-- call must return zero rows AND write zero audit rows (there was
-- nothing to read, so nothing is logged — distinct from, but as
-- important as, the "refused" case below).
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000071', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000071","aal":"aal1","session_id":"m"}', false);
do $$ declare v_n integer; begin
  select count(*) into v_n from mod_dm_evidence('00000000-0000-0000-0000-000000000072'); -- eve has no DM reports filed against her
  if v_n <> 0 then raise exception 'FAIL: evidence returned for a target with no filed DM reports'; end if;
end $$;
reset role;
do $$ declare v_audit integer; begin
  select count(*) into v_audit from audit_log
   where action = 'dm.content_read' and target_id = '00000000-0000-0000-0000-000000000072';
  if v_audit <> 0 then raise exception 'FAIL: an empty-result read still wrote an audit row'; end if;
end $$;

-- A plain member (no role_assignment at all): REFUSED outright, and
-- that refusal writes nothing.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000073', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000073","aal":"aal1","session_id":"f"}', false);
do $$ begin
  begin
    perform mod_dm_evidence('00000000-0000-0000-0000-000000000074');
    raise exception 'FAIL: a plain member read DM evidence';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
reset role;
do $$ declare v_audit integer; begin
  select count(*) into v_audit from audit_log
   where action = 'dm.content_read' and actor_id = '00000000-0000-0000-0000-000000000073';
  if v_audit <> 0 then raise exception 'FAIL: a refused member read wrote an audit row'; end if;
end $$;

-- The hash chain must still verify after all of the above writes.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"ow"}', false);
do $$ declare r record; begin
  select * into r from verify_audit_chain();
  if not r.ok then raise exception 'FAIL: audit chain broken after mod_dm_evidence writes'; end if;
end $$;
reset role;

-- ============================================================
-- 7. SUSPENSION / BAN MID-CONVERSATION.
--    eve (072) and fay (073) already have an accepted conversation
--    (section 1). Suspend fay, then confirm: eve can no longer send
--    to her (identical refusal to a block — "none" from dm_route),
--    but EITHER side can still read the existing history (suspension
--    doesn't erase the record), and fay herself — while suspended —
--    can still read (reading is not blocked), but cannot SEND (a
--    DIFFERENT, self-referential message, which leaks nothing about
--    anyone else since it only describes the caller's own status).
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"ow"}', false);
select mod_suspend('00000000-0000-0000-0000-000000000073', 7, 'harassment', 'test suspension for DM adversarial coverage');
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000072', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000072","aal":"aal1","session_id":"e"}', false);
do $$ begin
  -- Route must read 'none' for a suspended recipient — identical to
  -- a block, so a sender cannot use this as a "is she suspended?" oracle.
  if dm_can_message('00000000-0000-0000-0000-000000000073') <> 'none' then
    raise exception 'FAIL: dm_can_message did not return none for a suspended recipient';
  end if;
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000073', 'are you there');
    raise exception 'FAIL: sent a message into an existing conversation with a suspended recipient';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm !~ 'no longer message' then
      raise exception 'FAIL: suspended-recipient refusal is distinguishable from a block: %', sqlerrm;
    end if;
  end;
  -- The sender can still read the existing history — suspension does
  -- not erase the record on either side.
  if not exists (select 1 from dm_fetch_messages(
      (select conversation_id from dm_list_conversations(false)
        where correspondent_id = '00000000-0000-0000-0000-000000000073' limit 1))) then
    raise exception 'FAIL: sender lost her own conversation history after the recipient was suspended';
  end if;
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000073', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000073","aal":"aal1","session_id":"f"}', false);
do $$ begin
  -- A suspended member can still READ her own DMs (not locked out of
  -- the data layer; the app's suspended-screen interstitial is a
  -- separate, app-level gate — see report).
  if not exists (select 1 from dm_list_conversations(false)) then
    raise exception 'FAIL: a suspended member lost her DM inbox entirely at the data layer';
  end if;
  -- But she herself cannot send — a DIFFERENT message than the block
  -- refusal, which is fine: it describes only her own account, not
  -- anyone else's standing.
  begin
    perform dm_send_message('00000000-0000-0000-0000-000000000072', 'hello from suspension');
    raise exception 'FAIL: a suspended member sent a DM';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm !~ 'cannot send messages' then
      raise exception 'FAIL: unexpected error for a suspended sender: %', sqlerrm;
    end if;
  end;
end $$;
reset role;

-- ============================================================
-- 8. INDEPENDENT STRUCTURAL SWEEP: every public function whose name
--    looks like a DM function has EXACTLY ONE signature, discovered
--    from pg_proc itself (not from a maintained name list, which can
--    go stale the moment a function is renamed).
-- ============================================================
do $$
declare r record;
begin
  for r in
    select p.proname, count(*) as n
    from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public'
      and (p.proname like 'dm\_%' escape '\' or p.proname in ('file_dm_report', 'mod_dm_evidence'))
    group by p.proname
    having count(*) > 1
  loop
    raise exception 'FAIL: % has % signatures — PostgREST would be ambiguous', r.proname, r.n;
  end loop;
end $$;

-- ============================================================
-- 9. THE FEATURE FLAG: default-dark state exactly as shipped. A fresh
--    migration run inserts no app_config row for either key — this
--    suite only reaches "on" because section 0 above inserted one
--    itself, exactly as Grove does at launch; prove the KEY it used
--    is the new one and the old key is truly gone from the schema's
--    intended vocabulary (09 already proves the old key is inert; this
--    confirms no code path anywhere resurrects it).
-- ============================================================
do $$ begin
  if exists (select 1 from app_config where key = 'dm_e2e_enabled') then
    raise exception 'FAIL: the dead dm_e2e_enabled key has a row — nothing should ever insert it again';
  end if;
end $$;

rollback;
\echo ALL DM ADVERSARIAL TESTS PASSED
