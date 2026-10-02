# Local database verification

These files let the migrations and their security properties be
exercised against a plain Postgres 16 without a Supabase stack.

## How to run

```bash
createdb uf_test
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/00-supabase-shim.sql
for f in migrations/*.sql; do psql -v ON_ERROR_STOP=1 -d uf_test -f "$f"; done
psql -v ON_ERROR_STOP=1 -d uf_test -f tests/01-smoke.sql
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
