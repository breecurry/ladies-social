# PROGRESS — United Feminist

Updated: 2026-10-01

## Current state

**Phase 1 — the admission system — is built.** Signup with the two-lane
gate, vouching, the review queue with automated triage, roles and
privileges with database-layer enforcement, the hash-chained audit log,
and the app scaffold with the full design-token system. `typecheck`,
`lint` and `build` all pass, and the database migrations carry a local
smoke-test suite (`supabase/tests/`) covering the security invariants.

Not yet deployed: needs a Supabase project + hosting (Phase 0
provisioning), then `npm run bootstrap`.

## Done

- [x] Product definition and positioning
- [x] Membership model — open, two-lane admission, no gender screening
- [x] Visual identity and complete design token system
- [x] Security, verification and trust & safety architecture
- [x] Encryption approach and roles/permissions model
- [x] Terms of Service and Community Guidelines (draft; attorney review pending)
- [x] Technical architecture, database schema, phased build plan
- [x] Repo write access confirmed
- [x] **Phase 1 build — admission system**
  - [x] Next.js scaffold (App Router, strict TS, Tailwind v4 with the
        design tokens as real theme tokens, light + dark, ESLint + Prettier)
  - [x] SQL migrations: profiles + private-PII split, admission
        applications, vouch requests, roles, privileges, hash-chained
        audit log, E2E placeholder tables (`user_devices`,
        `one_time_prekeys` — deliberately empty), RLS everywhere
  - [x] Signup: email, phone, legal name (collected, verified-path, NOT
        publicly displayed by default), handle, 18+ date of birth, and
        the "Who invited you?" field directly above submit
  - [x] Two lanes: active vouch confirmation (48h window, decline/lapse
        → review queue, never rejection) and the reviewed queue
  - [x] Handle-enumeration hardening: identical response + padded
        timing whether the named handle exists or not; collapsed
        applicant-side status; daily per-member vouch-request cap
  - [x] `auto_admit` as an Owner-granted, revocable privilege; everyone
        else's confirmed vouch raises queue priority instead; per-member
        vouch statistics surfaced to the Owner (inform, never trigger)
  - [x] Automated triage: disposable-email list, phone line-type via
        Twilio Lookup (VOIP/prepaid flagged), signup velocity + /24 IP
        clustering, device-fingerprint match against banned accounts,
        profile-coherence heuristics; obvious automation auto-rejected
        and never shown to any reviewer, Owner included. No photos, no
        appearance, no gender — anywhere in admission.
  - [x] Owner-only role grants enforced at the database layer (trigger + SECURITY DEFINER functions + write privileges REVOKEd from
        every app role including service_role) with AAL2 step-up
  - [x] Append-only, hash-chained audit log (actor, role-at-time,
        action, target, before/after, session) with Owner-only AAL2
        read and a chain-verification function
  - [x] Auth: 30-min JWTs + refresh rotation (config), session
        revocation on role revoke, WebAuthn MFA factor + TOTP fallback,
        AAL2 enforced inside the database functions

## In progress

- [ ] Phase 0/1 provisioning: Supabase project, hosting, domain wiring,
      owner + system-account bootstrap, Owner MFA enrollment

## Not started

- [ ] Phase 2 — text social core (posts, replies, follows, feed)
- [ ] Phase 3 — media pipeline and moderation backbone
- [ ] Phase 4 — direct messages with photos
- [ ] Phase 5 — discovery and For You feed
- [ ] Phase 6 — launch hardening
- [ ] Audit-log daily WORM export (S3 Object Lock) — schema is ready;
      ship with provisioning
- [ ] Phone OTP verification at signup (Twilio Verify wiring in
      Supabase) — the number is collected and triaged today
- [ ] Email notification to a member when she receives a vouch request
      (currently in-app only, at /vouches)

## Blocked / needs the owner

- [ ] Attorney review of Terms of Service and Community Guidelines
- [ ] Trademark search on "United Feminist"
- [ ] NCMEC CyberTipline registration — required **before** any image upload ships
- [ ] PhotoDNA application — free, approx. one week lead time
- [ ] Name the external contact who receives reports about the Owner account
- [ ] Choose the founding cohort (10–50 people)
- [ ] Decide on point-in-time database recovery (~$100/mo) at launch
- [ ] Review the Phase 1 judgment calls listed below

## Phase 1 judgment calls (flagged, not silently decided)

1. **The architecture doc's invite-token tables were superseded** by the
   locked "Who invited you?" @handle flow (the Option C pivot). No
   `invitations` token table exists; vouching hangs off
   `vouch_requests` + `admission_applications`. Invite tokens/slots can
   return later if the owner ever wants shareable invites.
2. **The Owner's own vouch auto-admits** (she is the root of trust) —
   anyone else needs the explicitly granted `auto_admit` privilege.
3. **Handle availability at signup is checked openly** (as on any
   platform with unique handles), rate-limited per IP. This is a
   residual, deliberate information channel — distinct from the
   "Who invited you?" field, which leaks nothing.
4. **Auto-rejected applicants see "pending review" forever** rather
   than a rejection — a rejection message would be an oracle for bots.
   A human-rejected applicant does see "not approved".
5. **Admission decisions (approve/reject/request-info) are Owner +
   Admin**; Moderators and T&S Reviewers see the queue read-only.
6. **The voucher sees the applicant's legal name** in her vouch request
   — she cannot meaningfully confirm she knows the person from a handle
   alone, and the applicant named her deliberately.
7. **A duplicate phone number does not error at signup** (that would
   leak that the number belongs to an account); it is enforced at
   admission time instead, and surfaces as a flag in the queue.
8. **Vouch-request cap default is 5/day per member**; signup cap is
   10/day per IP. Both live in `app_config` and are tunable by SQL.

## Key decisions

See `README.md` for the summary table and `docs/architecture.md` for the
full reasoning. Notable:

- **Admission is never based on appearance or gender**, in either lane.
  This is a deliberate legal and ethical decision, not an oversight.
- **Real names are collected and verified but not publicly displayed by
  default.** Pseudonymity with accountability. The database itself
  guarantees a profile's display name is either empty (handle shows) or
  exactly the verified legal name — opt-in, reversible.
- **Only the Owner can grant or revoke any role or privilege**, and the
  database enforces it below the application: a BEFORE trigger rejects
  non-Owner grants, and no application role — the server's service key
  included — holds write privileges on the role tables at all.
- **DMs are not end-to-end encrypted in V1**, but the schema, franking,
  and key tables are built so that E2E is a configuration change later
  rather than a rewrite. The empty `user_devices` and `one_time_prekeys`
  tables shipped in Phase 1 are that readiness, not dead code. If E2E is
  ever enabled, the CSAM posture for DM images must be reopened —
  scanning does not survive encryption.
- **Images are served through Cloudflare** so that free CSAM scanning
  sees them, and EXIF is stripped at upload so location data never lands
  in storage. (Phase 3.)
