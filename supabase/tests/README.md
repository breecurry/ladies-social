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
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/08-tos-consent.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/09-dm-smoke.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/10-discover.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/11-admin-dashboard.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/12-avatars.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/13-full-analytics.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/14-phase2f.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/15-reposts-tab-and-tag-cap.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/16-passkey-gate.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/17-extended-passkey-gate.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/18-revoke-grants-and-signup-path.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/19-dm-adversarial.sql
# 20 is EXPECTED to fail — see its own section below.
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/20-suspension-visibility-regression.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/21-ban-route-authority-and-follow-counts.sql
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/22-dm-disclosure-dismissal.sql
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
## What the Terms-consent suite (08) proves

Covers migration 0019 (the Terms of Service agreement recorded at
signup):

- `user_private.tos_agreed_at` and `tos_version` exist and are
  **nullable** — accounts that predate the consent checkbox read as
  exactly what they are (no consent captured) and nothing locks them
  out;
- no account carries a consent it never gave: both columns start NULL
  and only `record_tos_consent()` can set them;
- recording is service_role-only (an authenticated member can neither
  call the function nor write the columns directly), stamps the
  consent moment and the **exact version string** of the document
  agreed to, and appends a `member.tos_consent` audit row carrying
  that version — the audit chain still verifies end to end;
- an empty version is refused (no unattributable consents), a
  non-member returns false and writes nothing, and the 200-character
  version guard holds.

The HTTP half — the signup route refusing a POST whose `tosAgreed`
field is absent or false — is enforced by `signupSchema`
(`z.literal(true)`) before any database call, and is verified with
curl against a running build; see PROGRESS.md.

## What the DM suite (09) proves

Covers migration 0020 (Phase 2C direct messages) as reworked by
migration 20261021000001 (the owner's decision: DMs are NOT end-to-end
encrypted; the platform can read message content, members are told so
plainly, and staff reads are audited):

- **the feature flag holds at the database, under its new honest
  name**: with no `app_config.dm_enabled = true` row (the shipped
  default), every member-facing DM function refuses with one calm
  message and the badge count returns 0 instead of erroring; a
  leftover row under the OLD key (`dm_e2e_enabled`) enables nothing;
- **the E2E layer is structurally gone**: no `user_devices` or
  `one_time_prekeys` tables, no device/prekey/franking functions,
  no ciphertext/header/frank_hash columns on `dm_messages` (which now
  carries a readable `body`, 1-2000 chars, blank refused), and **no DM
  function has a leftover second signature** — the PostgREST
  ambiguity guard, asserted against `pg_proc`;
- no DM function returns or even references `display_name` (checked
  structurally) — every DM surface is @handle-only below the app
  layer;
- **the inbox rules are server-enforced**: a sender the recipient
  follows lands in the main inbox; a stranger gets EXACTLY ONE silent
  request — no notification, never counted in the unread badge,
  invisible in Primary, visible in Requests — and cannot send a
  second message until accepted; the recipient cannot reply before
  accepting; declining hides the request without telling the sender
  and the one-message cap survives, so no path yields a second
  request;
- **block, DMs-off, and "no one" raise the IDENTICAL refusal**, so a
  blocked person cannot distinguish a block; an existing conversation
  stays readable on BOTH sides across a block (the history may be the
  evidence) while sending stops;
- **report evidence is a server-side snapshot**: file_dm_report copies
  the selected messages (body, sender, recipient, timestamp) from the
  real rows — nothing client-supplied is ever presented as the
  accused's words; a message id from another conversation voids the
  report; the safety@ email copy names no reporter and carries no
  message text;
- **every staff read of message content is audited**: each
  mod_dm_evidence() call that returns content writes a
  `dm.content_read` row to the hash-chained audit log naming the
  reader, the target, and the volume; a refused member read writes
  nothing; the moderation queue carries the case and a plain member
  cannot read the transcript;
- notifications fire only for accepted conversations, carry no message
  content, honour the `message` pref and the per-conversation mute,
  and marking a thread read clears them;
- "delete for me" clears only the deleter's view — messages AND the
  inbox preview; the other member keeps her copy; a new message
  resurfaces the thread with only the new content;
- RLS lockdown: no app role (member or service_role) can touch
  `dm_conversations`, `dm_messages`, or `dm_report_evidence` directly;
  another member's `dm_settings` rows are invisible; a non-participant
  cannot fetch a conversation through the functions either.

## What the Discover suite (10) proves

