# PROGRESS: Hersciety

Updated: 2026-10-09

## 🟢 LIVE STATUS — https://www.hersciety.com is UP (verified 2026-10-07)

Deployed and passing every production check: pages return 200; `/home`,
`/search`, `/notifications`, `/settings`, `/u/*` all 307 to `/login` when
logged out; the client bundle points at the correct Supabase project and
contains no service-role key or pepper; all six security headers present;
`robots.txt` disallows everything (still intentionally **noindex** — see
Deployment below); row-level security blocks anonymous reads; owner
`@getbakedwithbre` and system `@hersciety` accounts intact; zero runtime
errors.

Next, in order: **apply migration `20261013000001` (Discover) to the live
project** — the Discover feed code is on main and deploys with it, but the
feed's functions and the `discoverable` column do not exist on live until the
migration is applied (until then the Discover tab renders its calm empty
state and the Privacy toggle cannot save; nothing crashes) → **profile
pictures / avatars** (designed in `docs/design-phase2e-profile-pictures.md`;
unblocked now that the moderation console is live; PhotoDNA is voluntary and
NCMEC pre-registration is not required) → **admin dashboard** (designed in
`docs/design-phase2d-admin-dashboard-and-metrics.md`) → **Grove-Test**
(adversarial) → **Grove-Security** (mandatory before any public launch) →
the Owner's MFA enrolment → counsel sign-off, then flip `published: true` in
`src/lib/legal.ts` (one line per document).

Everything the older version of this list named is now done: the Supabase
Site URL is `https://www.hersciety.com`, Resend SMTP is configured and
sending, the auth rate limits were raised, Turnstile captcha is **on** and
enforcement is proven, and migrations `…0009` (age gate), `…0010`
(moderation), `…0011` (direct messages) and `…0012` (ToS consent) are all
applied to the live project.

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

**The Discover feed is built (Phase 2B Part 2, 2026-10-09).** Home now has
its two tabs (spec §4.1/§4.7): Following unchanged, and Discover — recent
root posts from across Hersciety, lightly ranked by
`feed_discover()` on **positive signals only**: recency (dominant by
construction), the viewer's own likes and follows, follow-graph proximity
(authors and posts favoured by the people she follows), log-damped aggregate
like counts, and a small time-limited cold-start lift for new authors. The
refused signals (design doc §11) are refused in code: reply volume,
controversy/ratio, report/block/mute counts, negative velocity and every
person-finder signal appear nowhere; blocks and mutes hard-filter, "show me
less" strongly down-ranks without filtering, suspended authors and removed
posts never surface. A member with zero follows lands on Discover (then the
last-chosen tab is remembered), unfollowed authors' cards carry the outlined
Follow pill, members with few follows get the people-first
`suggested_accounts()` module, and the empty/sparse states are the warm
founding-cohort ones from design doc §12 — never fake liveliness.
**Discoverability is ON by default with the opt-out in Settings → Privacy
(owner decision 2026-10-07):** `profiles.discoverable = false` removes a
member from every member's Discover feed AND the suggestions module at the
database layer, while she stays fully reachable by exact @handle search.
Identity is @handle-only on every Discover surface, and suite
`10-discover.sql` asserts structurally that neither new function references
`display_name`, plus the opt-out, block/mute/hide semantics, and
authenticated-only EXECUTE. ⚠️ **Migration `20261013000001_discover.sql` is
written, idempotent, and verified locally (fresh apply, re-run, and
populated-database apply all clean) but has NOT been applied to the live
project yet — Grove applies it after review.** Until it is applied, the
deployed Discover tab degrades gracefully (empty feed state, toggle save
fails with the calm retry toast); after it is applied, everything above is
live with no further deploy.

**The brand mark is live (2026-10-08).** The owner's logo — a purple
"Hersciety" wordmark whose dotted `i` is a speech bubble — is now real
assets rather than a loose file: `public/wordmark-light.png` and
`public/wordmark-dark.png` (1024×265), `src/app/icon.png`,
`src/app/apple-icon.png`, `src/app/favicon.ico` and
`src/app/opengraph-image.png`, all rendered by
`src/components/BrandWordmark.tsx` in the desktop rail, the mobile top bar,
the public header and the landing hero. The spec is
`docs/design-brand-mark-integration.md`. Two things to know before anyone
regenerates these: the source PNG carries a halo of **alpha 1-8 ghost
pixels** that poisons a naive bounding box (measure with a threshold — the
true trimmed ratio is 3.865:1, not the padded canvas's 2.74:1, and the halo
must be zeroed before resampling), and the icons are **auto-wired by Next.js
file convention**, so `layout.tsx` must NOT gain an `icons` or
`openGraph.images` block. The logo purple `#6901E2` is deliberately left
different from the UI token `--accent #6d28d9`; in dark mode the wordmark
renders in `#a78bfa`, because raw `#6901E2` measures 2.38:1 on the dark
background and is unreadable. `robots` / `SITE_INDEXABLE` was not touched —
the site is still **noindex** until the owner says otherwise.

