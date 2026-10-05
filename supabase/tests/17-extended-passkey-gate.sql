-- Behavioral smoke test for migration 20261020000001 (the "AAL2 OR
-- fresh passkey" gate extended to every remaining Owner sensitive
-- operation). Local only, like suites 01-16.
--
-- For EACH newly gated operation — grant_role, revoke_role,
-- owner_unban, and the Owner RLS reads of audit_log and user_private —
-- this suite proves:
--   - a STALE passkey entry is refused;
--   - a bare-string amr entry ("passkey" without a timestamp, the
--     RFC-8176 form) is refused;
--   - a FRESH NON-PASSKEY method (password) is refused;
--   - a fresh passkey at aal1 succeeds;
--   - aal2 still succeeds exactly as before;
--   - AND THE ONE THAT MATTERS MOST: a caller WITHOUT the Owner role —
--     including an ADMIN, the highest staff role — is still refused
--     with a perfectly fresh passkey. The gate changed how strongly
--     you must have authenticated, never who is allowed.
--
-- Plus the structural invariants of the migration:
--   - the operations record auth_method ('aal2'|'passkey') in their
--     audit detail; other moderation actions' audit entries are
--     unchanged (no auth_method key);
--   - exactly ONE signature per affected function (no PostgREST
--     ambiguity from a leftover overload);
--   - require_owner_aal2 is gone and nothing references it;
--   - EXECUTE posture: owner_sensitive_auth_method is callable by
--     authenticated only (RLS policies evaluate it as the querying
--     role); require_owner_sensitive_auth and mod_record_action by no
--     app role;
--   - both rewritten policies call the shared gate function and carry
--     no inline aal2 literal (the freshness window stays a one-line
--     change in one place);
--   - 0 tables without RLS, 0 SECURITY DEFINER functions without a
--     pinned search_path.
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000051', 'ida@test'),
  ('00000000-0000-0000-0000-000000000052', 'adda@test'),
  ('00000000-0000-0000-0000-000000000053', 'bana@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_member('00000000-0000-0000-0000-000000000051', 'ida@test', 'Ida Member', '1995-05-05', 'ida', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000052', 'adda@test', 'Ad Da', '1995-05-05', 'adda', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000053', 'bana@test', 'Ba Na', '1995-05-05', 'bana', null, null, null, '{}'::jsonb, false);

set role authenticated;

-- Owner at aal2: make adda an admin (the strongest non-owner for the
-- wrong-role proofs) and ban bana so owner_unban has work to refuse.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"so"}', false);
select grant_role('00000000-0000-0000-0000-000000000052', 'admin');
select mod_ban('00000000-0000-0000-0000-000000000053', 'spam', 'suite 17 setup ban', null, null, false);

-- ============================================================
-- 1. Refusals, as the OWNER, for every insufficient claim shape:
--    plain aal1; a bare-string amr; a fresh password entry; a stale
--    (1 h old) passkey. Each must refuse ALL five operations with the
--    gate's own error, and leave no side effects.
-- ============================================================
do $$
declare
  v_claims text;
