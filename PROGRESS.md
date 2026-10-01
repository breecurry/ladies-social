# PROGRESS — United Feminist

Updated: 2026-10-01 (end of kickoff session)

## Where things stand

**Planning complete. Phase 1 built, tested, and merged.** Nothing is running
yet — there is no Supabase project, so the next session starts with
provisioning.

## Done

- [x] Product definition, positioning, and the name
- [x] Membership model — open, two-lane admission, no gender screening
- [x] Visual identity and the complete design token system
- [x] Security, verification and trust & safety architecture
- [x] Encryption approach and the roles/permissions model
- [x] Terms of Service and Community Guidelines (draft; attorney review pending)
- [x] Technical architecture, database schema, phased build plan
- [x] **Phase 1 — admission system.** Scaffold, schema + RLS, design tokens,
      signup, both admission lanes, vouching, review queue with automated
      triage, roles with database-enforced owner-only grants, hash-chained
      audit log, auth with WebAuthn/TOTP. 17-assertion security smoke suite
      passing. Typecheck, lint, and build clean.

## Next session — start here

1. **Create the Supabase project.** Nothing runs until this exists.
2. Apply the migrations in `supabase/migrations/`.
3. Dashboard configuration: 30-minute JWTs, refresh token rotation, email
   confirmation, MFA factors, pg_cron.
4. Run `npm run bootstrap` to seed the Owner account and the system account.
5. First real signup on your own platform.

## Not started

- [ ] Phase 2 — text social core (posts, threaded replies, follows, feed)
- [ ] Phase 3 — media pipeline and moderation backbone
- [ ] Phase 4 — direct messages with photos
- [ ] Phase 5 — discovery and the For You feed
- [ ] Phase 6 — launch hardening

Deferred within Phase 1, needs provisioning first: phone OTP verification
(Twilio Verify), vouch-request email notifications (Resend), and the daily
audit log export to S3 Object Lock.

## Needs the owner

- [ ] Attorney review of the Terms and Guidelines
- [ ] Trademark search on "United Feminist"
- [ ] NCMEC CyberTipline registration — required **before** any image upload ships
- [ ] PhotoDNA application — free, roughly a week's lead time
- [ ] Name the external contact who receives reports about the Owner account
- [ ] Choose the founding cohort (10-50 people)
- [ ] Decide on point-in-time database recovery (~$100/mo) at launch
- [ ] Confirm whether admins should work the review queue, or the Owner alone

## Decisions worth not relitigating

- **Admission is never based on appearance or gender**, in either lane. This
  is deliberate, legal, and ethical — not an oversight. There is case law
  against the alternative.
- **Real names are collected and verified but not publicly displayed by
  default.** Pseudonymity with accountability.
- **Auto-admit is a privilege the Owner grants**, not a threshold members
  cross automatically.
- **Handle enumeration is treated as a security boundary.** The signup
  response is identical, and uniformly timed, whether or not the named
  inviter exists. Do not "simplify" this away.
- **DMs are not end-to-end encrypted in V1**, but the schema, franking, and
  key tables make E2E a later configuration change rather than a rewrite.
  If E2E is ever switched on, the CSAM posture for DM images must be
  reopened — scanning does not survive encryption.
- **Images are served through Cloudflare** so free CSAM scanning sees them,
  and EXIF is stripped at upload so location data never reaches storage.
