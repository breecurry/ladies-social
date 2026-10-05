-- ============================================================
-- 20261020000001 — Extend "AAL2 OR fresh passkey" to every remaining
-- Owner sensitive operation.
--
-- WHY. Migration 20261019000001 let a fresh passkey satisfy the
-- identity-reveal gate and deliberately stopped there, pending an
-- explicit Owner decision. The Owner has now made that decision: she
-- uses a passkey, not an authenticator app, so every operation that
-- still demanded aal2 alone was unusable by the person it exists for.
-- The combined gate — aal2 OR a passkey authentication fresh within
-- 5 minutes (owner_sensitive_auth_method(), 20261019000001; window
-- mirrored in src/lib/passkeys.ts PASSKEY_FRESHNESS_SECONDS, change
-- both together) — now covers:
--
--   * grant_role / revoke_role            (previously 0005, aal2-only)
--   * owner_unban                         (previously 0010, aal2-only)
--   * the audit_owner_read RLS policy     (previously 0009, aal2-only)
--   * the user_private_owner RLS policy   (previously 0009, aal2-only)
--
-- grant_privilege / revoke_privilege were on the Owner's list but NO
-- LONGER EXIST — 20261002000001 dropped the whole member-privilege
-- machinery. Nothing to widen there.
--
-- THIS IS AN AUTHENTICATION CHANGE, NOT AN AUTHORIZATION CHANGE.
-- Every role check is untouched: grant_role / revoke_role / owner_unban
-- still refuse everyone but the Owner (require_owner_sensitive_auth()
-- checks is_owner() before it looks at any claim, exactly as
-- require_owner_aal2() did), and both RLS policies still require
-- is_owner(). A member, admin or moderator with a perfectly fresh
-- passkey gets exactly what she got before: nothing.
--
-- THE RLS EXECUTE DECISION. RLS policy expressions run as the INVOKING
-- role, and owner_sensitive_auth_method() had EXECUTE revoked from all
-- app roles (20261019000001), so a policy calling it would fail for
-- every authenticated user. Resolution: GRANT EXECUTE on
-- owner_sensitive_auth_method() to authenticated. This is safe — the
-- function reads only the caller's own JWT claims and returns 'aal2',
-- 'passkey' or null, information the client already holds about its
-- own session; it reads no table, writes nothing, and escalates
-- nothing. The alternative (inlining the amr parsing into each policy)
-- would duplicate security logic in four places, which this project
-- avoids on principle — the freshness window must stay a one-line
-- change. require_owner_sensitive_auth() (the raising variant) stays
-- internal: nothing evaluated as an app role needs it.
--
-- AUDIT. Each operation writes the same entry as before, with the
-- detail now also recording which method satisfied the gate
-- ('auth_method': 'aal2'|'passkey'), the 20261019000001 pattern.
-- For owner_unban that detail travels through mod_record_action, which
-- gains a trailing OPTIONAL parameter; the audit entries of every
-- other moderation action are byte-identical to before (no null
-- auth_method key is ever added). The old 8-argument signature is
-- dropped in this same migration so exactly one signature remains.
--
-- require_owner_aal2() (0005) has no callers left after this migration
-- and is DROPPED — a dangling aal2-only gate invites accidental use in
-- a future operation the Owner could not pass. Repo-wide: nothing in
-- src/ or supabase/ references it (verified; suite 17 re-verifies
-- structurally).
--
-- Idempotent: safe to apply twice. RLS stays enabled on every table;
-- every function here is SECURITY DEFINER with a pinned search_path.
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- 1. Let RLS policies evaluate the gate as the querying role.
--    (See the EXECUTE decision above. anon and service_role stay
--    revoked: anon holds no SELECT on the gated tables at all, and
--    service_role bypasses RLS.)
-- ------------------------------------------------------------
grant execute on function owner_sensitive_auth_method() to authenticated;

-- ------------------------------------------------------------
-- 2. grant_role / revoke_role (0005): the gate swaps from
--    require_owner_aal2() to require_owner_sensitive_auth(); the
--    Owner check, eligibility checks, trigger protections and audit
--    entries are IDENTICAL except for the added auth_method detail.
-- ------------------------------------------------------------
create or replace function grant_role(p_target uuid, p_role system_role) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_method text;
begin
  v_method := require_owner_sensitive_auth();
  if p_role = 'owner' then
    raise exception 'The owner role cannot be granted.';
  end if;
  if not exists (select 1 from profiles
                 where user_id = p_target and status in ('active', 'restricted') and not is_system) then
    raise exception 'Target account is not eligible for a role.';
  end if;
  insert into role_assignments (user_id, role, granted_by) values (p_target, p_role, auth.uid());
  perform append_audit('role.grant', 'user', p_target::text,
                       jsonb_build_object('role', p_role, 'auth_method', v_method));
