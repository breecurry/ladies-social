# PROGRESS: United Feminist

Updated: 2026-10-05

## Where things stand

**Phase 2A, the text social core, is built.** Posts (text only, 500
chars), threaded replies (adjacency list with denormalised root/depth,
three visible levels then re-root), follows with the owner's exact
mechanics (one-tap follow with undo toast, profile-only confirmed
unfollow), the Following feed (fan-out-on-read, zero counts hidden),
profiles with follower/following lists, people search by @handle, the
conventional three-dot overflow with the full safety set (copy link,
show-me-less, mute, block with confirmation, report with routing),
in-app notifications with a red 9+ -capped badge and per-type prefs,
and the re-architected settings IA (Account, Privacy, Safety,
Notifications, Appearance, About) with the legal-name opt-in moved
into Privacy with a preview.

The app shell replaced the old text-link layout: desktop left rail +
centred 600px column, mobile 5-slot bottom tab bar, composer as a
modal/bottom sheet with a late-revealing counter and per-post reply
controls.

Migration 0013 (`20261005000001_social_core.sql`) is forward-only and
idempotent against the live database and is covered by a new security
smoke suite (`supabase/tests/02-social-smoke.sql`): mutual-hard blocks
in both directions, mute filtering, the structural guarantee that no
feed/thread/search function can return a legal name, report routing
with `owner_conflict` invisible in-app to everyone including the
Owner, notification RLS, and DEFINER-only write paths. Typecheck,
lint, build, and both smoke suites pass.

**Not in 2A, deliberately:** Discover + ranking (2B, with moderation
groundwork), the age gate screens (spec §17), reshares/quotes (schema
arrives additively with the feature), image upload of any kind (hard-
gated on NCMEC + PhotoDNA registration), DMs, owner moderation queue.

## Done

- [x] Product definition, positioning, and the name
- [x] Membership model: **fully open registration, conduct-based removal**
      (supersedes the earlier two-lane admission model)
- [x] Visual identity and the complete design token system
- [x] Security, verification and trust & safety architecture
- [x] Encryption approach and the roles/permissions model
- [x] Terms of Service and Community Guidelines (draft; **now stale on
      admission, see below**; attorney review pending)
- [x] Technical architecture, database schema, phased build plan
- [x] **Phase 1: identity and the security skeleton.** Scaffold, schema +
      RLS, design tokens, signup, roles with database-enforced owner-only
      grants, hash-chained audit log, auth with TOTP MFA (WebAuthn pending
      Supabase support). Security smoke suite passing.
- [x] **Automated provisioning path**: `scripts/provision.sh`
      (`npm run provision`) and `docs/provisioning.md`.
- [x] **Gate removal (2026-10-02).** Open signup (email, password, handle,
      legal name, date of birth); vouch/admission system deleted end to end;
      `pending_vouch` removed from the trust model; migrations 0011 + 0012
      are forward-only and idempotent against the live database.
- [x] **Phase 2A: text social core (2026-10-05).** Migration 0013 (follows,
      mutual-hard blocks, mutes, show-me-less, posts + threading, likes,
      conduct-only reports with routing, notifications), the app shell,
      feed, composer, thread view, profiles + lists, people search,
      overflow safety menu, notifications surface, and the settings IA.
      New smoke suite `02-social-smoke.sql` covering the social-core
      security invariants.

## Next session, start here

1. **Apply migration 0013 to the live project**: `supabase db push` (or
   re-run `npm run provision`, which is idempotent). 0013 is forward-only
   and idempotent; 0001-0012 are already applied.
2. **Phase 2B**: Discover feed (chronological, with the hide signal
   suppressing hidden accounts) + the age gate screens (spec §17) + the
   minimal report-review/ban tooling committed to before strangers can
   find each other (nothing writes `banned_identifiers` yet).
3. **Legal documents need revision for open registration** (separate task):
   ToS §1.2 (references the admission process), all of §3 "Admission and the
   Vouching System" (§§3.1-3.7), §2.5 (invitation-system wording), §9.4
   (invitation tokens), and the attorney-review preamble items 1-2; Community
   Guidelines membership/vouching passages (opening "how members arrive",
   "The Community We Are Building", "Admission abuse", and the entire
   "Inviter accountability" section with its table).

## Known gaps and deliberate skips in Phase 2A (re-flag, do not lose)

- Swipe mute/block accelerator, keyboard j/k shortcuts, the new-posts
  pill, offline banner/PWA caching, the one-time overflow tooltip, and
  account deactivation/deletion UI (Settings, Account explains the
  interim email path). All flagged by design; none block 2B.
- The desktop right rail (persistent search + getting-started card at
  xl) is not built; search is a primary nav destination, so nothing is
  unreachable.
- The on-card Follow pill appears in people rows (search, lists); feed
  cards do not need it (Following-only feed) and thread reply cards do
  not carry it yet; it becomes load-bearing with Discover in 2B.
- Notifications fetch the latest 50 with no pager; fine for the
  founding cohort.
- Report history shows reason/status only (no deep link to the
  reported content); enough to close the loop until the 2B review
  tooling exists.

## Not started

- [ ] Phase 2B: Discover + age gate + minimal moderation/ban tooling
- [ ] Phase 3: media pipeline and moderation backbone (includes the ban
      actions that feed `banned_identifiers`)
- [ ] Phase 4: direct messages with photos
- [ ] Phase 5: discovery ranking and the For You feed
- [ ] Phase 6: launch hardening

Deferred, needs the owner's call: phone verification and age verification
(both under evaluation; `user_private.phone_e164` and the `phone_hash`
ban-list kind are kept for the former). Also deferred: the daily audit log
export to S3 Object Lock.

## Needs the owner

- [ ] Attorney review of the Terms and Guidelines (after the open-registration
      revision)
- [ ] Trademark search on "United Feminist"
- [ ] NCMEC CyberTipline registration, required **before** any image upload ships
- [ ] PhotoDNA application, free, roughly a week's lead time
- [ ] Name the external contact who receives reports about the Owner account
- [ ] Choose the founding cohort (the first 10-50 people she asks to join)
- [ ] Decide on point-in-time database recovery (~$100/mo) at launch

## Decisions worth not relitigating

- **Membership is open and removal is conduct-based.** No invite, no vouch,
  no queue, and never any appearance or gender screening. The gate was
  removed by the owner's explicit decision on 2026-10-02.
- **Roles stay, in full.** "I can ban whoever I want" IS the owner/admin role
  machinery; owner-only role granting is enforced at the database layer and
  covered by the smoke suite. Do not delete roles.
- **Ban evasion is the load-bearing defence now.** Banned email/device hashes
  are checked at signup and refused silently, with uniform response timing so
  a banned person cannot confirm detection. Build Phase 3 ban actions to feed
  `banned_identifiers` on every permanent ban.
- **Real names are collected but not publicly displayed by default.**
  Pseudonymity with accountability.
- **DMs are not end-to-end encrypted in V1**, but the schema, franking, and
  key tables make E2E a later configuration change rather than a rewrite.
  If E2E is ever switched on, the CSAM posture for DM images must be
  reopened, because scanning does not survive encryption.
- **Images are served through Cloudflare** so free CSAM scanning sees them,
  and EXIF is stripped at upload so location data never reaches storage.