Covers migration 0021 (Phase 2B Part 2 — the Discover feed):

- **the Discoverability opt-out holds at the database**: a member who
  turns `profiles.discoverable` off (it defaults ON — owner decision
  2026-10-07) never surfaces in anyone's `feed_discover()` and is never
  returned by `suggested_accounts()`, while remaining fully reachable
  by exact `@handle` through `search_people()` and keeping her own
  Discover view intact; RLS confines the toggle to the member's own
  row;
- **no Discover function returns or even references `display_name`**
  (checked structurally against `pg_proc`): the widest surface in the
  product is @handle-only below the app layer, like every other read
  path;
- EXECUTE on both functions is authenticated-only (anon and
  service_role are refused);
- ranking is positive-signal-only in behaviour: a cold-start member
  with zero follows and zero likes still gets a populated feed (never
  containing her own posts), offset pagination is deterministic, and
  following an author flips `viewer_follows` (the card's Follow-pill
  signal) while retiring her from suggestions;
- the safety filters match every other read path: mutual blocks remove
  both directions from feed and suggestions, mutes remove the author
  entirely, hide ("show me less") **suppresses without hard-filtering**
  the feed (P2 spec §4.8) while keeping the account out of
  suggestions, and a suspended author's posts and moderation-removed
  posts never surface.

## What the admin-dashboard suite (11) proves

- **Owner-only is enforced at the data layer**: an ordinary member
  calling `owner_directory()`, `owner_directory_count()`,
  `owner_member_count()`, or `owner_member_detail()` directly gets
  **zero rows**, and `owner_metrics()`, `owner_reveal_identity()`, and
  `owner_directory_export()` raise — even at AAL2. Hiding the UI is
  not the gate;
- **no raw activity timestamp reaches a browsable surface**: the
  directory, count, detail, and export functions return only the five
  coarse bucket labels (checked structurally against their result
  shapes — no `last_login`/`last_active` column exists on any of
  them), `profiles` has not gained a `last_active_at` column, and the
  bucket derivation from `user_private.last_login_at` is verified
  behaviourally;
- **no admin-dashboard function returns or even references
  `display_name`** (checked structurally against `pg_proc`) — the
  directory, the surface most tempted to show a legal name, is
  @handle-only below the app layer;
- the **identity reveal** is refused at aal1, refused without a stated
  reason, refused for the system account, and at AAL2-with-reason it
  returns the `user_private` record (device signals as a **count**,
  never hashes) with an `identity.reveal` entry — handle and reason
  included — in the hash-chained audit log;
- the **export** is identity-free (glance columns only) and lands in
  the audit log as `directory.export` with the filter set and row
  count;
- **metrics are literal**: top-line totals and every segmented
  breakdown carry the exact count at any N (1 reads as 1 — the former
  k=5 suppression is gone, asserted); zeros read as real `0`s; the
  all-time range fabricates no previous-period comparison (there is no
  prior all-time period); and the full-analytics sections
  (engagement, sessions, presence, leaderboards, streaks, virality,
  retention — behaviour covered by suite 12) are present in the
  payload;
- **deleted members are gone from every surface** — directory (even
  when asked for by explicit status filter), detail, member count, and
  the metrics headline — and the system account appears nowhere;
- search is exact-and-prefix `@handle` only (substrings do not match),
  and keyset pagination pages without overlap.

## What the avatar smoke test proves (12-avatars)

- the **avatar key resolver is mutual-hard on blocks**: a block in
  EITHER direction returns no key to either party (`blocked_either`,
  the posts semantics — never the one-way `profiles_read` semantics),
  while a mute changes nothing (mute is a feed tool, not an identity
  tool);
- a context with **no member resolves nothing**, `anon` holds no
  EXECUTE on any avatar function, and a suspended viewer resolves
  nothing either;
- **suspended / banned owners resolve to nothing** (letter placeholder
  everywhere) and come back when standing is restored;
- `avatar_media` and `avatar_upload_tickets` carry **RLS with zero
  policies and zero direct privileges** — the SECURITY DEFINER
  functions are the only path — and **no table in `public` is without
  RLS**;
- members **cannot write `profiles.avatar_media_key` directly** (the
  0009 column grant is revoked; the pipeline functions are the only
  writers), and **no filename-shaped column exists** anywhere in the
  feature;
- **a report freezes the accused's current avatar key** as evidence;
  a frozen object is never purgeable and `avatar_mark_purged` refuses
  it, even after the member swaps or removes the photo;
