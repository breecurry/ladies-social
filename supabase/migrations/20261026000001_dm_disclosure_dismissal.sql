-- ============================================================
-- 0034 — DM disclosure banner: dismissible, on a 45-day cycle.
--
-- Owner decision (2026-10-06): the DM disclosure banner (original
-- decision 2026-10-05) gets an X. Once a member dismisses it she does
-- not see it again for a minimum quiet period (45 days today — the
-- number is a single constant in the app, src/lib/dm/disclosure.ts,
-- and is passed into the functions below rather than duplicated
-- here). After the quiet period it returns at full prominence and can
-- be dismissed again. THE COPY ITSELF IS UNCHANGED and remains
-- load-bearing against the published Privacy Policy §5.
--
-- What this migration does:
--   1. Two nullable columns on dm_settings (the existing lazy-create
--      table: absent row = defaults, here "never dismissed"):
--        * disclosure_dismissed_at      — when she last dismissed it;
--        * disclosure_dismissed_version — WHICH disclosure she
--          dismissed. The version exists so a CHANGED disclosure
--          overrides the timer: if the copy ever materially changes
--          (because staff access behaviour changed), the app bumps
--          its version constant and every member sees the new text
--          immediately, not up to 45 days later.
--   2. dm_disclosure_should_show(current_version, quiet_days) — the
--      single show/hide rule, evaluated against the database clock
--      (never a client clock). Shows when ANY of: never dismissed
--      (including no dm_settings row), dismissed version older than
--      the current version, or dismissed longer ago than the quiet
--      period. Only an explicit false hides; every odd state shows.
--   3. dm_dismiss_disclosure(version) — records a dismissal for the
--      CALLER ONLY (auth.uid(); there is no user parameter, so
--      writing another member's state through this function is
--      structurally impossible). Timestamps with now() server-side.
--
-- Both functions follow the neighbouring DM conventions exactly:
-- SECURITY DEFINER, pinned search_path, assert_dm_enabled() inside
-- (the database enforces the feature flag in every DM function),
-- revoked from public/anon/service_role, granted to authenticated
-- only. dm_settings RLS (own-row only) is unchanged and still guards
-- the direct table path.
--
-- Idempotent and safe to re-run against production: guarded column
-- adds, signature-qualified drops before recreate (exactly one
-- signature per function — the PostgREST ambiguity guard), re-runs
-- never touch member data.
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- 1. Dismissal state on dm_settings. Nullable, no default: an absent
--    row OR null columns both read as "never dismissed", preserving
--    the table's lazy-create pattern (0020).
-- ------------------------------------------------------------
alter table dm_settings add column if not exists disclosure_dismissed_at timestamptz;
alter table dm_settings add column if not exists disclosure_dismissed_version integer;

do $$ begin
  if not exists (select 1 from pg_constraint
                 where conname = 'dm_settings_disclosure_version_positive'
                   and conrelid = 'dm_settings'::regclass) then
    alter table dm_settings add constraint dm_settings_disclosure_version_positive
      check (disclosure_dismissed_version is null or disclosure_dismissed_version >= 1);
  end if;
end $$;

-- ------------------------------------------------------------
-- 2. The show/hide rule. The version and the quiet period are
--    parameters so each is defined ONCE, in the app, next to the UI
--    that uses them. The decision clock is now() — the database's —
--    so a wrong client clock can neither hide the banner longer nor
--    forge a dismissal time.
-- ------------------------------------------------------------
drop function if exists dm_disclosure_should_show(integer, integer);
create function dm_disclosure_should_show(p_current_version integer, p_quiet_days integer)
returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me      uuid := auth.uid();
  v_at      timestamptz;
  v_version integer;
begin
  perform assert_dm_enabled();
  if v_me is null then raise exception 'Not signed in.'; end if;
  -- Nonsense arguments fail toward showing: a disclosure's safe
  -- failure direction is visible.
  if p_current_version is null or p_quiet_days is null or p_quiet_days < 0 then
    return true;
  end if;
  select s.disclosure_dismissed_at, s.disclosure_dismissed_version
    into v_at, v_version
    from dm_settings s
   where s.user_id = v_me;
  if not found or v_at is null or v_version is null then
    return true;  -- never dismissed (including: no dm_settings row yet)
  end if;
  if v_version < p_current_version then
    return true;  -- the disclosure changed since she dismissed it
  end if;
  if v_at < now() - make_interval(days => p_quiet_days) then
    return true;  -- the quiet period has elapsed
  end if;
  return false;
end $$;

-- ------------------------------------------------------------
-- 3. Record a dismissal — caller's own row only, server clock only.
--    Lazy-creates the dm_settings row with its defaults when absent.
-- ------------------------------------------------------------
drop function if exists dm_dismiss_disclosure(integer);
create function dm_dismiss_disclosure(p_version integer)
returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_me uuid := auth.uid();
begin
  perform assert_dm_enabled();
  if v_me is null then raise exception 'Not signed in.'; end if;
  if not is_active_member() then raise exception 'Not an active member.'; end if;
  if p_version is null or p_version < 1 then
    raise exception 'Invalid disclosure version.';
  end if;
  insert into dm_settings (user_id, disclosure_dismissed_at, disclosure_dismissed_version)
  values (v_me, now(), p_version)
  on conflict (user_id) do update
     set disclosure_dismissed_at      = excluded.disclosure_dismissed_at,
         disclosure_dismissed_version = excluded.disclosure_dismissed_version,
         updated_at                   = now();
end $$;

-- ------------------------------------------------------------
-- 4. Privileges, the DM pattern: nothing for public/anon/service_role,
--    EXECUTE for authenticated only.
-- ------------------------------------------------------------
revoke execute on function dm_disclosure_should_show(integer, integer) from public, anon, service_role;
revoke execute on function dm_dismiss_disclosure(integer)              from public, anon, service_role;

grant execute on function dm_disclosure_should_show(integer, integer) to authenticated;
grant execute on function dm_dismiss_disclosure(integer)              to authenticated;
