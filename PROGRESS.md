# PROGRESS: United Feminist

Updated: 2026-10-02

## Where things stand

**The admission gate is gone.** The owner opened registration ("all are
welcome"): no invite, no vouch, no inviter field, no approval queue, no gender
screening of any kind. Enforcement is conduct-based and after the fact:
bullying and harassment are banable offenses, and the ban-evasion blocklist
(email/device hashes checked silently at signup) is now the load-bearing
defence behind "I can ban whoever I want including any new accounts they may
make."

The entire vouch/admission system was deleted as dead code in the same change
(tables, functions, types, RLS policies, pages, API routes, tests), and two
forward-only migrations (0011, 0012) apply the removal safely to the live
database. The first-run trap (new accounts defaulting to a `pending_vouch`
trust level that nothing could ever promote them out of) is fixed by removing
that enum value entirely: new accounts are full members the moment they exist.
The `male_account` report reason was removed from the planned reports schema
in `docs/architecture.md`; it never existed in the live database.

What stays, deliberately: owner-only role granting enforced at the database
layer (trigger + SECURITY DEFINER + REVOKE), the hash-chained audit log,
ban/suspension machinery, email verification, and the bot pre-filter
(disposable email domains, subnet velocity, profile coherence, device
fingerprints), repurposed from review-queue routing to auto-flagging.

Typecheck, lint, build, and the security smoke suite (now covering open
signup, ban-evasion refusal, and the roles/audit invariants) all pass.

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

## Next session, start here

1. **Apply the new migrations to the live project**: `supabase db push`
   (or re-run `npm run provision`, which is idempotent). Migrations 0011 and
   0012 remove the admission system and fix the trust-level default.
2. **Phase 2, text social core** (posts, threaded replies, follows, feed).
   Full design spec: `docs/design-phase2-social-core.md`. The first-run trap
   that blocked Phase 2 is fixed.
3. **Legal documents need revision for open registration** (separate task):
   ToS §1.2 (references the admission process), all of §3 "Admission and the
   Vouching System" (§§3.1–3.7), §2.5 (invitation-system wording), §9.4
   (invitation tokens), and the attorney-review preamble items 1–2; Community
   Guidelines membership/vouching passages (opening "how members arrive",
   "The Community We Are Building", "Admission abuse", and the entire
   "Inviter accountability" section with its table).

## Not started

- [ ] Phase 2: text social core (posts, threaded replies, follows, feed)
- [ ] Phase 3: media pipeline and moderation backbone (includes the ban
      actions that feed `banned_identifiers`)
- [ ] Phase 4: direct messages with photos
- [ ] Phase 5: discovery and the For You feed
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
