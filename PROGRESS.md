# PROGRESS: Hersciety

Updated: 2026-10-05 (some older section headings below carry day stamps a
few days ahead of the real calendar — their content and order are correct)

## 🟢 LIVE STATUS — https://www.hersciety.com is UP (verified 2026-10-07)

Deployed and passing every production check: pages return 200; `/home`,
`/search`, `/notifications`, `/settings`, `/u/*` all 307 to `/login` when
logged out; the client bundle points at the correct Supabase project and
contains no service-role key or pepper; all six security headers present;
`robots.txt` disallows everything (still intentionally **noindex** — see
Deployment below); row-level security blocks anonymous reads; owner
`@getbakedwithbre` and system `@hersciety` accounts intact; zero runtime
errors.

Migration `20261014000001` (admin dashboard) **is applied to the live
project** (Grove, 2026-10-09; three idempotent runs, verified in the live
schema): `/owner/members` and `/owner/insights` are live.

All migrations through `20261019000001` are applied to the live project, and
the avatar storage layer is configured and live.
**⚠️ Migration `20261020000001` (the extended passkey gate — see its
section below) is written and tested but NOT YET APPLIED to the live
project; the deployed code degrades gracefully until it is applied.**
Next, in order: **apply migration `20261020000001`** → **Grove-Test**
(adversarial) → **Grove-Security** (mandatory before any public launch) →
the Owner's passkey walkthrough end to end → counsel sign-off, then flip
`published: true` in `src/lib/legal.ts` (one line per document).

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

**Small-fix batch (2026-10, migration `20261025000001` — written, tested,
NOT yet applied to the live project; the deployed code degrades gracefully
until Grove applies it).** Three independent fixes:

1. **Ban-through-a-block** (`src/app/api/mod/ban/route.ts`): the POST
   handler's typed-handle gate read `profiles` through the CALLER'S
   RLS-scoped client; since `20261023000001`, `profiles_read` honours
   `internal.blocked_by`, so a target who had blocked the acting admin
   vanished from that read and the route 404'd — the ban could not be
   completed by that admin. The route now (a) checks the caller is
   admin/owner FIRST, via her own `role_assignments` (the exact set
   `mod_ban()` enforces — `mod_assert_actionable(target, 2)`), then (b)
   does the handle lookup with the service client, re-imposing only the
   nobody-sees-`deleted` branch of `profiles_read`. Order matters: the
   privileged read before the authority check would have been a
   handle↔user_id oracle for accounts RLS deliberately hides. Suite 21
   pins all four database facts this rests on.
2. **Follow counts now agree with the follow lists**
   (`src/app/(member)/u/[handle]/page.tsx` + migration
   `20261025000001`): the profile header counted raw `follows` rows, so
   suspended/banned counterparties and block relationships still counted
   while the lists (`list_followers()`/`list_following()`) filtered them
   — "12 followers" above a list of 10, and a side channel revealing
   what the lists hide. New `profile_follow_counts(p_user)` reuses the
   lists' predicate VERBATIM; the page calls it and falls back to the
   old raw counts only when the RPC is missing (deploy-before-migrate
   posture). Suite 21 asserts counts == lists against the lists
   themselves, so predicate drift fails the build.
3. **Stale comment** in `supabase/tests/19-dm-adversarial.sql` §5
   corrected (duplicate evidence ids are de-duplicated since
   `20261023000001`; the 10-id boundary test's comment described the
   old gap). Comment only; no assertion changed.

Gates at push time: `tsc` clean, `eslint` clean, `next build` clean; all
21 local suites pass (the new migration applied three times in a row —
idempotent — with exactly one `profile_follow_counts` signature in
`pg_proc`). ⚠️ Stale docs noticed, deliberately left alone: suite 20's
header and `supabase/tests/README.md` still say the profile-row leak is
EXPECTED TO FAIL, but `20261023000001` fixed it and suite 20 now passes
clean end to end — a docs-only follow-up should update both.

**Hashtags, @-mentions, reposts and quote-posts are built (Phase 2F,
2026-10-10).** To `docs/design-phase2f-hashtags-mentions-reposts.md`, with
two owner decisions honoured exactly: **both plain reposts AND quote-posts
shipped together, as ordinary first-class features with no friction,
warnings, or discouraging copy** (her explicit override of the design's
defer-quotes recommendation — do not re-litigate), and **"Who can mention
you" defaults to Everyone**.

- **Hashtags**: parsed server-side in `create_post` (word boundary, Unicode
  letters/numbers/underscore with at least one letter, folded canonical
  form, 64-char cap, at most 30 distinct tags indexed per post), rendered
  as accent links with the author's casing preserved, tag pages at
  `/t/<canonical-tag>` (newest first, block- and mute-aware, warm empty
  state), tag search as a second axis behind a leading `#` in the one
  search box (people search stays @handle-only, untouched), and trending
  ranked by **distinct people over a 48-hour window, recency-weighted —
  never raw post volume**, shown with literal counts (1 is 1, zero is an
  invitation, no suppression thresholds of any kind). Trending lives on the
  pre-query Search screen (top five) and the `/t` page (top twenty),
  snapshot-backed with a read-through refresh so it works with or without
  pg_cron. Staff suppress a tag in two audited, reversible tiers from the
  console's new Topics room (`/mod/tags`): de-trend (moderator+) pulls it
  from trending and suggestions, block (admin+) also makes the tag page
  unavailable; neither touches any post or author. Members report conduct,
  never tags. The console shows the calm brigade signal (share of a tag's
  48-hour participants on accounts under a week old) as information for a
  human, never an automatic action.
