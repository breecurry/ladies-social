-- ============================================================
-- 0009 — Row Level Security + privilege lockdown.
--
-- Everything gets RLS ENABLED. A table with no policy for an operation
-- denies it. On top of RLS, raw write privileges on sensitive tables
-- are REVOKEd from anon, authenticated and — for the security-critical
-- tables — from service_role as well, so the ONLY write path is the
-- SECURITY DEFINER functions. RLS protects against policy mistakes;
-- the REVOKEs protect against bugs and injection in server code that
-- holds the service key.
-- ============================================================
set search_path = public, extensions;

alter table profiles               enable row level security;
alter table user_private           enable row level security;
alter table banned_identifiers     enable row level security;
alter table signup_attempts        enable row level security;
alter table app_config             enable row level security;
alter table role_assignments       enable row level security;
alter table privilege_grants       enable row level security;
alter table audit_log              enable row level security;
alter table admission_applications enable row level security;
alter table vouch_requests         enable row level security;
alter table user_devices           enable row level security;
alter table one_time_prekeys       enable row level security;

-- ------------------------------------------------------------
-- profiles: readable by ADMITTED members (and always by yourself).
-- Pending applicants cannot browse membership — an applicant must not
-- be able to use a half-made account to confirm who is on the platform.
-- ------------------------------------------------------------
create policy profiles_read on profiles for select
  using ((is_admitted_member() or user_id = auth.uid()) and status <> 'deleted');

-- Self-update of non-identity fields. display_name is additionally
-- constrained by trigger to NULL or the verified legal name; handle,
-- trust_level, status, is_system, founding_member, vouched_by changes
-- are blocked by column-level privileges below.
create policy profiles_self_update on profiles for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

revoke all on profiles from anon;
revoke insert, update, delete on profiles from authenticated;
grant update (display_name, bio, avatar_media_key, search_indexable) on profiles to authenticated;
-- Inserts happen only inside create_application()/bootstrap (DEFINER).
revoke insert, update, delete on profiles from service_role;

-- ------------------------------------------------------------
-- user_private: the subject may read her own row; the Owner may read
-- all rows but ONLY with a fresh MFA step-up (AAL2) — contact info
-- views are privileged actions. Admins and moderators get nothing.
-- No one writes directly, service_role included.
-- ------------------------------------------------------------
create policy user_private_self on user_private for select
  using (auth.uid() = user_id);
