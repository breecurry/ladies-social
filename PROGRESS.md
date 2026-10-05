# PROGRESS: Hersciety

Updated: 2026-10-07

## 🟢 LIVE STATUS — https://www.hersciety.com is UP (verified 2026-10-07)

Deployed and passing every production check: pages return 200; `/home`,
`/search`, `/notifications`, `/settings`, `/u/*` all 307 to `/login` when
logged out; the client bundle points at the correct Supabase project and
contains no service-role key or pepper; all six security headers present;
`robots.txt` disallows everything (still intentionally **noindex** — see
Deployment below); row-level security blocks anonymous reads; owner
`@getbakedwithbre` and system `@hersciety` accounts intact; zero runtime
errors.

Next, in order: set the Supabase **Site URL to `https://www.hersciety.com`**
(with the www — see the warning in Deployment), re-add the Resend SMTP
credentials on the rebuilt project, re-raise the auth rate limits, enroll MFA,
then Phase 2B (Discover feed, age gate, and moderation/report-action tooling —
nothing can action a report today, which is why the site stays noindex).

## Naming (decided 2026-10-06, spelling corrected 2026-10-07; do not re-litigate)

Three layers, each with its own name. Confusing them breaks things:

- **Hersciety is the product brand and the canonical domain.** Everything a
  user reads says Hersciety (H-E-R-S-C-I-E-T-Y, with an S), and the app lives
  at **hersciety.com**.
  ⚠️ **"Herciety" (no S) is a misspelling that briefly shipped on
  2026-10-06, and herciety.com is a DIFFERENT domain owned by an unrelated
  third party. Never reference the misspelling or that domain anywhere; do
  not "correct" the spelling back.** The misspelled handle @herciety stays
  permanently reserved in the database (migration 0016) purely as an
  impersonation guard.
- **United Feminist is the company.** unitedfeminist.com is the secondary
  domain and redirects to hersciety.com, but it **still owns all email**: the
  four live contact aliases (safety@ / appeals@ / support@ / legal@
  unitedfeminist.com) and the transactional sender address stay put, because
  they are routed, working, named by address in the legal documents, and the
  email provider's DKIM is verified for unitedfeminist.com only.
- **Curry Co LLC (Tennessee) is the legal entity.** Legal documents read
  "Hersciety, a service operated by Curry Co LLC."

**WEBAUTHN_RP_ID is `hersciety.com` (set 2026-10-06, spelling corrected
2026-10-07).** Changing it was safe only because the database was rebuilt the
same day, has exactly
two accounts, and has never been deployed: a relying-party ID is effectively
permanent once members hold passkeys, because changing it invalidates every
one of them. If the Owner enrolled a passkey before this change, she must
re-enroll it once. Do not change this value again.

## Where things stand

