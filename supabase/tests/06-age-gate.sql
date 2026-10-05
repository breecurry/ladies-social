-- Behavioral + structural smoke test of the age gate (migration 0017,
-- spec §17). What this file proves:
--
--   1. STRUCTURALLY, a block can never take in a person: the table has
--      exactly five columns (id, fingerprint_hash, reference_code,
--      created_at, expires_at) — no email, no name, no DOB, no IP can
--      exist in a block row, and this test breaks the moment a future
--      migration adds a column here;
--   2. user_private.dob is GONE (data minimisation: the raw birth date
--      is validated, never retained; age_attested_at remains);
--   3. no app role can touch age_gate_blocks directly — RLS is on with
--      zero policies AND every table privilege is revoked;
--   4. recording is service_role-only, idempotent per device (same
--      code, same expiry — failing again does not restart the clock),
--      audit-logged by code alone, and the code is short, unambiguous
--      and unique;
--   5. reading matches by fingerprint hash OR reference code (case-
--      and whitespace-insensitively), and an expired block neither
--      matches nor lingers (opportunistic pruning);
--   6. the support unlock is Owner-only (a signed-in member is
--      refused), deletes exactly the quoted block, and is audit-
--      logged; the audit chain still verifies end to end;
--   7. create_member still refuses an under-18 date at the database.
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000003', 'ada@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_member('00000000-0000-0000-0000-000000000003', 'ada@test', 'Ada Lovelace', '1995-05-05', 'ada', null, null, null, '{}'::jsonb, false);

-- ============================================================
-- 1. STRUCTURAL data minimisation. The block table holds a hashed
--    fingerprint, timestamps and a code — and can hold NOTHING else.
-- ============================================================
do $$ declare cols text; begin
  select string_agg(attname, ',' order by attname) into cols
    from pg_attribute
    where attrelid = 'public.age_gate_blocks'::regclass
      and attnum > 0 and not attisdropped;
  if cols <> 'created_at,expires_at,fingerprint_hash,id,reference_code' then
    raise exception 'FAIL: age_gate_blocks columns changed to (%) — a block must never hold identifying data', cols;
  end if;
  if exists (select 1 from pg_attribute
             where attrelid = 'public.user_private'::regclass
               and attname = 'dob' and not attisdropped) then
    raise exception 'FAIL: user_private.dob still exists; the raw birth date must not be retained';
  end if;
  if not exists (select 1 from pg_attribute
                 where attrelid = 'public.user_private'::regclass
                   and attname = 'age_attested_at' and not attisdropped) then
    raise exception 'FAIL: user_private.age_attested_at missing — the derived 18+ record must remain';
  end if;
end $$;

-- ============================================================
-- 2. No app role reaches the table directly: RLS on, zero policies,
--    zero table privileges.
-- ============================================================
do $$ declare r text; p text; begin
  if not (select relrowsecurity from pg_class where oid = 'public.age_gate_blocks'::regclass) then
    raise exception 'FAIL: RLS is not enabled on age_gate_blocks';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'age_gate_blocks') then
    raise exception 'FAIL: age_gate_blocks has policies; it must have none';
  end if;
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    foreach p in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE'] loop
      if has_table_privilege(r, 'public.age_gate_blocks', p) then
        raise exception 'FAIL: % holds % on age_gate_blocks', r, p;
      end if;
    end loop;
  end loop;
end $$;

-- ============================================================
-- 3. Recording: service_role-only, idempotent per device, audited.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ begin
  begin
    perform record_age_gate_block('\xaa11'::bytea);
    raise exception 'FAIL: authenticated recorded an age-gate block';
  exception when insufficient_privilege then null;
  end;
  begin
    perform get_age_gate_block('\xaa11'::bytea, null);
    raise exception 'FAIL: authenticated read an age-gate block';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

