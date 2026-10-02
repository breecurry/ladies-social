-- ============================================================
-- 0012 — Trust level: remove 'pending_vouch' entirely.
--
-- THE FIRST-RUN TRAP THIS FIXES: profiles.trust_level defaulted to
-- 'pending_vouch' and four code paths gated on
-- trust_level <> 'pending_vouch'. Under open registration nothing
-- can ever promote an account out of that state, so every new member
-- would have been permanently and silently blocked. The enum value
-- is REMOVED (not just defaulted away) so the trap cannot return:
-- with no 'pending_vouch' label in the type, no future code path can
-- park anyone in it.
--
-- 'member' and 'established' are kept: bootstrap and the system
-- account use 'established', and later phases use it for trust-tiered
-- decisions (e.g. media-scan sampling rates).
--
-- Postgres cannot drop a value from an enum, so the type is
-- recreated and the dependent column retyped. The only other
-- dependents were functions already dropped or replaced (0011 dropped
-- the admission functions and grant_privilege's trust check went with
-- the privilege machinery; is_admitted_member is replaced below).
--
-- Forward-only and idempotent.
-- ============================================================
set search_path = public, extensions;

-- The profiles_read policy depends on is_admitted_member(), which
-- references 'pending_vouch'. Both are replaced below.
drop policy if exists profiles_read on profiles;
drop function if exists is_admitted_member();

do $do$
begin
  if exists (select 1
             from pg_enum e
             join pg_type t on t.oid = e.enumtypid
             where t.typname = 'trust_level' and e.enumlabel = 'pending_vouch') then
    -- Migrate existing rows out of the removed state first. These are
    -- accounts the old gate left unadmitted; under "all are welcome"
    -- they are simply members.
    update profiles set trust_level = 'member' where trust_level = 'pending_vouch';

    alter table profiles alter column trust_level drop default;
    alter type trust_level rename to trust_level_old;
    create type trust_level as enum ('member', 'established');
    alter table profiles
      alter column trust_level type trust_level
      using (trust_level::text::trust_level);
    drop type trust_level_old;
  end if;
end
$do$;

-- New accounts are members from the moment they exist.
alter table profiles alter column trust_level set default 'member';

-- Replaces is_admitted_member(): with no admission step, "may use the
-- platform" is purely an account-status question. Suspended, banned,
-- deactivated and deleted accounts stay locked out exactly as before.
create or replace function is_active_member() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (
    select 1 from profiles
    where user_id = auth.uid()
      and status in ('active', 'restricted')
  )
$$;

create policy profiles_read on profiles for select
  using ((is_active_member() or user_id = auth.uid()) and status <> 'deleted');