begin
  foreach v_claims in array array[
    -- plain aal1, no amr at all
    '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal1","session_id":"so"}',
    -- amr as RFC-8176 bare strings: carries no timestamp, must not match
    '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal1","session_id":"so","amr":["passkey"]}',
    -- a fresh entry of the WRONG method
    jsonb_build_object('sub', '00000000-0000-0000-0000-000000000001', 'aal', 'aal1', 'session_id', 'so',
      'amr', jsonb_build_array(jsonb_build_object('method', 'password',
                                                  'timestamp', floor(extract(epoch from now()))::bigint)))::text,
    -- a passkey entry gone stale
    jsonb_build_object('sub', '00000000-0000-0000-0000-000000000001', 'aal', 'aal1', 'session_id', 'so',
      'amr', jsonb_build_array(jsonb_build_object('method', 'passkey',
                                                  'timestamp', floor(extract(epoch from now()))::bigint - 3600)))::text
  ] loop
    perform set_config('request.jwt.claims', v_claims, false);

    begin
      perform grant_role('00000000-0000-0000-0000-000000000051', 'moderator');
      raise exception 'FAIL: grant_role passed with claims %', v_claims;
    exception when others then
      if sqlerrm like 'FAIL:%' then raise; end if;
      if sqlerrm not like 'Fresh verification%' then
        raise exception 'FAIL: grant_role refused for the wrong reason (%) with claims %', sqlerrm, v_claims;
      end if;
    end;

    begin
      perform revoke_role('00000000-0000-0000-0000-000000000052', 'admin');
      raise exception 'FAIL: revoke_role passed with claims %', v_claims;
    exception when others then
      if sqlerrm like 'FAIL:%' then raise; end if;
      if sqlerrm not like 'Fresh verification%' then
        raise exception 'FAIL: revoke_role refused for the wrong reason (%) with claims %', sqlerrm, v_claims;
      end if;
    end;

    begin
      perform owner_unban('00000000-0000-0000-0000-000000000053', 'should not happen');
      raise exception 'FAIL: owner_unban passed with claims %', v_claims;
    exception when others then
      if sqlerrm like 'FAIL:%' then raise; end if;
      if sqlerrm not like 'Fresh verification%' then
        raise exception 'FAIL: owner_unban refused for the wrong reason (%) with claims %', sqlerrm, v_claims;
      end if;
    end;

    if exists (select 1 from audit_log) then
      raise exception 'FAIL: audit_log readable with claims %', v_claims;
    end if;
    if exists (select 1 from user_private where user_id <> auth.uid()) then
      raise exception 'FAIL: another member''s user_private row readable with claims %', v_claims;
    end if;
  end loop;

  -- No side effects slipped through anywhere above.
  if exists (select 1 from role_assignments
             where user_id = '00000000-0000-0000-0000-000000000051' and revoked_at is null) then
    raise exception 'FAIL: a refused grant_role still wrote an assignment';
  end if;
  if not exists (select 1 from role_assignments
                 where user_id = '00000000-0000-0000-0000-000000000052'
                   and role = 'admin' and revoked_at is null) then
    raise exception 'FAIL: a refused revoke_role still revoked the admin';
  end if;
  if not exists (select 1 from profiles
                 where user_id = '00000000-0000-0000-0000-000000000053' and status = 'banned') then
    raise exception 'FAIL: a refused owner_unban still unbanned the account';
  end if;
end $$;

-- ============================================================
-- 2. A fresh passkey at aal1 unlocks all five operations for the
--    Owner, and each function's audit entry records
--    auth_method = 'passkey'.
-- ============================================================
select set_config('request.jwt.claims',
  jsonb_build_object('sub', '00000000-0000-0000-0000-000000000001', 'aal', 'aal1', 'session_id', 'so',
    'amr', jsonb_build_array(jsonb_build_object('method', 'passkey',
                                                'timestamp', floor(extract(epoch from now()))::bigint - 60)))::text,
  false);
do $$ begin
  -- The RLS reads.
  if not exists (select 1 from audit_log) then
    raise exception 'FAIL: the Owner cannot read audit_log with a fresh passkey';
  end if;
  if not exists (select 1 from user_private
                 where user_id = '00000000-0000-0000-0000-000000000051') then
    raise exception 'FAIL: the Owner cannot read user_private with a fresh passkey';
  end if;

  -- The role functions and the unban.
  perform grant_role('00000000-0000-0000-0000-000000000051', 'moderator');
  if not exists (select 1 from role_assignments
                 where user_id = '00000000-0000-0000-0000-000000000051'
                   and role = 'moderator' and revoked_at is null) then
    raise exception 'FAIL: passkey grant_role wrote no assignment';
  end if;
  perform revoke_role('00000000-0000-0000-0000-000000000051', 'moderator');
  if exists (select 1 from role_assignments
             where user_id = '00000000-0000-0000-0000-000000000051' and revoked_at is null) then
    raise exception 'FAIL: passkey revoke_role left the assignment active';
  end if;
  perform owner_unban('00000000-0000-0000-0000-000000000053', 'suite 17 passkey unban');
  if not exists (select 1 from profiles
                 where user_id = '00000000-0000-0000-0000-000000000053' and status = 'active') then
    raise exception 'FAIL: passkey owner_unban did not reopen the account';
  end if;
