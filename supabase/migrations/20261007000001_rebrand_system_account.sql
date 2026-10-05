-- ============================================================
-- 0015 — Rebrand: the system account becomes @herciety / "Herciety".
--
-- The naming model (owner decision 2026-10-06, recorded in
-- docs/architecture.md): Herciety is the PRODUCT BRAND and the
-- canonical domain (herciety.com). United Feminist is the COMPANY and
-- the secondary domain; unitedfeminist.com redirects to herciety.com
-- but still owns all email (safety@/appeals@/support@/legal@ and the
-- transactional sender address). Curry Co LLC is the LEGAL ENTITY.
--
-- What this migration does:
--   1. Reserves brand and platform handles BELOW the app layer. The
--      app refuses RESERVED_HANDLES (src/lib/validation.ts) in the
--      signup route, but create_member() had no equivalent database
--      check, so once the system account stops being @unitedfeminist
--      that handle would be claimable by any caller that reached the
--      database directly — a plain impersonation vector. The
--      reserved_handles table + trigger close that permanently, for
--      BOTH brand handles and the platform-reserved names.
--   2. Renames the live system account (handle + display_name). The
--      display_name trigger from 0002 returns early for is_system
--      rows, so the UPDATE passes it; updated_at is set explicitly
--      because that early return skips the touch.
--   3. CREATE OR REPLACEs create_system_account() so fresh installs
--      seed "Herciety". Same signature, same SECURITY DEFINER +
--      pinned search_path, same single-system-account guard, same
--      audit call; existing EXECUTE grants are preserved by REPLACE.
--
-- Forward-only and idempotent: safe against the live database
-- (0001-0014 applied) and safe to re-run.
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- 1. Reserved handles, enforced in the database. RLS is enabled with
--    NO policies and every app-role privilege revoked: the table is
--    invisible and immutable to anon/authenticated/service_role.
--    Only the SECURITY DEFINER trigger function reads it. Changing
--    the list is SQL, deliberate, like app_config.
-- ------------------------------------------------------------
create table if not exists reserved_handles (
  handle     citext primary key,
  reason     text not null,
  created_at timestamptz not null default now()
);
alter table reserved_handles enable row level security;
revoke all on reserved_handles from anon, authenticated, service_role;

-- Mirrors RESERVED_HANDLES in src/lib/validation.ts (the app-layer
-- check stays: it gives the polite, field-level signup error; this
-- table is the floor underneath it).
insert into reserved_handles (handle, reason) values
  ('herciety',        'Product brand; the system account''s handle.'),
  ('unitedfeminist',  'Company name and the system account''s former handle. Impersonation guard.'),
  ('united_feminist', 'Company name variant. Impersonation guard.'),
  ('admin',           'Platform-reserved.'),
  ('administrator',   'Platform-reserved.'),
  ('moderator',       'Platform-reserved.'),
  ('support',         'Platform-reserved.'),
  ('help',            'Platform-reserved.'),
  ('safety',          'Platform-reserved.'),
  ('legal',           'Platform-reserved.'),
  ('appeals',         'Platform-reserved.'),
  ('official',        'Platform-reserved.'),
  ('system',          'Platform-reserved.'),
  ('owner',           'Platform-reserved.'),
  ('staff',           'Platform-reserved.')
on conflict (handle) do nothing;

-- The system account itself is exempt (is_system), so the rename in
-- step 2 and future create_system_account() calls pass. The error is
-- a bare tag, not prose: the API route already answers reserved
-- handles before the database is reached, so this surfaces only to a
-- caller who bypassed the app layer, and it reveals nothing beyond
-- "unavailable".
create or replace function enforce_reserved_handles() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not new.is_system and exists (
    select 1 from reserved_handles r where r.handle = new.handle
  ) then
    raise exception 'handle_reserved';
  end if;
  return new;
end $$;

revoke execute on function enforce_reserved_handles() from public, anon, authenticated, service_role;

drop trigger if exists trg_profiles_reserved_handle on profiles;
create trigger trg_profiles_reserved_handle
  before insert or update of handle on profiles
  for each row execute function enforce_reserved_handles();

-- ------------------------------------------------------------
-- 2. Rename the live system account. Audited with before/after state;
--    a re-run finds nothing to change and appends nothing.
-- ------------------------------------------------------------
do $do$
declare
  v_old record;
begin
  select user_id, handle, display_name into v_old
    from profiles
   where is_system
     and (handle is distinct from 'herciety'
          or display_name is distinct from 'Herciety');
  if found then
    update profiles
       set handle       = 'herciety',
           display_name = 'Herciety',
           updated_at   = now()
     where user_id = v_old.user_id;
    perform append_audit('system.account_renamed', 'user', v_old.user_id::text,
      '{}'::jsonb,
      jsonb_build_object('handle', v_old.handle, 'display_name', v_old.display_name),
      jsonb_build_object('handle', 'herciety', 'display_name', 'Herciety'));
  end if;
end $do$;

-- ------------------------------------------------------------
-- 3. Fresh installs seed the new name (bootstrap.mjs passes the
--    matching handle 'herciety').
-- ------------------------------------------------------------
create or replace function create_system_account(p_user uuid, p_handle citext) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if exists (select 1 from profiles where is_system) then
    raise exception 'A system account already exists.';
  end if;
  insert into profiles (user_id, handle, display_name, trust_level, status, is_system)
  values (p_user, p_handle, 'Herciety', 'established', 'active', true);
  perform append_audit('system.account_created', 'user', p_user::text);
end $$;