end $$;

create or replace function revoke_role(p_target uuid, p_role system_role) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_id     uuid;
  v_method text;
begin
  v_method := require_owner_sensitive_auth();
  select id into v_id from role_assignments
   where user_id = p_target and role = p_role and revoked_at is null;
  if v_id is null then
    raise exception 'No active % assignment for this user.', p_role;
  end if;
  update role_assignments set revoked_at = now(), revoked_by = auth.uid() where id = v_id;
  perform revoke_user_sessions(p_target);
  perform append_audit('role.revoke', 'user', p_target::text,
                       jsonb_build_object('role', p_role, 'auth_method', v_method),
                       jsonb_build_object('active', true),
                       jsonb_build_object('active', false));
end $$;

-- ------------------------------------------------------------
-- 3. mod_record_action (0010) gains a trailing optional
--    p_auth_method. Only owner_unban passes it; every other caller is
--    untouched and their audit detail is byte-identical (the key is
--    only added when a method is actually recorded). The old 8-arg
--    signature is dropped FIRST so exactly one signature survives —
--    a leftover overload would make PostgREST ambiguous.
-- ------------------------------------------------------------
drop function if exists mod_record_action(uuid, bigint, mod_action, report_reason, integer, text, text, timestamptz);

create or replace function mod_record_action(
  p_target uuid, p_post bigint, p_action mod_action, p_rule report_reason,
  p_days integer, p_message text, p_note text, p_expires timestamptz,
  p_auth_method text default null
) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  insert into moderation_actions
    (target_user_id, post_id, action, rule, duration_days, message, note,
     actor_id, actor_role, expires_at)
  values
    (p_target, p_post, p_action, p_rule, p_days,
     nullif(btrim(coalesce(p_message, '')), ''),
     nullif(btrim(coalesce(p_note, '')), ''),
     auth.uid(), actor_role_name(auth.uid()), p_expires);
  perform append_audit('mod.' || p_action::text, 'user', p_target::text,
                       jsonb_build_object(
                         'rule', p_rule, 'days', p_days,
                         'post_id', p_post)
                       || case when p_auth_method is null then '{}'::jsonb
                               else jsonb_build_object('auth_method', p_auth_method) end);
end $$;

-- DROP recreated the default PUBLIC execute; restore the internal-only
-- posture of 0010 (reachable solely from inside DEFINER bodies).
revoke execute on function mod_record_action(uuid, bigint, mod_action, report_reason, integer, text, text, timestamptz, text)
  from public, anon, authenticated, service_role;

-- ------------------------------------------------------------
-- 4. owner_unban (0010): same gate swap; Owner-only as before; the
--    mod.unban audit entry now records auth_method.
-- ------------------------------------------------------------
create or replace function owner_unban(p_target uuid, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_method text;
begin
  v_method := require_owner_sensitive_auth();
  if not exists (select 1 from profiles where user_id = p_target and status = 'banned') then
    raise exception 'This account is not banned.';
  end if;
  update profiles set status = 'active', status_expires_at = null
   where user_id = p_target;
  perform mod_record_action(p_target, null, 'unban', null, null, null, p_note, null, v_method);
  perform mod_notify(p_target, 'Your account has been reopened following review.', null);
end $$;

-- ------------------------------------------------------------
-- 5. The RLS reads (0009): Owner + (aal2 OR fresh passkey). The
--    is_owner() condition is unchanged — these remain invisible to
--    every other member, passkey or not. DROP+CREATE keeps this
--    re-runnable; RLS stays enabled on both tables throughout (the
--    tables default-deny between the two statements inside this
--    transaction, never the reverse).
-- ------------------------------------------------------------
drop policy if exists user_private_owner on user_private;
create policy user_private_owner on user_private for select
  using (is_owner() and owner_sensitive_auth_method() is not null);

drop policy if exists audit_owner_read on audit_log;
create policy audit_owner_read on audit_log for select
  using (is_owner() and owner_sensitive_auth_method() is not null);

-- ------------------------------------------------------------
-- 6. The aal2-only gate now has zero callers; remove it so it cannot
--    be reached for by a future migration by muscle memory.
-- ------------------------------------------------------------
drop function if exists require_owner_aal2();