end $$;

reset role;
do $$ begin
  if not exists (select 1 from audit_log
                 where action = 'role.grant'
                   and target_id = '00000000-0000-0000-0000-000000000051'
                   and detail ->> 'role' = 'moderator'
                   and detail ->> 'auth_method' = 'passkey') then
    raise exception 'FAIL: passkey role.grant not audited with auth_method';
  end if;
  if not exists (select 1 from audit_log
                 where action = 'role.revoke'
                   and target_id = '00000000-0000-0000-0000-000000000051'
                   and detail ->> 'auth_method' = 'passkey') then
    raise exception 'FAIL: passkey role.revoke not audited with auth_method';
  end if;
  if not exists (select 1 from audit_log
                 where action = 'mod.unban'
                   and target_id = '00000000-0000-0000-0000-000000000053'
                   and detail ->> 'auth_method' = 'passkey') then
    raise exception 'FAIL: passkey mod.unban not audited with auth_method';
  end if;
  -- Audit shape of every OTHER moderation action is unchanged: the
  -- setup ban (and anything else that stated no method) carries no
  -- auth_method key at all, not a null one.
  if exists (select 1 from audit_log
             where action like 'mod.%' and action <> 'mod.unban'
               and detail ? 'auth_method') then
    raise exception 'FAIL: a moderation action other than unban gained an auth_method key';
  end if;
end $$;
set role authenticated;

-- ============================================================
-- 3. aal2 still works for all five, recording auth_method = 'aal2'.
-- ============================================================
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"so"}', false);
select mod_ban('00000000-0000-0000-0000-000000000053', 'spam', 'suite 17 re-ban for the aal2 leg', null, null, false);
do $$ begin
  if not exists (select 1 from audit_log) then
    raise exception 'FAIL: the Owner cannot read audit_log at aal2';
  end if;
  if not exists (select 1 from user_private
                 where user_id = '00000000-0000-0000-0000-000000000051') then
    raise exception 'FAIL: the Owner cannot read user_private at aal2';
  end if;
  perform grant_role('00000000-0000-0000-0000-000000000051', 'moderator');
  perform revoke_role('00000000-0000-0000-0000-000000000051', 'moderator');
  perform owner_unban('00000000-0000-0000-0000-000000000053', 'suite 17 aal2 unban');
  if not exists (select 1 from profiles
                 where user_id = '00000000-0000-0000-0000-000000000053' and status = 'active') then
    raise exception 'FAIL: aal2 owner_unban did not reopen the account';
  end if;
end $$;

reset role;
do $$ begin
  if not exists (select 1 from audit_log
                 where action = 'role.grant' and detail ->> 'auth_method' = 'aal2'
                   and target_id = '00000000-0000-0000-0000-000000000051') then
    raise exception 'FAIL: aal2 role.grant not audited with auth_method';
  end if;
  if not exists (select 1 from audit_log
                 where action = 'role.revoke' and detail ->> 'auth_method' = 'aal2'
                   and target_id = '00000000-0000-0000-0000-000000000051') then
    raise exception 'FAIL: aal2 role.revoke not audited with auth_method';
  end if;
  if not exists (select 1 from audit_log
                 where action = 'mod.unban' and detail ->> 'auth_method' = 'aal2'
                   and target_id = '00000000-0000-0000-0000-000000000053') then
    raise exception 'FAIL: aal2 mod.unban not audited with auth_method';
  end if;
end $$;
set role authenticated;

