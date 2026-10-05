-- Behavioral smoke test of the security invariants (local only).
-- Covers: owner-only role grants (trigger + REVOKE + AAL2), open
-- signup via create_member (18+, ban-evasion refusal, member-on-arrival),
-- audit-log immutability and tamper detection, the display-name
-- trigger, profile RLS for active vs banned accounts, and schema
-- hygiene (the admission system is actually gone).
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

-- Seed auth users
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000002', 'member@test'),
  ('00000000-0000-0000-0000-000000000003', 'ada@test'),
  ('00000000-0000-0000-0000-000000000004', 'bea@test'),
  ('00000000-0000-0000-0000-000000000005', 'minor@test'),
  ('00000000-0000-0000-0000-000000000006', 'evader@test');

-- 1. Owner bootstrap works once...
select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', '+15550000001');
-- ...and refuses to run twice.
do $$ begin
  begin
    perform bootstrap_owner('00000000-0000-0000-0000-000000000002', 'bree2', 'X Y', '1990-01-01', 'x@test', null);
    raise exception 'FAIL: second bootstrap_owner succeeded';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

-- 2. Direct INSERT of a role with a non-owner grantor is rejected BY TRIGGER
--    even for a superuser session (the DB layer, not the app, says no).
do $$ begin
  begin
    insert into role_assignments (user_id, role, granted_by)
    values ('00000000-0000-0000-0000-000000000002', 'admin', '00000000-0000-0000-0000-000000000002');
    raise exception 'FAIL: non-owner grant was accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

-- 3. The owner role itself is never grantable, even by the Owner.
do $$ begin
  begin
    insert into role_assignments (user_id, role, granted_by)
    values ('00000000-0000-0000-0000-000000000002', 'owner', '00000000-0000-0000-0000-000000000001');
    raise exception 'FAIL: owner role was granted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

-- 4. service_role holds NO write privilege on role_assignments,
--    user_private, or audit_log.
set role service_role;
do $$ begin
  begin
    insert into role_assignments (user_id, role, granted_by)
    values ('00000000-0000-0000-0000-000000000002', 'admin', '00000000-0000-0000-0000-000000000001');
    raise exception 'FAIL: service_role inserted a role';
  exception when insufficient_privilege then null;
  end;
  begin
    -- (dob no longer exists — dropped by 0017, data minimisation)
    insert into user_private (user_id, legal_name, email)
    values ('00000000-0000-0000-0000-000000000002', 'X Y', 'x@test');
    raise exception 'FAIL: service_role inserted into user_private';
  exception when insufficient_privilege then null;
  end;
  begin
    update audit_log set action = 'tampered' where seq = (select min(seq) from audit_log);
    raise exception 'FAIL: service_role updated the audit log';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- 5. Open signup: create_member creates a full member immediately.
select create_member('00000000-0000-0000-0000-000000000003', 'ada@test', 'Ada Member',
  '1995-05-05', 'ada', '203.0.113.5', null, null, '{"score":0}'::jsonb, false);
do $$ declare tl trust_level; s account_status; n int; begin
  select trust_level, status into tl, s from profiles where user_id = '00000000-0000-0000-0000-000000000003';
  if tl <> 'member' then raise exception 'FAIL: new signup trust_level is %, expected member', tl; end if;
  if s <> 'active' then raise exception 'FAIL: new signup status is %, expected active', s; end if;
  select count(*) into n from user_private where user_id = '00000000-0000-0000-0000-000000000003';
  if n <> 1 then raise exception 'FAIL: user_private row missing'; end if;
  select count(*) into n from audit_log where action = 'member.signup';
  if n <> 1 then raise exception 'FAIL: signup not audit-logged'; end if;
end $$;

-- 6. Flagged signals are recorded but do NOT block the account.
select create_member('00000000-0000-0000-0000-000000000004', 'bea@test', 'Bea Member',
  '1995-05-05', 'bea', '203.0.113.6', null, null,
  '{"score":0.7,"reasons":["disposable email domain"]}'::jsonb, true);
do $$ declare tl trust_level; f jsonb; begin
  select trust_level into tl from profiles where user_id = '00000000-0000-0000-0000-000000000004';
  if tl <> 'member' then raise exception 'FAIL: flagged signup was blocked (%)', tl; end if;
  select signup_flags into f from user_private where user_id = '00000000-0000-0000-0000-000000000004';
  if f is null or f ->> 'score' <> '0.7' then raise exception 'FAIL: signup flags not recorded'; end if;
end $$;

-- 7. Under-18 signups are refused.
do $$ begin
  begin
    perform create_member('00000000-0000-0000-0000-000000000005', 'minor@test', 'Too Young',
      (current_date - interval '17 years')::date, 'minor', null, null, null, '{}'::jsonb, false);
    raise exception 'FAIL: under-18 signup accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

-- 8. Ban evasion: a banned email hash gets 'banned_identifier' and no account.
insert into banned_identifiers (kind, value_hash, reason)
values ('email_hash', '\xdeadbeef'::bytea, 'test ban');
do $$ declare n int; begin
  begin
    perform create_member('00000000-0000-0000-0000-000000000006', 'evader@test', 'Eve Evader',
      '1990-01-01', 'evader', null, '\xdeadbeef'::bytea, null, '{}'::jsonb, false);
    raise exception 'FAIL: banned identifier created an account';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm <> 'banned_identifier' then raise exception 'FAIL: wrong refusal (%)', sqlerrm; end if;
  end;
  select count(*) into n from profiles where handle = 'evader';
  if n <> 0 then raise exception 'FAIL: evader profile exists'; end if;