- **Mentions**: the client now links ONLY the mentions the server resolved
  at post time (returned per post as id + current handle), so fake handles
  are plain text, links never re-point to a later claimant of a handle,
  and an unreachable account's mention falls back to plain text with no
  status leak. The composer gained mention autocomplete (combobox pattern,
  avatar + @handle only, follows ranked first, blocked accounts never
  appear) and hashtag autocomplete on the same surface. Abuse controls:
  the existing bidirectional block wall and mute suppression are kept and
  asserted in suite 14; a new **"Who can mention you"** setting (Settings →
  Privacy: Everyone default / People you follow / No one) gates both the
  notification and mentioned-participant status at post time; and at most
  **10 mention notifications fire per post** — past the cap mentions still
  render and link, only the pings stop.
- **Reposts and quote-posts**: the Repeat control sits between Reply and
  Like with its count (hidden at zero); plain repost is one optimistic tap
  with an undo toast (no confirmation — the like/follow treatment), undo is
  the same control again. Reposts interleave in the Following feed (one
  card however many followed people reposted it, "@handle reposted" /
  "and N others" attribution, original author primary) and in the profile
  Posts tab by repost time. A repost renders only while the original is
  visible, its author reachable, and **no block exists between viewer and
  either party nor between reposter and original author** — no stub, no
  leak. Quote opens the composer with the original as a nested card;
  a quote-post is a normal post carrying the original in a bordered card
  linking to the thread, degrading to a neutral "This post is unavailable."
  stub (the quoting member's own words always survive). The author gets
  `reshare` / `quote` notifications, on by default, pref-gated (new rows in
  Settings → Notifications), never to self, never across a block, not when
  muted. Discover ranking gains the two repost signals as positive lifts
  mirroring likes (reach-damped aggregate count + reposted-author
  affinity); reposts are never a negative signal anywhere. `reply_control`
  does not restrict reposting (amplification is not participation);
  self-repost is refused in the database; self-quote is allowed.
- Data layer: migration `20261017000001_hashtags_mentions_reposts.sql` —
  `tags` / `post_tags` / `trending_tags` (RLS on, function-only, no direct
  app-role access), `reshares` (RLS own-row, likes pattern),
  `posts.quoted_post_id` + `posts.reshare_count`,
  `profiles.mention_policy`, notif_type values `reshare` and `quote`, and
  rebuilt read functions returning repost state, attribution, resolved
  mentions, and the quoted card. `internal.blocked_pair()` was added for
  the third-party block checks the repost walls need (the caller-scoped
  `blocked_either` from 0014 rightly refuses them); it has no app-role
  EXECUTE and is reachable only through the DEFINER read functions, so the
  0014 block-graph-probing fix stands. Suite `14-phase2f.sql` covers all
  of it; all 14 suites pass on a fresh database. ⚠️ **NOT yet applied to
  the live project.** The deployed UI degrades gracefully until the apply:
  mentions link by shape, tag/trending surfaces render their calm empty
  or not-found states, and the repost action shows a calm error toast.

**Profile pictures are built (Phase 2E, 2026-10-10).** The first image
feature in the product, to `docs/design-phase2e-profile-pictures.md`, with
the safety model as the spine:

- **Upload → crop → store → serve**: the own-profile avatar gains a camera
  edit affordance and the Edit profile dialog a photo row; both open the
  crop step (square frame, circular-mask preview, drag + zoom slider +
  arrow-key nudging; rejections always state their reason). The client
  exports a square and uploads via ticket → presigned PUT to the R2
  **staging** bucket (never served) → commit, where the server is the
  authority: real bytes sniffed (static JPEG/PNG/WebP only, 8 MB cap,
  256px minimum, ~50 MP decompression-bomb ceiling), decoded,
  **auto-oriented first, then re-encoded so EXIF/GPS/XMP/ICC and the EXIF
  thumbnail are gone** before anything servable exists (proven by
  `npm run test:avatar-pipeline`), three square WebP variants (96/192/400)
  plus a blurhash written to the **media** bucket under an opaque 48-hex
  CSPRNG key — no handle, user id, counter, timestamp, or filename
  anywhere; the original filename is never read, stored, or returned, and
  a new upload always mints a new key. Serving is public-with-unguessable-
  key through the Cloudflare media zone (`NEXT_PUBLIC_MEDIA_URL`,
  immutable cache), matching post media by design.
- **Scanning (owner decision 2026-10-09, supersedes the spec's §13
  recommendation): Cloudflare's zone-level CSAM Scanning Tool only**,
  already enabled on the zone; it operates on Cloudflare's cache, out of
  band. There is deliberately **zero scanning code and no scanning vendor**
  in the app. What the law needs when out-of-band detection fires is built:
  **removal preserves, never hard-deletes** — a report freezes the accused's
  current avatar key as evidence at filing time (`reports.
  reported_avatar_key`), any report in open/in_review/escalated/actioned
  blocks purging, a csam-reason report pins a `legal_hold` (the ≥1-year
  anchor, Owner path only), and a moderation removal is retained for the
  2-year moderation-records window. Only a clean, unreported,
  self-removed/superseded object is ever deleted from storage, and the
  database makes that call, never the route.
- **The resolver is the control, not the UI**: every surface resolves
  photos through `avatar_keys()` — SECURITY DEFINER, authenticated-only —
  which gates on **`blocked_either(auth.uid(), owner)`, the bidirectional
  POSTS semantics** (a block in either direction means the real key reaches
  neither party; `profiles_read`'s one-way `blocked_by` is deliberately not
  relied on), and on standing: suspended/banned/deactivated/deleted owners,
  removed/purged objects, and non-member viewers all resolve to nothing.
  Mute changes nothing (identity is not a feed). Logged-out visitors never
  see an avatar (auth gate + anon holds no EXECUTE). The 0009 column grant
  that let members write `profiles.avatar_media_key` directly is revoked —
  the pipeline functions are the only writers.
- **Surfaces**: the letter avatar stays the deliberate default everywhere
  (zero new tokens). Photos appear on post cards, replies, profile headers,
  people rows, notifications, the DM surfaces and the member's own nav
  circles, resolved through one batched client cache. **Staff surfaces stay
  letter-placeholder-only**: the moderation console and Owner directory
  render no member photo, except the one deliberate place — the case view's
  "Reported profile photo" panel, blurred by default (average-color block,
  no clear pixels) behind a click-to-reveal with the report category named,
  with Remove (preserving, member notified with the rule, reversible via
  Reinstate) on the ladder's `remove_content` rung. **A csam-reported image
  never renders in the console at all** — excluded at the database.
- Suite `12-avatars.sql` proves the mutual-hard block in both directions,
  the logged-out/suspended/banned nothing-answers, the evidence freeze and
  purge refusals, preserve-and-reinstate, the ticket rate limit, the
  locked tables (RLS, zero policies, zero direct grants), the absence of
  any filename column, and the structural absence of `display_name` from
  every avatar function. `tests/13` and all earlier suites still pass.

✅ **Migration `20261015000001_avatars.sql` was APPLIED to the live project
by Grove on 2026-10-09** — HTTP 201, re-run twice more clean to prove
idempotency against production. Verified in the live schema (not the
migration file): `avatar_media` and `avatar_upload_tickets` both exist with
RLS enabled and zero policies (functions-only lockdown); `avatar_keys()`
uses the bidirectional `blocked_either` and does NOT use `blocked_by`, so a
block hides the photo in both directions; zero avatar functions reference
`display_name`; the database still has 0 tables without RLS and 0 unpinned
SECURITY DEFINER functions. The migration also revoked the migration-0009
column grant that had let members write `profiles.avatar_media_key` directly
through PostgREST, bypassing the ingest pipeline and the evidence trail —
verified: `authenticated` now holds no UPDATE privilege on that column.

✅ **THE AVATAR STORAGE LAYER IS LIVE (Grove, 2026-10-10).** Profile pictures
work end to end in production. What was provisioned:

- **R2 enabled on the Cloudflare account by the Owner.** Before that, every
  R2 API call returned `10042 "Please enable R2 through the Cloudflare
  Dashboard"` — a product activation, not a permissions problem.
- **Two buckets created** (location hint `enam`): `hersciety-avatars-staging`
  (raw uploads, never publicly served) and `hersciety-media` (re-encoded,
  metadata-free output, publicly served).
- **`media.hersciety.com` mapped to `hersciety-media`** as an R2 custom
  domain: SSL active, ownership active. It returns 404 at the root, which is
  correct — there are no objects yet.
- **A bucket-scoped R2 API token** holding only Bucket Item Read + Write on
  those two buckets. It cannot reach any other bucket on the account. The S3
  credential pair is the token id plus the SHA-256 of the token value.
- **All six env vars set on Production**, `R2_SECRET_ACCESS_KEY` as an
  encrypted variable. No other variable was touched — in particular none of
  the Supabase decoy variables that caused the 2026-10-07 outage.
- **Deployment `dpl_EUr1HbFArL7Gb7mJ6kLp9FYbjSjo` is READY** (Vercel
  snapshots env vars per deployment, so a redeploy was required).
- **Verified after deploy:** `/` `/login` `/signup` 200; `/home` `/settings`
  `/owner` 307 to /login; `media.hersciety.com` serving with a valid
  certificate; and a leak check across ten client bundles plus the page HTML
  searching for the secret's *actual value* found **no occurrence** — the
  credential is server-side only.
- The R2 path was smoke-tested with a real signed request before wiring:
  PUT 200, DELETE 204, GET-after-delete 404, no test object left behind.

🔁 **If the R2 credential is ever lost, do not hunt for it.** Cloudflare shows
a token value once. Delete the token, mint a new bucket-scoped one, update
`R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY`, redeploy. The whole rotation
takes minutes and nothing is damaged.

**The Owner's admin dashboard is built (Phase 2D, 2026-10-10).** The
Owner-tools cluster is now a hub at `/owner` with two new rooms alongside
Roles, Audit log, and Age gate:

- **`/owner/members` — the member directory**, search-first per the spec: it
  opens on the total member count, an exact-and-prefix `@handle` search,
  status/staff/joined/activity filters (all URL state), and the most recent
  arrivals under a recent-window cap — never an endless scroll of everyone.
  Rows are `@handle`, join date, status chip, role chip, and a **coarse
  activity bucket whose label is derived server-side from
  `user_private.last_login_at`; no raw activity timestamp ever reaches the
  browser on a browsable surface** (`profiles` has no `last_active_at` and
  must never gain one). Deleted accounts and the system account appear
  nowhere and count nowhere. The directory has **no account-changing action
  at all, bulk or single** (spec §9); its one bulk operation is the
  identity-free, confirm-gated, audit-logged CSV export of the current view.
- **The glance view** (`/owner/members/[handle]`) shows standing and conduct
  — status, role, counts, de-identified enforcement history reused from
  `mod_enforcement_history()`, a one-way link into `/mod` — and never the
  person. **The identity panel** at its foot is the one place identity
  exists: Owner-only, AAL2 step-up, a mandatory stated reason, and an
  `identity.reveal` entry written to the hash-chained audit log by the
  database *before* the data returns. Device signals are a count, never
  hashes.
- **`/owner/insights` — full analytics**: a descriptor registry
  (`src/lib/metrics.ts`) rendered by one `MetricCard`, so the fiftieth
  metric is a declaration, not a design. 26 metrics in six sections —
  membership (total with exact status breakdown, **real net change**:
  +joined −departed +reinstated from recorded departure events, active
  members), engagement (**DAU/WAU/MAU and stickiness, sessions, time on
  site, online now, precise per-member last-seen, streaks**), growth
  (signups, follows with per-member follower growth, **1/7/30-day cohort
  retention**), content (posts, posts per member, likes, likes per post,
  reply depth), **per-member leaderboards** (most posts, likes given,
  likes received, most active by sessions), and safety (reports filed and
  resolved, median time to resolution, enforcement actions). **Every
  number is literal** — the owner's decision (2026-10): the original
  build's k=5 suppression, percentage-withholding, "not enough data"
  states, and "refused metrics" prohibition were a design preference that
  was never hers, and they are deleted — from the SQL, from
  `src/lib/metrics.ts`, from the card, and from suite 11's assertions.
  Per-member figures are @handle-keyed; the identity line is untouched.
- **Everything is Owner-only, enforced at the data layer**: the `owner_*`
  functions filter on `is_owner()` (zero rows for anyone else) or raise;
  the pages' redirects are courtesy, not the gate. The spec's Admin
  handle-lookup (§6.2) is deliberately not built yet — owner decision:
  visibility is Owner-only for now and widening later is a deliberate act.
- Suite `11-admin-dashboard.sql` proves the owner-only gate, the
  no-raw-timestamp rule, the `display_name` structural absence, the reveal's
  AAL2+reason+audit chain, the export log, suppression, and deleted-member
  erasure.

Migration `20261014000001_admin_dashboard.sql` **is applied to the live
project** (2026-10-09). ✅ **Migration `20261016000001_full_analytics.sql` was APPLIED to the live
project by Grove on 2026-10-09** — HTTP 201, re-run twice more clean to prove
idempotency against production. Verified in the live schema: `owner_metrics()`
contains no suppression logic of any kind and is still Owner-gated via
`is_owner()`; `member_sessions`, `account_status_events` and
`analytics_collection` all exist with RLS enabled; `profiles` carries the
`deactivated_at`, `banned_at` and `deleted_at` departure stamps, so net change
can genuinely go down by one; `analytics_collection` is seeded with
tracked-since rows for `sessions` and `departures`; zero new functions
reference `display_name`; the database still has 0 tables without RLS and 0
unpinned SECURITY DEFINER functions. It
supersedes `owner_metrics()`, adds the collection the new metrics need —
`member_sessions` (client heartbeat via `session_heartbeat()`, RLS
own-rows-read, function-only writes), `account_status_events` plus
`deactivated_at`/`banned_at`/`deleted_at` departure stamps on `profiles`
(trigger-maintained, so "down by one" is a real recorded event), and
`analytics_collection` tracked-since labels (no fabricated history) — all
with RLS; the 0-tables-without-RLS invariant holds. Until Grove applies
it, Insights renders its calm error state in production; nothing crashes.
Suite 13 covers the new behaviour; `display_name` appears in none of it.

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
authenticated-only EXECUTE. ✅ **Migration `20261013000001_discover.sql` was
APPLIED to the live project by Grove on 2026-10-09** via
`POST /v1/projects/{ref}/database/query` — HTTP 201, then re-run twice more
clean to prove idempotency against production. Verified in the live schema
(not the migration file): `profiles.discoverable` is `boolean NOT NULL
DEFAULT true` with both existing profiles backfilled `true`; both functions
are SECURITY DEFINER with `search_path` pinned to `public, extensions,
pg_temp`; `pg_get_functiondef` confirms neither references `display_name`;
EXECUTE is granted to `authenticated` and the owner only, with zero grants to
`anon`, `PUBLIC`, or `service_role`; the database still has **0 tables
without RLS**; and both accounts are intact. Discover is fully live — no
further deploy needed.

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

### Discover follow-up: the opt-out is not surfaced at signup (2026-10-09)

- **`docs/design-phase2b-moderation-and-discover.md` specifies that the
  Discoverability opt-out should be prominent at signup. It shipped only in
  Settings → Privacy.** Discoverability defaults to ON, so a member who never
  opens Settings is discoverable without having been told so at the moment she
  joins. On a platform whose members are specifically hiding from specific
  people, that gap is a safety-posture issue rather than a cosmetic one.
  This is **not a new decision** — the design already called for it; it is
  simply unbuilt. Small follow-up: surface the choice (or at minimum a plain
  statement of the default, with a link) in the signup flow. No migration
  needed; the column and the write path already exist and are live.

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

- [x] ~~**Phase 2F: hashtags, @-mentions and reposts**~~ — **BUILT
      2026-10-10** to `docs/design-phase2f-hashtags-mentions-reposts.md`
      (see "Where things stand"). Both owner decisions honoured: plain
      reposts AND quote-posts shipped together as first-class features, and
      "Who can mention you" defaults to Everyone. Migration
      **`20261017000001`** is written and tested but **NOT applied to the
      live project yet** — that apply is the next action.
- [x] ~~Phase 2B remainder: Discover feed + the Discoverability settings
      toggle~~ — DONE 2026-10-09, migration `20261013000001` **applied to
      live and verified by Grove** (see "Where things stand")
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

- [ ] **Apply migration `20261021000001` (DM rework, removes E2E) to the
      live project** — written, verified locally (fresh apply, double
      re-run, data-preservation re-run), NOT applied. Applying migrations
      is Grove's step. The code is deployed and degrades cleanly until
      then (the feature is dark at both layers regardless).
- [ ] **Apply migration `20261017000001` (Phase 2F) to the live project** —
      the hashtags/mentions/reposts data layer. Code is deployed and
      degrades gracefully until the apply happens. (Applying migrations is
      Grove's step, outside the build agent's scope, per standing practice.)

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
- [x] ~~Decide how the DM crypto gets independently reviewed~~ — **DEAD,
      owner decision 2026-10-09: DMs are not end-to-end encrypted, so there
      is no cryptography to review. Never re-raise an encryption review in
      any form.** The remaining gate before DMs turn on is Grove-Test +
      Grove-Security passing the non-E2E rework, then the Owner flips the
      two `dm_enabled` layers.
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
- 🔒 **DMs are NOT end-to-end encrypted. Owner decision, 2026-10-09 — FINAL,
  supersedes the 2026-10-07 E2E decision.** The platform owner can read
  message content; members are told so plainly and up front on every
  Messages surface; messages may be disclosed to authorities in matters
  involving trafficking or sexual exploitation, including of minors. The
  disclosure is considered a feature. The breach trade-off is known and
  accepted; the mitigation is access hardening (zero-policy RLS,
  functions-only access, every staff content read written to the audit
  log), not encryption. **Do not re-propose E2E in any form, and never
  propose an encryption review — there is no cryptography left to
  review.** The rework (migration `20261021000001`) deleted the Double
  Ratchet layer, franking, device keys (and the one-device limit), and
  renamed the flag to `dm_enabled`. **First release is text-only and 1:1
  only.** A side effect of the reversal: server-side CSAM hash-scanning of
  DM images is possible again if DM images ever ship.
  Full design: `docs/design-phase2c-direct-messages.md`.
- **Images are served through Cloudflare** so free CSAM scanning sees them,
  and EXIF is stripped at upload so location data never reaches storage.

## Security — Content-Security-Policy (2026-10-05)

**Status: SHIPPED**

Added a nonce-based CSP header implemented in `src/proxy.ts`
(Next.js 16 proxy convention). Every response now includes:

```
content-security-policy: default-src 'self'; script-src 'self' 'nonce-{NONCE}' https://challenges.cloudflare.com; style-src 'self' 'unsafe-inline'; img-src 'self' https://media.hersciety.com data: blob:; font-src 'self'; connect-src 'self' https://hiphjzhlwiztqgezzipf.supabase.co https://challenges.cloudflare.com https://7f79ff00b7bec4dea299ac9e824cface.r2.cloudflarestorage.com; frame-src https://challenges.cloudflare.com; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'
```

The `unsafe-inline` in style-src is a deliberate, documented tradeoff for
inline `style={{ }}` attributes in 6 components (blurhash colours, crop
overlay). All other directives are strict. Full reasoning in KNOWLEDGE/app.md.

Files changed: `src/proxy.ts` (new), `src/lib/supabase/middleware.ts`,
`src/app/layout.tsx`, `next.config.ts`.

## Responsive fixes + account menu + 40-char tag cap + Reposts tab (2026-10-05)

**Status: SHIPPED (code); migration `20261018000001` WRITTEN, NOT APPLIED**

Four working increments on main (fc417b7, 9379aba, 78879c4, ccb0d91):

1. **Mobile account menu (blocker).** `AccountMenu` extracted from
   `AppShell.tsx` into `src/components/shell/AccountMenu.tsx` (single
   definition, viewer-context-fed) and mounted on the own-profile
   header below `lg`. Before this, no viewport under 1024px could log
   out, reach Settings, or open /mod and /owner.
2. **Overflow fixes.** Tag-page `h1` breaks long tags; tag rows in
   trending/search/autocomplete truncate; safety-page handles
   truncate; all owner pages gain `p-4`; audit JSON wraps; the avatar
   crop viewport is `min(288px, 100vw - 64px)` with measured crop
   maths.
3. **Polish.** 44px touch targets (filter pills, mod/insights tabs,
   camera button hit area); `viewport-fit=cover` so safe-area insets
   engage; top bar + DM header safe-area-aware; `Card` pads
   `p-4 sm:p-6` with a `padded={false}` opt-out.
4. **Muted inert tokens + Reposts tab.** Refused/unresolved mentions
   and over-40 hashtag tokens render muted (`text-text-tertiary`);
   hashtag cap 40 on both sides (Owner decision); profile Reposts tab
   via `profile_posts(p_reposts => true)`. Suites 05/14 updated,
   suite 15 added; all 15 suites pass on a locally migrated database.

## Passkeys + the identity-reveal gate (2026-10-05)

**Status: SHIPPED (code); migration `20261019000001` WRITTEN, NOT APPLIED**

Three working increments on main:

1. **Passkey registration and management.** The old "Add a passkey /
   security key" button called a WebAuthn-as-MFA API the auth backend
   refuses to enable — a guaranteed failure for every member. It now
   uses real passkey registration; Settings → Security lists, renames
   (authenticator-derived friendly names), and removes passkeys, with
   plain-language error copy that names no vendor. TOTP enrollment and
   step-up untouched. Browser client opts into the beta passkey API.
2. **Passkey sign-in.** A secondary "Sign in with a passkey" button on
   the login page (discoverable credentials — no email asked).
   Password sign-in unchanged.
3. **The gate.** `owner_reveal_identity` accepts AAL2 OR a passkey
   authentication fresh within 5 minutes, read server-side from the
   JWT `amr` claim (array of `{method, timestamp}` objects). The
   audit entry now records which method satisfied the gate. Every
   other AAL2 requirement is deliberately unchanged. IdentityPanel
   offers an in-place passkey re-confirmation when the session is
   stale. Suite 16 added; suites 01–16 pass on a locally migrated
   database (fresh apply + re-run of the new migration).

The new migration is NOT applied to the live project — until it is,
the identity reveal keeps requiring AAL2 exactly as before (the shipped
UI degrades to the authenticator-app path).

## The passkey gate extended to all Owner sensitive operations (2026-10-05)

**Status: SHIPPED (code); migration `20261020000001` WRITTEN, NOT APPLIED**

By explicit Owner decision (she uses a passkey, not an authenticator
app, and was locked out of running her own platform), the
"AAL2 OR fresh passkey" gate now covers everything that was aal2-only:

1. **`grant_role` / `revoke_role` / `owner_unban`** call
   `require_owner_sensitive_auth()` instead of `require_owner_aal2()`;
   their audit entries record `auth_method: 'aal2'|'passkey'`
   (`mod_record_action` gained a trailing optional parameter for the
   unban — the old signature is dropped, exactly one remains; every
   other moderation action's audit entry is byte-identical).
   `grant_privilege`/`revoke_privilege` no longer exist (dropped in
   `20261002000001`) — nothing to widen.
2. **The RLS policies `audit_owner_read` and `user_private_owner`**
   now use `is_owner() and owner_sensitive_auth_method() is not null`.
   To make that evaluable by the querying role,
   `owner_sensitive_auth_method()` is EXECUTE-granted to
   `authenticated` (it reads only the caller's own JWT and returns a
   string the client already knows; the raising variant stays
   internal). The orphaned `require_owner_aal2()` is dropped.
3. **Authorization unchanged everywhere**: every operation keeps its
   Owner check; suite 17 proves an ADMIN with a seconds-old passkey is
   refused all five operations and reads zero gated rows.
4. **Client:** `/owner/roles` and `/owner/audit` now offer the same
   in-place "Confirm with your passkey" as IdentityPanel (shared
   `stepUpWithPasskey()` helper in `src/lib/passkeys.ts`, including
   the switched-account refusal), with the authenticator path
   alongside. Suite 17 added; suites 01–17 pass on a locally migrated
   database (fresh apply of all migrations + re-run of the new one).

The new migration is NOT applied to the live project — until it is,
role changes, unbans and the audit-log/user_private reads keep
requiring AAL2 exactly as before (the new prompts degrade to a refused
action with the server's step-up message).

## DM rework: end-to-end encryption REMOVED (2026-10-05)

**Status: SHIPPED (code); migration `20261021000001_dm_remove_e2e.sql`
WRITTEN, NOT APPLIED. The feature stays DARK at both layers.**

Owner decision (2026-10-09, final): DMs are NOT end-to-end encrypted.
The platform owner can read message content; members are told so
plainly on every Messages surface; messages may be disclosed to
authorities in matters involving trafficking or sexual exploitation,
including of minors. This was a DELETION, not a build:

1. **Removed the whole cryptographic layer**: `src/lib/dm/crypto.ts`
   (Double Ratchet / X3DH), the IndexedDB store and protocol client,
   device registration + prekeys (the `user_devices` and
   `one_time_prekeys` tables are DROPPED — nothing outside DMs used
   them), message franking, safety numbers / VerifyDialog /
   DmBootstrap, the `/api/dm/devices|prekeys|bundle` routes, the
   `@noble/*` dependencies, and `scripts/dm-crypto-test.ts`. The
   one-device-per-account limit died with the keys: phone + laptop
   now simply work.
2. **Reshaped `dm_messages`** to a readable `body` (1-2000 chars)
   instead of header/ciphertext/frank_hash (0 rows existed; the
   reshape is guarded so a post-launch re-run cannot touch data).
3. **Access hardening replaces E2E** (the owner's accepted
   mitigation): zero-policy RLS on every content table (functions are
   the only path and verify participation); staff reach content only
   through `mod_dm_evidence()`, and **every such call writes a
   `dm.content_read` row to the hash-chained audit log**; Supabase
   provides AES-256 at rest (infrastructure-level, always on; nothing
   further is configurable at this tier — documented honestly in the
   design doc, including the direct-SQL residual risk).
4. **Report evidence is now a server-side snapshot**: the reporter
   selects 1-10 messages and `file_dm_report()` copies them from the
   real rows (no client-supplied plaintext, no franking, no
   verified/unverified distinction — a server copy cannot be
   fabricated). The snapshot table stays separate so evidence
   survives message/account deletion.
5. **Flag renamed** `dm_e2e_enabled` → `dm_enabled` (env
   `DM_ENABLED`); the migration deletes any old-key row and inserts
   nothing. A row under the old key enables nothing (suite 09 proves
   it). Both layers remain OFF.
6. **The unmissable disclosure** (`DmDisclosure`, persistent banner on
   inbox + every thread): "Your messages are not private from
   Hersciety. Direct messages are not end-to-end encrypted. The
   platform owner and moderators can read them, and every one of
   those reads is logged. Messages may be disclosed to authorities in
   matters involving trafficking or sexual exploitation, including of
   minors."
7. **RPC signatures changed** (old signatures dropped explicitly —
   exactly one signature per DM function, asserted structurally in
   suite 09): `dm_send_message(uuid,text)`,
   `file_dm_report(uuid,report_reason,text,bigint[])`, and new return
   shapes for `dm_fetch_messages`, `dm_list_conversations` (now
   carries a server-side `last_body` preview), `mod_dm_evidence`
   (volatile now — it writes the audit row).

Verified locally on a fresh Postgres: all migrations 0001→20261021
apply clean; the new migration re-runs twice (plain +
--single-transaction) with notices only; a third run against a
database WITH message data left the data untouched; suites 01-17 all
pass (09 fully rewritten for the non-E2E design); `tsc --noEmit`,
`eslint .`, and `next build` green with the flag off AND on.

Until the migration is applied, production code degrades cleanly: the
feature is dark (env unset), `dmFeatureOn()` treats any error as off,
and even with env set the DB functions still gate on the absent
`dm_enabled` row.

## Pre-launch audit batch: mentions RLS, suspension expiry, pepper, last-passkey guard, HSTS (2026-10-05)

Five scoped fixes from the pre-launch security audit, in one pass:

- **Migration `20261022000001`** (written, tested locally — fresh apply
  plus two re-runs, all 17 suites green — **NOT YET APPLIED to the live
  project**; Grove applies it):
  - `post_mentions_read` now excludes rows across a block, mirroring
    `posts_read`: a blocked member can no longer enumerate who was
    mentioned in posts she cannot see, or which posts mention a person.
    Mention metadata is as protected as the post itself.
  - **Suspensions now actually end** (Community Guidelines promise):
    installs `pg_cron` (1.6.4 available on the live project, previously
    not installed) and schedules `hersciety-status-expiry-sweep` every 5
    minutes running `sweep_expired_statuses()`, which mirrors
    `refresh_my_status()` exactly — status → `active`,
    `status_expires_at` → null, one `mod.status_expired` audit row per
    member (actor honestly `system`; the sign-in path records the member
    — neither path notifies, by matched design). The sign-in path stays
    as belt-and-braces; READ COMMITTED predicate re-check means the two
    can never double-process. Until the migration is applied, behaviour
    is exactly as before: lapsed suspensions clear only on sign-in.
  - NOTE for whoever applies it: installing pg_cron also makes the 0025
    `hersciety-trending-tags` schedule *possible* — that job was silently
    skipped when 0025 ran on live (no pg_cron then). Trending has a
    read-through fallback, so this is an optimisation, not a bug; re-run
    0025's DO block or schedule it by hand if wanted.
- **`IDENTIFIER_HASH_PEPPER` is now required** (`requireEnv`): the
  `"dev-only-pepper"` fallback is gone. In this public repo that fallback
  was a known HMAC key — if the env var ever went missing from a deploy,
  anyone could compute identifier hashes and probe ban status. The var IS
  set in Vercel (prod + preview), so nothing changes live; a deploy that
  loses it now fails signup/ban/age-gate requests loudly instead of
  weakening silently. Local dev needs the var in `.env.local`
  (`.env.example` updated; `openssl rand -hex 32`). No script or test
  depended on the fallback.
- **Last-passkey guard** (`SecurityPanel.tsx`): removing your final
  passkey is refused when no verified second factor exists, with a calm
  message to add a replacement passkey first. Without this, the Owner
  (passkeys-only by explicit choice — no TOTP, do not nag) could strand
  herself out of every privileged action. No TOTP push added.
- **HSTS completed** in `next.config.ts`: `max-age=63072000;
  includeSubDomains; preload`, overriding Vercel's bare-max-age platform
  default. `includeSubDomains` is what extends coverage to
  `media.hersciety.com`. ⚠️ `preload` marks eligibility only — actually
  submitting hersciety.com to hstspreload.org is a deliberate,
  slow-to-reverse human step that has NOT been taken. Verify the live
  response header after deploy (Vercel docs say custom headers override
  the platform default; one community report disagrees — check, don't
  assume).

## Multi-part threads — "Add to thread" (2026-10-05)

Built to `docs/design-multi-part-threads.md` (the approved spec; its
judgment calls were implemented, not re-litigated). The owner's ask: write a
long post as connected replies to your own thread, like Threads.

- **Composer**: a fresh draft is one part and looks exactly as before. "Add
  to thread" (full-width, Plus glyph) appends a part with its own fresh 500
  characters, joined by the thread-rail connector and captioned "Part k of
  N" in words. Per-part late-reveal counter (shows at 60 remaining,
  warning, danger at 0); typing stops at 500 and offers "Add another part";
  a paste past 500 auto-flows into connected parts with ONE Undo, splitting
  at sentence boundaries first, then paragraph > newline > space, never
  inside a @mention/#hashtag/URL (the splitter shares `src/lib/text.ts`
  with the renderer and counts code points); a single >500 tokenless run
  hard-breaks and the notice says so. Reorder via Move up/down buttons
  (44px, named for SR), remove with Undo toast; the last part cannot be
  removed. Trailing empty parts are dropped at publish; an interior empty
  part is flagged in place and blocks Post with the reason named (and read
  via aria-describedby). Cap: **25 parts** — derived from create_post's
  depth-30 refusal (last part at depth 24 leaves five reply levels); the
  Add control disables with the reason, never hides. Button reads **"Post
  all N"**. Mobile (<lg): unfocused parts collapse to chips (position,
  first line, full marker, controls); Add + the focused counter + Post ride
  a sticky bar above the keyboard.