create policy user_private_owner on user_private for select
  using (is_owner() and coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2');

revoke all on user_private from anon;
revoke insert, update, delete on user_private from authenticated;
revoke insert, update, delete on user_private from service_role;

-- ------------------------------------------------------------
-- banned_identifiers / signup_attempts / app_config: server-side only.
-- No policies -> deny for anon/authenticated; service_role reads
-- (RLS-bypass) and writes where its grants below allow.
-- ------------------------------------------------------------
revoke all on banned_identifiers from anon, authenticated;
revoke all on signup_attempts    from anon, authenticated;
revoke all on app_config         from anon, authenticated;
revoke insert, update, delete on app_config from service_role; -- config changes are SQL, deliberate

-- ------------------------------------------------------------
-- role_assignments / privilege_grants: visible to the Owner and to the
-- subject. NO write privilege for ANY app role — service_role included.
-- Writes exist only through grant_role()/revoke_role()/grant_privilege()
-- /revoke_privilege(), which enforce Owner + AAL2, on top of the
-- Layer-1 triggers. This is the "injection cannot escalate" guarantee.
-- ------------------------------------------------------------
create policy roles_visible on role_assignments for select
  using (is_owner() or user_id = auth.uid());
create policy privileges_visible on privilege_grants for select
  using (is_owner() or user_id = auth.uid());

revoke all on role_assignments from anon;
revoke insert, update, delete on role_assignments from authenticated;
revoke insert, update, delete on role_assignments from service_role;
revoke all on privilege_grants from anon;
revoke insert, update, delete on privilege_grants from authenticated;
revoke insert, update, delete on privilege_grants from service_role;

-- ------------------------------------------------------------
-- audit_log: Owner read, with AAL2. No UPDATE or DELETE policy exists
-- at all, and no role — service_role included — holds any write
-- privilege. Inserts happen only inside append_audit() (DEFINER).
-- ------------------------------------------------------------
create policy audit_owner_read on audit_log for select
  using (is_owner() and coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2');

revoke all on audit_log from anon;
revoke insert, update, delete on audit_log from authenticated;
revoke insert, update, delete on audit_log from service_role;

-- ------------------------------------------------------------
-- admission_applications: reviewers (T&S reviewer and up) see the
-- queue — EXCEPT the automated-abuse bucket, which is never shown to
-- anyone, the Owner included (locked requirement). Applicants have NO
-- direct read on their own row: my_application_status() returns a
-- collapsed status so Lane 1 and Lane 2 are indistinguishable from the
-- applicant's side (handle-enumeration safety).
-- ------------------------------------------------------------
create policy admissions_reviewer_read on admission_applications for select
  using (is_reviewer_or_above() and triage_bucket <> 'auto_rejected' and status <> 'auto_rejected');

revoke all on admission_applications from anon;
revoke insert, update, delete on admission_applications from authenticated;
revoke insert, update, delete on admission_applications from service_role;

-- ------------------------------------------------------------
-- vouch_requests: a member sees requests ADDRESSED TO HER (that is the
-- product surface); the Owner sees all. Applicants see nothing.
-- All writes via DEFINER functions.
-- ------------------------------------------------------------
create policy vouch_requests_voucher_read on vouch_requests for select
  using (voucher_user_id = auth.uid() or is_owner());

revoke all on vouch_requests from anon;
revoke insert, update, delete on vouch_requests from authenticated;
revoke insert, update, delete on vouch_requests from service_role;

-- ------------------------------------------------------------
-- E2E placeholders: self-read for devices; prekeys deny-all until the
-- E2E phase defines their access pattern. Empty in Phase 1 by design.
-- ------------------------------------------------------------
create policy user_devices_self on user_devices for select
  using (user_id = auth.uid());
revoke all on user_devices     from anon;
revoke insert, update, delete on user_devices from authenticated;
revoke all on one_time_prekeys from anon, authenticated;

-- ------------------------------------------------------------
-- Function EXECUTE lockdown. Default PUBLIC execute is revoked on all
-- sensitive functions; each is then granted only to the roles that
-- legitimately call it. DEFINER functions check authority internally
-- as well — the grants here are the outer fence, not the enforcement.
-- ------------------------------------------------------------
-- Server-only (service_role). Revoking PUBLIC removes the implicit
-- grant from every role, so the legitimate caller is re-granted
-- explicitly.
revoke execute on function bootstrap_owner(uuid, citext, text, date, citext, text) from public;
revoke execute on function create_system_account(uuid, citext)        from public;
revoke execute on function create_application(uuid, citext, text, date, citext, text, citext, inet, bytea, jsonb, triage_bucket)
                                                                      from public;
revoke execute on function record_signup_attempt(inet, bytea)         from public;
revoke execute on function count_signups_from_subnet(inet, interval)  from public;
revoke execute on function count_signup_attempts_from_ip(inet, interval) from public;
revoke execute on function identifier_is_banned(text, bytea)          from public;
revoke execute on function lapse_expired_vouch_requests()             from public;
revoke execute on function revoke_user_sessions(uuid)                 from public;
grant execute on function bootstrap_owner(uuid, citext, text, date, citext, text) to service_role;
grant execute on function create_system_account(uuid, citext)         to service_role;
grant execute on function create_application(uuid, citext, text, date, citext, text, citext, inet, bytea, jsonb, triage_bucket)
                                                                      to service_role;
grant execute on function record_signup_attempt(inet, bytea)          to service_role;
grant execute on function count_signups_from_subnet(inet, interval)   to service_role;
grant execute on function count_signup_attempts_from_ip(inet, interval) to service_role;
grant execute on function identifier_is_banned(text, bytea)           to service_role;
grant execute on function lapse_expired_vouch_requests()              to service_role;

-- Internal-only (reachable solely from inside DEFINER functions, which
-- execute as the function owner — no app role needs EXECUTE):
revoke execute on function append_audit(text, text, text, jsonb, jsonb, jsonb) from public;
revoke execute on function admit_application(uuid, admission_status, uuid)     from public;
revoke execute on function phone_in_use_by_member(uuid)               from public;
revoke execute on function config_int(text, integer)                  from public;
revoke execute on function require_owner_aal2()                       from public;

-- Authenticated members (each function verifies identity/role itself):
revoke execute on function grant_role(uuid, system_role)              from public;
revoke execute on function revoke_role(uuid, system_role)             from public;
revoke execute on function grant_privilege(uuid, member_privilege)    from public;
revoke execute on function revoke_privilege(uuid, member_privilege)   from public;
revoke execute on function confirm_vouch(uuid)                        from public;
revoke execute on function decline_vouch(uuid)                        from public;
revoke execute on function my_application_status()                    from public;
revoke execute on function get_my_vouch_requests()                    from public;
revoke execute on function submit_info_response(text)                 from public;
revoke execute on function review_approve(uuid, text)                 from public;
revoke execute on function review_reject(uuid, text)                  from public;
revoke execute on function review_request_info(uuid, text)            from public;
revoke execute on function owner_vouch_stats()                        from public;
revoke execute on function verify_audit_chain()                       from public;
revoke execute on function set_display_name_visibility(boolean)       from public;
grant execute on function grant_role(uuid, system_role)               to authenticated;
grant execute on function revoke_role(uuid, system_role)              to authenticated;
grant execute on function grant_privilege(uuid, member_privilege)     to authenticated;
grant execute on function revoke_privilege(uuid, member_privilege)    to authenticated;
grant execute on function confirm_vouch(uuid)                         to authenticated;
grant execute on function decline_vouch(uuid)                         to authenticated;
grant execute on function my_application_status()                     to authenticated;
grant execute on function get_my_vouch_requests()                     to authenticated;
grant execute on function submit_info_response(text)                  to authenticated;
grant execute on function review_approve(uuid, text)                  to authenticated;
grant execute on function review_reject(uuid, text)                   to authenticated;
grant execute on function review_request_info(uuid, text)             to authenticated;
grant execute on function owner_vouch_stats()                         to authenticated;
grant execute on function verify_audit_chain()                        to authenticated;
grant execute on function set_display_name_visibility(boolean)        to authenticated;

-- Helper predicates are used inside RLS policies, which evaluate as the
-- querying role — authenticated needs EXECUTE on them (default PUBLIC
-- grant already provides it; stated here for the record):
-- is_owner, is_admin_or_owner, is_moderator_or_above, is_reviewer_or_above,
-- is_admitted_member, is_active_owner, has_privilege, actor_role_name.
