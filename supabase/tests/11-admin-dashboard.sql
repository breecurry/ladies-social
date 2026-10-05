-- Behavioral + structural smoke test for migration 0022 (Phase 2D,
-- admin dashboard): the Owner's member directory, the identity
-- reveal, the logged export, and the Insights metrics read.
--
-- The headline security properties:
--   1. OWNER-ONLY AT THE DATA LAYER: a non-Owner member calling any
--      of these functions directly gets zero rows or an exception —
--      the UI is not the gate.
--   2. NO RAW ACTIVITY TIMESTAMP: the directory and glance functions
--      return only the coarse bucket LABEL; their result shapes carry
--      no last-login timestamp. The precise time exists solely inside
--      the AAL2-gated, reason-stated, audit-logged identity reveal.
--   3. The structural legal-name rule extends to every new function:
--      none references profiles.display_name.
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000003', 'ada@test'),
  ('00000000-0000-0000-0000-000000000004', 'bea@test'),
  ('00000000-0000-0000-0000-000000000005', 'cat@test'),
  ('00000000-0000-0000-0000-000000000007', 'system@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_system_account('00000000-0000-0000-0000-000000000007', 'hersciety');
select create_member('00000000-0000-0000-0000-000000000003', 'ada@test', 'Ada Lovelace', '1995-05-05', 'ada', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000004', 'bea@test', 'Bea Arthur',   '1995-05-05', 'bea', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000005', 'cat@test', 'Cat Stevens',  '1995-05-05', 'cat', null, null, null, '{}'::jsonb, false);

-- Activity signals: ada logged in today, bea 45 days ago, cat never.
update user_private set last_login_at = now()                      where user_id = '00000000-0000-0000-0000-000000000003';
update user_private set last_login_at = now() - interval '45 days' where user_id = '00000000-0000-0000-0000-000000000004';

-- ============================================================
-- 1. STRUCTURAL: the functions exist, none references display_name
--    (signature or body), and the directory/glance result shapes
--    carry no raw last-login timestamp — only the bucket label.
-- ============================================================
do $$ declare f text; sig text; src text; begin
  foreach f in array array['owner_member_count', 'owner_directory',
                           'owner_directory_count', 'owner_member_detail',
                           'owner_reveal_identity', 'owner_directory_export',
                           'owner_metrics', 'owner_activity_bucket'] loop
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
  -- The no-raw-timestamp rule, structurally: the browsable surfaces
  -- (directory, count, detail, export) must not return last_login in
  -- any form. Only owner_reveal_identity (AAL2 + reason + audit) may.
  foreach f in array array['owner_directory', 'owner_directory_count',
                           'owner_member_detail', 'owner_directory_export'] loop
    select pg_get_function_result(p.oid) into sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = f;
    if position('last_login' in sig) > 0 or position('last_active' in sig) > 0 then
      raise exception 'FAIL: % exposes a raw activity timestamp', f;
    end if;
  end loop;
end $$;

-- profiles must NOT have gained a last_active_at column.
do $$ begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'profiles'
               and column_name = 'last_active_at') then
    raise exception 'FAIL: profiles.last_active_at exists — forbidden';
  end if;
end $$;

-- EXECUTE posture: authenticated only; the internal bucket helper is
-- callable by no app role at all.
do $$ declare f text; begin
  foreach f in array array[
    'public.owner_member_count()',
    'public.owner_directory(text, account_status[], boolean, timestamptz, timestamptz, text[], timestamptz, uuid, integer)',
    'public.owner_directory_count(text, account_status[], boolean, timestamptz, timestamptz, text[])',
    'public.owner_member_detail(citext)',
    'public.owner_reveal_identity(uuid, text)',
    'public.owner_directory_export(text, account_status[], boolean, timestamptz, timestamptz, text[])',
    'public.owner_metrics(text)'] loop
    if has_function_privilege('anon', f, 'execute') then
      raise exception 'FAIL: anon can execute %', f;
    end if;
    if has_function_privilege('service_role', f, 'execute') then
      raise exception 'FAIL: service_role can execute %', f;
    end if;
    if not has_function_privilege('authenticated', f, 'execute') then
      raise exception 'FAIL: authenticated cannot execute %', f;
    end if;
  end loop;
  foreach f in array array['anon', 'authenticated', 'service_role'] loop
    if has_function_privilege(f, 'public.owner_activity_bucket(timestamptz)', 'execute') then
      raise exception 'FAIL: % can execute the internal bucket helper', f;
    end if;
  end loop;
end $$;

-- ============================================================
-- 2. OWNER-ONLY AT THE DATA LAYER: an ordinary member calling each
--    function directly gets zero rows (reads) or an exception
--    (metrics, reveal, export).
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal2","session_id":"sa"}', false);

do $$ begin
  if (select count(*) from owner_directory()) <> 0 then
    raise exception 'FAIL: non-owner can read the directory';
  end if;
  if owner_member_count() <> 0 then
    raise exception 'FAIL: non-owner sees the member count';
  end if;
  if owner_directory_count() <> 0 then
    raise exception 'FAIL: non-owner sees the directory match count';
  end if;
  if (select count(*) from owner_member_detail('bree')) <> 0 then
    raise exception 'FAIL: non-owner can read a member detail';
  end if;
