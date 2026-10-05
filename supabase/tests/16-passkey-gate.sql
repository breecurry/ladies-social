-- Behavioral smoke test for migration 20261019000001 (the identity
-- reveal accepting AAL2 OR a fresh passkey). Local only, like suites
-- 01-15.
--
-- Headline properties:
--   - amr is parsed as an ARRAY OF OBJECTS ({ method, timestamp });
--     the RFC-8176 string form ("passkey" as a bare string) carries no
--     timestamp and must NOT satisfy the gate (fail closed);
--   - a fresh (< 5 min) passkey entry unlocks the reveal at aal1, and
--     the audit entry records auth_method = 'passkey';
--   - a stale passkey entry, a fresh NON-passkey entry, and a plain
--     aal1 session are all refused;
--   - aal2 still works and records auth_method = 'aal2';
--   - the gate is Owner-only even with a fresh passkey;
--   - the raising helper (require_owner_sensitive_auth) is callable by
--     no app role; owner_sensitive_auth_method is callable by
--     authenticated ONLY so RLS policies can evaluate it (that grant,
--     and the widening of the gate to the other sensitive operations,
--     is 20261020000001 — suite 17 proves all of it).
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000041', 'ida@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_member('00000000-0000-0000-0000-000000000041', 'ida@test', 'Ida Member', '1995-05-05', 'ida', null, null, null, '{}'::jsonb, false);

-- The migration really replaced the reveal's gate (and only the gate).
do $$ declare src text; begin
  select p.prosrc into src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'owner_reveal_identity';
  if position('require_owner_sensitive_auth' in src) = 0 then
    raise exception 'FAIL: owner_reveal_identity does not use the combined gate';
  end if;
  if position('require_owner_aal2' in src) > 0 then
    raise exception 'FAIL: owner_reveal_identity carries a dead aal2-only gate';
  end if;
  if position('display_name' in src) > 0 then
    raise exception 'FAIL: owner_reveal_identity references display_name';
  end if;
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);

-- ============================================================
-- 1. Refusals: plain aal1; amr as strings; fresh non-passkey method;
--    stale passkey.
-- ============================================================
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal1","session_id":"so"}', false);
do $$ begin
  begin
    perform * from owner_reveal_identity('00000000-0000-0000-0000-000000000041', 'test reason');
    raise exception 'FAIL: identity revealed at plain aal1';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal1","session_id":"so","amr":["passkey"]}', false);
do $$ begin
  begin
    perform * from owner_reveal_identity('00000000-0000-0000-0000-000000000041', 'test reason');
    raise exception 'FAIL: a bare string amr entry satisfied the gate';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

select set_config('request.jwt.claims',
  jsonb_build_object('sub', '00000000-0000-0000-0000-000000000001', 'aal', 'aal1', 'session_id', 'so',
    'amr', jsonb_build_array(jsonb_build_object('method', 'password',
                                                'timestamp', floor(extract(epoch from now()))::bigint)))::text,
  false);
do $$ begin
  begin
    perform * from owner_reveal_identity('00000000-0000-0000-0000-000000000041', 'test reason');
    raise exception 'FAIL: a fresh PASSWORD amr entry satisfied the gate';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

select set_config('request.jwt.claims',
  jsonb_build_object('sub', '00000000-0000-0000-0000-000000000001', 'aal', 'aal1', 'session_id', 'so',
    'amr', jsonb_build_array(jsonb_build_object('method', 'passkey',
                                                'timestamp', floor(extract(epoch from now()))::bigint - 3600)))::text,
  false);
do $$ begin
  begin
    perform * from owner_reveal_identity('00000000-0000-0000-0000-000000000041', 'test reason');
    raise exception 'FAIL: an hour-old passkey entry satisfied the gate';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

