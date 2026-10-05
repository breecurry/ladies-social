# Local database verification

These files let the migrations and their security properties be
exercised against a plain Postgres 16 without a Supabase stack.

## How to run

```bash
createdb uf_test
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/00-supabase-shim.sql
psql -d uf_test -c "grant usage on schema auth to anon, authenticated, service_role;"
for f in migrations/*.sql; do psql -v ON_ERROR_STOP=1 -d uf_test -f "$f"; done
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/01-smoke.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/02-social-smoke.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/03-adversarial-regressions.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/04-known-vulnerabilities.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/05-hardening-regressions.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/06-age-gate.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/07-moderation.sql
```

`00-supabase-shim.sql` mirrors what hosted Supabase provides (an `auth`
schema with `auth.uid()`/`auth.jwt()` reading request GUCs, the
`anon`/`authenticated`/`service_role` roles, and Supabase's default
privileges). It is for local testing only and is never applied to a
real project.

## What the smoke test proves

- `bootstrap_owner()` seeds exactly one Owner and refuses to run twice;
- a role INSERT whose grantor is not the Owner is rejected **by the
  trigger**, even in a superuser session;
- the owner role itself is never grantable, even by the Owner;
- `service_role` holds no write privilege on `role_assignments`,
  `user_private`, or `audit_log`;
- open signup (`create_member`) creates a full, active member
  immediately: trust level `member`, private record written, signup
  audit-logged;
- flagged bot signals are recorded on the private record but never
  block an account;
- under-18 signups are refused;
- a signup matching a banned email or device hash raises
  `banned_identifier` and creates nothing (ban-evasion enforcement);
- `grant_role` demands the Owner at AAL2 (fails at aal1, fails for
  non-owners at aal2); revocation works and closes the assignment;
- the audit log verifies end to end, UPDATE/DELETE are blocked for
  every role, and corrupting a row breaks the hash chain at exactly
  that row;
- `display_name` can only ever be NULL or the member's verified legal
  name (trigger-enforced opt-in);
- an active member can browse profiles the moment she signs up, and a
  banned account can see nobody but herself;
- the admission system is actually gone: no vouch/admission/privilege
  tables or types survive, `pending_vouch` no longer exists in
  `trust_level`, and the column default is `member`.

## What the social smoke test (02) proves

- posts and reports can only be written through their SECURITY DEFINER
  functions (`create_post` / `delete_post` / `file_report`); direct
  INSERTs fail for `authenticated` and `service_role` alike;
- **no feed, thread, search, list, or notification function returns or
  even references `display_name`** (checked structurally against
  `pg_proc`), a non-opted-in legal name reads as NULL, and another
  member's `user_private` row is unreadable: the legal-name rule is
  enforced below the app layer;
- `report_reason` contains no `male_account` value (conduct-only
  reporting, asserted against `pg_enum`);
- blocks are mutual-hard: the blocked member cannot read the blocker's
  posts or profile, cannot find her in search, cannot follow, like, or
  reply; the blocker loses the blocked member's content too but keeps
  the handle for her unblock list; the Owner and the system account
  cannot be blocked; a blocked author's reply tombstones in threads
  rather than orphaning the subtree;
- mutes remove an author from the Following feed and the notification
  list; "show me less" (hidden_accounts) stores its signal but does
  NOT filter the Following feed (spec §4.8);
- reply controls (`followed`, `mentioned`) are enforced inside
  `create_post`; mentions are parsed, recorded, and notified exactly
  once (a parent author is never double-notified);
- like counters stay exact through like and unlike, likes rows are
  visible only to their owner, and `notification_prefs` toggles are
  honoured;
- report routing is computed server-side (`standard` / `admin_only`);
  the reporter always sees her own reports with an identical shape, an
  accused moderator never sees the report about herself, and — per the
  owner's decision of 2026-10-05, which supersedes the original
  `owner_conflict` sealed lane — a report naming the Owner routes
  `admin_only`, IS visible to the Owner in the normal panel, and every
  report queues an email copy for safety@unitedfeminist.com that names
  no reporter and carries no report text;
- notifications are readable by their owner only, `read_at` is the only
  writable column, and `notif_mark_all_read()` touches nobody else's
  rows;
- `delete_post` is author-only, soft-deletes, and keeps `reply_count`
  exact.

## What the adversarial regression suite (03) proves

