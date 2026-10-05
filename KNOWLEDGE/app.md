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

`supabase/tests/` 01-09 against local Postgres per tests/README.md.
09-dm-smoke covers the DM invariants; `npm run test:dm-crypto` unit-
tests the protocol under Node. Extend suites; never replace them.

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
