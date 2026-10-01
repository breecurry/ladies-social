# PROGRESS — United Feminist

Updated: 2026-10-01

## Current state

**Planning complete. No application code written yet.**

All four planning deliverables are committed under `docs/`. Every major
product, legal, security, and architecture decision is locked. The next step
is building Phase 1.

## Done

- [x] Product definition and positioning
- [x] Membership model — open, two-lane admission, no gender screening
- [x] Visual identity and complete design token system
- [x] Security, verification and trust & safety architecture
- [x] Encryption approach and roles/permissions model
- [x] Terms of Service and Community Guidelines (draft; attorney review pending)
- [x] Technical architecture, database schema, phased build plan
- [x] Repo write access confirmed

## In progress

- [ ] Phase 1 build — admission system (signup, two-lane gate, vouching,
      review queue, roles, audit log)

## Not started

- [ ] Phase 2 — text social core (posts, replies, follows, feed)
- [ ] Phase 3 — media pipeline and moderation backbone
- [ ] Phase 4 — direct messages with photos
- [ ] Phase 5 — discovery and For You feed
- [ ] Phase 6 — launch hardening

## Blocked / needs the owner

- [ ] Attorney review of Terms of Service and Community Guidelines
- [ ] Trademark search on "United Feminist"
- [ ] NCMEC CyberTipline registration — required **before** any image upload ships
- [ ] PhotoDNA application — free, approx. one week lead time
- [ ] Name the external contact who receives reports about the Owner account
- [ ] Choose the founding cohort (10–50 people)
- [ ] Decide on point-in-time database recovery (~$100/mo) at launch

## Key decisions

See `README.md` for the summary table and `docs/architecture.md` for the
full reasoning. Notable:

- **Admission is never based on appearance or gender**, in either lane.
  This is a deliberate legal and ethical decision, not an oversight.
- **Real names are collected and verified but not publicly displayed by
  default.** Pseudonymity with accountability.
- **DMs are not end-to-end encrypted in V1**, but the schema, franking, and
  key tables are built so that E2E is a configuration change later rather
  than a rewrite. If E2E is ever enabled, the CSAM posture for DM images
  must be reopened — scanning does not survive encryption.
- **Images are served through Cloudflare** so that free CSAM scanning sees
  them, and EXIF is stripped at upload so location data never lands in
  storage.
