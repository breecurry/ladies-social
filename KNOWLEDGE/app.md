# Hersciety — application knowledge

Locked architecture decisions and operating facts for anyone (human or
agent) working on this codebase. PROGRESS.md records state over time;
this file records the things that must stay true.

## Identity rule (the most dangerous thing to get wrong)

`profiles.display_name` is the member's REAL LEGAL NAME. It is
nullable, trigger-locked, and publicly displayed only by explicit
opt-in. **The @handle leads everywhere** — feeds, threads, search,
notifications, moderation, and every DM surface. No search or lookup
function may ever match or return `display_name`; smoke suites 02, 07,
and 09 assert this structurally against `pg_proc`. Many members are
hiding from specific people. Safety beats convenience in every call.

## Direct messages (Phase 2C, reworked) — NOT end-to-end encrypted, text-only, 1:1

🔴 **Owner decision 2026-10-09, FINAL — the rework landed 2026-10-05
(migration `20261021000001_dm_remove_e2e.sql`, which supersedes the E2E
design of `20261011000001`): DMs are NOT end-to-end encrypted. The
platform owner CAN read message content. Members are told so plainly on
every Messages surface, and messages may be disclosed to authorities in
matters involving trafficking or sexual exploitation (including of
minors).** This is deliberate and considered a feature. Do not
re-propose E2E in any form, and do not propose a cryptographic review —
there is no cryptography left to review. The breach trade-off (a DB
breach exposes content; members are often hiding from specific people)
is known and accepted; the mitigation is the access hardening below.

### 🚩 THE FEATURE FLAG: `dm_enabled` — OFF in production

Renamed from `dm_e2e_enabled` (which became a lie). The complete DM
stack ships dark. **Grove-Test and Grove-Security passing are the gate
that turns it on.** Two layers, BOTH must be on:

1. **Environment: `DM_ENABLED=true`** (read in `src/lib/dm/flag.ts`,
   server-side only). Gates every DM page, the Messages nav entries,
   the settings surfaces, and every `/api/dm/*` route (plain 404 while
   off). Set per Vercel environment.
2. **Database: `app_config` row `dm_enabled` = `true`** (checked by
   `dm_feature_enabled()` inside every DM SECURITY DEFINER function).
   Stops hand-crafted Supabase RPC calls while off. The migration
   deliberately does NOT insert this row, and DELETES any leftover
   `dm_e2e_enabled` row — a row under the old key enables nothing
   (suite 09 proves it). To flip:
   `insert into app_config (key, value) values ('dm_enabled', 'true'::jsonb)
    on conflict (key) do update set value = 'true'::jsonb;`

⚠️ Preview and Production share the live Supabase project, so the
database layer is shared: flipping the DB flag enables the *data layer*
everywhere at once, while the env var keeps the Production *UI* dark.
Go-live order: apply migration → Grove-Test + Grove-Security pass →
flip the DB flag → set `DM_ENABLED=true` in Production → redeploy
(Vercel snapshots env vars per deployment).

### What the rework removed (all deleted, none of it dormant)

The Double Ratchet / X3DH layer (`src/lib/dm/crypto.ts`), the IndexedDB
plaintext store and protocol orchestration (`store.ts`, `client.ts`),
device registration and prekeys (`user_devices` and `one_time_prekeys`
TABLES ARE DROPPED; `dm_register_device` / `dm_add_prekeys` /
`dm_my_device` / `dm_prekey_bundle` / `dm_active_device` dropped),
message franking (the server reads content now; proving a sender sent
unreadable content is moot), safety numbers / VerifyDialog /
key-change notices, the `@noble/*` dependencies, and **the one-device-
per-account limit — phone + laptop now simply work.**
`dm_messages` now carries a readable `body` (1–2000 chars) instead of
`header`/`ciphertext`/`frank_hash`. All DM tables held 0 rows at
reshape time; nothing was migrated.

