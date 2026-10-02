-- ============================================================
-- 0011 — Open registration: the admission gate is removed.
--
-- Owner decision (2026-10-02): "all are welcome." Fully open
-- registration. No invite, no vouch, no inviter field, no approval
-- queue, no admission lanes. Enforcement is conduct-based and
-- after the fact: bullying/harassment is a banable offense, and the
-- Owner can ban any account including new accounts a banned person
-- creates (ban-evasion matching below and in 0002's
-- banned_identifiers stays, and is now load-bearing).
--
-- This migration deletes the entire vouch/admission system as dead
-- code and replaces create_application() with create_member(), a
-- plain open-signup path that keeps the bot pre-filter signals
-- (disposable email, velocity/IP clustering, device fingerprints
-- matched against banned accounts) as auto-flagging rather than as
-- review-queue routing.
--
-- KEPT, deliberately: roles/privilege enforcement for ROLES
-- (owner-only grants, triggers, SECURITY DEFINER, REVOKEs), the
-- hash-chained audit log, account status (ban/suspension) machinery,
-- banned_identifiers, signup_attempts, email verification.
-- DROPPED: vouch_requests, admission_applications, privilege_grants
-- (its only privilege, auto_admit, existed solely for vouching),
-- every admission function, the vouch-lapse cron job, and the
-- admission-only config knobs.
--
-- Forward-only and idempotent: safe against a live database where
-- 0001–0010 are already applied, and safe to re-run.
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- 1. Unschedule the vouch-lapse job (0010) where pg_cron exists.
-- ------------------------------------------------------------
do $do$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Dynamic SQL: cron.job must not be referenced statically, or this
    -- block fails to plan on databases without pg_cron.
    execute $q$
      select cron.unschedule('uf-lapse-vouch-requests')
      where exists (select 1 from cron.job where jobname = 'uf-lapse-vouch-requests')
    $q$;
  end if;
end
$do$;

-- ------------------------------------------------------------
-- 2. Drop the admission/vouch functions. Signatures that reference
--    admission types must go before the types do.
-- ------------------------------------------------------------
drop function if exists create_application(uuid, citext, text, date, citext, text, citext, inet, bytea, jsonb, triage_bucket);
drop function if exists admit_application(uuid, admission_status, uuid);
drop function if exists confirm_vouch(uuid);
drop function if exists decline_vouch(uuid);
drop function if exists lapse_expired_vouch_requests();
drop function if exists get_my_vouch_requests();
drop function if exists my_application_status();
drop function if exists submit_info_response(text);
drop function if exists review_approve(uuid, text);
drop function if exists review_reject(uuid, text);
drop function if exists review_request_info(uuid, text);
drop function if exists owner_vouch_stats();
-- One-number-one-account was enforced at admission time; with no
-- admission step it has no enforcement point. Phone verification is
-- still under evaluation by the Owner; if it ships, uniqueness is
-- re-enforced at verification time. user_private.phone_e164 and the
-- 'phone_hash' banned_identifiers kind are kept for that future.
drop function if exists phone_in_use_by_member(uuid);
-- config_int() was only ever called by create_application().
drop function if exists config_int(text, integer);

-- ------------------------------------------------------------
-- 3. Drop the privilege machinery. auto_admit was the only privilege
--    and it existed solely for the vouch flow. ROLE machinery
--    (role_assignments, grant_role, revoke_role, triggers) is
--    untouched. If owner-grantable member privileges are ever needed
--    again, the pattern lives in git history (0003/0005).
-- ------------------------------------------------------------
drop function if exists grant_privilege(uuid, member_privilege);
drop function if exists revoke_privilege(uuid, member_privilege);
drop function if exists has_privilege(uuid, member_privilege);
drop table if exists privilege_grants; -- drops its triggers and policies
drop function if exists enforce_owner_only_privileges();

-- ------------------------------------------------------------
-- 4. Drop the admission tables and their types.
-- ------------------------------------------------------------
drop table if exists vouch_requests;
drop table if exists admission_applications; -- drops its touch trigger too
drop function if exists touch_admission_updated_at();
drop type if exists vouch_request_status;
drop type if exists admission_status;
drop type if exists triage_bucket;
drop type if exists member_privilege;

-- The accountability chain pointed at the member whose vouch covered
-- an account; with vouching gone it can never be populated again.
alter table profiles drop column if exists vouched_by;

-- Admission-only knobs. The per-IP signup rate limit stays.
delete from app_config where key in ('vouch_requests_per_member_per_day', 'vouch_deadline_hours');

-- ------------------------------------------------------------
-- 5. Bot pre-filter, repurposed: signals that used to order the
--    review queue are now recorded as auto-flags. Flagged signups
--    still get accounts (there is no queue to hold them); the Owner
--    can see the flags and act after the fact.
-- ------------------------------------------------------------
alter table user_private add column if not exists signup_flags jsonb;

-- ------------------------------------------------------------
-- 6. create_member — the single entry point for open signup.
--    Runs AFTER the auth user exists (email verification flows from
--    Supabase Auth). SECURITY DEFINER because service_role has no
--    direct INSERT on profiles/user_private (deliberately, 0009).
--
--    Ban evasion is checked HERE as well as in the API route (belt
--    and braces): a banned email or device hash raises
--    'banned_identifier', and the caller responds exactly as it does
--    on success, creating nothing. A banned person learns nothing.
-- ------------------------------------------------------------
create or replace function create_member(
  p_user_id          uuid,
  p_email            citext,
  p_legal_name       text,
  p_dob              date,
  p_handle           citext,
  p_signup_ip        inet,
  p_email_hash       bytea,
  p_fingerprint_hash bytea,
  p_signals          jsonb default '{}'::jsonb,
  p_flagged          boolean default false
) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if p_dob > (current_date - interval '18 years') then
    raise exception 'Members must be 18 or older.';
  end if;

  if (p_email_hash is not null and identifier_is_banned('email_hash', p_email_hash))
     or (p_fingerprint_hash is not null and identifier_is_banned('device_hash', p_fingerprint_hash)) then
    raise exception 'banned_identifier';
  end if;

  insert into profiles (user_id, handle, trust_level)
  values (p_user_id, p_handle, 'member');

  insert into user_private (user_id, legal_name, dob, email,
                            device_fingerprint_hash, signup_ip, signup_flags)
  values (p_user_id, p_legal_name, p_dob, p_email,
          p_fingerprint_hash, p_signup_ip,
          case when p_flagged then coalesce(p_signals, '{}'::jsonb) end);

  perform append_audit('member.signup', 'user', p_user_id::text,
                       jsonb_build_object('flagged', p_flagged,
                                          'signals', coalesce(p_signals, '{}'::jsonb)));
end $$;

revoke execute on function create_member(uuid, citext, text, date, citext, inet, bytea, bytea, jsonb, boolean) from public;
grant execute on function create_member(uuid, citext, text, date, citext, inet, bytea, bytea, jsonb, boolean) to service_role;
