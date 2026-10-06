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
--     cross-member insert raises);
--   * TAMPER GUARD (migration 20261027000001): a member cannot forge
--     her OWN dismissal state either. Direct own-row table writes to
--     disclosure_dismissed_at / disclosure_dismissed_version are
--     silently clamped by trg_dm_settings_disclosure_guard (the write
--     itself succeeds — the settings card must never start erroring —
--     but the two columns keep their previous values, or stay null on
--     insert); the settings card's exact upsert shape still works; a
--     forged future version through the RPC parameter
--     (dm_dismiss_disclosure(9999)) is recorded but INERT, because
--     should_show hides only on an EXACT version match — every forged
--     state fails TOWARD SHOWING.
-- The 45 is a parameter here exactly as in the app: the constant
-- lives once, in src/lib/dm/disclosure.ts, and is passed in.
-- (Superuser writes below that SIMULATE past states set the
-- transaction-local marker uf.allow_disclosure_dismissal first —
-- the same gate dm_dismiss_disclosure() uses — because the clamp
-- guards every path, superusers included.)
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000052', 'gia@test'),
  ('00000000-0000-0000-0000-000000000053', 'hana@test'),
  ('00000000-0000-0000-0000-000000000054', 'ida@test'),
  ('00000000-0000-0000-0000-000000000057', 'system@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_system_account('00000000-0000-0000-0000-000000000057', 'hersciety');
select create_member('00000000-0000-0000-0000-000000000052', 'gia@test',  'Gia Test',  '1995-05-05', 'gia9',  null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000053', 'hana@test', 'Hana Test', '1995-05-05', 'hana9', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000054', 'ida@test',  'Ida Test',  '1995-05-05', 'ida9',  null, null, null, '{}'::jsonb, false);

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
  -- The tamper guard (20261027000001) is in place: the trigger exists
  -- on dm_settings and fires before INSERT and UPDATE.
  select count(*) into n from pg_trigger
   where tgrelid = 'dm_settings'::regclass
     and tgname = 'trg_dm_settings_disclosure_guard';
  if n <> 1 then
    raise exception 'FAIL: trg_dm_settings_disclosure_guard missing from dm_settings';
  end if;
  select count(*) into n
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'enforce_disclosure_dismissal_path';
  if n <> 1 then
    raise exception 'FAIL: enforce_disclosure_dismissal_path has % signatures', n;
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

-- Timer states are set directly (superuser, through the clamp's own
-- marker) — the function itself only ever writes now(), so past
-- states are simulated, not forged.
select set_config('uf.allow_disclosure_dismissal', 'on', false);
update dm_settings set disclosure_dismissed_at = now() - interval '1 day'
 where user_id = '00000000-0000-0000-0000-000000000052';
select set_config('uf.allow_disclosure_dismissal', '', false);

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

select set_config('uf.allow_disclosure_dismissal', 'on', false);
update dm_settings set disclosure_dismissed_at = now() - interval '46 days'
 where user_id = '00000000-0000-0000-0000-000000000052';
select set_config('uf.allow_disclosure_dismissal', '', false);

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

-- ============================================================
-- 6. TAMPER GUARD (migration 20261027000001): the dismissal state
--    cannot be forged — not through the table, not through the RPC's
--    version parameter. At this point gia's genuine state is
--    version 1, dismissed moments ago (section 5 verified it).
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000052', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000052","aal":"aal1","session_id":"g"}', false);
do $$ declare s dm_settings%rowtype; n integer; begin
  -- 6a. A direct own-row UPDATE forging BOTH columns: the statement
  -- itself SUCCEEDS (1 row — the clamp is silent, because the
  -- settings card's writes must never start erroring) but the two
  -- disclosure columns keep their previous values.
  update dm_settings
     set disclosure_dismissed_version = 9999,
         disclosure_dismissed_at      = now() + interval '10 years'
   where user_id = auth.uid();
  get diagnostics n = row_count;
  if n <> 1 then
    raise exception 'FAIL: the clamped own-row update did not succeed silently (rows: %)', n;
  end if;
  select * into s from dm_settings where user_id = auth.uid();
  if s.disclosure_dismissed_version is distinct from 1 then
    raise exception 'FAIL: a direct table write forged disclosure_dismissed_version (now %)', s.disclosure_dismissed_version;
  end if;
  if s.disclosure_dismissed_at is null or s.disclosure_dismissed_at > now() then
    raise exception 'FAIL: a direct table write forged disclosure_dismissed_at (now %)', s.disclosure_dismissed_at;
  end if;

  -- 6b. Each column alone is clamped too.
  update dm_settings set disclosure_dismissed_version = 9999 where user_id = auth.uid();
  update dm_settings set disclosure_dismissed_at = now() + interval '10 years' where user_id = auth.uid();
  select * into s from dm_settings where user_id = auth.uid();
  if s.disclosure_dismissed_version is distinct from 1 or s.disclosure_dismissed_at > now() then
    raise exception 'FAIL: a single-column direct write forged dismissal state';
  end if;

  -- 6c. The genuine state survived the tamper attempts: still hidden
  -- for the current version, still shown for a bumped one.
  if dm_disclosure_should_show(1, 45) is distinct from false then
    raise exception 'FAIL: tamper attempts disturbed a genuine dismissal';
  end if;
  if dm_disclosure_should_show(2, 45) is distinct from true then
    raise exception 'FAIL: a bumped version no longer shows after tamper attempts';
  end if;

  -- 6d. THE SETTINGS CARD'S EXACT WRITE SHAPE still works: supabase-js
  -- .upsert({user_id, requests_from, dms_enabled, read_receipts})
  -- becomes INSERT ... ON CONFLICT (user_id) DO UPDATE SET <each
  -- payload column> = excluded.<column>. The settings it owns change;
  -- the dismissal state it never mentions is untouched.
  insert into dm_settings (user_id, requests_from, dms_enabled, read_receipts)
  values (auth.uid(), 'followed', false, true)
  on conflict (user_id) do update
     set user_id       = excluded.user_id,
         requests_from = excluded.requests_from,
         dms_enabled   = excluded.dms_enabled,
         read_receipts = excluded.read_receipts;
  select * into s from dm_settings where user_id = auth.uid();
  if s.requests_from <> 'followed' or s.dms_enabled <> false or s.read_receipts <> true then
    raise exception 'FAIL: the settings card''s upsert shape no longer updates the settings it owns';
  end if;
  if s.disclosure_dismissed_version is distinct from 1
     or s.disclosure_dismissed_at is null or s.disclosure_dismissed_at > now() then
    raise exception 'FAIL: the settings card''s upsert shape disturbed the dismissal state';
  end if;

  -- 6e. A malicious upsert that ALSO smuggles the disclosure columns
  -- into both arms: the owned settings land, the smuggled columns are
  -- clamped.
  insert into dm_settings (user_id, requests_from, disclosure_dismissed_at, disclosure_dismissed_version)
  values (auth.uid(), 'no_one', now() + interval '10 years', 9999)
  on conflict (user_id) do update
     set requests_from                = excluded.requests_from,
         disclosure_dismissed_at      = excluded.disclosure_dismissed_at,
         disclosure_dismissed_version = excluded.disclosure_dismissed_version;
  select * into s from dm_settings where user_id = auth.uid();
  if s.requests_from <> 'no_one' then
    raise exception 'FAIL: the mixed upsert did not update the owned column';
  end if;
  if s.disclosure_dismissed_version is distinct from 1 or s.disclosure_dismissed_at > now() then
    raise exception 'FAIL: a mixed upsert smuggled forged dismissal state past the clamp';
  end if;

  -- 6f. The RPC's version parameter is client-controlled at the
  -- PostgREST surface, so a forged FUTURE version gets recorded —
  -- but it is INERT: only an EXACT version match hides, so the
  -- banner shows MORE, not less. And a genuine dismissal recovers.
  perform dm_dismiss_disclosure(9999);
  if dm_disclosure_should_show(1, 45) is distinct from true then
    raise exception 'FAIL: a forged future version through the RPC hid the banner';
  end if;
  perform dm_dismiss_disclosure(1);
  if dm_disclosure_should_show(1, 45) is distinct from false then
    raise exception 'FAIL: a genuine dismissal no longer hides after an RPC forgery';
  end if;
end $$;
reset role;

-- 6g. The INSERT arm of the clamp: ida (who has NO dm_settings row)
-- writes her first row the way the card would, but smuggles forged
-- dismissal state into it. The row is created, her owned settings
-- land, the smuggled columns are clamped to null — never dismissed.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000054', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000054","aal":"aal1","session_id":"i"}', false);
do $$ declare s dm_settings%rowtype; begin
  insert into dm_settings (user_id, read_receipts, disclosure_dismissed_at, disclosure_dismissed_version)
  values (auth.uid(), true, now() + interval '10 years', 9999);
  select * into s from dm_settings where user_id = auth.uid();
  if not found or s.read_receipts <> true then
    raise exception 'FAIL: ida''s first-row insert did not land her owned settings';
  end if;
  if s.disclosure_dismissed_at is not null or s.disclosure_dismissed_version is not null then
    raise exception 'FAIL: an INSERT smuggled forged dismissal state past the clamp';
  end if;
  if dm_disclosure_should_show(1, 45) is distinct from true then
    raise exception 'FAIL: ida''s forged insert suppressed the banner';
  end if;
end $$;
reset role;

rollback;
\echo ALL DM DISCLOSURE DISMISSAL TESTS PASSED
