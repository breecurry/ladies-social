-- Behavioral smoke test of Phase 1 security invariants (local only).
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

-- Seed auth users
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000002', 'member@test'),
  ('00000000-0000-0000-0000-000000000003', 'applicant1@test'),
  ('00000000-0000-0000-0000-000000000004', 'applicant2@test'),
  ('00000000-0000-0000-0000-000000000005', 'applicant3@test'),
  ('00000000-0000-0000-0000-000000000006', 'mod@test');

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

-- 4. service_role holds NO write privilege on role_assignments.
set role service_role;
do $$ begin
  begin
    insert into role_assignments (user_id, role, granted_by)
    values ('00000000-0000-0000-0000-000000000002', 'admin', '00000000-0000-0000-0000-000000000001');
    raise exception 'FAIL: service_role inserted a role';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- 5. Signup: applicant1 names the owner (resolves, cap ok) -> awaiting_vouch + vouch request.
select create_application('00000000-0000-0000-0000-000000000003', 'applicant1@test', 'Ada Applicant',
  '1995-05-05', 'ada', '+15550000003', 'bree', '203.0.113.5', null, '{"score":0}'::jsonb, 'clean');
do $$ declare s admission_status; n int; begin
  select status into s from admission_applications where user_id = '00000000-0000-0000-0000-000000000003';
  if s <> 'awaiting_vouch' then raise exception 'FAIL: expected awaiting_vouch, got %', s; end if;
  select count(*) into n from vouch_requests where applicant_user_id = '00000000-0000-0000-0000-000000000003' and status='pending';
  if n <> 1 then raise exception 'FAIL: expected 1 vouch request, got %', n; end if;
end $$;

-- 6. Signup: applicant2 names a NONEXISTENT handle -> queued, no request, NO ERROR.
select create_application('00000000-0000-0000-0000-000000000004', 'applicant2@test', 'Bea Applicant',
  '1995-05-05', 'bea', '+15550000004', 'nosuchmember', '203.0.113.6', null, '{"score":0}'::jsonb, 'clean');
do $$ declare s admission_status; n int; begin
  select status into s from admission_applications where user_id = '00000000-0000-0000-0000-000000000004';
  if s <> 'queued' then raise exception 'FAIL: expected queued, got %', s; end if;
  select count(*) into n from vouch_requests where applicant_user_id = '00000000-0000-0000-0000-000000000004';
  if n <> 0 then raise exception 'FAIL: unexpected vouch request'; end if;
end $$;

-- 7. Applicant-side status is identical for both lanes ('pending').
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
do $$ declare st text; begin
  select status into st from my_application_status();
  if st <> 'pending' then raise exception 'FAIL: lane1 applicant sees %', st; end if;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
do $$ declare st text; begin
  select status into st from my_application_status();
  if st <> 'pending' then raise exception 'FAIL: lane2 applicant sees %', st; end if;
end $$;
-- Applicant cannot read her own application row or any vouch_requests.
do $$ declare n int; begin
  select count(*) into n from admission_applications;
  if n <> 0 then raise exception 'FAIL: applicant can read applications'; end if;
  select count(*) into n from vouch_requests;
  if n <> 0 then raise exception 'FAIL: applicant can read vouch requests'; end if;
end $$;

-- 8. Owner confirms the vouch (Owner vouch = auto-admit) -> admitted_vouched.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal1","session_id":"sess-owner"}', false);
do $$ declare rid uuid; s admission_status; tl trust_level; begin
  select id into rid from vouch_requests where applicant_user_id = '00000000-0000-0000-0000-000000000003' and status='pending';
  perform confirm_vouch(rid);
  select status into s from admission_applications where user_id = '00000000-0000-0000-0000-000000000003';
  if s <> 'admitted_vouched' then raise exception 'FAIL: expected admitted_vouched, got %', s; end if;
  select trust_level into tl from profiles where user_id = '00000000-0000-0000-0000-000000000003';
  if tl <> 'member' then raise exception 'FAIL: trust level %', tl; end if;
end $$;
reset role;

-- 9. grant_role requires AAL2: fails at aal1, succeeds at aal2.
set role authenticated;
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
reset role;

-- 10. auto_admit privilege: owner grants to the new moderator; her vouch then auto-admits.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"sess-owner"}', false);
select grant_privilege('00000000-0000-0000-0000-000000000003', 'auto_admit');
reset role;
select create_application('00000000-0000-0000-0000-000000000005', 'applicant3@test', 'Cat Applicant',
  '1995-05-05', 'cat', '+15550000005', 'ada', '203.0.113.7', null, '{"score":0}'::jsonb, 'clean');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"s3"}', false);