set role service_role;
do $$ declare c1 text; c2 text; e1 timestamptz; e2 timestamptz; n int; begin
  select reference_code, expires_at into c1, e1 from record_age_gate_block('\xaa11'::bytea);
  if c1 !~ '^[2-9A-HJKMNP-Z]{4,8}$' then
    raise exception 'FAIL: reference code % is not in the unambiguous format', c1;
  end if;
  if e1 < now() + interval '13 days' or e1 > now() + interval '15 days' then
    raise exception 'FAIL: block expiry % is not about 14 days out', e1;
  end if;
  -- Same device again: same code, same expiry (no clock restart).
  select reference_code, expires_at into c2, e2 from record_age_gate_block('\xaa11'::bytea);
  if c2 <> c1 or e2 <> e1 then
    raise exception 'FAIL: re-recording the same device changed the block (% -> %)', c1, c2;
  end if;
  -- A different device gets a different code.
  select reference_code into c2 from record_age_gate_block('\xbb22'::bytea);
  if c2 = c1 then raise exception 'FAIL: two devices share a reference code'; end if;
  perform set_config('t.code1', c1, false);
  perform set_config('t.code2', c2, false);
  select count(*) into n from audit_log where action = 'age_gate.block';
  if n <> 2 then raise exception 'FAIL: expected 2 age_gate.block audit rows, found %', n; end if;
  -- The audit rows identify the block by code only.
  if exists (select 1 from audit_log
             where action = 'age_gate.block'
               and (target_id !~ '^[2-9A-HJKMNP-Z]{4,8}$' or target_type <> 'age_gate_block')) then
    raise exception 'FAIL: age_gate.block audit rows carry more than the code';
  end if;
end $$;

-- ============================================================
-- 4. Reading: by fingerprint, by code (case/whitespace-insensitive),
--    nothing for strangers, and expired blocks vanish.
-- ============================================================
do $$ declare c text; n int; begin
  select reference_code into c from get_age_gate_block('\xaa11'::bytea, null);
  if c is distinct from current_setting('t.code1') then
    raise exception 'FAIL: fingerprint lookup returned % instead of the device''s code', c;
  end if;
  select reference_code into c from get_age_gate_block(null, '  ' || lower(current_setting('t.code1')) || ' ');
  if c is distinct from current_setting('t.code1') then
    raise exception 'FAIL: code lookup is not case/whitespace-insensitive';
  end if;
  select count(*) into n from get_age_gate_block('\xdddd'::bytea, 'ZZZZ');
  if n <> 0 then raise exception 'FAIL: an unknown device/code matched a block'; end if;
end $$;
reset role;

-- Expiry (superuser backdates the row; no app path can).
update age_gate_blocks set expires_at = now() - interval '1 minute'
  where reference_code = current_setting('t.code2');
set role service_role;
do $$ declare n int; begin
  select count(*) into n from get_age_gate_block('\xbb22'::bytea, null);
  if n <> 0 then raise exception 'FAIL: an expired block still matches'; end if;
end $$;
reset role;
do $$ declare n int; begin
  select count(*) into n from age_gate_blocks where reference_code = current_setting('t.code2');
  if n <> 0 then raise exception 'FAIL: an expired block was not pruned'; end if;
end $$;

-- ============================================================
-- 5. Support unlock: Owner-only, exact, audited, chain intact.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ begin
  begin
    perform lookup_age_gate_block(current_setting('t.code1'));
    raise exception 'FAIL: a non-owner member looked up a block';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    perform clear_age_gate_block(current_setting('t.code1'));
    raise exception 'FAIL: a non-owner member cleared a block';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal1","session_id":"so"}', false);
do $$ declare c text; ok boolean; begin
  select reference_code into c from lookup_age_gate_block(lower(current_setting('t.code1')));
  if c is distinct from current_setting('t.code1') then
    raise exception 'FAIL: Owner lookup did not find the block';
  end if;
  select clear_age_gate_block(current_setting('t.code1')) into ok;
  if not ok then raise exception 'FAIL: Owner clear returned false for an existing block'; end if;
  select clear_age_gate_block(current_setting('t.code1')) into ok;
  if ok then raise exception 'FAIL: clearing an already-cleared block claimed success'; end if;
end $$;
reset role;

set role service_role;
do $$ declare n int; begin
  select count(*) into n from get_age_gate_block('\xaa11'::bytea, null);
  if n <> 0 then raise exception 'FAIL: a cleared device is still blocked'; end if;
end $$;
reset role;

do $$ declare n int; ok boolean; begin
  select count(*) into n from audit_log where action = 'age_gate.unblock';
  if n <> 1 then raise exception 'FAIL: expected 1 age_gate.unblock audit row, found %', n; end if;
  select v.ok into ok from verify_audit_chain() v;
  if not ok then raise exception 'FAIL: audit chain broken after age-gate activity'; end if;
end $$;

-- ============================================================
-- 6. The database floor under the gate: an under-18 date is refused
--    by create_member no matter what reaches it.
-- ============================================================
do $$ begin
  begin
    perform create_member('00000000-0000-0000-0000-000000000009', 'kid@test', 'Too Young',
      (current_date - interval '17 years')::date, 'kiddo', null, null, null, '{}'::jsonb, false);
    raise exception 'FAIL: under-18 signup accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

rollback;
\echo ALL AGE GATE TESTS PASSED