### The disclosure (verbatim, src/components/dm/DmDisclosure.tsx)

Persistent banner on the inbox and every thread, never dismissible,
never a tooltip:

> **Your messages are not private from Hersciety.** Direct messages
> are not end-to-end encrypted. The platform owner and moderators can
> read them, and every one of those reads is logged. Messages may be
> disclosed to authorities in matters involving trafficking or sexual
> exploitation, including of minors.

The "every read is logged" clause is enforced by `mod_dm_evidence()`
(below). If that enforcement ever changes, the copy must change with
it.

### Access hardening — the mitigation that replaces E2E (do not weaken)

- RLS on every DM table; `dm_conversations`, `dm_participant_state`,
  `dm_messages`, `dm_report_evidence` have ZERO policies and zero
  direct privileges — the SECURITY DEFINER functions (pinned
  search_path) are the only path, and each verifies participation.
  `dm_settings` alone is member-writable, own-row.
- Staff reach message content through exactly ONE function:
  `mod_dm_evidence(p_target)` (report evidence only; no
  browse-all-conversations surface exists, deliberately).
- **Every `mod_dm_evidence()` call that returns content writes a
  `dm.content_read` row to the hash-chained audit_log** (reader,
  target, volume). Suite 09 asserts it.
- Encryption at rest: Supabase encrypts all data at rest with AES-256
  (infrastructure-level, always on, not configurable). Honest limits:
  it does not protect against credentialed DB access, and direct SQL
  (dashboard, stolen credentials) bypasses RLS and the audit trail —
  that residual risk is the accepted trade-off of the owner decision.

### Inbox rules (server-enforced in dm_route / dm_send_message — unchanged)

- Main inbox receives only from people the recipient follows.
- Everyone else gets EXACTLY ONE message request: silent (no
  notification row, never counted anywhere), no second message until
  accepted. Declining hides the request but keeps the conversation row
  — the row itself is the one-request cap.
- Settings (`dm_settings`): requests from everyone (default) /
  followed / no_one, a global DM off switch, read receipts (off by
  default).
