-- ============================================================
-- 0035 — DM disclosure dismissal: close the forgery paths.
--
-- The dismissal state (0034) exists so the DM disclosure banner
-- returns after the quiet period, and IMMEDIATELY when the
-- disclosure's version is bumped because the copy materially changed.
-- That reach guarantee — a changed disclosure reaches EVERY member —
-- is only real if a member cannot forge the state. Two forgeries
-- were possible, both self-inflicted but both permanent:
--
--   1. DIRECT TABLE WRITE. dm_settings keeps INSERT/UPDATE grants to
--      authenticated with own-row RLS (0020), because the settings
--      card writes requests_from / dms_enabled / read_receipts
--      directly. Nothing stopped the same own-row PostgREST write
--      from also setting disclosure_dismissed_at far in the future
--      (defeating the quiet period forever) or
--      disclosure_dismissed_version sky-high (defeating the
--      version re-show forever).
--   2. THE RPC's VERSION PARAMETER. dm_dismiss_disclosure(p_version)
--      is EXECUTE-granted to authenticated, so at the PostgREST
--      surface the version is CLIENT-controlled no matter what the
--      app's route passes. rpc dm_dismiss_disclosure(9999) forged
--      the version just like forgery 1.
--
-- What this migration does:
--
--   1. A BEFORE INSERT OR UPDATE trigger on dm_settings SILENTLY
--      CLAMPS the two disclosure columns — an INSERT gets NULL
--      ("never dismissed"), an UPDATE keeps the previous values —
--      unless a transaction-local marker is set, and the only thing
--      that sets the marker is dm_dismiss_disclosure() (the
--      owner-bootstrap GUC pattern, 0003/0005; clients cannot reach
--      set_config through PostgREST). Chosen over column-level
--      privileges because (a) the trigger guards EVERY write path,
--      present and future, not just the authenticated role's direct
--      writes, and (b) column grants would mean revoking the
--      table-level INSERT/UPDATE and enumerating allowed columns, so
--      every future dm_settings column would silently break the
--      settings card until someone remembered a grant — a failure
--      pointing the wrong way. The clamp is silent, not an error, so
--      the settings card's upsert (user_id, requests_from,
--      dms_enabled, read_receipts — it never touches the disclosure
--      columns) keeps working completely unchanged.
--   2. dm_disclosure_should_show() now hides ONLY when the recorded
--      version is EXACTLY the current one. A recorded version
--      GREATER than the current is a state the real flow can never
--      produce (nobody has dismissed a disclosure that does not
--      exist yet), so it reads as "show", like every other odd
--      state. This defangs the RPC parameter: a forged
--      dm_dismiss_disclosure(9999) now makes the banner show MORE
--      (immediately, every surface, until a genuine dismissal),
--      never less. Residual, accepted: a member who guesses the NEXT
--      version exactly can pre-dismiss that one bump, hiding it for
--      at most one quiet period from the forgery (dismissed_at is
--      always the server clock) — bounded and self-inflicted, versus
--      the unbounded hole it replaces. Closing even that would
--      require the database to know the app's current version
--      constant, which 0034 deliberately defines in exactly one
--      place (src/lib/dm/disclosure.ts).
--   3. dm_dismiss_disclosure() recreated identically plus the
--      marker, so the normal dismissal path (the X on the banner →
--      POST /api/dm/disclosure → this function) behaves exactly as
--      before.
--
-- Fail-safe direction: every clamp and every odd state reads as
-- "never dismissed" / "show". A write path nobody has thought of yet
-- can only make the banner show MORE often, never less. (This
-- includes trigger-firing bulk loads: a plain COPY restore re-shows
-- the banner rather than ever suppressing it.)
--
-- No app change: same signatures, same grants; the settings card and
-- the dismissal route are untouched. Code deployed before this
-- migration is applied behaves identically (the code did not
-- change); applying it changes nothing visible to a member who is
-- not forging writes.
--
-- Idempotent and safe to re-run against production: create-or-
-- replace, drop-trigger-if-exists, signature-qualified drops before
-- recreate (exactly one signature per function — the PostgREST
-- ambiguity guard), re-runs never touch member data.
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- 1. The clamp. Plain (invoker) plpgsql: it touches nothing but the
--    row being written and one GUC, so it needs no definer rights.
-- ------------------------------------------------------------
create or replace function enforce_disclosure_dismissal_path() returns trigger
language plpgsql set search_path = public, extensions, pg_temp as $$
begin
  if coalesce(current_setting('uf.allow_disclosure_dismissal', true), '') = 'on' then
    return new; -- inside dm_dismiss_disclosure() only
  end if;
  if tg_op = 'INSERT' then
    new.disclosure_dismissed_at      := null;
    new.disclosure_dismissed_version := null;
  else
    new.disclosure_dismissed_at      := old.disclosure_dismissed_at;
    new.disclosure_dismissed_version := old.disclosure_dismissed_version;
  end if;
  return new;
end $$;

drop trigger if exists trg_dm_settings_disclosure_guard on dm_settings;
create trigger trg_dm_settings_disclosure_guard
  before insert or update on dm_settings
  for each row execute function enforce_disclosure_dismissal_path();

-- ------------------------------------------------------------
-- 2. The show/hide rule: hide only on an EXACT version match. The
--    only change from 0034 is `<` → `is distinct from`; everything
--    else is identical.
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
  if v_version is distinct from p_current_version then
    return true;  -- not the current disclosure: older (the copy
                  -- changed since she dismissed it) or newer (a state
                  -- the real flow cannot produce — a forgery or a
                  -- rollback — which fails toward showing)
  end if;
  if v_at < now() - make_interval(days => p_quiet_days) then
    return true;  -- the quiet period has elapsed
  end if;
  return false;
end $$;

-- ------------------------------------------------------------
-- 3. Record a dismissal — caller's own row only, server clock only.
--    Identical to 0034 plus the transaction-local marker that lets
--    its write through the clamp.
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
  perform set_config('uf.allow_disclosure_dismissal', 'on', true); -- transaction-local
  insert into dm_settings (user_id, disclosure_dismissed_at, disclosure_dismissed_version)
  values (v_me, now(), p_version)
  on conflict (user_id) do update
     set disclosure_dismissed_at      = excluded.disclosure_dismissed_at,
         disclosure_dismissed_version = excluded.disclosure_dismissed_version,
         updated_at                   = now();
  perform set_config('uf.allow_disclosure_dismissal', '', true);
end $$;

-- ------------------------------------------------------------
-- 4. Privileges, the DM pattern: nothing for public/anon/service_role,
--    EXECUTE for authenticated only. (The trigger function needs no
--    grants — `returns trigger` is not invocable over PostgREST.)
-- ------------------------------------------------------------
revoke execute on function dm_disclosure_should_show(integer, integer) from public, anon, service_role;
revoke execute on function dm_dismiss_disclosure(integer)              from public, anon, service_role;

grant execute on function dm_disclosure_should_show(integer, integer) to authenticated;
grant execute on function dm_dismiss_disclosure(integer)              to authenticated;
