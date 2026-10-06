-- 20261022000002_lock_owner_unblockable_decision.sql
--
-- NO SCHEMA CHANGE. This migration adds a single database object comment.
--
-- WHY IT EXISTS
-- `forbid_blocking_protected()` prevents any member from blocking the Owner's
-- account or the system account. Two independent security audits have now
-- flagged that as a finding (Phase 2A "P1-E", pre-launch audit "P1-3"), on the
-- reasoning that members who are hiding from specific people should be able to
-- separate from anyone, including the platform owner.
--
-- THE OWNER HAS ANSWERED. THE ANSWER IS NO, AND THE CURRENT BEHAVIOUR IS
-- CORRECT. She was asked three separate times because the answer was never
-- recorded where the next auditor would see it. A note in an engineer's
-- memory does not travel: audit tooling reads the live schema, not anyone's
-- notes. So the decision is recorded ON the function, where it cannot be
-- missed by whoever next reads this code and mistakes a deliberate choice for
-- an oversight.
--
-- IDEMPOTENT: `comment on function` is a straight overwrite and is safe to
-- re-run any number of times.

set search_path = public, extensions;

comment on function forbid_blocking_protected() is
  'DELIBERATE OWNER DECISION, CONFIRMED 2026-10-05 - DO NOT "FIX" THIS. '
  'Blocking the Owner account or the system account is intentionally '
  'impossible. Two security audits have raised this as a finding (Phase 2A '
  'P1-E, pre-launch P1-3) on the reasoning that a safe-space platform should '
  'let any member separate from anyone. The Owner has considered that and '
  'rejected it: the Owner account is the operator of the platform, not a peer '
  'in the social graph, and a member''s remedy regarding the operator is '
  'leaving, reporting or appeal rather than a block. This is settled. Do not '
  'report it as a vulnerability and do not open it again.';