- **Block, DMs-off, and "no one" raise the IDENTICAL refusal** ("You
  can no longer message this account.") so a blocked person cannot
  distinguish a block. An existing conversation stays readable on BOTH
  sides across a block; only sending stops.
- Notifications (`notif_type` 'message') fire only for accepted
  conversations, carry no content (kept deliberately, shoulder-surfing
  safety), honour the per-type pref and per-conversation mute, one
  unread per sender.
- The inbox rows now carry a server-side preview (`last_body`, 160
  chars, respects the member's delete-for-me horizon).

### Moderation hand-off

A DM report files with `report_subject` 'message' via
`file_dm_report(conversation, reason, details, message_ids bigint[])`:
the reporter selects 1–10 messages and the SERVER snapshots them into
`dm_report_evidence` (body/sender/recipient/sent_at copied from the
real rows — nothing client-supplied is ever shown as the accused's
words; a foreign message id voids the report). Same duplicate/hourly
guards, staff routing, csam auto-escalation, and safety@ outbox copy
(no reporter, no message text) as `file_report()`. The snapshot has no
FK to the message so it survives deletion (preservation obligations).
The console renders it via `DmEvidence` and tells the moderator the
read was audit-logged.

### Known limits of this release (deliberate, not bugs)

- No unsend / delete-for-everyone; no per-message delete (conversation
  delete-for-me only).
- No push notifications (no push infrastructure platform-wide).
- No typing indicators or presence — the server never emits them.
- Text only; no message-content search yet (now possible server-side,
  but a product decision for later).
- DM images remain gated behind design §9 — and server-side CSAM
  hash-scanning of DM images is now possible, which E2E had ruled out.

## Passkeys and the sensitive-action gate (built 2026-10-05)

**The two WebAuthn features are not the same thing.** WebAuthn as a
SECOND FACTOR (`auth.mfa.webauthn.*`) is NOT supported by the auth
backend (enabling it is refused with HTTP 422) — the old
SecurityPanel button that called it failed for every member and is
gone. What IS enabled is **Passkeys** (`registerPasskey()`,
`signInWithPasskey()`, `auth.passkey.*`): passwordless PRIMARY
sign-in, a **beta API that may change without notice** — pin-check
`@supabase/supabase-js` behavior on upgrade. Project config (set,
do not touch): `passkey_enabled=true`, RP ID `hersciety.com`, origins
`https://www.hersciety.com` + `https://hersciety.com`.
🔒 **Changing the RP ID invalidates every existing passkey.** It is
locked.

- The browser client (`src/lib/supabase/browser.ts`) opts into
  `auth.experimental.passkey` — deprecated/ignored in the installed
  SDK (passkeys are on by default since ~2.105) but kept against
  version drift.
- A passkey session is **aal1**. Passkeys do NOT raise the assurance
  level; TOTP remains the only AAL2 factor. Members can still enroll
  an authenticator app — passkeys are an addition, not a replacement.
- **The sensitive-action gate**: migration `20261019000001` built it
  for `owner_reveal_identity`; migration `20261020000001` extends it —
  BY EXPLICIT OWNER DECISION (she uses a passkey, not an authenticator
  app) — to every remaining Owner sensitive operation: `grant_role`,
  `revoke_role`, `owner_unban`, and the Owner RLS reads of `audit_log`
  and `user_private`. Each accepts "aal2 OR fresh passkey". Fresh =
  the JWT `amr` claim (ARRAY OF OBJECTS `{method, timestamp}`, never
  a string match) has a `passkey` entry whose timestamp — the
  authentication time, which SURVIVES token refresh — is within
  **5 minutes**. Enforced server-side in
  `owner_sensitive_auth_method()` / `require_owner_sensitive_auth()`;
  mirrored client-side only as a hint (`src/lib/passkeys.ts`,
  `PASSKEY_FRESHNESS_SECONDS` — change both together). Every audit
  entry for these operations records `auth_method: 'aal2'|'passkey'`.
- **Authentication changed, authorization did not.** Every operation
  above is still Owner-only (`is_owner()` first, claims second), and
  the RLS policies keep their `is_owner()` condition. `grant_privilege`
  / `revoke_privilege` no longer exist (dropped in `20261002000001`).
  `require_owner_aal2()` is DROPPED by `20261020000001` (zero callers
  remained). `owner_sensitive_auth_method()` is EXECUTE-granted to
  `authenticated` ONLY so the two RLS policies can evaluate it as the
  querying role — it reads nothing but the caller's own JWT and leaks
  nothing; the raising variant stays internal.
- Step-up = re-running `signInWithPasskey()`. That **rotates the
  session id**; nothing is keyed to session id except per-row
  attribution in `audit_log`, which is correct as recorded. The
  ceremony can also surface a DIFFERENT account from the picker — the
  shared `stepUpWithPasskey()` helper in `src/lib/passkeys.ts` detects
  the user-id change and refuses; EVERY step-up surface (IdentityPanel,
  PasskeyStepUpPrompt on /owner/roles and /owner/audit) must go through
  that helper, never reimplement the ceremony.
- Error copy lives in `src/lib/passkeys.ts` and never names a vendor;
  a dismissed browser prompt maps to `null` (show nothing). SSO and
  anonymous users cannot register passkeys; a user with verified MFA
  factors must be at aal2 to MANAGE passkeys (`insufficient_aal` is
  mapped to plain copy).
- **Removing the LAST passkey is refused when no verified second
  factor exists** (`SecurityPanel.tsx`, `removalWouldStrand`): without
  it the Owner — who uses passkeys as her ONLY second factor, by
  explicit choice — could make the privileged-action gate permanently
  unreachable. The refusal message suggests adding a replacement
  passkey, never TOTP. Do not add TOTP nagging; do not make TOTP a
  requirement.

## Migrations

Forward-only, idempotent, never edit an applied file. `main`
auto-deploys to production BEFORE migrations are applied, so new code
must degrade gracefully against the un-migrated database (every DM
entry point treats errors as "feature off"). Migration
`20261011000001` is written and tested (fresh, re-run, single
transaction, populated) but NOT applied to the live project — Grove
applies it after review. Migration `20261020000001` (the extended
passkey gate) is likewise written, tested fresh + re-run locally, and
NOT applied — until Grove applies it, role changes, unbans and the
audit_log/user_private reads still demand aal2 and the new passkey
step-up prompts degrade to a refused action (same deploy-skew posture
as `20261019000001`). Migration `20261022000001` (post_mentions block
filter + the suspension-expiry sweep) is written and tested (fresh
apply + two re-runs locally, suites 01-17 green) and NOT applied — no
deployed code depends on it, so there is no skew at all: until Grove
applies it, mention metadata still leaks across blocks and lapsed
suspensions still clear only on sign-in (the pre-fix behaviour,
nothing worse). It installs pg_cron (first migration to do so) and
schedules `hersciety-status-expiry-sweep` (*/5) running
`sweep_expired_statuses()`, which mirrors `refresh_my_status()`
exactly — same status flip, same `mod.status_expired` audit action, no
notification. Any future lapsed-status logic must change BOTH
functions together.

## Tests

`supabase/tests/` 01-17 against local Postgres per tests/README.md.
09-dm-smoke covers the DM invariants; 14-phase2f covers hashtags,
mention policy and caps, reposts, quotes, trending, and tag
suppression; 15 covers the profile Reposts tab walls and the
40-character tag cap; 16 covers the identity-reveal gate (AAL2 or a
fresh passkey); 17 covers the gate's extension to grant_role /
revoke_role / owner_unban and the audit_log / user_private RLS reads —
including that a non-owner with a perfectly fresh passkey is still
refused everywhere; `npm run test:dm-crypto` unit-tests the protocol
under Node. Extend suites; never replace them.

## Hashtags, mentions, reposts (Phase 2F, built 2026-10-10)

Spec: `docs/design-phase2f-hashtags-mentions-reposts.md`. Migration
`20261017000001` (write-then-review; Grove applies). The facts an agent
must not violate:

- **Quote-posts are a first-class feature by OWNER DECISION
  (2026-10-09), overriding the design's recommendation to defer them.**
  Never add friction, warnings, interstitials, confirmation dialogs,
  cooldowns, or discouraging copy to quote-posts, and never frame them
  in code or docs as a dunk vector or as something to restrict later.
  The safety posture lives in the ABUSE CONTROLS, not in withholding
  capability: the block walls, the mention policy, the notification
  cap, and distinct-person trending. "This could be misused" is a
  reason to design controls, not to remove features.
- **"Who can mention you" defaults to Everyone** (owner decision). The
  enum is `mention_policy` on `profiles` (everyone/followed/no_one),
  enforced inside `create_post`: it gates BOTH the mention notification
  AND the `post_mentions` participant row. A block always beats the
  setting. At most 10 mention notifications fire per post; rows past
  the cap still render and link.
- **The client links only resolved mentions.** Every post read shape
  carries `mentions` (stored member id + CURRENT handle, filtered to
  reachable, unblocked accounts) and the renderer
  (`src/components/post/PostBody.tsx` + `src/lib/text.ts`) links
  exactly those tokens. The tokenizer's rules mirror the server parser
  character for character — change one, change both. When `mentions`
  is absent (pre-migration rows) the renderer falls back to
  link-by-shape; that fallback is the documented skew behavior, not
  dead code.
- **Trending counts DISTINCT PEOPLE, never raw posts** (48-hour
  window, recency-weighted, repost counts the reposter once). There is
  deliberately NO minimum-participation floor, no k-anonymity
  suppression, no "not enough data" state: counts are literal (owner
  rule). `get_trending_tags()` is volatile with a read-through refresh
  (advisory-locked) so it stays honest without pg_cron; the cron job
  keeps it warm where the extension exists.
- **`internal.blocked_pair()` exists because `blocked_either()` is
  caller-scoped** (0014 P1-1) and raises when the caller is neither
  party. The repost rules need third-party checks (reposter↔author,
  quoter↔quoted-author). blocked_pair has NO app-role EXECUTE — it is
  reachable only through the SECURITY DEFINER read functions, so the
  block-graph-probing fix stands. Never grant it to app roles.
- **Repost visibility is derived, never stored**: a repost (and the
  embedded card of a quote) renders only while the original is
  visible, its author reachable, and no block exists between the
  viewer and either party NOR between the reposter/quoter and the
  original author. A failed wall yields nothing for a repost and the
  neutral unavailable stub for a quoted card — the quoting member's
  own words always survive, with no author name and no reason leaked.
- **`tags`, `post_tags`, `trending_tags` are function-only tables**
  (RLS on, zero policies, zero direct app-role grants — the
  avatar_media lockdown). `reshares` follows the likes pattern
  (own-row RLS, trigger-maintained counter + notification,
  self-repost refused in the policy). `reply_control` does not
  restrict reposting or quoting.
- **Tag suppression is staff-only and two-tier**: de-trend
  (moderator+, out of trending and suggestions, posts stay) and block
  (admin+, tag page unavailable too), both reversible, both
  `append_audit`-ed. Members report conduct in posts, never tags —
  there is no member-facing report-a-tag flow and none may be added
  without a design pass.
- The canonical tag fold is `lower(normalize(tag, NFC))` server-side
  and `tag.normalize("NFC").toLowerCase()` client-side; `/t/<tag>`
  redirects any non-canonical casing to the one canonical URL.

## Brand mark (integrated 2026-10-05, spec: docs/design-brand-mark-integration.md)

The owner's wordmark logo is live. The authoritative design spec is
`docs/design-brand-mark-integration.md` (measured WCAG numbers; do not
re-derive). The facts an agent must not violate:

- **Light theme wordmark fill is `#6901E2`; dark theme is `#a78bfa`**
  (the existing dark `--accent`). Raw `#6901E2` measures 2.38:1 on the
  dark background — never render it on dark surfaces.
- **Logo fill ≠ UI token.** `--accent` stays `#6d28d9` (light). Do not
  reconcile them; the whole contrast table depends on the token.
- Assets: `public/wordmark-light.png` / `public/wordmark-dark.png`
  (1024×265 — the spec manifest said 1024×374 by assuming the source
  canvas ratio 2.74:1 was the glyph ratio; the true tight-trimmed glyph
  ratio is 3.86:1, and tight trim per the spec's own "no baked padding"
  rule won); `src/app/icon.png` (512), `apple-icon.png` (180, no
  alpha), `favicon.ico` (48/32/16; the 16px frame has a deliberately
  thickened tail), `opengraph-image.png` (1200×630) + its `.alt.txt`.
  Icons are the white speech bubble (the dot over the "i") on a filled
  `#6901E2` tile, no pre-baked corner rounding.
- `src/components/BrandWordmark.tsx` renders the mark; the light/dark
  swap is the `.brand-wordmark` display rules in `globals.css`, which
  mirror the token theme selectors so manual `[data-theme]` overrides
  are honoured. It is an `<img>`, not a CSS mask, on purpose
  (forced-colors safety). `alt="Hersciety"` everywhere; on the landing
  hero the image IS the `h1` text.
- Icon/OG files are wired by Next.js **file convention** — never add an
  `icons` or `openGraph.images` block to `layout.tsx` metadata.
- The old root-level extensionless `hersciety` PNG was deleted when
  these assets replaced it. Source master, if ever needed again, is in
  git history at commit `c5554c2`.
- Vector (SVG) source still unknown — if the owner produces one, the
  two wordmark PNGs collapse to a single `currentColor` SVG (spec §8).

## Avatars (Phase 2E) — the first image feature (built 2026-10-10)

Spec: `docs/design-phase2e-profile-pictures.md`. Migration
`20261015000001_avatars.sql` (write-then-review; Grove applies). The
facts an agent must not violate:

- **Scanning is Cloudflare's zone-level CSAM Scanning Tool ONLY** (owner
  decision 2026-10-09, superseding the spec's section 13 recommendation).
  It runs on Cloudflare's cache, out of band. There is deliberately NO
  scanning code, NO PhotoDNA, NO Hive, and none may be added without a
  new owner decision. The in-band half of the duty IS built and must
  stay: **removal preserves, never hard-deletes** (report holds,
  `legal_hold` on csam-reason reports, 2-year retention of
  moderation-removed objects).
- **The avatar key resolver is `avatar_keys()` and it gates on
  `blocked_either(auth.uid(), owner)` — BIDIRECTIONAL, the posts
  semantics.** Never resolve an avatar through a raw `profiles` read:
  `profiles_read` filters only one direction (`internal.blocked_by`).
  A UI placeholder fallback is not the control; the key must never
  reach a blocked client. Any new surface that shows an avatar goes
  through `avatar_keys()` (client: `useAvatarMedia`; server: the RPC).
- **Keys are opaque**: 48-hex CSPRNG, objects at
  `av/{key}/{96|192|400}.webp`, staging at `st/{48hex}`. A new upload
  mints a NEW key. No filename column exists anywhere and none may be
  added; the uploaded filename is never read, stored, or returned.
- **Metadata dies server-side** in `src/lib/media/ingest.ts`:
  auto-orient first, then full re-encode — no `withMetadata` anywhere.
  `npm run test:avatar-pipeline` is the gate proving EXIF/GPS/XMP/ICC
  do not survive; keep it green.
- **Members cannot write `profiles.avatar_media_key` directly** (the
  0009 column grant is revoked). The only writers are
  `avatar_commit_record`, `remove_avatar`, `mod_remove_avatar`,
  `mod_reinstate_avatar`.
- **Staff surfaces render the letter placeholder only** — never pass
  `userId`/`media` to `Avatar` in `/mod` or `/owner` surfaces. The one
  exception is the case view's reported-photo panel
  (`mod_avatar_evidence`): blurred by default, click-to-reveal, and
  csam-reported images are excluded at the database.
- **Serving** is public-with-unguessable-key via the Cloudflare media
  zone (`NEXT_PUBLIC_MEDIA_URL`), matching post media. The signed-token
  Worker variant was considered and deliberately not built. Env:
  `R2_ENDPOINT`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`,
  `R2_STAGING_BUCKET`, `R2_MEDIA_BUCKET`, `NEXT_PUBLIC_MEDIA_URL` —
  all absent means every surface degrades to the letter placeholder
  and upload fails cleanly.
- Suite `supabase/tests/12-avatars.sql` asserts all of the above
  structurally and behaviourally. Extend it; never weaken the
  both-directions block assertions.

## Content-Security-Policy (CSP) — 2026-10-05

**Implementation**: Nonce-based, per-request, in `src/proxy.ts`
(Next.js 16 proxy convention — replaces the deprecated `middleware.ts`).
The nonce is forwarded to server components via the `x-nonce` request
header; `src/app/layout.tsx` reads it with `headers()` and applies it
to the theme-init inline `<script>` tag.

**Policy (full)**:
```
default-src 'self'; script-src 'self' 'nonce-{NONCE}' https://challenges.cloudflare.com; style-src 'self' 'unsafe-inline'; img-src 'self' https://media.hersciety.com data: blob:; font-src 'self'; connect-src 'self' https://hiphjzhlwiztqgezzipf.supabase.co https://challenges.cloudflare.com https://7f79ff00b7bec4dea299ac9e824cface.r2.cloudflarestorage.com; frame-src https://challenges.cloudflare.com; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'
```

**Origin allowlist and why each is required**:
- `'self'` — app's own origin for all resource types
- `'nonce-{NONCE}'` in script-src — theme-init inline script in layout.tsx
- `https://challenges.cloudflare.com` in script-src, frame-src, connect-src
  — Cloudflare Turnstile (login/signup). Script loaded dynamically via
  `document.createElement('script')` — cannot receive a nonce.
  Renders its challenge in a cross-origin iframe. Makes validation XHR calls.
- `https://media.hersciety.com` in img-src — Cloudflare R2 avatar images
- `data:` in img-src — TOTP QR code returned as data:image/svg+xml by
  `supabase.auth.mfa.enroll()` (confirmed in @supabase/auth-js source)
- `blob:` in img-src — AvatarEditor crop preview (URL.createObjectURL)
- `https://hiphjzhlwiztqgezzipf.supabase.co` in connect-src — all Supabase
  REST, auth and RPC calls; no WebSocket/realtime in use
- `https://7f79ff00b7bec4dea299ac9e824cface.r2.cloudflarestorage.com`
  in connect-src — avatar upload: browser PUTs directly to R2 staging
  bucket via presigned URL returned from /api/avatar/ticket

**Tradeoffs**:
- `'unsafe-inline'` in style-src is required because 6 components use
  `style={{ ... }}` JSX for dynamically computed values: blurhash-derived
  background colours (Avatar, AppShell, AvatarEvidence) and AvatarEditor
  layout/overlay dimensions. These cannot be moved to static Tailwind classes
  because the values are computed at runtime from data. Nonces do not apply
  to `style=` attributes (only to `<style>` elements), so `'unsafe-inline'`
  is the only correct allowance. This weakens style injection protection
  but does not affect script injection prevention.

**Files changed**:
- `src/proxy.ts` — new file (Next.js 16 proxy; replaces `src/middleware.ts`)
- `src/lib/supabase/middleware.ts` — updated to accept `requestHeaders`
  parameter and forward it through both `NextResponse.next` calls
- `src/app/layout.tsx` — made async, reads nonce from `x-nonce` header,
  applies `nonce=` attribute to theme-init script
- `next.config.ts` — comment updated (CSP is no longer "TODO")

**Note**: `middleware.ts` is the deprecated Next.js 15 convention. Next.js 16
uses `proxy.ts` with `export function proxy`. The old convention's
`response.headers.set()` calls were silently ignored on response headers.
Always use `proxy.ts` with `export function proxy` going forward.

## Responsive pass, account menu, 40-char tag cap, Reposts tab (2026-10-05)

Migration `20261018000001` (write-then-review; **Grove applies — NOT
applied at build time**). The facts an agent must not violate:

- **The account menu is ONE shared component**
  (`src/components/shell/AccountMenu.tsx`), mounted twice: the desktop
  rail (variant `rail`, popup opens upward) and the member's OWN
  profile header below `lg` (variant `profile`, popup opens downward
  and inward — Owner-approved placement, Threads convention). It reads
  `handle`/`isOwner`/`mod` from the viewer context (`Providers.tsx`),
  so adding or moving a mount point is a one-line change. Never
  duplicate the menu markup; never remove the mobile mount — below
  1024px it is the ONLY path to Log out, Settings, /mod and /owner.
- **The hashtag cap is 40 characters (OWNER DECISION 2026-10,
  replacing the design's 64).** A `#token` over 40 is not a hashtag:
  not indexed, not linked, rendered as muted `text-text-tertiary` —
  the SAME inert treatment as a well-shaped mention the server did not
  resolve (one visual language for "recognised, intentionally not
  live"). No truncation, no warning, no friction; the post always
  succeeds. Server (`create_post`) and client (`src/lib/text.ts`
  `TAG_MAX`, the `inert` segment kind) change together, always.
- **The profile Reposts tab** filters through the SAME
  `profile_posts` function via a new `p_reposts` flag (default false)
  so every visibility wall is one code path. The client sends
  `p_reposts` ONLY when true: PostgREST matches named arguments, so an
  unknown argument would break the Posts/Replies tabs on a database
  that predates the migration.
- `viewport-fit=cover` is set in `src/app/layout.tsx`; the shell's
  `env(safe-area-inset-*)` maths (bottom nav, top bar, DM header,
  toasts, dialogs) is live, not decorative. Keep top-bar height and
  the DM header offset in sync (`calc(48px + env(safe-area-inset-top))`).
- `Card` (`src/components/ui.tsx`) pads `p-4 sm:p-6`; padding
  overrides via `className` are UNRELIABLE (stylesheet order beats
  class order) — flush cards must use `padded={false}`.

## Multi-part threads ("Add to thread", built 2026-10-05)

Spec: `docs/design-multi-part-threads.md` (approved; implemented as
written). Migration `20261024000001`. Operating facts that must stay
true:

- **A chain is a shape, not a record.** The maximal run of consecutive
  same-author posts down a reply spine starting at a TOP-LEVEL post;
  the continuation of a part is its earliest same-author direct reply,
  ordered `(created_at, id)` — the id matters because an atomically
  published chain shares one transaction timestamp. No new posts
  column. `internal.chain_head_of` / `internal.chain_info` are the one
  source of chain truth; every surface (get_thread's `spine_seq`, the
  feeds' `chain_index`/`chain_count`, the Replies-tab filter) derives
  from them. If the definition ever changes, change it there only.
- **The 25-part cap is derived, not taste**: create_post refuses a
  reply at depth >= 30; 25 parts put the last part at depth 24 and
  leave five levels for readers. Enforced in the composer AND in
  create_thread. Do not raise it without raising the depth cap story.
- **create_thread is the only multi-part write path.** It loops
  create_post inside one transaction so every per-part check (active
  author, 500 cap, empty-body, mentions, hashtags, reply control,
  depth) is reused verbatim — never duplicate those checks. Its
  idempotency key is `(user_id, uuid)` in `internal.thread_idempotency`
  (no app-role access, RLS on, zero policies), honoured 24h, swept
  opportunistically inside the function (no cron dependency). The key
  row lives and dies with the posting transaction.
- **Replies are single-part on purpose**: a chain starts at a top-level
  post by definition, so the reply composer never offers "Add to
  thread". A quote chain is fine (the quote rides part 1 only).
- **Deploy-before-migrate posture**: the composer feature-probes the
  `chain_head()` RPC once per page load (`probeMultiPart` in
  Composer.tsx; negative results retry on next mount) and offers
  multi-part only when it exists. The thread page treats a chain_head
  error as "no resolver" and falls back to the old behavior. All new
  row fields (`spine_seq`, `chain_index`, `chain_count`) are optional
  in `database.types.ts`.
- **Numbering is live, never stored.** "Part k of N" counts only
  readable parts, so deleting part 3 of 5 renumbers to 1..4 and the
  thread view shows "The author removed this part" at the gap. A
  wholly unreachable chain (suspension/ban/mute/block/all-deleted)
  renders ONE "This thread is unavailable" — never a stack of blank
  part cards, never the shape of a banned member's thread.
- **The splitter and the counter share `src/lib/text.ts`**
  (`codePointLength`, `splitForThread`, `PART_LIMIT`, `PART_CAP`).
  Both count code points, matching Postgres char_length. The splitter
  never lands inside anything `tokenizeBody` draws as a token (plus
  URLs); whitespace-free runs longer than 500 are the only hard-break
  case and the UI names it. Keep the tokenizer and splitter in the
  same file so they cannot drift.
