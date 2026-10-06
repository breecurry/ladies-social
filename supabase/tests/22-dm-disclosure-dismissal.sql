-- Behavioral test of the DM disclosure dismissal cycle (migration
-- 20261026000001, local only). The product promise under test (owner,
-- 2026-10-06): the disclosure banner gets an X; one dismissal quiets
-- it on every DM surface for a minimum of 45 days; a bumped disclosure
-- version overrides the timer so changed copy is seen immediately;
-- every unreadable or odd state fails TOWARD SHOWING. Covers:
--   * structure: columns, exactly one signature per new function
--     (PostgREST ambiguity guard), anon locked out, authenticated in;
--   * flag off: both functions refuse (the database enforces the DM
--     feature flag inside every DM function);
--   * never dismissed shows — both as "no dm_settings row at all" and
--     as "row exists, disclosure columns null";
--   * dismissing hides, and lazy-creates the row with the table's
--     defaults intact;
--   * dismissed yesterday hides; dismissed 46 days ago shows;
--   * dismissed-but-version-bumped shows even inside the 45 days;
--   * the cycle repeats: a second dismissal quiets it again;
--   * invalid arguments refuse (dismiss) or show (should_show);
--   * a member can NEITHER read NOR write another member's dismissal
--     state — through the function (structurally: no user parameter)
--     and through the table (RLS: cross-member update touches 0 rows,
--     cross-member insert raises).
-- The 45 is a parameter here exactly as in the app: the constant
-- lives once, in src/lib/dm/disclosure.ts, and is passed in.
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000052', 'gia@test'),
  ('00000000-0000-0000-0000-000000000053', 'hana@test'),
  ('00000000-0000-0000-0000-000000000057', 'system@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_system_account('00000000-0000-0000-0000-000000000057', 'hersciety');
select create_member('00000000-0000-0000-0000-000000000052', 'gia@test',  'Gia Test',  '1995-05-05', 'gia9',  null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000053', 'hana@test', 'Hana Test', '1995-05-05', 'hana9', null, null, null, '{}'::jsonb, false);

-- ============================================================
-- 1. STRUCTURAL: the dismissal columns exist and are nullable (null =
--    never dismissed, the lazy-default pattern); each new function has
--    EXACTLY ONE signature; anon holds no EXECUTE, authenticated does.
-- ============================================================
do $$ declare f text; n integer; begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'dm_settings'
                   and column_name = 'disclosure_dismissed_at'
                   and is_nullable = 'YES') then
    raise exception 'FAIL: dm_settings.disclosure_dismissed_at missing or not nullable';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'dm_settings'
                   and column_name = 'disclosure_dismissed_version'
                   and is_nullable = 'YES') then
    raise exception 'FAIL: dm_settings.disclosure_dismissed_version missing or not nullable';
  end if;
  foreach f in array array['dm_disclosure_should_show', 'dm_dismiss_disclosure'] loop
    select count(*) into n
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public' and p.proname = f;
    if n = 0 then raise exception 'FAIL: function % missing', f; end if;
    if n > 1 then
      raise exception 'FAIL: % has % signatures — PostgREST would be ambiguous', f, n;
    end if;
  end loop;
  if has_function_privilege('anon', 'dm_disclosure_should_show(integer, integer)', 'execute') then
    raise exception 'FAIL: anon can execute dm_disclosure_should_show';
  end if;
  if has_function_privilege('anon', 'dm_dismiss_disclosure(integer)', 'execute') then
    raise exception 'FAIL: anon can execute dm_dismiss_disclosure';
  end if;
  if not has_function_privilege('authenticated', 'dm_disclosure_should_show(integer, integer)', 'execute') then
    raise exception 'FAIL: authenticated cannot execute dm_disclosure_should_show';
  end if;
  if not has_function_privilege('authenticated', 'dm_dismiss_disclosure(integer)', 'execute') then
    raise exception 'FAIL: authenticated cannot execute dm_dismiss_disclosure';
  end if;
end $$;

