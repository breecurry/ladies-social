-- ============================================================
-- 0003 — Roles and privileges: Owner-only grants, enforced at the
-- database layer (two independent layers, per the roles design):
--
--   Layer 1: BEFORE triggers on role_assignments / privilege_grants
--            reject any write whose actor is not the active Owner —
--            even a code path that somehow obtains INSERT cannot grant.
--   Layer 2 (0009): ALL write privileges on these tables are REVOKEd
--            from anon, authenticated AND service_role. The only write
--            path is the SECURITY DEFINER functions in 0005, which
--            re-check Owner + AAL2 themselves. SQL injection in an
--            admin endpoint therefore cannot escalate: the endpoint's
--            database role simply has no INSERT to abuse.
-- ============================================================
set search_path = public, extensions;

create table role_assignments (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles (user_id),
  role       system_role not null,
  granted_by uuid not null references profiles (user_id),
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by uuid references profiles (user_id)
);
create unique index uq_active_role   on role_assignments (user_id, role) where revoked_at is null;
create unique index uq_single_owner  on role_assignments (role) where role = 'owner' and revoked_at is null;
create index idx_role_assignments_user on role_assignments (user_id);

-- auto_admit lives here: a grantable, revocable privilege — NOT an
-- earned counter. Same Owner-only enforcement as roles.
create table privilege_grants (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles (user_id),
  privilege  member_privilege not null,
  granted_by uuid not null references profiles (user_id),
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by uuid references profiles (user_id)
);
create unique index uq_active_privilege on privilege_grants (user_id, privilege) where revoked_at is null;
create index idx_privilege_grants_user on privilege_grants (user_id);

-- ------------------------------------------------------------
-- Helper predicates (SECURITY DEFINER: they bypass RLS, which also
-- breaks the self-reference recursion when used inside policies).
-- ------------------------------------------------------------
create or replace function is_active_owner(p_user uuid) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (
    select 1 from role_assignments
    where user_id = p_user and role = 'owner' and revoked_at is null
  )
$$;

create or replace function is_owner() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select is_active_owner(auth.uid())
$$;

create or replace function is_admin_or_owner() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (
    select 1 from role_assignments
    where user_id = auth.uid() and role in ('owner', 'admin') and revoked_at is null
  )
$$;

create or replace function is_moderator_or_above() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (
    select 1 from role_assignments
    where user_id = auth.uid() and role in ('owner', 'admin', 'moderator') and revoked_at is null
  )
$$;

-- T&S reviewer: READ-ONLY queue access; included for queue visibility only.
create or replace function is_reviewer_or_above() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (
    select 1 from role_assignments
    where user_id = auth.uid()
      and role in ('owner', 'admin', 'moderator', 'ts_reviewer')
      and revoked_at is null
  )
$$;

create or replace function has_privilege(p_user uuid, p_privilege member_privilege) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (
    select 1 from privilege_grants
    where user_id = p_user and privilege = p_privilege and revoked_at is null
  )
$$;

-- An admitted member in acceptable standing (used by profile RLS so
-- pending applicants cannot browse membership).
create or replace function is_admitted_member() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (
    select 1 from profiles
    where user_id = auth.uid()
      and trust_level <> 'pending_vouch'
      and status in ('active', 'restricted')
  )
$$;

-- Actor's highest role name, recorded in the audit log at action time.
create or replace function actor_role_name(p_user uuid) returns text
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(
    (select role::text from role_assignments
     where user_id = p_user and revoked_at is null
     order by case role
       when 'owner' then 0 when 'admin' then 1
       when 'moderator' then 2 else 3 end
     limit 1),
    'member')
$$;

-- ------------------------------------------------------------
-- Layer 1 triggers. The owner role itself is never grantable; it is
-- seeded exactly once by bootstrap_owner() (0005) via a transaction-
-- local GUC that nothing else sets. Assignments are append-only:
-- the only legal UPDATE is filling in the revocation fields, and only
-- the Owner can do that. DELETE is forbidden outright (history).
-- ------------------------------------------------------------
create or replace function enforce_owner_only_grants() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    if new.role = 'owner' then
      if coalesce(current_setting('uf.allow_owner_bootstrap', true), '') = 'on'
         and not exists (select 1 from role_assignments where role = 'owner' and revoked_at is null) then
        return new; -- one-time seed, via bootstrap_owner() only
      end if;
      raise exception 'The owner role cannot be granted.';
    end if;
    if new.revoked_at is not null or new.revoked_by is not null then
      raise exception 'New role assignments cannot be created pre-revoked.';
    end if;
    if not is_active_owner(new.granted_by) then
      raise exception 'Only the Owner may grant roles.';
    end if;
    return new;
  end if;

  -- UPDATE: revocation only, by the Owner only.
  if new.role = 'owner' then
    raise exception 'The owner role cannot be modified.';
  end if;
  if new.user_id <> old.user_id or new.role <> old.role
     or new.granted_by <> old.granted_by or new.granted_at <> old.granted_at then
    raise exception 'Role assignments are immutable; only revocation fields may change.';
  end if;
  if old.revoked_at is not null then
    raise exception 'This role assignment is already revoked.';
  end if;
  if new.revoked_at is null or new.revoked_by is null or not is_active_owner(new.revoked_by) then
    raise exception 'Only the Owner may revoke roles.';
  end if;
  return new;
end $$;

create trigger trg_roles_owner_only
  before insert or update on role_assignments
  for each row execute function enforce_owner_only_grants();

create or replace function forbid_delete() returns trigger
language plpgsql as $$
begin
  raise exception 'Rows in %.% cannot be deleted.', tg_table_schema, tg_table_name;
end $$;

create trigger trg_roles_no_delete
  before delete on role_assignments
  for each row execute function forbid_delete();

create or replace function enforce_owner_only_privileges() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    if new.revoked_at is not null or new.revoked_by is not null then
      raise exception 'New privilege grants cannot be created pre-revoked.';
    end if;
    if not is_active_owner(new.granted_by) then
      raise exception 'Only the Owner may grant privileges.';
    end if;
    return new;
  end if;

  if new.user_id <> old.user_id or new.privilege <> old.privilege
     or new.granted_by <> old.granted_by or new.granted_at <> old.granted_at then
    raise exception 'Privilege grants are immutable; only revocation fields may change.';
  end if;
  if old.revoked_at is not null then
    raise exception 'This privilege grant is already revoked.';
  end if;
  if new.revoked_at is null or new.revoked_by is null or not is_active_owner(new.revoked_by) then
    raise exception 'Only the Owner may revoke privileges.';
  end if;
  return new;
end $$;

create trigger trg_privileges_owner_only
  before insert or update on privilege_grants
  for each row execute function enforce_owner_only_privileges();

create trigger trg_privileges_no_delete
  before delete on privilege_grants
  for each row execute function forbid_delete();