end $$;

do $$ begin
  begin
    perform owner_metrics('30d');
    raise exception 'FAIL: non-owner read the metrics';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    perform * from owner_reveal_identity('00000000-0000-0000-0000-000000000004', 'curiosity');
    raise exception 'FAIL: non-owner revealed an identity (even at aal2)';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    perform * from owner_directory_export();
    raise exception 'FAIL: non-owner exported the directory';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

-- ============================================================
-- 3. The Owner's directory: rows are @handle-keyed, activity is only
--    ever one of the five bucket labels, the system account never
--    appears, search is prefix-only, and keyset pagination pages
--    without overlap.
-- ============================================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal1","session_id":"so"}', false);

do $$ declare bad int; begin
  if (select count(*) from owner_directory()) <> 4 then
    raise exception 'FAIL: owner directory should hold bree+ada+bea+cat';
  end if;
  if exists (select 1 from owner_directory() d where d.handle = 'hersciety') then
    raise exception 'FAIL: the system account appears in the directory';
  end if;
  select count(*) into bad from owner_directory() d
   where d.activity_bucket not in ('Active recently', 'This month', 'Earlier',
                                   'Dormant', 'New, not yet active');
  if bad > 0 then
    raise exception 'FAIL: a row carries something other than a bucket label';
  end if;
  if (select d.activity_bucket from owner_directory() d where d.handle = 'ada') <> 'Active recently'
     or (select d.activity_bucket from owner_directory() d where d.handle = 'bea') <> 'Earlier'
     or (select d.activity_bucket from owner_directory() d where d.handle = 'cat') <> 'New, not yet active' then
    raise exception 'FAIL: bucket derivation is wrong';
  end if;
  if (select d.staff_role from owner_directory() d where d.handle = 'bree') <> 'owner' then
    raise exception 'FAIL: the Owner row is missing her role chip';
  end if;
  if exists (select 1 from owner_directory() d where d.handle = 'ada' and d.staff_role is not null) then
    raise exception 'FAIL: an ordinary member carries a staff role';
  end if;
end $$;

-- Search: exact-and-prefix @handle only; '@' tolerated; '_' literal.
do $$ begin
  if (select count(*) from owner_directory(p_query => 'ad')) <> 1
     or not exists (select 1 from owner_directory(p_query => '@ada') d where d.handle = 'ada') then
    raise exception 'FAIL: prefix handle search broken';
  end if;
  if (select count(*) from owner_directory(p_query => 'da')) <> 0 then
    raise exception 'FAIL: substring search must not match';
  end if;
end $$;

-- Keyset pagination: two pages of two, no overlap, newest-join first.
do $$ declare
  page1 record; last_created timestamptz; last_user uuid; n1 int; n2 int;
begin
  select count(*) into n1 from (select * from owner_directory(p_limit => 2)) p;
  if n1 <> 2 then raise exception 'FAIL: page 1 size'; end if;
  select d.joined_at, d.user_id into last_created, last_user
    from owner_directory(p_limit => 2) d order by d.joined_at asc, d.user_id asc limit 1;
  select count(*) into n2
    from owner_directory(p_before_created => last_created, p_before_user => last_user) d2
   where exists (select 1 from owner_directory(p_limit => 2) d1 where d1.user_id = d2.user_id);
  if n2 <> 0 then raise exception 'FAIL: keyset pages overlap'; end if;
end $$;

-- Activity filter composes with the rest: only ada logged in within
-- 7 days (bootstrap_owner records no login for bree).
do $$ begin
  if (select count(*) from owner_directory(p_activity => array['Active recently'])) <> 1 then
    raise exception 'FAIL: activity filter broken';
  end if;
end $$;

-- ============================================================
-- 4. The identity reveal: refused at aal1, refused without a reason,
--    and at aal2-with-reason it returns the private record AND the
--    audit log carries the reveal (with the reason) BEFORE the read.
-- ============================================================
do $$ begin
  begin
    perform * from owner_reveal_identity('00000000-0000-0000-0000-000000000003', 'test reason');
    raise exception 'FAIL: identity revealed at aal1';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"so"}', false);

do $$ begin
  begin
    perform * from owner_reveal_identity('00000000-0000-0000-0000-000000000003', '  ');
    raise exception 'FAIL: identity revealed with a blank reason';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    perform * from owner_reveal_identity('00000000-0000-0000-0000-000000000007', 'checking the system account');
    raise exception 'FAIL: the system account has no identity to reveal';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

