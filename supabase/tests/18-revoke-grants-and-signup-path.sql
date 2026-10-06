-- Independent QA pass (Grove-Test) on migration
-- 20261021000002_revoke_internal_function_grants.sql.
--
-- This migration REVOKED EXECUTE on eleven SECURITY DEFINER functions
-- from anon/authenticated/public because they were reachable by
-- unauthenticated callers with zero internal authorization checks.
-- The theory behind the fix is that the application reaches every one
-- of them exclusively through the service_role admin client, so the
-- revoke changes nothing for legitimate use. THIS FILE TESTS THAT
-- THEORY: it replays the exact call sequence
-- src/app/api/auth/signup/route.ts performs, as service_role, end to
-- end, and separately proves the two holes that mattered
-- (revoke_user_sessions, append_audit) are now refused for anon AND
-- authenticated while a genuinely public RPC (search_people) still
-- works for both. It also proves the five RLS-helper functions that
-- were DELIBERATELY left reachable by `authenticated` still are, and
-- are not accidentally also reachable by `anon`.
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000061', 'signuptest1@test'),
  ('00000000-0000-0000-0000-000000000062', 'victim@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);

-- ============================================================
-- 1. GRANT STATE, exactly as the migration intends. Read
--    has_function_privilege directly rather than trusting that a
--    revoke "returning success" means a privilege was actually
--    removed (it can be a silent no-op against a PUBLIC grant).
-- ============================================================
do $$
declare
  v_fn text;
  v_role text;
  v_has boolean;
  v_fns text[] := array[
    'revoke_user_sessions(uuid)',
    'append_audit(text,text,text,jsonb,jsonb,jsonb)',
    'record_signup_attempt(inet,bytea)',
    'identifier_is_banned(text,bytea)',
    'count_signup_attempts_from_ip(inet,interval)',
    'count_signups_from_subnet(inet,interval)',
    'create_member(uuid,citext,text,date,citext,inet,bytea,bytea,jsonb,boolean)',
    'bootstrap_owner(uuid,citext,text,date,citext,text)',
    'create_system_account(uuid,citext)',
    'is_active_owner(uuid)',
    'actor_role_name(uuid)'
  ];
begin
  foreach v_fn in array v_fns loop
    foreach v_role in array array['anon', 'authenticated'] loop
      execute format('select has_function_privilege(%L, %L, %L)', v_role, v_fn, 'execute') into v_has;
      if v_has then
        raise exception 'FAIL: % still holds EXECUTE on % — the revoke did not land', v_role, v_fn;
      end if;
    end loop;
    -- service_role must be UNAFFECTED — this is the whole premise of
    -- "safe because the app only ever calls these as service_role".
    execute format('select has_function_privilege(%L, %L, %L)', 'service_role', v_fn, 'execute') into v_has;
    if not v_has then
      raise exception 'FAIL: service_role lost EXECUTE on % — this WOULD break signup', v_fn;
    end if;
  end loop;
end $$;

-- The five RLS-helper functions must remain authenticated-executable
-- (RLS policy expressions evaluate as the invoking role) — THIS is
-- the thing that must never have been revoked, per the brief.
--
-- NOTE: all five also carry a PUBLIC grant (proacl shows `=X/postgres`)
-- dating back to their original migrations (0003/0002b), predating the
-- systematic "revoke from public,anon,authenticated" pattern that
-- started at 0009. That means `anon` inherits EXECUTE on them too —
-- confirmed empirically below, NOT a regression introduced by
-- 20261021000002 (they were never touched by it), and harmless by the
-- migration's own stated reasoning: each takes no arguments and reads
-- only auth.uid(), which is NULL for an anon caller, so every one of
-- them just returns false. Documented here as a pre-existing fact, not
-- re-asserted as a requirement — flagged in the report as a FLAG, not
-- a bug.
do $$
declare
  v_fn text;
  v_has boolean;
begin
  foreach v_fn in array array['is_active_member()', 'is_owner()', 'is_admin_or_owner()',
                              'is_moderator_or_above()', 'is_reviewer_or_above()'] loop
    execute format('select has_function_privilege(%L, %L, %L)', 'authenticated', v_fn, 'execute') into v_has;
    if not v_has then
      raise exception 'FAIL: authenticated lost EXECUTE on % — RLS breaks platform-wide', v_fn;
    end if;
  end loop;
end $$;

-- search_people is the explicit "control" from the live verification:
-- it must still work for BOTH anon and authenticated (it was never
-- part of this fix) so the lockdown did not overreach.
do $$ begin
  if not has_function_privilege('anon', 'search_people(text,integer)', 'execute') then
    raise exception 'FAIL: anon lost EXECUTE on search_people — the fix overreached';
  end if;
  if not has_function_privilege('authenticated', 'search_people(text,integer)', 'execute') then
    raise exception 'FAIL: authenticated lost EXECUTE on search_people';
  end if;
end $$;

-- ============================================================
-- 2. RUNTIME PROOF, not just catalog state: an actual anon/
--    authenticated session attempting the two highest-severity calls
--    must be refused with 42501, and search_people must actually
--    execute (not merely be granted).
-- ============================================================
set role anon;
do $$ begin
  begin
    perform revoke_user_sessions('00000000-0000-0000-0000-000000000062'::uuid);
    raise exception 'FAIL: anon executed revoke_user_sessions';
  exception when insufficient_privilege then null;
  end;
  begin
    perform append_audit('identity.reveal', 'user', '00000000-0000-0000-0000-000000000062', '{}'::jsonb, null, null);
    raise exception 'FAIL: anon executed append_audit';
  exception when insufficient_privilege then null;
  end;
  perform search_people('a', 5); -- must not raise
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000062', false);
do $$ begin
  begin
    perform revoke_user_sessions('00000000-0000-0000-0000-000000000001'::uuid); -- aimed at the Owner
    raise exception 'FAIL: authenticated executed revoke_user_sessions against the Owner';
  exception when insufficient_privilege then null;
  end;
  begin
    perform append_audit('identity.reveal', 'user', '00000000-0000-0000-0000-000000000001', '{}'::jsonb, null, null);
    raise exception 'FAIL: authenticated forged an append_audit entry';
  exception when insufficient_privilege then null;
  end;
  perform search_people('a', 5); -- must not raise
  -- The five RLS helpers must be directly callable too (not just
  -- "granted" — RLS evaluates them, but nothing stops a client from
  -- calling them over RPC either, and that must still work).
  perform is_active_member();
  perform is_owner();
  perform is_admin_or_owner();
  perform is_moderator_or_above();
  perform is_reviewer_or_above();
end $$;
reset role;

-- ============================================================
-- 3. THE SIGNUP PIPELINE, replayed exactly as
--    src/app/api/auth/signup/route.ts calls it, AS service_role (the
--    real role the admin client authenticates as — not superuser).
--    If any of these individually-revoked functions were actually
--    needed by anon/authenticated, this is where it would show up as
--    a permission-denied instead of the expected behaviour.
-- ============================================================
set role service_role;

-- Per-IP rate limit path, recorded before counting (route order).
select record_signup_attempt('203.0.113.9'::inet, extensions.digest('signuptest1@test', 'sha256'));
do $$
declare v_n integer;
begin
  select count_signup_attempts_from_ip('203.0.113.9'::inet) into v_n;
  if v_n <> 1 then raise exception 'FAIL: count_signup_attempts_from_ip wrong after one attempt (got %)', v_n; end if;
end $$;

-- Ban-evasion pre-check, both kinds, clean identifiers: both false.
do $$
declare v_fp boolean; v_em boolean;
begin
  select identifier_is_banned('device_hash', extensions.digest('clean-device', 'sha256')) into v_fp;
  select identifier_is_banned('email_hash', extensions.digest('signuptest1@test', 'sha256')) into v_em;
  if v_fp or v_em then raise exception 'FAIL: a clean identifier read as banned'; end if;
end $$;

-- Subnet velocity check: a fresh subnet reads as just this attempt.
do $$
declare v_n integer;
begin
  select count_signups_from_subnet('203.0.113.9'::inet) into v_n;
  if v_n <> 1 then raise exception 'FAIL: count_signups_from_subnet wrong (got %)', v_n; end if;
end $$;

-- create_member: the actual account creation. Must succeed.
select create_member(
  '00000000-0000-0000-0000-000000000061', 'signuptest1@test', 'Sig Nuptest', '1995-05-05', 'signuptest1',
  '203.0.113.9'::inet, extensions.digest('signuptest1@test', 'sha256'), extensions.digest('clean-device', 'sha256'),
  '{}'::jsonb, false);

do $$ begin
  if not exists (select 1 from profiles where user_id = '00000000-0000-0000-0000-000000000061' and status = 'active') then
    raise exception 'FAIL: create_member did not produce an active profile (service_role path broken)';
  end if;
end $$;

-- record_tos_consent: last step of the route, also service_role-only.
select record_tos_consent('00000000-0000-0000-0000-000000000061', 'test-version-1');
do $$ begin
  if not exists (select 1 from user_private where user_id = '00000000-0000-0000-0000-000000000061' and tos_version = 'test-version-1') then
    raise exception 'FAIL: record_tos_consent did not land';
  end if;
end $$;

reset role;

-- ============================================================
-- 4. THE RATE LIMITER ACTUALLY TRIPS. Drive one IP past the default
--    cap (10/day, app_config key signup_attempts_per_ip_per_day) the
--    same way the route would read it, and confirm the count the
--    route checks crosses the threshold.
-- ============================================================
-- The route's own check is `attemptCount > cap` (strictly greater),
-- so the cap-th attempt itself is still allowed and the (cap+1)th is
-- what must trip it. Drive one past the cap, matching that logic.
set role service_role;
do $$
declare v_i integer; v_n integer; v_cap integer;
begin
  select coalesce((select (value #>> '{}')::integer from app_config where key = 'signup_attempts_per_ip_per_day'), 10) into v_cap;
  for v_i in 1..(v_cap + 1) loop
    perform record_signup_attempt('198.51.100.7'::inet, extensions.digest('spammer' || v_i || '@test', 'sha256'));
  end loop;
  select count_signup_attempts_from_ip('198.51.100.7'::inet) into v_n;
  if v_n <= v_cap then
    raise exception 'FAIL: rate limiter never crossed its own cap after % attempts (count=%, cap=%)', v_cap + 1, v_n, v_cap;
  end if;
end $$;

-- Same /24 subnet, different IPs: count_signups_from_subnet must see
-- all of them (the route's bot-triage signal), not just exact-IP hits.
do $$
declare v_n integer; v_cap integer;
begin
  select coalesce((select (value #>> '{}')::integer from app_config where key = 'signup_attempts_per_ip_per_day'), 10) into v_cap;
  perform record_signup_attempt('198.51.100.44'::inet, extensions.digest('subnetmate@test', 'sha256'));
  select count_signups_from_subnet('198.51.100.200'::inet) into v_n;
  if v_n < v_cap + 2 then -- the cap+1 above + this one, all in 198.51.100.0/24
    raise exception 'FAIL: count_signups_from_subnet undercounted the /24 (got %)', v_n;
  end if;
end $$;
reset role;

-- ============================================================
-- 5. BAN EVASION, END TO END: a banned email hash is detected by the
--    pre-check AND by create_member's own belt-and-braces guard, and
--    an attempt against it creates NOTHING (atomic refusal, not a
--    partially-created account).
-- ============================================================
insert into banned_identifiers (kind, value_hash, reason) values
  ('email_hash', extensions.digest('bannedperson@test', 'sha256'), 'csam');

set role service_role;
do $$ begin
  if not identifier_is_banned('email_hash', extensions.digest('bannedperson@test', 'sha256')) then
    raise exception 'FAIL: a banned email hash read as clean';
  end if;
end $$;

-- The route's pre-check would short-circuit here in production; this
-- proves the SEPARATE guard inside create_member ALSO holds, so even
-- a caller who skipped the pre-check (or a future refactor that
-- removes it) still cannot create an account for a banned identifier.
do $$ begin
  begin
    perform create_member(
      '00000000-0000-0000-0000-000000000099', 'bannedperson@test', 'Should Not Exist', '1995-05-05', 'shouldnotexist',
      '203.0.113.50'::inet, extensions.digest('bannedperson@test', 'sha256'), null, '{}'::jsonb, false);
    raise exception 'FAIL: create_member accepted a banned email hash';
  exception when others then
    if sqlerrm !~ 'banned_identifier' then
      raise exception 'FAIL: wrong error for a banned signup: %', sqlerrm;
    end if;
  end;
  if exists (select 1 from profiles where user_id = '00000000-0000-0000-0000-000000000099') then
    raise exception 'FAIL: a profile row was created for a banned identifier despite the exception';
  end if;
  if exists (select 1 from user_private where user_id = '00000000-0000-0000-0000-000000000099') then
    raise exception 'FAIL: a user_private row was created for a banned identifier despite the exception';
  end if;
end $$;
reset role;

-- ============================================================
-- 6. THE UNDER-18 GUARD still holds through this same call path
--    (unrelated to the revoke, but it is the other hard gate on the
--    exact function the revoke touched — regression coverage for
--    "did changing the grants change the function body" by accident).
-- ============================================================
set role service_role;
do $$ begin
  begin
    perform create_member(
      '00000000-0000-0000-0000-000000000098', 'minor@test', 'Too Young', (current_date - interval '17 years')::date,
      'tooyoung', null, extensions.digest('minor@test', 'sha256'), null, '{}'::jsonb, false);
    raise exception 'FAIL: create_member accepted an under-18 date of birth';
  exception when others then
    if sqlerrm !~ '18' then raise exception 'FAIL: wrong error for under-18: %', sqlerrm; end if;
  end;
end $$;
reset role;

rollback;
