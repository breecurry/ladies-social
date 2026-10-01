-- ============================================================
-- 0001 — Extensions and enums
-- Phase 1: admission, identity, roles, audit. No social features.
-- ============================================================
set search_path = public, extensions;

create extension if not exists pgcrypto with schema extensions; -- digest()/hmac for hash chaining
create extension if not exists citext   with schema extensions; -- case-insensitive handles/emails
create extension if not exists pg_trgm  with schema extensions; -- handle/name search (used from Phase 2)

-- Roles are grantable by the Owner ONLY (enforced by trigger + SECURITY
-- DEFINER functions in 0003/0005). 'member' is the absence of a row here.
create type system_role as enum ('owner', 'admin', 'moderator', 'ts_reviewer');

-- Privileges are Owner-grantable capabilities that are NOT roles.
-- 'auto_admit': this member's confirmed vouch admits the applicant
-- immediately instead of raising her review-queue priority.
create type member_privilege as enum ('auto_admit');

create type trust_level    as enum ('pending_vouch', 'member', 'established');
create type account_status as enum ('active', 'restricted', 'suspended', 'banned', 'deactivated', 'deleted');

-- Two-lane admission (locked product decision, "Option C"):
--   Lane 1: applicant named an inviter; the named member must ACTIVELY
--           confirm the vouch. Submission grants nothing.
--   Lane 2: no inviter named / handle did not resolve / vouch declined
--           or lapsed -> human review queue. Never auto-rejection.
--   auto_rejected: obvious automated abuse, never shown to any reviewer.
create type admission_status as enum (
  'awaiting_vouch',    -- Lane 1: vouch request outstanding (48h window)
  'queued',            -- Lane 2: waiting for human review
  'info_requested',    -- reviewer asked the applicant for more information
  'admitted_vouched',  -- admitted by a confirmed vouch from an auto_admit holder
  'admitted_reviewed', -- admitted by a human reviewer
  'rejected',          -- rejected by a human reviewer
  'auto_rejected'      -- automated-abuse bucket; hidden from every queue
);

create type vouch_request_status as enum ('pending', 'confirmed', 'declined', 'lapsed', 'cancelled');

-- Automated triage buckets. Review is NEVER based on appearance,
-- photographs, or gender — there is no photo anywhere in admission.
create type triage_bucket as enum ('clean', 'flagged', 'auto_rejected');