**Direct messages are built — end-to-end encrypted, text-only, 1:1 —
and ship DARK behind the `dm_e2e_enabled` feature flag (Phase 2C,
2026-10-05).** The server stores ciphertext only: migration
`20261011000001_direct_messages.sql` wires the (until now empty)
`user_devices` / `one_time_prekeys` tables from 0007, adds
conversations with the silent one-request cap, Messages settings, and
client-side report-with-evidence whose franking commitments the
database verifies with pgcrypto — the reporter cannot fabricate a
message and the sender cannot deny one, while the platform reads ONLY
what a reporter chooses to attach. The crypto is an X3DH-style
agreement plus a Double Ratchet on audited MIT primitives
(@noble/curves, @noble/ciphers, @noble/hashes — libsignal is AGPLv3
and deliberately unused), unit-tested with `npm run test:dm-crypto`.
The inbox rules are enforced in the database, not the UI: main inbox
only from people you follow; everyone else gets exactly one silent
request (no notification, no badge, preview-only, no second message
until accepted, and declining can never grant a second one); block /
DMs-off / "no one" all refuse with the identical message so a block is
indistinguishable. Every DM surface is @handle-only (suite
09-dm-smoke asserts it structurally). **Nothing is reachable until the
external cryptographic audit passes and both flag layers are flipped —
`DM_E2E_ENABLED` in the environment and the `dm_e2e_enabled` row in
app_config; see KNOWLEDGE/app.md for the exact go-live order.** There
is no readable-by-the-platform fallback: off means the surfaces do not
exist. ✅ **Migration `20261011000001` WAS APPLIED to the live project on
2026-10-08** (via the Supabase management API, HTTP 201; re-run twice more
against production, clean both times, so idempotency is proven on live).
Verified after: five DM tables with RLS on all of them, 18 DM functions,
`message` added to both `report_subject` and `notif_type`, zero tables
without RLS database-wide, both accounts intact. It also closed a real
pre-existing hole — `user_devices` and `one_time_prekeys` have had NO RLS
since 0007 created them, and now do. 🔒 **`dm_e2e_enabled` has 0 rows in
`app_config`: the feature is dark at the database layer, not just the UI.**