- **moderation removal preserves**: the profile reverts to the
  placeholder, the object row is marked (never deleted, never
  purgeable), the enforcement history and a member-facing notification
  naming the rule are written, and **reinstatement restores** the
  photo end to end;
- a **csam-reason report never reaches the console evidence panel**
  and pins a `legal_hold` on the frozen object;
- upload tickets are refused for suspended and restricted members,
  capped per hour, single-consume and single-redeem; malformed keys
  are rejected; and **no avatar function returns or references
  `display_name`** (checked structurally against `pg_proc`).

## What the full-analytics suite (13) proves

Covers migration 0023 (full analytics — the owner's decision that
every number is the literal number, plus the collection it needs):

- **every number is literal**: breakdowns, leaderboards, stickiness,
  and retention rates carry exact values at any N — a count of 1 reads
  as 1 and a 1-of-2 cohort reads as a real 50.0;
- **the heartbeat works and is bounded**: a member's first heartbeat
  opens a session, repeats within the 30-minute gap extend the same
  session, one after the gap opens a new one; direct writes to
  `member_sessions` are refused for every app role, and RLS confines a
  member's reads to her own sessions;
- **departures are real recorded events**: a status change stamps
  `deactivated_at` / `banned_at` / `deleted_at` and appends to the
  `account_status_events` ledger; a reinstatement clears the stamp and
  appends the return; net change is real arithmetic (joined − departed
  + returned) and the series carries its honest tracked-since label —
  no history is fabricated;
- **engagement, sessions, presence**: DAU/WAU/MAU count real activity
  over the standard fixed windows, stickiness is the real DAU/MAU
  ratio, session durations are the real derived minutes, and presence
  names who is online right now with a precise per-member last-seen;
- **leaderboards, streaks, virality, retention** compute exact values
  (most posts, likes given and received, sessions, follower growth,
  consecutive-day streaks, likes per post, cohort shares at 1/7/30
  days) — and every per-member entry is `@handle`-keyed, structurally
  carrying nothing but handle and value;
- **the privacy posture holds**: no new function references
  `display_name`; `owner_metrics()` still raises for a non-Owner (the
  internal active-count helper is callable by no app role); the three
  new tables all have RLS enabled, and the ledger and tracked-since
  tables are not even directly readable.

## What the revoke-grants / signup-path suite proves (18)

Independent QA (Grove-Test) on migration
`20261021000002_revoke_internal_function_grants.sql`, which revoked
EXECUTE on eleven SECURITY DEFINER functions from
`anon`/`authenticated`/`public` after a pre-launch audit found them
reachable by unauthenticated callers. This suite proves the fix closed
the hole WITHOUT breaking the one legitimate caller, `service_role`:

- catalog state matches intent for all eleven functions
  (`has_function_privilege` against `anon`/`authenticated`, not just
  "the revoke returned success" — a revoke against an already-absent
  grant is a silent no-op); `service_role` keeps EXECUTE on all eleven,
  which is the entire premise the fix relies on;
- the five RLS-helper functions deliberately left reachable by
  `authenticated` (`is_active_member`, `is_owner`, `is_admin_or_owner`,
  `is_moderator_or_above`, `is_reviewer_or_above`) still are — RLS
  policy expressions evaluate as the invoking role, so revoking any of
  these would have broken row-level security platform-wide;
- `search_people` — never part of this fix — still works for both
  `anon` and `authenticated` (the exact control used in the live
  verification);
- runtime proof, not just catalog state: an actual `anon` session and
  an actual `authenticated` session attempting `revoke_user_sessions`
  and `append_audit` are both refused with `insufficient_privilege`,
  while `search_people` and the five RLS helpers actually execute;
- the FULL signup pipeline (`record_signup_attempt` →
  `count_signup_attempts_from_ip` → `identifier_is_banned` ×2 →
  `count_signups_from_subnet` → `create_member` →
  `record_tos_consent`), replayed as `service_role` in the exact order
  `src/app/api/auth/signup/route.ts` calls it, succeeds end to end;
- the rate limiter actually trips past its own configured cap, and
  `count_signups_from_subnet` catches a /24 of distinct IPs, not just
  exact-IP repeats;
- ban evasion is enforced twice: the pre-check (`identifier_is_banned`)
  AND `create_member`'s own belt-and-braces guard both refuse a banned
  email hash, and the refusal creates NOTHING (no `profiles` row, no
  `user_private` row) — not a partially-created account;