-- ============================================================
-- 2. A fresh passkey at aal1 unlocks the reveal. (Until 20261020000001
--    this section also proved the OTHER sensitive operations refused a
--    passkey; the Owner has since decided to extend the gate to them,
--    and suite 17 now owns every assertion about those operations.)
-- ============================================================
select set_config('request.jwt.claims',
  jsonb_build_object('sub', '00000000-0000-0000-0000-000000000001', 'aal', 'aal1', 'session_id', 'so',
    'amr', jsonb_build_array(jsonb_build_object('method', 'passkey',
                                                'timestamp', floor(extract(epoch from now()))::bigint - 60)))::text,
  false);
do $$ declare r record; begin
  select * into r from owner_reveal_identity('00000000-0000-0000-0000-000000000041',
                                             'fresh passkey check');
  if r.legal_name <> 'Ida Member' or r.email <> 'ida@test' then
    raise exception 'FAIL: reveal returned the wrong private record';
  end if;
end $$;

reset role;
do $$ begin
  if not exists (select 1 from audit_log
                 where action = 'identity.reveal'
                   and target_id = '00000000-0000-0000-0000-000000000041'
                   and detail ->> 'reason' = 'fresh passkey check'
                   and detail ->> 'auth_method' = 'passkey') then
    raise exception 'FAIL: the passkey-gated reveal is not in the audit log with auth_method';
  end if;
end $$;
set role authenticated;

-- ============================================================
-- 3. aal2 still works, and records auth_method = 'aal2'.
-- ============================================================
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"so"}', false);
do $$ declare r record; begin
  select * into r from owner_reveal_identity('00000000-0000-0000-0000-000000000041',
                                             'aal2 regression check');
  if r.legal_name <> 'Ida Member' then
    raise exception 'FAIL: reveal broken at aal2';
  end if;
  if not exists (select 1 from audit_log
                 where action = 'identity.reveal'
                   and detail ->> 'reason' = 'aal2 regression check'
                   and detail ->> 'auth_method' = 'aal2') then
    raise exception 'FAIL: aal2 reveal did not record auth_method';
  end if;
end $$;

-- ============================================================
-- 4. Owner-only, even with a fresh passkey.
-- ============================================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000041', false);
select set_config('request.jwt.claims',
  jsonb_build_object('sub', '00000000-0000-0000-0000-000000000041', 'aal', 'aal1', 'session_id', 'si',
    'amr', jsonb_build_array(jsonb_build_object('method', 'passkey',
                                                'timestamp', floor(extract(epoch from now()))::bigint - 10)))::text,
  false);
do $$ begin
  begin
    perform * from owner_reveal_identity('00000000-0000-0000-0000-000000000001', 'not the owner');
    raise exception 'FAIL: a member with a fresh passkey used the reveal';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

reset role;

-- ============================================================
-- 5. EXECUTE posture: the raising helper is internal; the method
--    helper is authenticated-only (RLS policies evaluate it as the
--    querying role since 20261020000001); the reveal stays
--    authenticated-only.
-- ============================================================
do $$ declare f text; begin
  foreach f in array array['anon', 'authenticated', 'service_role'] loop
    if has_function_privilege(f, 'public.require_owner_sensitive_auth()', 'execute') then
      raise exception 'FAIL: % can execute require_owner_sensitive_auth', f;
    end if;
  end loop;
  foreach f in array array['anon', 'service_role'] loop
    if has_function_privilege(f, 'public.owner_sensitive_auth_method()', 'execute') then
      raise exception 'FAIL: % can execute owner_sensitive_auth_method', f;
    end if;
  end loop;
  if not has_function_privilege('authenticated', 'public.owner_sensitive_auth_method()', 'execute') then
    raise exception 'FAIL: authenticated cannot execute owner_sensitive_auth_method — the audit_log/user_private RLS policies would deny the Owner';
  end if;
  if not has_function_privilege('authenticated', 'public.owner_reveal_identity(uuid, text)', 'execute') then
    raise exception 'FAIL: authenticated lost execute on owner_reveal_identity';
  end if;
  if has_function_privilege('anon', 'public.owner_reveal_identity(uuid, text)', 'execute') then
    raise exception 'FAIL: anon can execute owner_reveal_identity';
  end if;
end $$;

rollback;
\echo 'PASSKEY GATE SMOKE: ALL CHECKS PASSED'