-- ============================================================
-- 2. FLAG OFF: both functions refuse, like every other DM function.
--    (The app treats the should_show error as "show" — and the DM
--    pages are 404 while the flag is off anyway.)
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000052', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000052","aal":"aal1","session_id":"g"}', false);
do $$ begin
  begin
    perform dm_disclosure_should_show(1, 45);
    raise exception 'FAIL: dm_disclosure_should_show ran while feature off';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm <> 'Direct messages are not available.' then
      raise exception 'FAIL: wrong off-flag error from should_show: %', sqlerrm;
    end if;
  end;
  begin
    perform dm_dismiss_disclosure(1);
    raise exception 'FAIL: dm_dismiss_disclosure ran while feature off';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm <> 'Direct messages are not available.' then
      raise exception 'FAIL: wrong off-flag error from dismiss: %', sqlerrm;
    end if;
  end;
end $$;
reset role;

insert into app_config (key, value) values ('dm_enabled', 'true'::jsonb)
on conflict (key) do update set value = 'true'::jsonb;

-- ============================================================
-- 3. THE CYCLE, as gia (who has NO dm_settings row yet):
--    never-dismissed shows → dismissing hides (and lazy-creates the
--    row with intact defaults) → yesterday hides → 46 days ago shows
--    → version bump shows inside the window → dismissing again hides
--    again. Invalid arguments refuse or show.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000052', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000052","aal":"aal1","session_id":"g"}', false);
do $$ declare s dm_settings%rowtype; begin
  -- Never dismissed, no row at all → SHOW.
  if dm_disclosure_should_show(1, 45) is distinct from true then
    raise exception 'FAIL: no dm_settings row did not show the disclosure';
  end if;

  -- Dismiss. Hides, lazy-creates the row, keeps the table defaults.
  perform dm_dismiss_disclosure(1);
  if dm_disclosure_should_show(1, 45) is distinct from false then
    raise exception 'FAIL: a fresh dismissal did not hide the disclosure';
  end if;
  select * into s from dm_settings where user_id = auth.uid();
  if not found then raise exception 'FAIL: dismissal did not lazy-create dm_settings'; end if;
  if s.requests_from <> 'everyone' or s.dms_enabled <> true or s.read_receipts <> false then
    raise exception 'FAIL: lazy-created dm_settings row lost its defaults';
  end if;
  if s.disclosure_dismissed_version <> 1 or s.disclosure_dismissed_at is null
     or s.disclosure_dismissed_at < now() - interval '1 minute' then
    raise exception 'FAIL: dismissal state not recorded with the server clock';
  end if;

  -- Invalid dismiss versions refuse.
  begin
    perform dm_dismiss_disclosure(0);
    raise exception 'FAIL: dm_dismiss_disclosure accepted version 0';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    perform dm_dismiss_disclosure(null);
    raise exception 'FAIL: dm_dismiss_disclosure accepted a null version';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;

  -- Nonsense should_show arguments fail toward SHOWING.
  if dm_disclosure_should_show(null, 45) is distinct from true then
    raise exception 'FAIL: null current version did not fail toward showing';
  end if;
  if dm_disclosure_should_show(1, null) is distinct from true then
    raise exception 'FAIL: null quiet period did not fail toward showing';
  end if;
end $$;
reset role;

-- Timer states are set directly (superuser) — the function itself
-- only ever writes now(), so past states are simulated, not forged.
update dm_settings set disclosure_dismissed_at = now() - interval '1 day'
 where user_id = '00000000-0000-0000-0000-000000000052';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000052', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000052","aal":"aal1","session_id":"g"}', false);
do $$ begin
  if dm_disclosure_should_show(1, 45) is distinct from false then
    raise exception 'FAIL: dismissed YESTERDAY did not stay hidden';
  end if;
  -- Version bump overrides the timer: same yesterday-dismissal, new
  -- disclosure copy → SHOW immediately, 45-day window or not.
  if dm_disclosure_should_show(2, 45) is distinct from true then
    raise exception 'FAIL: a bumped disclosure version did not override the quiet period';
  end if;
end $$;
reset role;