do $$ declare rid uuid; s admission_status; begin
  select id into rid from vouch_requests where applicant_user_id = '00000000-0000-0000-0000-000000000005' and status='pending';
  perform confirm_vouch(rid);
  select status into s from admission_applications where user_id = '00000000-0000-0000-0000-000000000005';
  if s <> 'admitted_vouched' then raise exception 'FAIL: auto_admit vouch did not admit (%)', s; end if;
end $$;
reset role;

-- 11. Audit log: populated, chain verifies, tamper is detected, immutable.
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

-- 12. Daily vouch-request cap: the 6th naming of the same member in 24h
--     silently becomes Lane 2.
do $$ declare i int; uid uuid; s admission_status; begin
  for i in 10..15 loop
    uid := ('00000000-0000-0000-0000-0000000000' || i)::uuid;
    insert into auth.users (id, email) values (uid, 'bulk' || i || '@test');
    perform create_application(uid, ('bulk' || i || '@test')::citext, 'Bulk ' || i,
      '1995-05-05', ('bulk' || i)::citext, '+1555000' || (1000 + i), 'bree',
      '198.51.100.9', null, '{"score":0}'::jsonb, 'clean');
  end loop;
  -- 5 allowed -> awaiting_vouch; the 6th -> queued
  select status into s from admission_applications where user_id = '00000000-0000-0000-0000-000000000015';
  if s <> 'queued' then raise exception 'FAIL: cap not enforced (%)', s; end if;
end $$;

-- 13. Auto-rejected applications are invisible to the reviewer queue (even Owner).
do $$ declare uid uuid := '00000000-0000-0000-0000-000000000020'; begin
  insert into auth.users (id, email) values (uid, 'bot@test');
  perform create_application(uid, 'bot@test', 'Bot Bot', '1995-05-05', 'botbot',
    '+15550000020', null, '198.51.100.10', null, '{"score":1}'::jsonb, 'auto_rejected');
end $$;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"sess-owner"}', false);
do $$ declare n int; st text; begin
  select count(*) into n from admission_applications where triage_bucket = 'auto_rejected';
  if n <> 0 then raise exception 'FAIL: owner can see auto-rejected rows'; end if;
end $$;
-- ...and the bot sees the same 'pending' as everyone else (no oracle).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000020', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000020","aal":"aal1","session_id":"sb"}', false);
do $$ declare st text; begin
  select status into st from my_application_status();
  if st <> 'pending' then raise exception 'FAIL: auto-rejected applicant sees %', st; end if;
end $$;
reset role;

-- 14. Review actions: approve one of the queued bulk applicants; reject another.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"sess-owner"}', false);
do $$ declare app1 uuid; app2 uuid; s admission_status; tl trust_level; begin
  select id into app1 from admission_applications where user_id = '00000000-0000-0000-0000-000000000015';
  perform review_approve(app1, 'looks fine');
  select status into s from admission_applications where id = app1;
  if s <> 'admitted_reviewed' then raise exception 'FAIL: approve -> %', s; end if;
  select trust_level into tl from profiles where user_id = '00000000-0000-0000-0000-000000000015';
  if tl <> 'member' then raise exception 'FAIL: approved trust %', tl; end if;

  select a.id into app2 from admission_applications a where a.user_id = '00000000-0000-0000-0000-000000000004';
  perform review_reject(app2, 'incoherent');
  select status into s from admission_applications where id = app2;
  if s <> 'rejected' then raise exception 'FAIL: reject -> %', s; end if;
end $$;
-- Moderator (ts read path) cannot decide: applicant 'cat' is admitted; use a queued one.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal2","session_id":"s3"}', false);
do $$ declare app uuid; begin
  select id into app from admission_applications where status = 'queued' limit 1;
  begin
    perform review_approve(app, null);
    raise exception 'FAIL: moderator decided an application';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
reset role;

-- 15. display_name can only be NULL or the verified legal name.
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
  if d <> 'Ada Applicant' then raise exception 'FAIL: opt-in display name %', d; end if;
end $$;
select set_display_name_visibility(false);
reset role;

-- 16. Pending applicants cannot browse profiles.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000011', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000011","aal":"aal1","session_id":"sp"}', false);
do $$ declare n int; begin
  select count(*) into n from profiles where user_id <> '00000000-0000-0000-0000-000000000011';
  if n <> 0 then raise exception 'FAIL: pending applicant can browse % profiles', n; end if;
end $$;
reset role;

-- 17. Vouch lapse: force a deadline into the past and run the job.
do $$ declare n int; begin
  update vouch_requests set deadline = now() - interval '1 hour' where status = 'pending';
  select lapse_expired_vouch_requests() into n;
  if n < 1 then raise exception 'FAIL: lapse job processed nothing'; end if;
  if exists (select 1 from admission_applications where status = 'awaiting_vouch') then
    raise exception 'FAIL: awaiting_vouch rows survived the lapse job';
  end if;
end $$;

rollback;
\echo ALL SMOKE TESTS PASSED
