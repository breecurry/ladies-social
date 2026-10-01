-- ============================================================
-- 0005 — Role/privilege grant functions + owner bootstrap + session kill.
--
-- These SECURITY DEFINER functions are the ONLY write path to
-- role_assignments and privilege_grants (write privileges on the
-- tables themselves are revoked from every app role in 0009).
-- Every one re-checks Owner identity and requires AAL2 (a recent MFA
-- step-up) from the JWT, so a stolen aal1 session cannot change roles.
-- ============================================================
set search_path = public, extensions;

-- One-time owner seed. EXECUTE is granted to service_role only (0009);
-- it refuses to run twice. The transaction-local GUC is the only thing
-- the Layer-1 trigger accepts for an owner-role insert. Creates the
-- Owner's profile + private record too, because service_role has no
-- direct INSERT on those tables (deliberately).
create or replace function bootstrap_owner(
  p_user       uuid,
  p_handle     citext,
  p_legal_name text,
  p_dob        date,
  p_email      citext,
  p_phone      text default null
) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if exists (select 1 from role_assignments where role = 'owner' and revoked_at is null) then
    raise exception 'An Owner already exists; the owner role cannot be granted again.';
  end if;
  insert into profiles (user_id, handle, trust_level, status)
  values (p_user, p_handle, 'established', 'active');
  insert into user_private (user_id, legal_name, dob, email, phone_e164)
  values (p_user, p_legal_name, p_dob, p_email, nullif(p_phone, ''));
  perform set_config('uf.allow_owner_bootstrap', 'on', true); -- transaction-local
  insert into role_assignments (user_id, role, granted_by) values (p_user, 'owner', p_user);
  perform set_config('uf.allow_owner_bootstrap', '', true);
  perform append_audit('owner.bootstrap', 'user', p_user::text);
end $$;

-- The unblockable "United Feminist" system account (official notices
-- come from it, never from a personal account). Owner-seeded once.
create or replace function create_system_account(p_user uuid, p_handle citext) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if exists (select 1 from profiles where is_system) then
    raise exception 'A system account already exists.';
  end if;
  insert into profiles (user_id, handle, display_name, trust_level, status, is_system)
  values (p_user, p_handle, 'United Feminist', 'established', 'active', true);
  perform append_audit('system.account_created', 'user', p_user::text);
end $$;

create or replace function require_owner_aal2() returns void
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if not is_owner() then
    raise exception 'Only the Owner may perform this action.';
  end if;
  if coalesce(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' then
    raise exception 'Re-authentication (MFA step-up) is required for this action.';
  end if;
end $$;

-- Kill every session + refresh token for a user so a role/privilege
-- revocation takes effect within one short JWT window (15–30 min).
-- Defensive: if this environment denies access to the auth schema,
-- the revocation itself still succeeds and the short JWT expiry bounds
-- the exposure.
create or replace function revoke_user_sessions(p_user uuid) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  begin
    delete from auth.refresh_tokens where user_id = p_user::text;
    delete from auth.sessions where user_id = p_user;
  exception when insufficient_privilege or undefined_table then
    raise warning 'Could not revoke auth sessions for %; relying on JWT expiry.', p_user;
  end;
end $$;

create or replace function grant_role(p_target uuid, p_role system_role) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  perform require_owner_aal2();
  if p_role = 'owner' then
    raise exception 'The owner role cannot be granted.';
  end if;
  if not exists (select 1 from profiles
                 where user_id = p_target and status in ('active', 'restricted') and not is_system) then
    raise exception 'Target account is not eligible for a role.';
  end if;
  insert into role_assignments (user_id, role, granted_by) values (p_target, p_role, auth.uid());
  perform append_audit('role.grant', 'user', p_target::text,
                       jsonb_build_object('role', p_role));
end $$;

create or replace function revoke_role(p_target uuid, p_role system_role) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_id uuid;
begin
  perform require_owner_aal2();
  select id into v_id from role_assignments
   where user_id = p_target and role = p_role and revoked_at is null;
  if v_id is null then
    raise exception 'No active % assignment for this user.', p_role;
  end if;
  update role_assignments set revoked_at = now(), revoked_by = auth.uid() where id = v_id;
  perform revoke_user_sessions(p_target);
  perform append_audit('role.revoke', 'user', p_target::text,
                       jsonb_build_object('role', p_role),
                       jsonb_build_object('active', true),
                       jsonb_build_object('active', false));
end $$;

create or replace function grant_privilege(p_target uuid, p_privilege member_privilege) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  perform require_owner_aal2();
  if not exists (select 1 from profiles
                 where user_id = p_target
                   and trust_level <> 'pending_vouch'
                   and status in ('active', 'restricted')
                   and not is_system) then
    raise exception 'Target account is not an admitted member in good standing.';
  end if;
  insert into privilege_grants (user_id, privilege, granted_by) values (p_target, p_privilege, auth.uid());
  perform append_audit('privilege.grant', 'user', p_target::text,
                       jsonb_build_object('privilege', p_privilege));
end $$;

create or replace function revoke_privilege(p_target uuid, p_privilege member_privilege) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_id uuid;
begin
  perform require_owner_aal2();
  select id into v_id from privilege_grants
   where user_id = p_target and privilege = p_privilege and revoked_at is null;
  if v_id is null then
    raise exception 'No active % grant for this user.', p_privilege;
  end if;
  update privilege_grants set revoked_at = now(), revoked_by = auth.uid() where id = v_id;
  perform append_audit('privilege.revoke', 'user', p_target::text,
                       jsonb_build_object('privilege', p_privilege),
                       jsonb_build_object('active', true),
                       jsonb_build_object('active', false));
end $$;