update dm_settings set disclosure_dismissed_at = now() - interval '46 days'
 where user_id = '00000000-0000-0000-0000-000000000052';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000052', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000052","aal":"aal1","session_id":"g"}', false);
do $$ begin
  if dm_disclosure_should_show(1, 45) is distinct from true then
    raise exception 'FAIL: dismissed 46 DAYS AGO did not re-show';
  end if;
  -- …and she can dismiss it again: the cycle repeats.
  perform dm_dismiss_disclosure(1);
  if dm_disclosure_should_show(1, 45) is distinct from false then
    raise exception 'FAIL: the second dismissal did not hide the disclosure again';
  end if;
end $$;
reset role;

-- ============================================================
-- 4. ROW-WITHOUT-DISMISSAL SHOWS: hana creates her dm_settings row
--    the way the settings card does (direct own-row write under RLS)
--    without ever dismissing — the null disclosure columns must SHOW.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000053', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000053","aal":"aal1","session_id":"h"}', false);
insert into dm_settings (user_id, read_receipts)
values ('00000000-0000-0000-0000-000000000053', true);
do $$ begin
  if dm_disclosure_should_show(1, 45) is distinct from true then
    raise exception 'FAIL: a dm_settings row with null disclosure columns did not show';
  end if;
end $$;
reset role;

-- ============================================================
-- 5. ISOLATION: hana can neither READ nor WRITE gia's dismissal
--    state. The function takes no user parameter (structurally own-
--    row); the table paths are closed by RLS: a cross-member UPDATE
--    matches 0 rows, a cross-member INSERT raises, a cross-member
--    SELECT sees nothing. And hana dismissing quiets NOTHING for gia.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000053', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000053","aal":"aal1","session_id":"h"}', false);
do $$ declare n integer; begin
  -- READ: gia's row is invisible to hana.
  select count(*) into n from dm_settings
   where user_id = '00000000-0000-0000-0000-000000000052';
  if n <> 0 then raise exception 'FAIL: a member can read another member''s dm_settings row'; end if;

  -- WRITE, update path: touches 0 rows.
  update dm_settings
     set disclosure_dismissed_at = now() - interval '100 days',
         disclosure_dismissed_version = 1
   where user_id = '00000000-0000-0000-0000-000000000052';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: a member updated another member''s dismissal state'; end if;

  -- WRITE, insert path: RLS refuses (gia already has a row, so use a
  -- delete-then-insert attempt? No — inserting a duplicate would hit
  -- the primary key first. Target the OWNER, who has no row, so the
  -- refusal observed is RLS, not a key collision.)
  begin
    insert into dm_settings (user_id, disclosure_dismissed_at, disclosure_dismissed_version)
    values ('00000000-0000-0000-0000-000000000001', now(), 999);
    raise exception 'FAIL: a member inserted another member''s dm_settings row';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;

  -- The function writes the CALLER only.
  perform dm_dismiss_disclosure(1);
end $$;
reset role;

-- Superuser check: hana's dismissal landed on hana's row and gia's
-- state is exactly what section 3 left there (version 1, fresh).
do $$ declare g dm_settings%rowtype; h dm_settings%rowtype; begin
  select * into g from dm_settings where user_id = '00000000-0000-0000-0000-000000000052';
  select * into h from dm_settings where user_id = '00000000-0000-0000-0000-000000000053';
  if h.disclosure_dismissed_version is distinct from 1 or h.disclosure_dismissed_at is null then
    raise exception 'FAIL: hana''s own dismissal did not land';
  end if;
  if g.disclosure_dismissed_version is distinct from 1
     or g.disclosure_dismissed_at is null
     or g.disclosure_dismissed_at < now() - interval '1 minute' then
    raise exception 'FAIL: gia''s dismissal state was altered by hana''s session';
  end if;
  if exists (select 1 from dm_settings where user_id = '00000000-0000-0000-0000-000000000001') then
    raise exception 'FAIL: the cross-member insert created a row';
  end if;
end $$;

rollback;
\echo ALL DM DISCLOSURE DISMISSAL TESTS PASSED
