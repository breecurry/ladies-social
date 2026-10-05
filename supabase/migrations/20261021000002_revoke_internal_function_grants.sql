-- 20261021000002_revoke_internal_function_grants.sql
--
-- SECURITY FIX (pre-launch audit, 2026-10-05).
--
-- ROOT CAUSE
-- Supabase's hosted initialisation runs
--     grant execute on all routines in schema public to anon, authenticated;
-- as an EXPLICIT grant to those two roles. Migration 0009 hardened the
-- then-existing functions with `revoke execute ... from public`, which only
-- removes the PUBLIC pseudo-role grant and does NOT remove an explicit
-- per-role grant. Every function created from migration 0010 onward revokes
-- from `public, anon, authenticated, service_role` individually and is
-- therefore unaffected. The functions below predate that pattern and were
-- left reachable by unauthenticated callers through PostgREST.
--
-- VERIFIED BEFORE WRITING THIS MIGRATION
--   * All ten functions are invoked by the application exclusively through
--     the service_role admin client (src/app/api/auth/signup/route.ts,
--     src/app/api/auth/age-gate/route.ts), or only from inside other
--     SECURITY DEFINER bodies, which execute as `postgres` and do not
--     consult the calling role's EXECUTE privilege.
--   * `append_audit` has zero call sites in application code.
--   * service_role retains EXECUTE on all ten (confirmed via
--     has_function_privilege against the live database).
-- Therefore revoking anon/authenticated changes nothing for legitimate use.
--
-- WHAT EACH REVOKE CLOSES
--   revoke_user_sessions          unauthenticated session DoS: any caller
--                                 could force any member, including the
--                                 Owner, out of every session by passing a
--                                 user_id read from `profiles`.
--   append_audit                  audit-log injection: a caller controlled
--                                 action/target/detail and could fabricate
--                                 `identity.reveal`-style entries, polluting
--                                 the tamper-evidence record.
--   record_signup_attempt         rate-limiter poisoning: a caller could
--                                 write attempts against an arbitrary IP and
--                                 exhaust a third party's signup budget.
--   identifier_is_banned          ban-evasion oracle: a caller could test
--                                 arbitrary hashes against the ban list.
--   count_signup_attempts_from_ip reconnaissance on throttling state.
--   count_signups_from_subnet     reconnaissance on throttling state.
--   create_member                 profile creation for an arbitrary user_id.
--   bootstrap_owner               inert post-bootstrap, revoked for hygiene.
--   create_system_account         inert post-bootstrap, revoked for hygiene.
--   is_active_owner               owner enumeration by user_id.
--
-- IDEMPOTENT: `revoke` on a privilege that is already absent is a no-op in
-- PostgreSQL, so this file is safe to run repeatedly.

set search_path = public, extensions;

revoke execute on function revoke_user_sessions(uuid)
  from anon, authenticated;

revoke execute on function append_audit(text, text, text, jsonb, jsonb, jsonb)
  from anon, authenticated;

revoke execute on function record_signup_attempt(inet, bytea)
  from anon, authenticated;

revoke execute on function identifier_is_banned(text, bytea)
  from anon, authenticated;

revoke execute on function count_signup_attempts_from_ip(inet, interval)
  from anon, authenticated;

revoke execute on function count_signups_from_subnet(inet, interval)
  from anon, authenticated;

revoke execute on function create_member(
  uuid, citext, text, date, citext, inet, bytea, bytea, jsonb, boolean)
  from anon, authenticated;

revoke execute on function bootstrap_owner(
  uuid, citext, text, date, citext, text)
  from anon, authenticated;

revoke execute on function create_system_account(uuid, citext)
  from anon, authenticated;

-- ---------------------------------------------------------------------------
-- SECOND ROOT CAUSE — the mirror image of the first, found while verifying
-- that the revokes above had actually landed.
--
-- `is_active_owner` and `actor_role_name` carry an explicit grant to the
-- PUBLIC pseudo-role (`proacl` shows `=X/postgres`). anon and authenticated
-- therefore inherit EXECUTE through PUBLIC and never held a grant of their
-- own, so `revoke ... from anon, authenticated` is a silent no-op against
-- them. The first nine revokes above worked precisely because migration 0009
-- had already stripped their PUBLIC grant.
--
-- 🪤 THE GENERAL TRAP, both directions:
--      revoke from public             does NOT remove an explicit anon grant
--      revoke from anon, authenticated does NOT remove a PUBLIC grant
--    Always revoke from `public, anon, authenticated` together, and ALWAYS
--    re-read `has_function_privilege` afterwards — a revoke that removes
--    nothing still returns success.
--
-- VERIFIED SAFE TO REVOKE FROM PUBLIC:
--   is_active_owner(uuid)   zero RLS policies reference it; zero call sites
--                           in application code.
--   actor_role_name(uuid)   zero RLS policies reference it; zero call sites
--                           in application code; called only from inside
--                           `mod_record_action` and `append_audit`, both
--                           SECURITY DEFINER and therefore executing as
--                           `postgres`, which ignores the caller's EXECUTE.
--
-- ⛔ DELIBERATELY NOT REVOKED — these must stay reachable by `authenticated`
--    or row-level security breaks platform-wide. Each takes NO arguments and
--    reads only `auth.uid()`, so they leak nothing about any other member:
--      is_active_member()  is_owner()  is_admin_or_owner()
--      is_moderator_or_above()  is_reviewer_or_above()
--    The remaining PUBLIC-granted entries (audit_hash_chain,
--    enforce_display_name_is_legal_name, enforce_owner_only_grants,
--    stamp_status_change, forbid_delete, forbid_update) are TRIGGER
--    functions, which cannot be meaningfully invoked outside trigger
--    context. Left alone deliberately.

revoke execute on function is_active_owner(uuid)
  from public, anon, authenticated;

revoke execute on function actor_role_name(uuid)
  from public, anon, authenticated;