end $$;

-- 9. grant_role requires AAL2: fails at aal1, succeeds at aal2.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal1","session_id":"sess-owner"}', false);
do $$ begin
  begin
    perform grant_role('00000000-0000-0000-0000-000000000003', 'moderator');
    raise exception 'FAIL: grant_role succeeded at aal1';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"sess-owner"}', false);
select grant_role('00000000-0000-0000-0000-000000000003', 'moderator');
-- Non-owner calling grant_role fails even at aal2.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal2","session_id":"s2"}', false);
do $$ begin
  begin
    perform grant_role('00000000-0000-0000-0000-000000000004', 'admin');
    raise exception 'FAIL: non-owner granted a role';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
-- Revocation works and is owner-only.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"sess-owner"}', false);
select revoke_role('00000000-0000-0000-0000-000000000003', 'moderator');
do $$ declare n int; begin
  select count(*) into n from role_assignments
  where user_id = '00000000-0000-0000-0000-000000000003' and revoked_at is null;
  if n <> 0 then raise exception 'FAIL: role still active after revoke'; end if;
end $$;
reset role;

-- 10. Audit log: populated, chain verifies, tamper is detected, immutable.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"sess-owner"}', false);
do $$ declare r record; n int; begin
  select count(*) into n from audit_log;
  if n < 5 then raise exception 'FAIL: audit log too sparse (%)', n; end if;
  select * into r from verify_audit_chain();
  if not r.ok then raise exception 'FAIL: audit chain did not verify'; end if;
end $$;
do $$ declare s0 bigint; begin
  select min(seq) into s0 from audit_log;
  begin
    update audit_log set action = 'tampered' where seq = s0;
    raise exception 'FAIL: audit row updated';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from audit_log where seq = s0;
    raise exception 'FAIL: audit row deleted';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
-- Even table-privileged roles hit the immutability triggers:
do $$ declare s0 bigint; begin
  select min(seq) into s0 from audit_log;
  begin
    update audit_log set action = 'tampered' where seq = s0;
    raise exception 'FAIL: audit row updated by postgres';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
-- Tamper detection: disable the guard trigger as superuser and corrupt a row.
alter table audit_log disable trigger trg_audit_no_update;
update audit_log set detail = '{"evil": true}'::jsonb
 where seq = (select min(seq) + 1 from audit_log);
alter table audit_log enable trigger trg_audit_no_update;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"sess-owner"}', false);
do $$ declare r record; begin
  select * into r from verify_audit_chain();
  if r.ok then raise exception 'FAIL: tampering was not detected'; end if;
  if r.broken_at_seq <> (select min(seq) + 1 from audit_log) then
    raise exception 'FAIL: wrong break point %', r.broken_at_seq;
  end if;
end $$;
reset role;

-- 11. display_name can only be NULL or the verified legal name.
do $$ begin
  begin
    update profiles set display_name = 'Totally Fake Name' where handle = 'ada';
    raise exception 'FAIL: fabricated display name accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"s3"}', false);
select set_display_name_visibility(true);
do $$ declare d text; begin
  select display_name into d from profiles where user_id = '00000000-0000-0000-0000-000000000003';
  if d <> 'Ada Member' then raise exception 'FAIL: opt-in display name %', d; end if;
end $$;
select set_display_name_visibility(false);
reset role;

-- 12. Profile RLS: an active member can browse profiles the moment she
--     exists (no admission wait)...
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"s3"}', false);
do $$ declare n int; begin
  select count(*) into n from profiles where user_id <> '00000000-0000-0000-0000-000000000003';
  if n < 2 then raise exception 'FAIL: new member sees only % other profiles', n; end if;
end $$;
reset role;
-- ...and a banned account cannot browse anyone but herself.
update profiles set status = 'banned' where user_id = '00000000-0000-0000-0000-000000000004';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"s4"}', false);
do $$ declare n int; begin
  select count(*) into n from profiles where user_id <> '00000000-0000-0000-0000-000000000004';
  if n <> 0 then raise exception 'FAIL: banned account can browse % profiles', n; end if;
end $$;
reset role;

-- 13. Schema hygiene: the admission system is actually gone, and the
--     pending_vouch trap cannot return.
do $$ begin
  if to_regclass('public.vouch_requests') is not null then
    raise exception 'FAIL: vouch_requests still exists';
  end if;
  if to_regclass('public.admission_applications') is not null then
    raise exception 'FAIL: admission_applications still exists';
  end if;
  if to_regclass('public.privilege_grants') is not null then
    raise exception 'FAIL: privilege_grants still exists';
  end if;
  if exists (select 1 from pg_type where typname in ('admission_status','vouch_request_status','triage_bucket','member_privilege')) then
    raise exception 'FAIL: admission types still exist';
  end if;
  if exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
             where t.typname = 'trust_level' and e.enumlabel = 'pending_vouch') then
    raise exception 'FAIL: pending_vouch still in trust_level';
  end if;
  if (select column_default from information_schema.columns
      where table_schema = 'public' and table_name = 'profiles' and column_name = 'trust_level')
     not like '%member%' then
    raise exception 'FAIL: trust_level default is not member';
  end if;
  if exists (select 1 from app_config where key in ('vouch_requests_per_member_per_day','vouch_deadline_hours')) then
    raise exception 'FAIL: admission config knobs survived';
  end if;
end $$;

rollback;
\echo ALL SMOKE TESTS PASSED
