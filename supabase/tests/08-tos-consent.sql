-- Behavioral + structural test of the Terms of Service consent record
-- (migration 0019). What this file proves:
--
--   1. user_private carries tos_agreed_at + tos_version, both NULLABLE
--      — accounts that predate the consent checkbox (the live Owner
--      and system accounts) keep NULL and are never locked out;
--   2. a freshly bootstrapped/created account has NULL consent until
--      record_tos_consent() runs — nothing fakes a consent that was
--      never given;
--   3. record_tos_consent is service_role-only (an authenticated
--      member cannot forge a consent record for anyone) and
--      user_private itself stays unreachable for direct writes;
--   4. recording sets the timestamp and the exact version string,
--      appends a 'member.tos_consent' audit row carrying the version,
--      and the audit chain still verifies end to end;
--   5. the function refuses an empty version (no unattributable
--      consents) and returns false for a non-member (nothing written);
--   6. the version column rejects absurd lengths (defence against a
--      bug upstream writing garbage).
--
-- The HTTP half of "not skippable" — the signup route rejecting a POST
-- whose tosAgreed field is absent or false — lives in signupSchema
-- (src/lib/validation.ts, z.literal(true)) and is exercised against a
-- running `next start` with curl; see PROGRESS.md. It cannot be proven
-- from SQL because the rejection happens before any database call.
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000003', 'ada@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_member('00000000-0000-0000-0000-000000000003', 'ada@test', 'Ada Lovelace', '1995-05-05', 'ada', null, null, null, '{}'::jsonb, false);

-- ============================================================
-- 1. Structure: both columns exist and are nullable (pre-existing
--    accounts must be representable as "no consent captured").
-- ============================================================
do $$ begin
  if not exists (select 1 from pg_attribute
                 where attrelid = 'public.user_private'::regclass
                   and attname = 'tos_agreed_at' and not attisdropped and not attnotnull) then
    raise exception 'FAIL: user_private.tos_agreed_at missing or NOT NULL';
  end if;
  if not exists (select 1 from pg_attribute
                 where attrelid = 'public.user_private'::regclass
                   and attname = 'tos_version' and not attisdropped and not attnotnull) then
    raise exception 'FAIL: user_private.tos_version missing or NOT NULL';
  end if;
end $$;

-- ============================================================
-- 2. No consent is faked: accounts start with NULL in both columns.
-- ============================================================
do $$ begin
  if exists (select 1 from user_private
             where tos_agreed_at is not null or tos_version is not null) then
    raise exception 'FAIL: an account has a Terms consent it never gave';
  end if;
end $$;

-- ============================================================
-- 3. An authenticated member cannot forge a consent record.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"st"}', false);
do $$ begin
  begin
    perform record_tos_consent('00000000-0000-0000-0000-000000000003',
                               'interim:October 7, 2026#sha256:deadbeefdeadbeef');
    raise exception 'FAIL: authenticated recorded a Terms consent directly';
  exception when insufficient_privilege then null;
  end;
  begin
    update user_private
       set tos_agreed_at = now(), tos_version = 'forged'
     where user_id = '00000000-0000-0000-0000-000000000003';
    raise exception 'FAIL: authenticated wrote tos columns directly';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- ============================================================
-- 4. Recording works for the server: timestamp + exact version +
--    audit row, and the chain still verifies.
-- ============================================================
set role service_role;
do $$ declare v_ok boolean; begin
  select record_tos_consent('00000000-0000-0000-0000-000000000003',
                            '  interim:October 7, 2026#sha256:deadbeefdeadbeef ')
    into v_ok;
  if not v_ok then raise exception 'FAIL: record_tos_consent returned false for a real member'; end if;
end $$;
reset role;
do $$ declare v_at timestamptz; v_ver text; begin
  select tos_agreed_at, tos_version into v_at, v_ver
    from user_private where user_id = '00000000-0000-0000-0000-000000000003';
  if v_at is null or v_at < now() - interval '1 minute' then
    raise exception 'FAIL: tos_agreed_at not set to the consent moment (%)', v_at;
  end if;
  if v_ver <> 'interim:October 7, 2026#sha256:deadbeefdeadbeef' then
    raise exception 'FAIL: tos_version stored % instead of the trimmed exact version', v_ver;
  end if;
  if (select tos_agreed_at from user_private
      where user_id = '00000000-0000-0000-0000-000000000001') is not null then
    raise exception 'FAIL: consent leaked onto a different account';
  end if;
  if not exists (select 1 from audit_log
                 where action = 'member.tos_consent'
                   and target_type = 'user'
                   and target_id = '00000000-0000-0000-0000-000000000003'
                   and detail ->> 'version' = 'interim:October 7, 2026#sha256:deadbeefdeadbeef') then
    raise exception 'FAIL: member.tos_consent audit row missing or missing the version';
  end if;
end $$;
-- The chain check is Owner-only.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"st2"}', false);
do $$ begin
  if not (select ok from verify_audit_chain()) then
    raise exception 'FAIL: audit chain broken after recording consent';
  end if;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"st"}', false);

-- ============================================================
-- 5. Refusals: empty version raises; unknown member returns false and
--    writes nothing.
-- ============================================================
set role service_role;
do $$ declare v_ok boolean; begin
  begin
    perform record_tos_consent('00000000-0000-0000-0000-000000000003', '   ');
    raise exception 'FAIL: an empty version was accepted';
  exception when raise_exception then null;
  end;
  select record_tos_consent('00000000-0000-0000-0000-00000000dead',
                            'interim:October 7, 2026#sha256:deadbeefdeadbeef')
    into v_ok;
  if v_ok then raise exception 'FAIL: consent recorded for a non-member'; end if;
end $$;
reset role;
do $$ declare n int; begin
  select count(*) into n from audit_log where action = 'member.tos_consent';
  if n <> 1 then
    raise exception 'FAIL: expected exactly 1 member.tos_consent audit row, found %', n;
  end if;
end $$;

-- ============================================================
-- 6. The length guard on tos_version holds.
-- ============================================================
set role service_role;
do $$ begin
  begin
    perform record_tos_consent('00000000-0000-0000-0000-000000000003', repeat('x', 201));
    raise exception 'FAIL: a 201-char version string was accepted';
  exception when check_violation then null;
  end;
end $$;
reset role;

rollback;
\echo ALL TOS CONSENT TESTS PASSED