**The moderation console is built (Phase 2B, 2026-10-05).** Reports can
finally be actioned. Migration `20261010000001` is the data layer: the full
enforcement ladder as SECURITY DEFINER functions (dismiss/reopen, warn,
remove/restore content, restrict, suspend, permanent ban, escalate,
owner-only unban), every action appended to the hash-chained audit log and to
a `moderation_actions` history (2-year retention, pruned opportunistically).
Role boundaries are enforced at the database, not just the UI: a reviewer is
read-only, a moderator cannot ban and cannot suspend or restrict past 7 days,
an admin tops out at the guidelines' 30-day band, the Owner and the system
account can be neither suspended nor banned, and csam cases resolve only at
the Owner (everyone else escalates). Banning writes HMAC-only email/device
(and phone, when it exists) signals to `banned_identifiers`, which
`create_member()` already refuses — "I can ban whoever I want including any
new accounts they make" is now enforced end to end. **Owner decision
implemented (supersedes the design doc's original §7): reports naming the
Owner go to the normal admin panel, visible to her, and EVERY report queues
an email copy to safety@unitedfeminist.com** (durable `safety_email_outbox`,
sent via Resend once `RESEND_API_KEY` exists in the deployment env; the copy
carries case reference + reason + accused @handle, never the reporter, the
text, or a legal name). The console UI lives at `/mod` (account-menu entry
for staff, calm queue counts, the one red dot reserved for Critical), with
case-grouped reports, in-case thread context, audited reporter reveal, the
typed-@handle ban gate with de-identified evasion toggles, and the
member-facing states: restriction banner, suspension interstitial, banned
terminal screen with an appeal reference — the member always learns the rule
and the action, never the reporter. No moderation query returns
`display_name`, proven structurally by the new smoke suite
`tests/07-moderation.sql`. ⚠️ Not yet applied to the live project — see
"Needs the owner".

**Legal pages are live.** The Community Guidelines are published at
`/community-guidelines`, server-rendered from `docs/community-guidelines.md`
(the markdown stays the single source of truth; react-markdown with no
raw-HTML pass-through, so no XSS surface). `/terms-of-service` and
`/privacy-policy` are public 200 pages but show an interim
"being finalised with counsel" notice instead of draft text. **As of
2026-10-07 every owner decision blocking them is RESOLVED** — ToS §7.7 was
deleted outright (end-to-end encryption makes administrator access to DM
content without a member report technically impossible, which moots the
question), and all six Privacy Policy §8 retention periods are filled in
(account data 30 days after deletion, public content deleted with the
account, DM ciphertext deleted with the account, technical and security data
90 days, moderation records 2 years, ban-evasion signals 2 years). Every
description of a feature that does not exist has been removed: phone number
collection, image upload, CSAM scanning of images, and the Twilio, Hive,
PhotoDNA and AWS vendor entries. **The only thing still standing between
these documents and publication is attorney sign-off** on the remaining
judgment calls (arbitration and class waiver, DPA execution, and whether the
retention periods survive the applicable statutes of limitations).
**When a document gets sign-off, flip its
`published` flag in `src/lib/legal.ts` — one line per document — and the
real text goes live at the same URL.** Aliases `/terms` `/tos` `/privacy`
`/guidelines` `/legal` redirect to the canonical routes. Signup links the
Community Guidelines beside the 18+ checkbox; the public footer and
Settings → About link them too.

**Terms of Service consent is required at signup and recorded (2026-10-05,
migration 0019 `20261012000001_tos_consent.sql`).** The signup form carries a
SEPARATE "I agree to the Terms of Service" checkbox — deliberately not
bundled with the 18+ attestation — linking to `/terms-of-service` in a new
tab. It is enforced server-side (`signupSchema`, `z.literal(true)`): a POST
straight to `/api/auth/signup` without `tosAgreed: true` is rejected 400, so
the checkbox is not skippable by bypassing the UI. On success the server
records `user_private.tos_agreed_at` plus `tos_version` via the
service_role-only `record_tos_consent()` (audited as `member.tos_consent`;
RLS self + Owner, like all private data). The version identifier is DERIVED
from `docs/terms-of-service.md` at request time — its "Last updated" line
plus a sha256 content hash (`src/lib/legal.ts → termsOfServiceVersion()`) —
never a hand-bumped constant, so it cannot go stale; while the document is
unpublished it carries an `interim:` prefix that disappears by itself when
the `published` flag flips. **Code/DB skew is safe in both directions:** the
enforcement lives in the schema (no database needed), and the consent write
is best-effort until the migration is applied, so deploying ahead of the
migration never breaks signup.
**Policy for accounts that predate the checkbox** (the Owner and the system
account): their `tos_agreed_at` stays NULL — the truthful record that no
consent was captured when they were created, before the Terms were published
or any checkbox existed. Nothing gates sign-in on these columns; no lockout,
no re-consent interruption. The Owner is the party OFFERING the terms
(Curry Co LLC) and the system account is not a person, so there is no
consent gap to remediate. If counsel ever wants affirmative re-consent from
pre-existing accounts after publication, that is a deliberate future flow,
not a backfill.

**Bot protection: Cloudflare Turnstile is wired on signup AND login
(2026-10-05), with enforcement still OFF.** Turnstile, not reCAPTCHA — no
Google tracking on the most sensitive pages in the product. The widget
(`src/components/Turnstile.tsx`) renders from `NEXT_PUBLIC_TURNSTILE_SITE_KEY`
(already set in Vercel; without it the forms work untouched), passes its
token into Supabase as `captchaToken`, resets it after any failed attempt
(tokens are single-use), and degrades to a calm notice if the script cannot
load. Supabase holds the Turnstile secret in auth config with
`security_captcha_enabled = false`. **The flip to `true` happens only after
this code is deployed** — and note the switch is GLOBAL to Supabase auth: it
covers sign-in as well as signup, which is why the login form carries the
widget too.

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

**Shipped "dark" (noindex) on purpose.** Registration is open, and the
moderation console (Phase 2B) now exists in code — but it is live only once
migration `20261010000001` is applied to the hosted project (`npm run
provision`). Keep the site dark until that apply has happened and the console
has been exercised once. Three layers — the `X-Robots-Tag: noindex, nofollow`
response header, a disallow-all `/robots.txt`, and the per-page `robots` meta
tag — are all driven by one flag, `SITE_INDEXABLE` (see `src/lib/seo.ts`).
Default/unset = noindex (fail-safe). The owner flips it after her own visual
polish; moderation shipping does not auto-flip it.

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
- [x] **Phase 2C, direct messages (2026-10-05, dark behind the flag).**
      Migration 0020 (`20261011000001_direct_messages.sql`): E2E DM
      schema (ciphertext-only messages, devices + one-time prekeys,
      conversations with the one-request cap, dm_settings,
      franking-verified report evidence), all member functions gated on
      the `dm_e2e_enabled` app_config flag. Crypto layer + IndexedDB
      stores + inbox/thread/requests/settings surfaces + the console's
      DM-evidence transcript. New smoke suite `09-dm-smoke.sql` and the
      `test:dm-crypto` protocol unit test. OFF in production until the
      external crypto audit; `message` added to `report_subject` and
      `notif_type`.
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
      **Policy for accounts created before the §17 screens shipped
      (deliberate, 2026-10-05): they are treated as verified, because
      they are.** Every account ever created through the app passed the
      SAME server-enforced 18+ self-attestation at signup — the check
      has existed in `create_application()` (0008) and `create_member()`
      (0011) since each function's first day, the signup schema has
      rejected under-18 dates since Phase 1, and every `user_private`
      row carries `age_attested_at` (NOT NULL since 0002) plus a
      `member.signup` audit entry as evidence. §17 changed the
      *screens* and the *retention*, not the assurance method, so
      "re-verifying" an existing member would re-collect a birth date
      we deliberately do not retain, to establish a fact the database
      already records. There is no pre-gate cohort to remediate; no
      sign-in interstitial, no backfill, and no new column is needed
      (the migration adds no columns to existing tables — it only
      drops one — and was proven against a populated database:
      pre-existing accounts keep posting, searching and signing in
      untouched). If the age-assurance METHOD is ever upgraded (e.g.
      risk-triggered facial estimation per the decision record), that
      is the moment existing accounts may need a completion flow —
      self-attestation to self-attestation is not that moment.

## Historical next-steps (2026-10-06 session — all three since done)

Kept for the detail they carry; the live list is "Next, in order" at the top.
Provisioning happened 2026-10-06/07, the moderation console and age gate
shipped 2026-10-05, Discover shipped 2026-10-09, and the legal documents were
revised for open registration on 2026-10-07.

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
   flagged; the owner's own stored DOB is removed by it too. **Deploy
   order does not matter and signup keeps working in either skew**:
   new code + un-migrated DB degrades gracefully (under-18 still gets
   the rejection screen; the device block silently no-ops until 0017
   exists), and old code + migrated DB works because the replaced
   functions keep their signatures. Verified against a populated
   database simulating live accounts signed up before the gate.
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
- The on-card Follow pill appears in people rows (search, lists) and,
  since the Discover build, on Discover feed cards for unfollowed
  authors; Following feed cards and thread reply cards still do not
  carry it (you follow everyone in Following; threads are for reading).
- Notifications fetch the latest 50 with no pager; fine for the
  founding cohort.
- Report history shows reason/status only (no deep link to the
  reported content); enough to close the loop until the 2B review
  tooling exists.

## Not started

- [x] ~~Phase 2B remainder: Discover feed + the Discoverability settings
      toggle~~ — DONE 2026-10-09 (see "Where things stand"; migration
      `20261013000001` still needs applying to live)
- [ ] Phase 3: media pipeline and moderation backbone (CSAM scanning; the ban
      actions that feed `banned_identifiers` shipped with the console)
- [ ] Phase 4: DM images (text DMs shipped dark in 2C; images stay
      gated behind the five preconditions in the 2C design §17, chiefly
      NCMEC/PhotoDNA and the attorney-reviewed CSAM posture)
- [ ] Phase 5: the heavier model-driven For You feed with per-post "why you
      are seeing this" (Discover's light positive-signal ranking shipped in
      2B; the vector-similarity upgrade remains Phase 5)