- the under-18 guard on `create_member` still holds through the same
  call path (regression coverage that the grant change touched nothing
  in the function body).

**What this suite does NOT cover (see the QA report, UNVERIFIED):** a
true browser-to-GoTrue HTTP signup — there is no Docker in this
sandbox to stand up Supabase Auth/PostgREST locally, so
`anonAuth.auth.signUp()` itself (the one call in the route that is
NOT one of the eleven revoked functions) is exercised only by static
source review, not by execution.

## What the DM adversarial suite proves (19)

Independent QA (Grove-Test), written separately from the author's own
09-dm-smoke.sql, targeting what an adversary tries next:

- exact body-length boundaries: 1 char and exactly 2000 chars succeed
  (including 2000 four-byte emoji — char_length counts codepoints, not
  bytes, so there is no hidden byte-size ceiling); 2001 and 10000 both
  refuse the same way; empty and spaces-only both refuse;
- **FINDING, reproduced not asserted-fixed**: the blank-message guard
  (`char_length(btrim(p_body)) < 1`) uses Postgres's single-argument
  `btrim()`, which strips ONLY ascii spaces — a body of pure newlines
  or pure tabs satisfies the guard and is ACCEPTED as a visually blank
  message. The test is written so that it starts FAILING (loudly,
  labeled REGRESSION) the moment this is fixed, as a tripwire against
  silently re-introducing it;
- a null byte cannot reach a `text` column at all — Postgres refuses
  it at the protocol level ("null character not permitted") before any
  function body runs; an invalid UTF-8 byte sequence is structurally
  impossible to convert into `text` in a UTF8 database — both proven
  directly, not assumed;
- sender forgery has no parameter to exploit (`dm_send_message` takes
  no sender argument — always `auth.uid()`), and the only other path,
  a direct `insert into dm_messages` with someone else's id as
  `sender_id`, is refused by table grants for `authenticated`;
- `file_dm_report`'s message-id array: 0 ids, 11 ids (even with real
  ids among them — refusal is total, never thinned to 10), and one
  nonexistent id mixed with one real id (same conversation) are all
  refused, and NONE of the three refused attempts writes anything to
  `reports` or `dm_report_evidence` — all-or-nothing; exactly 10 real
  ids succeeds; a conversation the reporter isn't in is refused
  regardless of id validity;
- **FINDING, reproduced not asserted-fixed**: duplicate message ids in
  one report are not rejected and have no unique constraint to stop
  them — the same message is copied into `dm_report_evidence` twice,
  inflating both the evidence row count and the volume
  `mod_dm_evidence` later audits for that target. Same tripwire
  pattern as the blank-message finding;
- `mod_dm_evidence`'s audit promise, exactly: two calls against a
  target with real evidence produce exactly two new `dm.content_read`
  rows (not deduplicated), each naming reader/target/volume; a call
  against a target with ZERO filed evidence returns zero rows and
  writes ZERO audit rows (distinct from, but as important as, outright
  refusal); a plain member's call is refused outright and writes
  nothing; `verify_audit_chain()` still verifies after all of the
  above;
- suspension mid-conversation: `dm_can_message` reads 'none' for a
  suspended recipient (identical to a block — no oracle), sending into
  an existing accepted conversation is refused with the same
  block-shaped message, and the sender keeps her own read access to
  the history; the suspended party herself can still read her DMs at
  the data layer but cannot send (a different, self-describing
  refusal, which leaks nothing about anyone else);
- an independent structural sweep (grouping `pg_proc` by name for
  every `dm_%` function plus `file_dm_report`/`mod_dm_evidence`, not a
  maintained name list) confirms exactly one signature each;
- the dead `dm_e2e_enabled` key never reappears in `app_config`.

## What the suspension-visibility regression suite proves — AND FAILS ON (20)

Regression coverage for commit `097c318`, which corrected
`docs/community-guidelines.md` and the in-app `SuspendedScreen` to say
a suspended/banned member's profile AND posts are removed from the
platform. This suite checks whether the CODE actually delivers that,
across every public surface, as an uninvolved, active third member:

**Confirmed CLEAN** (all pass): `profile_posts` (her own posts, on her
own profile), `feed_following` (a follower's feed), `feed_hashtag` (a
tag page carrying her post), `search_people` (exact-handle search),
`list_following` (a follower's following list), `get_thread` (her ROOT
post tombstones — no handle, no body — rather than simply vanishing,
while an uninvolved reply in the same thread stays visible), and
mention rendering (a fresh post made AFTER her suspension that
`@mentions` her does not resolve her into the mentions list).