**Phase 2A, the text social core, is built and hardened.** Posts (text
only, 500
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

**Security hardening pass (2026-10-06).** An independent security audit
and an adversarial QA pass each reviewed Phase 2A; every P1 and P2
finding from both is fixed by migration 0014
(`20261006000001_social_core_hardening.sql`, forward-only, idempotent —
0013 itself is untouched) plus app-layer changes:

- **Block-state probing is dead.** `blocked_either`/`blocked_by` were
  RPC-callable with arbitrary ids (any member could map blocks between
  two other people, and a blocked person could ask point-blank "did she
  block me?"). `public.*` versions lost all app-role EXECUTE and
  `blocked_either` is caller-scoped; the RLS policies call twins in a
  new `internal` schema that PostgREST does not expose. `notif_enabled`
  likewise revoked.
- **The follows table filters blocks** (both directions, both columns).
  Previously a blocked member could enumerate her blocker's entire
  follower/following graph with a direct table read — the worst finding
  of the pass. Side effect, correct by design: follows that predate a
  block disappear from both parties' lists and counts.
- **`get_thread` returns nothing for a blocked author's root post**, so
  the app 404s instead of rendering a tombstone that confirms the post
  exists. In-thread tombstones are unchanged.
- **Reports are rate-limited**: one per (reporter, accused, reason) per
  24h, ten per reporter per hour, both refused with calm copy —
  mass-reporting can no longer bury a victim's queue.
- **Mentions require a word boundary** before `@` ("noreply@cat" no
  longer notifies @cat), **search escapes LIKE wildcards** ("a_a" no
  longer matches "ada"), **reply depth caps at 30**, **pagination uses
  composite (created_at, id) cursors** so timestamp ties are never
  skipped, and moderation-removed posts can never surface as parent
  excerpts or notification excerpts.
- **Security response headers shipped** in `next.config.ts`:
  `Referrer-Policy: no-referrer` (tightened at deploy 2026-10-05 from
  `strict-origin-when-cross-origin`, which still broadcast the bare origin
  — i.e. *membership of this platform* — on every outbound external click),
  `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, and a
  restrictive `Permissions-Policy`.
- **OverflowMenu closes on Escape** and returns focus to its trigger
  (keyboard users could open the safety menu but not dismiss it).

Test suites: `04-known-vulnerabilities.sql` is converted from
NOTICE-based documentation to a hard-failing regression gate (all six
QA findings fixed), and the new `05-hardening-regressions.sql` covers
the follows filter, report limits, root-post guard, depth cap, excerpt
visibility, and structural EXECUTE-privilege guards. One existing
assertion changed: 02 §8 files the moderator report as `spam` instead
of repeating `harassment`, which the new duplicate guard would refuse.

**Not in 2A, deliberately:** Discover + ranking (2B, with moderation
groundwork), the age gate screens (spec §17), reshares/quotes (schema
arrives additively with the feature), image upload of any kind (hard-
gated on NCMEC + PhotoDNA registration), DMs, owner moderation queue.

## Deployment (going live on hersciety.com)

**Host: Vercel** (first-party Next.js 16; `src/middleware.ts` auth gate runs
natively on every protected prefix). **DNS: Cloudflare in DNS-only / grey-cloud
mode** for the app records — Vercel issues and renews the Let's Encrypt
certificate and does the HTTP→HTTPS redirect itself. Do **not** turn on
Cloudflare's orange-cloud proxy in front of Vercel at launch: it interferes with
certificate issuance and blinds Vercel's firewall.

⚠️ **Canonical hostname is `www.hersciety.com`, NOT the apex.** An earlier
version of this document said the apex was canonical; the deployed reality is
the reverse and the deployment is the source of truth. Verified live:
`hersciety.com` → **308** → `https://www.hersciety.com`, and
`unitedfeminist.com` → **301** → `https://www.hersciety.com` preserving path
and query. **Set the Supabase Site URL to `https://www.hersciety.com` (with
the www) or auth links will break.**
`WEBAUTHN_RP_ID` stays `hersciety.com` — an RP ID may be a registrable suffix
of the origin, so it covers `www`. Do **not** narrow it to `www.`.

### ⚠️ Env vars: the app reads EXACTLY FOUR. Everything else is a decoy.

```
NEXT_PUBLIC_SUPABASE_URL        NEXT_PUBLIC_SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY       IDENTIFIER_HASH_PEPPER
```
`SUPABASE_SERVICE_ROLE_KEY` and `IDENTIFIER_HASH_PEPPER` are **server-only —
never `NEXT_PUBLIC_`, never in a client bundle; verified absent from
`.next/static`**. Never change `IDENTIFIER_HASH_PEPPER`: stored hashes depend
on it.

🪤 **Vercel's Supabase integration auto-injects ~13 more variables with
near-identical names** — `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY`, `SUPABASE_JWT_SECRET`,
`NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, `POSTGRES_*`. **The application reads
none of them.** On 2026-10-07 this cost a full outage: `SUPABASE_URL` had been
updated to the new project while `NEXT_PUBLIC_SUPABASE_URL` was missing
entirely, so every page returned HTTP 500 with
`Missing required environment variable: NEXT_PUBLIC_SUPABASE_URL`. If the site
is down, read the Vercel runtime log first — it names the variable — and
confirm the real list straight from the source:

```sh
grep -rhoE 'process\.env\.[A-Z0-9_]+' --include=*.ts --include=*.tsx src/
grep -rhoE 'requireEnv\("[A-Z0-9_]+"\)' --include=*.ts src/   # env.ts wrapper
```

🚨 **`NEXT_PUBLIC_*` values are inlined at BUILD time. Saving a variable in
Vercel changes nothing until a new deployment is built.**

`supabase/config.toml` is local-dev config and does **not** push auth settings
to the hosted project; set Site URL and the redirect allow-list in the Supabase
dashboard (Authentication → URL Configuration).

**Shipped "dark" (noindex) on purpose.** Registration is open but there is no
moderation action path yet (the `reports` table has no UPDATE route for any
role — that is Phase 2B), so the site must be reachable by a direct link but not
search-discoverable. Three layers — the `X-Robots-Tag: noindex, nofollow`
response header, a disallow-all `/robots.txt`, and the per-page `robots` meta
tag — are all driven by one flag, `SITE_INDEXABLE` (see `src/lib/seo.ts`).
Default/unset = noindex (fail-safe).

### How to go public (flip when moderation tooling ships)

1. In Vercel → **Settings → Environment Variables**, add `SITE_INDEXABLE` with
   value `true` (Production scope).
2. **Redeploy** (Deployments → latest → Redeploy, or push a commit). That single
   flag flips the header to absent, `/robots.txt` to `Allow: /`, and the meta tag
   to indexable in one step. To go dark again, delete the var (or set it to
   anything other than `true`) and redeploy.
3. Do this **only after** report-review / ban tooling exists, because open
   registration + no moderation path + search-discoverable is the combination
   this flag exists to prevent.

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
- [x] **Phase 2A security hardening (2026-10-06).** Every P1/P2 finding
      from the independent security audit and the adversarial QA pass,
      fixed in migration 0014 + app layer (see "Where things stand").
      `04-known-vulnerabilities.sql` now hard-fails on regression; new
      `05-hardening-regressions.sql` gates the fixes.
- [x] **Phase 2B, age gate (spec §17).** Migration 0017
      (`20261009000001_age_gate.sql`): `age_gate_blocks` — a block row is
      a hashed device fingerprint, timestamps and a short reference code,
      and STRUCTURALLY nothing else (no email, no name, no DOB, no IP;
      `06-age-gate.sql` breaks if a column is ever added) — plus the
      record/get/lookup/clear SECURITY DEFINER functions. **Data
      minimisation: `user_private.dob` is dropped**; the 18+ check still
      runs in the form, the signup route, and `create_member()`/
      `bootstrap_owner()` (which keep `p_dob` for validation), but the
      raw birth date is no longer retained anywhere — `age_attested_at`
      is the derived record. Signup form now uses the §17.1 three-field
      blank date-of-birth group + 18+ attestation checkbox; an under-18
      date routes to the §17.2 rejection screen (which collects nothing)
      and soft-blocks the device for 14 days (fingerprint hash + cookie);
      a returning device meets the §17.3 blocked screen with its copyable
      reference code and the support mailto. Owner support unlock at
      `/owner/age-gate` (look up a quoted code, clear that one block);
      authority re-checked in the database. New smoke suite
      `06-age-gate.sql`.

## Next session, start here

1. **Provision the rebuilt live project.** The original Supabase project was
   deleted by accident on 2026-10-06. The live project is now ref
   `hiphjzhlwiztqgezzipf` (named `Hersciety`, Curry Co org, us-east-1), with
   migrations 0001-0015 applied but **no auth configuration set yet** — it
   all has to be configured fresh. Run `npm run provision` with
   `SUPABASE_PROJECT_REF=hiphjzhlwiztqgezzipf` to assert the auth posture
   (30-minute JWTs, refresh rotation, required email confirmation, TOTP, Site
   URL `https://hersciety.com`) and to seed the Owner + the @hersciety system
   account (both steps are skipped automatically if already done). The script
   now refuses to create a new project unless `SUPABASE_ALLOW_CREATE=yes` is
   passed explicitly, so a name or ref mismatch stops loudly instead of
   silently spawning a duplicate.
2. **Phase 2B remainder**: Discover feed (chronological, with the hide signal
   suppressing hidden accounts) + the minimal report-review/ban tooling
   committed to before strangers can find each other (nothing writes
   `banned_identifiers` yet). The age gate (spec §17) is DONE — but
   migration 0017 is **not yet applied to the live project**; the next
   `npm run provision` (or `supabase db push`) applies it. ⚠️ 0017 drops
   `user_private.dob` (data minimisation, see Done) — deliberate and
   flagged; the owner's own stored DOB is removed by it too.
3. **Legal documents need revision for open registration** (separate task):
   ToS §1.2 (references the admission process), all of §3 "Admission and the
   Vouching System" (§§3.1-3.7), §2.5 (invitation-system wording), §9.4
   (invitation tokens), and the attorney-review preamble items 1-2; Community
   Guidelines membership/vouching passages (opening "how members arrive",
   "The Community We Are Building", "Admission abuse", and the entire
   "Inviter accountability" section with its table).

## Known gaps and deliberate skips in Phase 2A (re-flag, do not lose)

### Deferred from the 2026-10-06 hardening pass (deliberate, tracked)

- **Content-Security-Policy is not set yet.** The theme-init inline
  script in `src/app/layout.tsx` needs a nonce or hash before a useful
  CSP can ship; doing it badly (`unsafe-inline`) would be security
  theatre. Separate follow-up task; the other response headers are live.
- **`middleware.ts` is not renamed to `proxy.ts`** even though Next.js 16
  emits a deprecation notice suggesting it. That file is route
  protection; renaming it inside a security fix pass was judged not
  worth the risk. Do it as its own tiny change with its own verification.
- **Post ids remain sequential bigints.** The security audit flagged
  sequential ids as a probing aid (a blocked person can watch id gaps to
  infer activity). Moving to UUIDs or opaque short codes is a costly
  structural change — needs the owner's call, banked for Phase 2B+.
- **The Owner's personal account is still unblockable**
  (`forbid_blocking_protected` protects both `is_system` accounts and
  the owner role). Both auditors recommend protecting only `is_system`
  so the Owner's human account is blockable like anyone's; this is the
  owner's personal decision and is deliberately NOT changed here. If
  she says yes it is a one-line follow-up migration; if no, drop it.

### Skips carried over from the 2A build

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
- [ ] Trademark search on "Hersciety" (the earlier "United Feminist" name was
      never cleared either)
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