do $$ declare r record; begin
  select * into r from owner_reveal_identity('00000000-0000-0000-0000-000000000003',
                                             'member asked me to confirm her account');
  if r.legal_name <> 'Ada Lovelace' or r.email <> 'ada@test' then
    raise exception 'FAIL: reveal returned the wrong private record';
  end if;
  if r.device_signal_count <> 0 then
    raise exception 'FAIL: device signals must be a count (0 here)';
  end if;
  if not exists (select 1 from audit_log
                 where action = 'identity.reveal'
                   and target_id = '00000000-0000-0000-0000-000000000003'
                   and detail ->> 'reason' = 'member asked me to confirm her account'
                   and detail ->> 'handle' = 'ada') then
    raise exception 'FAIL: the reveal is not in the audit log';
  end if;
end $$;

-- ============================================================
-- 5. The export: identity-free columns, and the bulk read lands in
--    the audit log with the filter set and the row count.
-- ============================================================
do $$ declare n int; begin
  select count(*) into n from owner_directory_export();
  if n <> 4 then raise exception 'FAIL: export row count'; end if;
  if not exists (select 1 from audit_log
                 where action = 'directory.export'
                   and (detail ->> 'rows')::int = 4) then
    raise exception 'FAIL: the export is not in the audit log';
  end if;
end $$;

-- ============================================================
-- 6. Metrics: honest totals, segmented breakdowns suppressed below
--    the floor (k=5) while top-line totals are exempt, and the
--    refused engagement metrics are structurally absent.
-- ============================================================
do $$ declare m jsonb; e jsonb; begin
  m := owner_metrics('30d');
  -- Top-line total: 4 real members (system excluded), shown exactly.
  if (m -> 'total_members' ->> 'value')::int <> 4 then
    raise exception 'FAIL: total members should be 4, got %', m -> 'total_members' ->> 'value';
  end if;
  -- Segmented breakdown: active = 4 members < 5 → suppressed.
  select x into e from jsonb_array_elements(m -> 'total_members' -> 'breakdown') x
   where x ->> 'status' = 'active';
  if (e ->> 'suppressed')::boolean is distinct from true or e -> 'count' <> 'null'::jsonb then
    raise exception 'FAIL: a sub-floor breakdown was not suppressed: %', e;
  end if;
  if (m ->> 'suppression_floor')::int <> 5 then
    raise exception 'FAIL: suppression floor is not 5';
  end if;
  -- Signups in the window = all 4 (everyone just joined).
  if (m -> 'signups' ->> 'value')::int <> 4 then
    raise exception 'FAIL: signups in range';
  end if;
  -- Active members (fixed 30d window): ada logged in; others have
  -- no qualifying action except bea (45d ago, outside the window).
  if (m -> 'active_members' ->> 'value')::int <> 1 then
    raise exception 'FAIL: active members should be 1, got %', m -> 'active_members' ->> 'value';
  end if;
  if (m -> 'active_members' ->> 'window_days')::int <> 30 then
    raise exception 'FAIL: active members must be the fixed 30-day window';
  end if;
  -- Zero states are real values, not absences.
  if (m -> 'reports_filed' ->> 'value')::int <> 0
     or (m -> 'enforcement_actions' ->> 'value')::int <> 0 then
    raise exception 'FAIL: zero metrics must read as 0';
  end if;
  -- The REFUSED metrics are absent by name, now and forever.
  if m ? 'dau' or m ? 'mau' or m ? 'stickiness' or m ? 'time_on_site'
     or m ? 'session_length' or m ? 'streaks' or m ? 'top_posters'
     or m ? 'most_active' or m ? 'online_now' or m ? 'presence'
     or m ? 'k_factor' or m ? 'virality' then
    raise exception 'FAIL: a refused engagement metric has appeared';
  end if;
  -- 'all' range carries no previous-period comparison.
  m := owner_metrics('all');
  if (m -> 'signups' -> 'previous') <> 'null'::jsonb then
    raise exception 'FAIL: all-time must not fabricate a comparison';
  end if;
end $$;

-- ============================================================
-- 7. Deleted accounts are gone from every surface: the directory
--    (even when asked for explicitly), the detail view, the count,
--    and the metrics headline. The system account likewise.
-- ============================================================
reset role;
update profiles set status = 'deleted' where handle = 'bea';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"so"}', false);

do $$ declare m jsonb; begin
  if exists (select 1 from owner_directory(p_statuses => array['deleted']::account_status[]) d) then
    raise exception 'FAIL: deleted accounts are browsable';
  end if;
  if exists (select 1 from owner_directory(p_statuses => array['active','restricted','suspended','banned','deactivated','deleted']::account_status[]) d
             where d.handle = 'bea') then
    raise exception 'FAIL: a deleted member appears in the directory';
  end if;
  if (select count(*) from owner_member_detail('bea')) <> 0 then
    raise exception 'FAIL: a deleted member has a detail view';
  end if;
  if owner_member_count() <> 3 then
    raise exception 'FAIL: member count must exclude the deleted';
  end if;
  m := owner_metrics('30d');
  if (m -> 'total_members' ->> 'value')::int <> 3 then
    raise exception 'FAIL: metrics headline must exclude the deleted';
  end if;
end $$;

reset role;
rollback;
\echo 'ADMIN DASHBOARD SMOKE: ALL CHECKS PASSED'