**FAILS, by design, on the current tree**: the profile ROW ITSELF —
`handle`, `bio`, `founding_member`, `created_at` — is still fully
readable by any other active member. `src/app/(member)/u/[handle]/page.tsx`
does a plain `.from("profiles").select(...)` with no status filter in
the app code, and the `profiles_read` RLS policy
(`20261006000001_social_core_hardening.sql`) excludes only
`status = 'deleted'` — `'suspended'` and `'banned'` both still pass.
The assertion encodes the PUBLISHED PROMISE, not the current schema,
and is deliberately left red: a passing test here would mean the test
had been weakened to match the bug. See the QA report for severity and
a suggested fix location.

Also characterises, without re-discovering, the KNOWN and ALREADY-
QUEUED expiry gap: `refresh_my_status()` only clears an expired
`status_expires_at` for `auth.uid()` — the suspended member's own next
sign-in. Confirmed here: a third party's read does not flip it,
another member calling `refresh_my_status()` on her own account cannot
clear someone else's expiry, and only the suspended member's own call
restores her to `active`. Nothing else in the schema — no cron
extension is installed, no trigger, no Owner action — clears it.

## What the ban-route-authority / follow-counts suite proves (21)

Regression coverage for the 2026-10 small-fix batch (ban-through-a-block
and list-matching follow counts):

- the database facts the `/api/mod/ban` fix rests on: a member who has
  blocked an admin is INVISIBLE to that admin's user-scoped `profiles`
  read (which is why the route's typed-handle gate must use the service
  client, after its own admin/owner check), while `mod_ban()` itself
  goes straight through the block — moderation never consults blocks;
- `mod_ban()` admits exactly admin and owner (tier >= 2): a moderator
  and a plain member are both refused with the permission error — the
  same set the route now gates on BEFORE any privileged read;
- the enumeration that authority-first ordering prevents: an ordinary
  member cannot read a banned member's profile row at all, so a
  service-client handle lookup without a prior authority check would
  hand that hidden mapping to any authenticated caller;
- `profile_follow_counts()` (migration `20261025000001`) returns
  numbers EQUAL to the row counts of `list_followers()` /
  `list_following()` for the same viewer — asserted against the lists
  themselves, not just hardcoded expectations, so the suite fails if
  the predicates ever drift — across every state: untouched, suspended
  counterparty, banned counterparty, counterparty-blocked-the-viewer,
  own-profile view, and a viewer<->owner block (counts go to zero with
  the lists);
- structure: exactly ONE `profile_follow_counts` signature in
  `pg_proc`, EXECUTE for `authenticated` only (not `anon`, not
  `service_role`, not `public`).

## What the DM disclosure dismissal suite proves (22)

Covers migration `20261026000001` (owner decision 2026-10-06: the DM
disclosure banner gets an X; the original always-on decision was
2026-10-05). The copy itself is unchanged and untested here — this
suite tests WHEN it shows, which is decided by
`dm_disclosure_should_show(current_version, quiet_days)` against the
database clock, with the version and the 45-day quiet period passed in
from their single home in `src/lib/dm/disclosure.ts`:

- structure: the two nullable `dm_settings` columns exist (null =
  never dismissed, the lazy-default pattern), each new function has
  exactly one signature (the PostgREST ambiguity guard), anon holds no
  EXECUTE, authenticated does;
- both functions refuse while the DM feature flag is off, like every
  other DM function;
- **never dismissed shows** — with no `dm_settings` row at all, and
  with a row whose disclosure columns are null;
- **dismissing hides** and lazy-creates the row with the table's
  defaults intact, stamped by the server clock (`now()`), never a
  client clock;
- **dismissed yesterday stays hidden; dismissed 46 days ago shows
  again** — and can be dismissed again (the cycle repeats);
- **a bumped disclosure version shows IMMEDIATELY, inside the quiet
  period** — changed copy overrides the timer by design;
- invalid arguments fail safe: bad dismiss versions refuse, nonsense
  should-show arguments return SHOW (the safe failure direction for a
  disclosure is visible);
- **isolation**: a member can neither read nor write another member's
  dismissal state — the dismiss function takes no user parameter
  (structurally own-row), a cross-member UPDATE matches 0 rows, a
  cross-member INSERT raises under RLS, a cross-member SELECT sees
  nothing, and one member's dismissal quiets nothing for anyone else.
