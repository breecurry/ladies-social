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
