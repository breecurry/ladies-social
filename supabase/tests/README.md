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
psql -d uf_test -f tests/04-known-vulnerabilities.sql   # no ON_ERROR_STOP: see header
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
- report routing is computed server-side (`standard` / `admin_only` /
  `owner_conflict`); the reporter always sees her own reports with an
  identical shape, an accused moderator never sees the report about
  herself, and an `owner_conflict` report is invisible in-app to
  everyone, the Owner included;
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

## Confirmed vulnerabilities (04) — OPEN, not fixed by QA

`04-known-vulnerabilities.sql` is a deliberately non-aborting proof of
six findings from the same adversarial pass that do NOT currently hold.
Per the QA mandate (find, never fix), the migration was not patched.
Each check prints a `PASS`/`FAIL (FINDING N, OPEN)` notice and the file
always completes cleanly, so it is safe to run without breaking an
automated pass; flip an assertion to a hard `raise exception` once its
finding is fixed so it gates the suite like 01-03 do. Summary (full
detail and severity in the finding's own comment block and in the QA
report):

1. **`blocked_either(uuid, uuid)`** is callable by any member with two
   ARBITRARY other members' ids and leaks whether a block exists
   between them — not scoped to the caller.
2. **`blocked_by(uuid)`** lets the caller directly confirm whether an
   arbitrary target has blocked her, contradicting the migration's own
   "the other person is never told" design intent.
3. **`notif_enabled(uuid, text)`** leaks an arbitrary member's
   notification-preference setting, bypassing `notification_prefs`'
   own-row-only RLS.
4. **`search_people()`** does not escape `_` before building its `LIKE`
   pattern, so a query containing `_` matches any character there
   (e.g. `a_a` matches `ada`).
5. The **mention regexp** has no boundary before `@`, so a handle-shaped
   substring inside ordinary text (e.g. `noreply@cat`) is parsed as a
   real mention and notifies that handle.
6. **`feed_following`** pagination has no tiebreaker beyond
   `created_at`; two posts sharing an identical timestamp cause the
   page boundary to silently skip one of them.