-- ============================================================
-- 4. RIGHT PASSKEY, WRONG ROLE, STILL DENIED. An ADMIN — the highest
--    staff role — with a passkey seconds old gets refused everywhere,
--    with the AUTHORIZATION error, and sees zero gated rows. Then the
--    same for a plain member, and for the admin at aal2 (the gate
--    never outranked the role check in either direction).
-- ============================================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000052', false);
select set_config('request.jwt.claims',
  jsonb_build_object('sub', '00000000-0000-0000-0000-000000000052', 'aal', 'aal1', 'session_id', 'sa',
    'amr', jsonb_build_array(jsonb_build_object('method', 'passkey',
                                                'timestamp', floor(extract(epoch from now()))::bigint - 5)))::text,
  false);
do $$ begin
  begin
    perform grant_role('00000000-0000-0000-0000-000000000051', 'moderator');
    raise exception 'FAIL: an admin with a fresh passkey granted a role';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm not like 'Only the Owner%' then
      raise exception 'FAIL: admin grant_role refused for the wrong reason: %', sqlerrm;
    end if;
  end;
  begin
    perform revoke_role('00000000-0000-0000-0000-000000000052', 'admin');
    raise exception 'FAIL: an admin with a fresh passkey revoked a role';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm not like 'Only the Owner%' then
      raise exception 'FAIL: admin revoke_role refused for the wrong reason: %', sqlerrm;
    end if;
  end;
  begin
    perform owner_unban('00000000-0000-0000-0000-000000000053', 'should not happen');
    raise exception 'FAIL: an admin with a fresh passkey ran owner_unban';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm not like 'Only the Owner%' then
      raise exception 'FAIL: admin owner_unban refused for the wrong reason: %', sqlerrm;
    end if;
  end;
  if exists (select 1 from audit_log) then
    raise exception 'FAIL: an admin with a fresh passkey can read audit_log';
  end if;
  if exists (select 1 from user_private where user_id <> auth.uid()) then
    raise exception 'FAIL: an admin with a fresh passkey can read another member''s user_private row';
  end if;
end $$;

-- A plain member with a fresh passkey: identical nothing.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000051', false);
select set_config('request.jwt.claims',
  jsonb_build_object('sub', '00000000-0000-0000-0000-000000000051', 'aal', 'aal1', 'session_id', 'si',
    'amr', jsonb_build_array(jsonb_build_object('method', 'passkey',
                                                'timestamp', floor(extract(epoch from now()))::bigint - 5)))::text,
  false);
do $$ begin
  begin
    perform grant_role('00000000-0000-0000-0000-000000000051', 'moderator');
    raise exception 'FAIL: a member with a fresh passkey granted herself a role';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm not like 'Only the Owner%' then
      raise exception 'FAIL: member grant_role refused for the wrong reason: %', sqlerrm;
    end if;
  end;
  if exists (select 1 from audit_log) then
    raise exception 'FAIL: a member with a fresh passkey can read audit_log';
  end if;
  if exists (select 1 from user_private where user_id <> auth.uid()) then
    raise exception 'FAIL: a member with a fresh passkey can read another member''s user_private row';
  end if;
end $$;

-- The admin at aal2 (full strength, wrong role): still nothing.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000052', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000052","aal":"aal2","session_id":"sa"}', false);
do $$ begin
  begin
    perform grant_role('00000000-0000-0000-0000-000000000051', 'moderator');
    raise exception 'FAIL: an admin at aal2 granted a role';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm not like 'Only the Owner%' then
      raise exception 'FAIL: admin-at-aal2 grant_role refused for the wrong reason: %', sqlerrm;
    end if;
  end;
  if exists (select 1 from audit_log) then
    raise exception 'FAIL: an admin at aal2 can read audit_log';
  end if;
  if exists (select 1 from user_private where user_id <> auth.uid()) then
    raise exception 'FAIL: an admin at aal2 can read another member''s user_private row';
  end if;
end $$;

reset role;

