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

## Direct messages (Phase 2C) — E2E, text-only, 1:1

Owner decision 2026-10-07, built 2026-10-05 (migration
`20261011000001_direct_messages.sql`): DMs are **end-to-end encrypted
from the first release**. The server stores ciphertext only and can
never read a message body. Text-only and 1:1 only; group E2E is a
materially harder protocol and comes later, deliberately.

### 🚩 THE FEATURE FLAG: `dm_e2e_enabled` — OFF in production

The complete DM stack ships dark. **An external cryptographic audit is
the gate that turns it on** (browser E2E is roughly 60-80% as strong as
native; this is known and accepted, but unaudited ratchet code must not
carry real members' conversations). The flag has two layers, and BOTH
must be on for the feature to exist:

1. **Environment: `DM_E2E_ENABLED=true`** (read in
   `src/lib/dm/flag.ts`, server-side only). Gates every DM page, the
   Messages nav entries, the settings surfaces, and every `/api/dm/*`
   route (plain 404 while off). Set it per Vercel environment: ON in
   Preview for exercising the feature, ABSENT in Production.
2. **Database: `app_config` row `dm_e2e_enabled` = `true`** (checked by
   `dm_feature_enabled()` inside every DM SECURITY DEFINER function).
   This stops hand-crafted Supabase RPC calls from reaching DMs while
   the feature is off. The migration deliberately does NOT insert this
   row. To flip:
   `insert into app_config (key, value) values ('dm_e2e_enabled', 'true'::jsonb)
    on conflict (key) do update set value = 'true'::jsonb;`

⚠️ Preview and Production share the live Supabase project, so the
database layer is shared: flipping the DB flag enables the *data layer*
everywhere at once, while the env var keeps the Production *UI* dark.
That window (DB on, prod env off) is for the audit/preview period only.
Go-live order: apply migration → flip the DB flag → set
`DM_E2E_ENABLED=true` in Production → redeploy.

When the flag is off there is NO fallback messaging path. Off means the
surfaces do not exist — never readable-by-the-server DMs.

### Crypto (src/lib/dm/crypto.ts)

- **Libraries (permissive, audited, pinned in package.json):**
  `@noble/curves` 2.4.0 (MIT), `@noble/ciphers` 2.4.0 (MIT),
  `@noble/hashes` 2.4.0 (MIT). **libsignal is AGPLv3 and must never be
  used, vendored, or ported.**
- X3DH-style agreement (x25519 identity + signed prekey + optional
  one-time prekey, ed25519 signature on the signed prekey) feeding a
  Double Ratchet (HKDF root chain, HMAC message chains, XChaCha20-
  Poly1305 AEAD, header-bound AAD, skipped-key handling capped at 200).
- Identity key on the wire = 64 bytes: x25519 DH public ‖ ed25519
  signing public (two keypairs, no Edwards↔Montgomery conversion).
- **Franking** (HMAC-key construction, CRYPTO 2017; never raw AES-GCM —
  "invisible salamanders"):
  `frank = HMAC-SHA256(K_frank, "hersciety-dm-frank-v1"\n sender_uuid \n recipient_uuid \n plaintext)`;
  `K_frank` rides inside the ciphertext; the server stores
  `sha256(frank)` per message. A report reveals plaintext + `K_frank`
  for exactly the chosen messages; `file_dm_report()` recomputes with
  pgcrypto and marks each message verified or not. The reporter cannot
  fabricate; the sender cannot deny; the platform reads ONLY reported
  messages.
- **One active device per account** in this release. Registering a new
  device (new browser, cleared storage) revokes the old one; old
  messages become unreadable on the new device — the honest E2E trade,
  said in the UI, never papered over with a server-readable backup.
  Device keys, ratchet sessions, and decrypted history live in
  IndexedDB (`hersciety-dm` database).

### Inbox rules (server-enforced in dm_send_message / dm_prekey_bundle)

- Main inbox receives only from people the recipient follows.
- Everyone else gets EXACTLY ONE message request: silent (no push, no
  badge, no notification row, never counted anywhere), preview-only, no
  second message until accepted. Declining hides the request but keeps
  the conversation row — the row itself is the one-request cap, so no
  path yields a second request. Request-state conversations are never
  deleted for this reason.
- Settings (`dm_settings`): who can send a request = everyone (default)
  / followed / no_one, a global DM off switch, read receipts (off by
  default). "Who can message you" is structurally follow-gated and is
  not a setting.
- **Block, DMs-off, and "no one" raise the IDENTICAL refusal** ("You
  can no longer message this account.") so a blocked person cannot
  distinguish a block. The prekey-bundle endpoint enforces the same
  rules so it cannot be used as an oracle. An existing conversation
  stays readable on BOTH sides across a block (the history may be the
  evidence); only sending stops.
- Notifications (`notif_type` 'message') fire only for accepted
  conversations, carry no content and no preview, honour the per-type
  pref and the per-conversation mute, and cap at one unread per sender.

### Moderation hand-off

A DM report files with `report_subject` 'message' via
`file_dm_report()`: same duplicate/hourly guards, same staff routing
(accused staff → admin_only; reports naming the Owner go to the normal
admin panel per her decision), same safety@unitedfeminist.com outbox
copy (case reference + reason + accused @handle; never the reporter,
never message text). Evidence lives in `dm_report_evidence` (the ONLY
plaintext in the database, reporter-attached, franking-verified, no FK
to the message so it survives deletion — preservation obligations).
The console renders it via `mod_dm_evidence()` with per-message
verified markers and the honest limit: the evidence is only what the
reporter shared; the platform cannot pull more context.

### Known limits of this release (deliberate, not bugs)

- Single device; no multi-device fan-out, no encrypted backup, no
  history on a new device.
- No unsend / delete-for-everyone; no per-message delete (conversation
  delete-for-me only).
- No push notifications (no push infrastructure exists platform-wide).
- No typing indicators or presence — the server never emits them at
  all, which satisfies "off by default" structurally.
- Text only. DM images are gated behind the five preconditions in
  docs/design-phase2c-direct-messages.md §17.
- Browser E2E ≈ 60-80% of native strength (hostile-server JS is the
  residual risk); mitigations are CSP (still pending platform-wide),
  and the external audit gate.

## Migrations

Forward-only, idempotent, never edit an applied file. `main`
auto-deploys to production BEFORE migrations are applied, so new code
must degrade gracefully against the un-migrated database (every DM
entry point treats errors as "feature off"). Migration
`20261011000001` is written and tested (fresh, re-run, single
transaction, populated) but NOT applied to the live project — Grove
applies it after review.

## Tests

`supabase/tests/` 01-15 against local Postgres per tests/README.md.
09-dm-smoke covers the DM invariants; 14-phase2f covers hashtags,
mention policy and caps, reposts, quotes, trending, and tag
suppression; 15 covers the profile Reposts tab walls and the
40-character tag cap; `npm run test:dm-crypto` unit-tests the protocol
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