- [ ] Phase 6: launch hardening

Deferred, needs the owner's call: phone verification and age verification
(both under evaluation; `user_private.phone_e164` and the `phone_hash`
ban-list kind are kept for the former). Also deferred: the daily audit log
export to S3 Object Lock.

## Needs the owner

- [ ] Attorney review of the Terms of Service and Privacy Policy — their
      pages ship an interim notice until then (the Guidelines are published;
      counsel can still review them post-publication). **No owner decisions
      remain outstanding: ToS §7.7 is deleted and all six Privacy Policy §8
      retention periods are set (2026-10-07).** What is left is counsel's own
      judgment on arbitration and class waiver, DPA execution with current
      vendors, and whether the retention periods cover the applicable
      statutes of limitations. Once a document is
      signed off, flip its `published` flag in `src/lib/legal.ts`.
- [ ] Trademark search on "Hersciety" (the earlier "United Feminist" name was
      never cleared either)
- [ ] NCMEC CyberTipline registration, required **before** any image upload ships
- [ ] PhotoDNA application, free, roughly a week's lead time
- [ ] Apply migration `20261010000001` to the live project (`npm run provision`)
      — the moderation console's data layer; code is deployed and degrades
      gracefully until the apply happens
- [x] **`RESEND_API_KEY` is in the Vercel production env** (added by Bree
      2026-10-07, presence re-verified 2026-10-08). Per-report email copies
      to safety@unitedfeminist.com send on the current deployment. Note it is
      scoped to `production` only, so preview deploys do not send email —
      deliberate, not a defect.