-- ============================================================
-- 5. Structure: one signature each (no overload survived the
--    mod_record_action change), require_owner_aal2 gone and
--    unreferenced, the gated functions really call the combined gate,
--    and the policies call the shared function with no inline aal2
--    literal.
-- ============================================================
do $$
declare
  f text;
  n integer;
  src text;
begin
  foreach f in array array['grant_role', 'revoke_role', 'owner_unban', 'mod_record_action',
                           'owner_sensitive_auth_method', 'require_owner_sensitive_auth',
                           'owner_reveal_identity'] loop
    select count(*) into n
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public' and p.proname = f;
    if n <> 1 then
      raise exception 'FAIL: % has % signatures (PostgREST would be ambiguous)', f, n;
    end if;
  end loop;

  if exists (select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
             where ns.nspname = 'public' and p.proname = 'require_owner_aal2') then
    raise exception 'FAIL: require_owner_aal2 still exists';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
             where ns.nspname = 'public' and position('require_owner_aal2' in p.prosrc) > 0) then
    raise exception 'FAIL: a function still references require_owner_aal2';
  end if;

  foreach f in array array['grant_role', 'revoke_role', 'owner_unban'] loop
    select p.prosrc into src
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public' and p.proname = f;
    if position('require_owner_sensitive_auth' in src) = 0 then
      raise exception 'FAIL: % does not use the combined gate', f;
    end if;
  end loop;

  for f, src in
    select pol.polname, pg_get_expr(pol.polqual, pol.polrelid)
      from pg_policy pol
     where pol.polname in ('audit_owner_read', 'user_private_owner')
  loop
    if position('owner_sensitive_auth_method' in src) = 0 then
      raise exception 'FAIL: policy % does not call the shared gate function', f;
    end if;
    if position('is_owner' in src) = 0 then
      raise exception 'FAIL: policy % lost its Owner check', f;
    end if;
    if position('aal2' in src) > 0 then
      raise exception 'FAIL: policy % duplicates the gate logic inline', f;
    end if;
  end loop;
  select count(*) into n from pg_policy where polname in ('audit_owner_read', 'user_private_owner');
  if n <> 2 then
    raise exception 'FAIL: expected both rewritten policies to exist, found %', n;
  end if;
end $$;

-- ============================================================
-- 6. EXECUTE posture and the platform invariants: RLS on every table,
--    a pinned search_path on every SECURITY DEFINER function.
-- ============================================================
do $$ declare f text; n integer; begin
  foreach f in array array['anon', 'authenticated', 'service_role'] loop
    if has_function_privilege(f, 'public.require_owner_sensitive_auth()', 'execute') then
      raise exception 'FAIL: % can execute require_owner_sensitive_auth', f;
    end if;
    if has_function_privilege(f,
        'public.mod_record_action(uuid, bigint, mod_action, report_reason, integer, text, text, timestamptz, text)',
        'execute') then
      raise exception 'FAIL: % can execute mod_record_action', f;
    end if;
  end loop;
  if not has_function_privilege('authenticated', 'public.owner_sensitive_auth_method()', 'execute') then
    raise exception 'FAIL: authenticated cannot execute owner_sensitive_auth_method — the RLS policies would deny the Owner';
  end if;
  foreach f in array array['anon', 'service_role'] loop
    if has_function_privilege(f, 'public.owner_sensitive_auth_method()', 'execute') then
      raise exception 'FAIL: % can execute owner_sensitive_auth_method', f;
    end if;
  end loop;

  select count(*) into n
    from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  if n <> 0 then
    raise exception 'FAIL: % table(s) without RLS', n;
  end if;

  select count(*) into n
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.prosecdef
     and (p.proconfig is null
          or not exists (select 1 from unnest(p.proconfig) cfg where cfg like 'search_path=%'));
  if n <> 0 then
    raise exception 'FAIL: % SECURITY DEFINER function(s) without a pinned search_path', n;
  end if;
end $$;

rollback;
\echo 'EXTENDED PASSKEY GATE SMOKE: ALL CHECKS PASSED'
