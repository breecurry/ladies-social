# Database tests

Local verification of the Phase 1 security invariants against a plain
PostgreSQL 15/16 — no Supabase stack required.

```bash
createdb uftest
psql -d uftest -v ON_ERROR_STOP=1 -f supabase/tests/00-supabase-shim.sql
for f in supabase/migrations/*.sql; do
  psql -d uftest -v ON_ERROR_STOP=1 -f "$f"
done
psql -d uftest -f supabase/tests/01-smoke.sql   # expect: ALL SMOKE TESTS PASSED
```

`00-supabase-shim.sql` mimics what hosted Supabase provides (the `auth`
schema, `auth.uid()`/`auth.jwt()`, and the `anon`/`authenticated`/
`service_role` roles with Supabase's default table grants). It must
never be applied to a real Supabase project.

The smoke test asserts, among other things:

- the Owner can be bootstrapped exactly once, and the owner role is
  never grantable afterwards — even by the Owner;
- a role INSERT whose `granted_by` is not the active Owner is rejected
  by trigger **even for a superuser session**, and `service_role` holds
  no write privilege on `role_assignments` at all;
- `grant_role()` demands AAL2 and refuses non-Owner callers;
- Lane 1 creates a vouch request; an unresolvable "Who invited you?"
  handle silently produces a Lane 2 application with **no observable
  difference** for the applicant (status reads `pending` in both lanes,
  and applicants can read neither applications nor vouch requests);
- a confirmed vouch admits only when the voucher holds `auto_admit`
  (or is the Owner); otherwise it queues at raised priority;
- the daily per-member vouch-request cap silently reroutes to Lane 2;
- auto-rejected applications are invisible to every queue, the Owner's
  included, and the applicant still reads `pending` (no bot oracle);
- the audit log rejects UPDATE/DELETE for all roles, and corrupting a
  row (with its guard trigger forcibly disabled) breaks the hash chain
  at exactly that row, which `verify_audit_chain()` reports;
- `display_name` can only ever be NULL or the verified legal name;
- pending applicants cannot browse member profiles;
- the 48h lapse job moves silent vouch requests to the review queue.