- [ ] **Decide how the DM crypto gets independently reviewed** — the only
      gate left before messages can be turned on. Options put to the owner
      2026-10-08: (A) scoped review by one reputable crypto engineer —
      **recommended**, because this is a textbook X3DH + Double Ratchet on
      already-audited MIT primitives confined to roughly one module, not a
      bespoke protocol; (B) ship with an honest in-product "not yet
      independently reviewed" disclosure; (C) full firm audit now
      (~$15k-$50k); (D) leave DMs dark until there are members worth
      attacking. Until one is chosen, both flag layers stay off and no member
      can reach a DM surface.
- [x] **Apply migration `20261011000001` to the live project — DONE
      2026-10-08 by Grove**, verified and proven idempotent on production
      (three total runs). `…0011` is now USED; the next migration writer
      must take a fresh timestamp after `20261012000001`.
- [ ] Choose the founding cohort (the first 10-50 people she asks to join)
- [ ] Decide on point-in-time database recovery (~$100/mo) at launch

**Resolved 2026-10-05 (owner decision; was "name the external contact who
receives reports about the Owner account"):** there is NO external contact.
Reports naming the Owner go to the normal admin report panel, visible to her,
and every report emails a traceable copy to safety@unitedfeminist.com. Built
in migration `20261010000001`; the design doc's §7 is corrected. Do not
re-raise.

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
- 🔒 **DMs ARE end-to-end encrypted. Owner decision, 2026-10-07.** This
  reverses the earlier "not E2E in V1" position, which the owner overruled.
  She was right on the facts: end-to-end encryption and moderation are not
  mutually exclusive. Reporting works by client-side report-with-evidence —
  the reporting member's own device attaches the decrypted messages, and
  cryptographic franking proves the sender really sent them and the reporter
  did not fabricate them. The `user_devices` and `one_time_prekeys` tables
  from migration 0007 exist for exactly this and are finally populated by the
  DM build. **First release is text-only and 1:1 only**; group chat is a
  harder protocol and comes later.
  **The one capability given up is proactive server-side CSAM hash-scanning
  of DM images — and that costs nothing today, because no image upload exists
  anywhere in the product.** It only becomes a real trade-off if DM images
  are ever enabled, which is a separate gated decision with its own
  preconditions in `docs/design-phase2c-direct-messages.md`.
  ⚠️ Build caveats: browser E2E is roughly 60-80% of native-app security, so
  the crypto must pass an external audit before it ships; and libsignal is
  AGPLv3, so a permissively-licensed implementation is required.
  Full design: `docs/design-phase2c-direct-messages.md`.
- **Images are served through Cloudflare** so free CSAM scanning sees them,
  and EXIF is stripped at upload so location data never reaches storage.