- **Atomic publish**: new `create_thread(p_bodies[], p_reply_control,
  p_quote, p_key)` RPC inserts every part through `create_post` in ONE
  transaction (all existing per-part checks reused verbatim) — all parts or
  none. `p_key` is a client uuid minted per publish attempt and honoured
  for 24 hours (`internal.thread_idempotency`), so a retry after a lost
  response returns the already-posted head instead of double-posting; the
  key row commits/rolls back with the posts, and editing the draft mints a
  fresh key. Multi-part publish is NOT optimistically closed: on failure
  the composer keeps everything and says "Nothing was posted, so your
  draft is safe."
- **Display**: a chain is structural (maximal same-author run down the
  spine from a top-level post; continuation = earliest same-author reply,
  tie-broken by (created_at, id) since one transaction = one timestamp).
  `get_thread` now returns `spine_seq`; ThreadView renders the spine FLAT
  (parts never consume the root+2 nesting budget), labels each card "Part
  k of N" over the parts actually visible, shows a slim "The author
  removed this part" marker at a deleted part (live renumbering), and
  collapses a fully-unreachable chain to ONE "This thread is unavailable."
  Opening any part resolves to the head via the new `chain_head()` RPC and
  scrolls/highlights the tapped part. Feed/Discover/profile show a chain
  head as ONE card with "Show this thread · N parts" (spelled out for SR);
  a reposted or tag-feed mid-chain part carries "Part k of N · Show this
  thread." The profile Replies tab now suppresses chain continuations
  (they are the thread, not self-replies); genuine replies and non-spine
  self-replies are untouched.
- **Migration `20261024000001_multi_part_threads.sql`** — WRITTEN AND
  VERIFIED LOCALLY, **NOT applied to the live project** (Grove applies).
  Fresh apply + two re-runs clean (idempotent); full suite 01–19 green, 20
  fails identically at baseline `8a86a34` (the pre-existing suspended-
  profile-readable bug that migration `20261023000001`, owned by another
  agent, addresses — unrelated to this work). get_thread, feed_following,
  feed_discover, feed_hashtag and profile_posts were dropped (exact single
  signatures, return shapes grew) and recreated with identical arguments —
  no leftover second signatures — and their revoke/grant lockdown
  re-applied. Until the migration applies, the deployed code degrades
  cleanly: the composer probes `chain_head()` once per page load and hides
  "Add to thread" when it is missing, the thread page falls back to the
  old root resolution, and every card renders without chain cues (the new
  row fields are optional).
- **Not done, noted**: the quoted compact card inside a quote-post does not
  yet carry a "Part k of N" corner marker (design §18 names it for
  whenever quote surfaces chain parts; the link already lands on the full
  thread from the head). Reorder is buttons-only (drag was spec'd as a
  pointer-only enhancement, not required).
