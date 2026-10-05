-- ============================================================
-- 0016 — Brand spelling correction: "Herciety" becomes "HERSCIETY".
--
-- Owner correction 2026-10-07: the brand is Hersciety, with an S, and
-- the canonical domain is hersciety.com (held in her Cloudflare
-- account). The 0015 rebrand used the misspelling "Herciety";
-- herciety.com (no S) is a DIFFERENT domain owned by a third party and
-- must never be referenced anywhere.
--
-- What this migration does:
--   1. Reserves the correct handle 'hersciety' (and 'her_society'),
--      KEEPS 'herciety' reserved permanently - the misspelling is a
--      live impersonation vector - and corrects the recorded reasons.
--   2. Renames the system account to @hersciety / "Hersciety". Matches
--      ANY is_system row not already carrying the final name, so it
--      works whether the account was bootstrapped as @unitedfeminist,
--      renamed to @herciety by 0015, or seeded fresh. The 0002
--      display_name trigger returns early for is_system rows, so the
--      UPDATE passes it; updated_at is set explicitly because that
--      early return skips the touch.
--   3. CREATE OR REPLACEs create_system_account() to seed "Hersciety"
--      (same signature, SECURITY DEFINER, pinned search_path, single-
--      system-account guard, audit; REPLACE preserves grants).
--
-- Forward-only and idempotent: safe against the live database
-- (0001-0015 applied) and safe to re-run.
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- 1. Reserved handles. Both brand spellings stay reserved forever.
--    The UPDATEs are value-idempotent (re-runs rewrite the same text).
-- ------------------------------------------------------------
insert into reserved_handles (handle, reason) values
  ('hersciety',   'Product brand; the system account''s handle.'),
  ('her_society', 'Brand-adjacent variant. Impersonation guard.')
on conflict (handle) do nothing;

update reserved_handles
   set reason = 'Misspelling of the brand; the matching domain belongs to an unrelated third party. Impersonation guard.'
 where handle = 'herciety';

-- ------------------------------------------------------------
-- 2. Rename the system account. Audited with before/after state; a
--    re-run finds nothing to change and appends nothing.
-- ------------------------------------------------------------
do $do$
declare
  v_old record;
begin
  select user_id, handle, display_name into v_old
    from profiles
   where is_system
     and (handle is distinct from 'hersciety'
          or display_name is distinct from 'Hersciety');
  if found then
    update profiles
       set handle       = 'hersciety',
           display_name = 'Hersciety',
           updated_at   = now()
     where user_id = v_old.user_id;
    perform append_audit('system.account_renamed', 'user', v_old.user_id::text,
      '{}'::jsonb,
      jsonb_build_object('handle', v_old.handle, 'display_name', v_old.display_name),
      jsonb_build_object('handle', 'hersciety', 'display_name', 'Hersciety'));
  end if;
end $do$;

-- ------------------------------------------------------------
-- 3. Fresh installs seed the corrected name (bootstrap.mjs passes the
--    matching handle 'hersciety').
-- ------------------------------------------------------------
create or replace function create_system_account(p_user uuid, p_handle citext) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if exists (select 1 from profiles where is_system) then
    raise exception 'A system account already exists.';
  end if;
  insert into profiles (user_id, handle, display_name, trust_level, status, is_system)
  values (p_user, p_handle, 'Hersciety', 'established', 'active', true);
  perform append_audit('system.account_created', 'user', p_user::text);
end $$;