Written independently by Grove-Test (QA) against migration 0013, not by
its author. Hardens properties the author claimed but 01/02 did not
directly exercise: cross-member impersonation is refused on every
social-graph table that allows own-row writes (follows, mutes, blocks,
hidden_accounts, likes, notifications, post_mentions); a different
member's session cannot move `notifications.read_at` or
`profiles.display_name` even though the column grants exist (RLS still
scopes both to the caller's own row); `hidden_accounts` and `mutes` are
undiscoverable by their target even though real rows exist against her;
a mutual block tombstones correctly from BOTH sides inside a thread two
strangers share, including a nested reply attempt straight onto the
blocked party's own reply; mentions never cross a block; repeated
mentions of the same handle dedupe to one row/notification; and
`file_report` refuses a self-report.

## Confirmed vulnerabilities (04) — ALL FIXED by migration 0014, now a hard gate

`04-known-vulnerabilities.sql` began life as a deliberately non-aborting
proof of six findings from the QA adversarial pass. Migration 0014
(`20261006000001_social_core_hardening.sql`) fixed all six, and — per the
file's original header — every assertion has been converted to a hard
`raise exception`, so the file now runs with `ON_ERROR_STOP` and gates
the suite exactly like 01-03. What it locks down:

1. **`blocked_either(uuid, uuid)`** refuses an uninvolved third party:
   `public.blocked_either` lost EXECUTE for app roles entirely, and the
   RLS-facing twin `internal.blocked_either` (which `authenticated` must
   be able to execute for the policies to work, but which PostgREST does
   not expose) raises unless `auth.uid()` is one of the two parties.
2. **`blocked_by(uuid)`** can no longer answer "did she block me?" over
   RPC — no app role holds EXECUTE; the policy uses `internal.blocked_by`.
3. **`notif_enabled(uuid, text)`** is DEFINER-internal only (EXECUTE
   revoked from every app role).
4. **`search_people()`** escapes LIKE metacharacters; `a_a` no longer
   matches `ada`, while ordinary search still works.
5. The **mention parser** requires a word boundary before `@`:
   `noreply@cat` mentions nobody; `@cat` at start or after
   whitespace/punctuation still mentions.
6. **Pagination is deterministic under `created_at` ties** via a
   composite `(created_at, id)` cursor; the test walks a fully tied
   feed one row at a time and proves no skips and no repeats.

## Hardening regressions (05) — direct coverage for the 0014 fixes

`05-hardening-regressions.sql` asserts the fixes that 02/03/04 do not
already cover: the `follows_read` block filter (a blocked member cannot
enumerate her blocker's follow graph by reading the table directly,
while uninvolved members still see it); the report duplicate guard
(one per reporter/accused/reason per 24h) and the 10-per-hour cap with
a calm refusal; `get_thread` returning nothing — not a tombstone — for
a blocked author's root post while in-thread tombstones keep working;
the 30-level reply-depth cap; moderation-removed parents contributing
no excerpt/handle to `profile_posts`; and structural EXECUTE-privilege
guards (trigger functions, `notif_enabled`, and the paged functions'
authenticated-only grants) so a future migration cannot quietly reopen
any of this.

One historical note: the original suites' blind spot was that they only
ever exercised the helper functions in their intended internal role,
never as an uninvolved third party with arbitrary arguments — which is
exactly where findings 1-3 lived. 04 and 05 now exercise that calling
pattern explicitly; keep doing so for any future SECURITY DEFINER
helper that is (or must be) executable by `authenticated`.


## What the age-gate suite (06) proves

Covers migration 0017 (spec §17 — the account-creation age gate):

- **a block can never take in a person, structurally**: `age_gate_blocks`
  has exactly five columns (id, hashed fingerprint, reference code,
  created_at, expires_at), and the test fails the moment a future
  migration adds one — no email, name, DOB, or IP can ever live there;
- `user_private.dob` is gone (the raw birth date is validated but not
  retained) while `age_attested_at` — the derived 18+ record — remains;
- no app role (anon/authenticated/service_role) holds any direct
  privilege on the table; RLS is enabled with zero policies; the
  SECURITY DEFINER functions are the only path;
- recording is service_role-only and idempotent per device: the same
  fingerprint keeps its code AND its expiry (re-failing does not restart
  the 14-day clock), and every block/unblock is audit-logged by code
  alone;
- lookups match by fingerprint hash or by reference code, case- and
  whitespace-insensitively; expired blocks neither match nor linger;
- the support unlock is Owner-only (a signed-in member is refused),
  clears exactly the quoted block, returns false on a second clear, and
  leaves the audit chain verifying end to end;
- `create_member()` still refuses an under-18 date at the database, no
  matter what reaches it.

## What the moderation suite (07) proves

Covers migration 0018 (the moderation console's data layer):

- **no moderation function returns or even references `display_name`**
  (checked structurally against `pg_proc` for all 22 console and
  enforcement functions): every console surface is @handle-only below
  the app layer;
- the locked role boundaries hold at the database, not just in the UI:
  **a moderator cannot ban**, **a moderator cannot suspend or restrict
  for more than 7 days**, **an admin can** (and 31 days is refused for
  everyone — the guidelines' 30-day ceiling), a reviewer is read-only,
  **the Owner can be neither suspended nor banned**, and nobody can
  action herself or the system account;
- the owner's report-routing decision (2026-10-05): a report naming
  the Owner routes `admin_only` and is visible to her in the normal
  panel; nothing writes `owner_conflict` any more; every report queues
  its safety@ email copy, and the copy leaks no reporter, no report
  text, and no legal name;
- banning writes HMAC-only email/device signals to
  `banned_identifiers` and `create_member()` then refuses a matching
  signup — ban evasion enforced end to end;
- reversing a permanent ban demands the Owner at AAL2 (an admin is
  refused; the Owner at aal1 is refused);
- csam reports arrive auto-escalated, admins and moderators cannot
  resolve them (escalation is their only forward action), the Owner
  can;
- `moderation_actions` and `safety_email_outbox` are unreachable
  directly by members AND by service_role (no insert/delete);
- the member is told the rule and the action (`my_account_status`,
  system notifications with a body), never the reporter or the acting
  human; revealing reporters is a separate act that writes its own
  audit entry;
- **every enforcement action lands in the hash-chained `audit_log`**
  (claim, warn, remove, suspend, lift, ban, dismiss, reporter-reveal,
  filing), the ban entry records signal KINDS never values, and the
  chain still verifies end to end afterwards.
