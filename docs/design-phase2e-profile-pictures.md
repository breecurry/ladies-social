# Hersciety: Profile Pictures and Avatars (Phase 2E) Design Specification

**Status:** Design specification. Docs only. This document creates no application code, no database migration, and no image assets. It specifies the first image feature the platform has ever had: member avatars. A code pass and a schema pass should be buildable from this document plus the existing token system and the media pipeline already described in the architecture document, without the builder having to make product judgment calls.

**Date:** 2026-10

**Design thesis (inherited, not reopened):** "Calm paper, sharp tools." Warm, low-glare sand neutrals carry content; one Iris-violet accent carries interaction. See P2 (the Phase 2 social-core spec). This spec adds avatars inside that system. It does not redesign it.

**Locked context (do not reopen):** The @handle leads everywhere in the UI. `display_name` is the member's real legal name, is not public by default, and is opt-in only. No surface ever pairs an avatar with a legal name by default. Zero counts are hidden. The Owner account and the system account are unblockable. Reports naming the Owner go to the normal admin report panel plus an email copy to safety@unitedfeminist.com; there is no external independent recipient. Registration is open; enforcement is conduct-based. Search is @handle only. These are settled elsewhere and are treated here as fixed.

---

## 0. How to read this document

- **Tokens** are the CSS custom properties implemented in `src/app/globals.css`, named exactly as they appear there (for example `--accent`, `--accent-subtle`, `--surface`, `--radius-full`). This spec adds zero new tokens. Section 14 confirms that.
- **Contrast** is the WCAG 2.x relative-luminance method on sRGB throughout. Every ratio here is a computed number, not an assertion; the method and the measured table are in section 14. Pass thresholds: 4.5:1 for normal text, 3:1 for large text and for non-text graphics that are the sole identifier of meaning.
- **The media pipeline** this feature rides already exists in design intent. The architecture document, section 3.2 ("Media upload pipeline, identical for posts, avatars, and DMs"), is the authoritative description of the staging-bucket, EXIF-strip, scan, variant, and serving path. This spec does not restate it line by line; it reuses it and adds only what is avatar-specific. Where this spec and the architecture document agree, the architecture document is the implementation reference.
- **House style:** plain prose, ASCII only. Cross references read as "P2 section X" for the Phase 2 social-core spec, "P2B section X" for the moderation-and-discover spec, "P2D section X" for the admin-dashboard spec, and "the architecture document, section X" for the technical blueprint.

### 0.1 What exists today, verified against the repository

- **A letter avatar already ships.** `src/components/Avatar.tsx` renders a solid `accent-subtle` circle with the member's first handle letter in `accent`. It supports sizes 24, 32, 40, 48, 96, and 128 px, is a link to `/u/{handle}` with an `aria-label` of the @handle, and when `link={false}` (because the surrounding row is the link) its inner mark is marked `aria-hidden`. This is the default identity mark and it is used in the feed, replies, profile header, notifications, people lists, the composer, and the direct-message surfaces. It is good work and this spec keeps it.
- **The data column already exists.** `profiles.avatar_media_key text` is present in the schema (architecture document, section 2) and is the R2 key for a member's avatar. It is currently always null in practice because nothing writes it.
- **The pipeline already exists in design.** Architecture section 3.2 describes the exact upload-to-serve path for avatars. The `media_scan` enum (`pending`, `clear`, `flagged`, `blocked`) and a blurhash convention already exist for post media.
- **The platform has never rendered an uploaded image of any kind.** Avatars are the first. There is no established pattern for upload, crop, image moderation display, or image reporting in the product UI. This document establishes them.
- **The site is fully gated and not indexed.** Every member surface (`/home`, `/search`, `/notifications`, `/settings`, `/u/*`) returns a 307 redirect to `/login` when logged out, and `SITE_INDEXABLE` is unset so the whole site serves `noindex, nofollow`. The only brand image a logged-out visitor can see is the Open Graph share card, which is the wordmark, not any member's avatar.

### 0.2 The constraint that dominates this entire design

Members of this platform are hiding from specific people: ex-partners, stalkers, family, coordinated harassers. An uploaded image is the single richest leak vector a product like this can add. A photo can carry GPS coordinates, a device serial, a capture timestamp, and a filename that is often the member's real name. A predictable storage URL lets an attacker walk the bucket and harvest faces. A face shown to a blocked person, or left visible after a ban, undoes the protection the member came here for.

So the safety model is not a section of this design; it is the spine of it. Everything visual hangs off decisions made in section 2. If a visual choice ever conflicts with a safety rule in section 2, the safety rule wins and the visual is redrawn. This is stated once here so it does not have to be repeated at every surface.

---

## 1. Summary of decisions

For the reader who wants the answers before the reasoning.

1. **Metadata is stripped server-side by full re-encode, never optionally, never client-trusted.** The server decodes, auto-orients, and re-encodes every avatar before any byte of it is stored anywhere servable. EXIF, GPS, XMP, IPTC, and color-profile side channels do not survive. Section 2.1.
2. **The original filename is discarded at the edge of the system and never stored or returned.** Nothing in the database, the object key, or any API response ever carries the uploaded filename. Section 2.2.
3. **Object keys are opaque and unguessable.** An avatar key is a random identifier with no handle, no user id, no counter, and no timestamp in it. The bucket cannot be enumerated or walked. Changing an avatar mints a new key; it never overwrites the old one. Section 2.3.
4. **Avatar media is served through Cloudflare with an unguessable immutable key, not a signed token.** Avatars are public within the platform, so they match post media rather than DM media. The residual exposure (someone who already holds the exact URL can fetch the image) is named and mitigated, not hidden. Section 2.4.
5. **Logged-out visitors never see an avatar.** This falls out of the existing auth gate for free, and section 2.5 states what must stay true when the site is eventually indexed.
6. **A hard-blocked member sees the letter placeholder, not the photo, in both directions. A muted member still sees the photo.** Block hides identity; mute only quiets the feed. Section 2.6.
7. **An avatar follows its account's standing.** Suspended: hidden, placeholder shown, restored on lift. Banned: removed from every surface, media retained for evidence per the retention policy. Account deleted by the member: media hard-deleted with the account. Section 2.7.
8. **The avatar size scale is six named steps, not scattered pixel values.** xs 24, sm 32, md 40, lg 48, xl 96, 2xl 128, all masked to `radius-full`. Section 3.
9. **The default avatar stays the letter mark.** It is deliberate, legible, not gendered, and not a stock silhouette. It is kept and refined, not replaced. Section 5.
10. **Upload accepts static JPEG, PNG, and WebP, capped at 8 MB and a sane pixel ceiling, with a minimum of 256 by 256, and every rejection states its reason.** No animated avatars. Section 6.
11. **The crop step is a square frame with a circular-mask preview, drag and zoom, as a desktop modal and a mobile full-screen sheet.** Section 7.
12. **An avatar is reported through the existing report-the-member flow, with the specific avatar frozen as evidence at the moment of the report.** Section 9.
13. **A reported avatar reaches a moderator blurred, behind a deliberate click-to-reveal, and a CSAM-class report never renders the image in the console at all.** Section 10.
14. **A moderator can remove an avatar; removal reverts the member to the placeholder, tells the member which rule was broken, and is reversible for an honest mistake.** The removed image is preserved as evidence, never hard-deleted. Section 11.
15. **Adopt PhotoDNA plus Cloudflare CSAM scanning (both free) at upload, with Hive for visual triage.** The reasoning and the cost read are in section 13. This is a recommendation for the owner to decide.
16. **Zero new design tokens.** Section 14.

---

## 2. The avatar safety model

This is the load-bearing section. Build to it exactly.

### 2.1 Metadata is stripped server-side, by re-encode, and it is not optional

The only reliable way to strip image metadata is to decode the pixels and re-encode a fresh image from them. Editing or "removing EXIF" in place is fragile: metadata hides in EXIF, XMP, IPTC, embedded color profiles, thumbnail previews (an EXIF thumbnail can retain the original uncropped frame), and format-specific extension blocks. A full re-encode drops all of it because none of it is pixel data.

Rules, all mandatory:

- The server decodes the uploaded image, **auto-orients it first** (orientation lives in EXIF, so orientation has to be read and applied before the EXIF is thrown away, or the avatar comes out sideways), then re-encodes every served variant from the oriented raster. This matches architecture section 3.2 steps 4a and 4b exactly.
- Stripping happens **before anything is written to a servable location.** Raw uploads land only in the staging bucket, which is never served to anyone. The media bucket only ever receives re-encoded, metadata-free output.
- The strip is **server-side and authoritative.** The client may re-encode too (it does, as a side effect of the crop in section 7 and the downsize in architecture 3.2 step 1), but the client is never trusted to have done it. A crafted client can send anything; the server re-encode is the control.
- **Do not copy the EXIF thumbnail, and do not preserve the ICC color profile verbatim.** Convert to sRGB and embed at most a minimal sRGB tag. An embedded profile can be a fingerprinting and payload channel.

The outcome to verify at build time: run `exiftool` (or equivalent) over a served avatar variant and confirm it reports no GPS, no device make or model, no timestamps, no original filename, no XMP, and no embedded thumbnail. That check belongs in the Phase 3 media-pipeline test suite.

### 2.2 The original filename is never persisted and never exposed

Filenames leak real names constantly ("Jane-Smith-headshot-2024.jpg", "IMG from Mom's phone"). The rule is absolute:

- The uploaded filename is read only to validate the extension against the detected content type, and is then discarded. It is **never stored** in the database, **never used** to build the object key, and **never returned** in any API response, header, or error message.
- The stored object carries the opaque key from section 2.3 and nothing else. The `Content-Disposition` on serving, if set at all, uses a generic name, never the original.
- The schema already supports this: `profiles.avatar_media_key` stores a key, not a name, and there is no filename column to fill. Keep it that way. Do not add one.

### 2.3 Object keys are opaque, unguessable, and non-enumerable

If an avatar key were `avatars/<user_id>.jpg` or `avatars/<handle>/photo.jpg`, anyone who knew a handle could fetch the face, and anyone could walk the bucket by iterating ids. That is exactly the harvest an attacker wants against a platform of people in hiding. So:

- An avatar object key is a **random, high-entropy identifier** (a version-4 UUID or 128-plus bits of CSPRNG output), for example `av/7f3a9c2e-.../lg`. It contains **no user id, no handle, no sequential counter, and no timestamp.** Two members, and two uploads by the same member, share no guessable relationship in their keys.
- The key is **not derivable from anything public.** Knowing a member's @handle, user id, join order, or current avatar tells you nothing about the key of any variant. The mapping from member to key lives only in the `avatar_media_key` column behind RLS.
- **A new upload mints a new key; it never overwrites the previous object at the same path.** Overwriting would (a) let a stale Cloudflare cache keep serving the old image and (b) destroy an image that might be needed as evidence. New key, swap the column, then clean up the old object only when it is safe to do so (section 2.7 and section 11 govern when it is not safe).
- The staging bucket keys are likewise random and short-lived; staging objects are deleted immediately after the pipeline succeeds (architecture 3.2 step 4f).

### 2.4 How avatar media is served, and why not a signed token

There are two serving models already in the architecture: public post media (cached at the Cloudflare edge, long cache lifetime, immutable keys) and private DM media (a Cloudflare Worker validates a short-lived signed token issued only to conversation members). Avatars sit with **post media**, not DM media, for a deliberate reason: an avatar is shown to every logged-in member who can see the person at all, so it is "public within the platform." Gating every avatar render behind a per-request signed token would defeat edge caching on the single most-rendered image in the product (an avatar appears dozens of times per feed screen) for privacy it does not actually gain, because the image is shown to all members anyway.

So the serving model is: **Cloudflare-proxied `media.hersciety.com`, public cacheable, immutable unguessable key.** This keeps egress at zero and keeps avatars fast.

The residual exposure, stated plainly so it is a decision and not an accident: **a person who already possesses the exact avatar URL can fetch that image without logging in.** This is acceptable, and here is the full mitigation that makes it acceptable:

- The URL cannot be guessed or enumerated (section 2.3). An attacker cannot turn "I know her handle" into "I have her avatar URL."
- Profiles are not search-engine indexable (architecture section 3.7, threat model item 3), so the URL does not get crawled into the open web.
- `Referrer-Policy: no-referrer` is already shipped platform-wide (architecture section 3.1), so when a member clicks an outbound link, the avatar URL (and the fact that she is a member) is never sent to the destination.
- A hard-blocked person is served the placeholder, not the real key (section 2.6), so a known threat actor inside the platform cannot read the key off the page.

If the owner later decides even this residual is too much (for example, if avatars are ever shown to a lower-trust audience), the upgrade is contained: route avatars through the same signed-token Worker path as DM media. The schema and component do not change; only the serving URL construction does. Do not build that now; name it as the escape hatch.

### 2.5 Logged-out visitors never see an avatar

Because every member surface 307s to `/login` when logged out, and profiles are `noindex`, a logged-out visitor has no page on which an avatar is rendered. This is correct and it is free. Two things must stay true as the site matures:

- **When `SITE_INDEXABLE` is eventually flipped on, the member surfaces must remain auth-gated.** Indexing the public marketing pages is fine; the feed, profiles, and the avatars on them must still require login. The existing middleware gate already enforces this; the avatar feature must not add any logged-out render path (for example, do not put a member avatar in an Open Graph image for a profile page).
- **No avatar is ever embedded in a share card, email, or push notification.** Notification previews are already content-suppressed by default for shoulder-surfing safety (the DM spec, P2C, established this). Avatars inherit the same posture: identity imagery does not travel outside the authenticated app.

### 2.6 What a blocked or muted member can and cannot see

Block and mute are different tools and avatars honor the difference.

- **Block (mutual-hard in this product).** When a block exists in either direction between the viewer and the avatar's owner, the viewer is served the **letter placeholder**, never the photo, and critically **never the real object key.** The photo is hidden both ways: the person you blocked cannot see your face, and you do not see theirs. This is the identity-hiding tool and avatars must respect it completely.
  - Build note, important: the `profiles_read` RLS policy today permits any authenticated member to read a profile row regardless of blocks (architecture section 2.1 shows `profiles_read` filtering only on `status <> 'deleted'`). That means `avatar_media_key` could leak to a blocked person through a raw profile read even if the UI hides it. The avatar key must therefore be **resolved through a block-aware path**, not read raw: either a `SECURITY DEFINER` resolver that returns a null key when a block exists in either direction, or an RLS change that nulls the key for blocked viewers. The UI falling back to the placeholder is not sufficient on its own; the key must not reach the blocked client. Flag this to the schema pass.
- **Mute (soft).** Mute hides someone's posts from your feed; it does not hide who they are. A muted member's avatar still renders normally on their profile, in search, and in people lists. Muting is "I do not want this in my feed," not "I am hiding from this person." Avatars follow that.
- **Restrict and hide ("show me less").** These are ranking and feed signals (P2 section 4.8), not identity controls. They do not change avatar visibility.

### 2.7 Avatar lifecycle on suspend, ban, and account deletion

An avatar is identity, so it has to track the account's standing. The states map onto the existing `account_status` enum (`active`, `restricted`, `suspended`, `banned`, `deactivated`, `deleted`).

- **Active / restricted:** avatar shows normally. (Restricted limits what the member can do, not how they appear.)
- **Suspended:** the avatar is hidden and the **placeholder is shown** everywhere, for the duration of the suspension, and is **restored automatically when the suspension lifts.** This matches the existing behavior where a suspended member's posts vanish from feeds while suspended (noted in the moderation console build). The avatar object is retained, not deleted; lifting the suspension re-points to it.
- **Banned:** the avatar is **removed from every surface** and the member reverts to the placeholder permanently. The avatar media object is **retained for the moderation-records retention window (2 years per the approved retention policy), not hard-deleted**, because a banned account's avatar may be evidence (impersonation, NCII, harassment imagery). CSAM-class material is retained on its own 1-year-minimum clock under the architecture's preservation rule and is never deleted on the normal schedule.
- **Deactivated:** treated like suspended for display (placeholder, media retained) since deactivation is reversible.
- **Deleted (member-initiated account deletion):** the avatar media is **hard-deleted** along with the account, after the standard 30-day account-data window, **unless** the media is under a legal hold or tied to a preserved moderation or CSAM event, in which case the preservation obligation wins and overrides the deletion. This is the one place the "always honor a deletion request" instinct is correctly overridden, and it is overridden only for genuinely preserved evidence, never for convenience.
- **Member removes their own avatar (no enforcement involved):** the media is a clean, unreported, non-evidence object, so it is **hard-deleted** and the member reverts to the placeholder. This is distinct from a moderator removal (section 11), which preserves.

---

## 3. The avatar size scale

Avatars render at many sizes across the app. Rather than scatter pixel values, this is a six-step scale with names. The pixel values are exactly the ones the existing `Avatar.tsx` already implements, so this formalizes what is shipped rather than changing it.

| Token name | Diameter | Letter type size | Primary use |
| --- | --- | --- | --- |
| avatar-xs | 24 px | `text-micro` | dense inline contexts, stacked facepiles if ever added |
| avatar-sm | 32 px | `text-caption` | notifications, reply depth 2, DM thread header, nav profile destination |
| avatar-md | 40 px | `text-body` | reply depth 1, people and follow lists, composer, new-message dialog, Discover suggestion cards |
| avatar-lg | 48 px | `text-heading` | root post card, DM inbox rows |
| avatar-xl | 96 px | `text-display` | profile header on mobile |
| avatar-2xl | 128 px | `text-display` | profile header on desktop |

Rules that apply at every size:

- **Masked to `radius-full`.** Every avatar is a circle, placeholder and photo alike. Store the image square (section 6.6); the circle is a CSS mask so one stored asset serves every shape need.
- **The letter scales with the circle.** The placeholder letter uses the type size in the table, centered, at weight 600, so it reads as proportionate rather than floating. This is already how `Avatar.tsx` behaves.
- **Serving variant is chosen by rendered size times device pixel ratio**, not one variant for all (section 6.6). A 24 px avatar on a 3x screen still asks for a 96 px-ish source, so it stays crisp.
- **Minimum touch target.** When an avatar is itself the tap target (the nav profile destination, a bare avatar link), the interactive area is padded to at least 44 by 44 px even when the visible circle is 24 or 32 px. The feed and reply avatars sit inside a larger row tap target already, so the visible circle can be small without shrinking the hit area.

---

## 4. Where the avatar appears

Every placement, the size it uses, and anything special about it. The shell is not changed by this feature; the avatar simply gains a photo where it previously showed only a letter.

| Surface | Size | Notes |
| --- | --- | --- |
| Desktop left-rail Profile destination | avatar-sm (32) | The avatar is the nav item (P2 section 1.1). Active state is a 2px `accent` ring (already shipped as `ring-2 ring-accent`); the ring doubles as the selected indicator and still reads over a photo. |
| Desktop left-rail account control | avatar-sm (32) | Avatar plus @handle plus caret at the rail bottom (P2 section 1.2). |
| Mobile bottom-tab Profile destination | avatar-sm (shown at 28) | Already a small `accent-subtle` letter circle with a 2px accent active ring (P2 section 1.3). Photo replaces the letter; active ring unchanged. |
| Root post card | avatar-lg (48) | Top-left, links to profile (P2 section 4.2). |
| Reply, depth 1 | avatar-md (40) | Inside the reply header, never on the thread rail (P2 section 6.3). |
| Reply, depth 2 | avatar-sm (32) | Same rule. |
| Quoted post (nested compact card) | avatar-md (40) | P2 section 4.4. |
| Composer and inline compose prompt | avatar-md (40) | Grounds whose voice this is (P2 sections 5.1 to 5.3). |
| Profile header | avatar-xl (96) mobile, avatar-2xl (128) desktop | `radius-full`, overlaps the header boundary by about one third, with a **3px `surface` ring** so it reads cleanly against any background (P2 section 7.1). The own-profile header gains the edit affordance in section 6.1. |
| Follower and following lists, people search rows (`PersonRow`) | avatar-md (40) | P2 sections 7.2 and 7.3. |
| Notifications list | avatar-sm (32) | The actor's avatar (P2 section 9.3 context). |
| Discover suggested-accounts cards | avatar-md (40) | P2B section (people-first cold start); same identity block as everywhere. |
| DM inbox rows | avatar-lg (48) | P2C. |
| DM thread header | avatar-sm (32) | P2C. |
| New-message dialog results | avatar-md (40) | P2C. |
| Moderation console (identity strip, case views, reporter reveal) | placeholder only | **Staff surfaces deliberately show the letter placeholder, never the live photo.** Reasoning in section 10. The one exception is the dedicated reported-image panel, which is click-to-reveal. |
| Owner member directory and metrics (P2D) | placeholder only | Same reasoning: these are surveillance-adjacent surfaces where the @handle is the identity that matters and showing faces aids nothing while risking display of unreviewed images. |

The single consistent rule: **everywhere a member is shown to other members, the avatar is the photo (falling back to the placeholder). Everywhere a member is shown to staff for enforcement, the avatar is the placeholder unless a moderator deliberately reveals a reported image.**

---

## 5. The default avatar when none is set

Most members on a brand-new platform will not have uploaded a photo, so the default is not an edge case; it is the common case, and it has to look deliberate.

**The decision: keep the letter avatar that already ships, and refine it.** A solid `accent-subtle` circle with the member's first handle character in `accent`, weight 600, centered, sized by the scale in section 3.

Why this is the right default and not a placeholder silhouette:

- **It is never gendered.** A generic person-silhouette default reads as a specific body, usually male-coded, and on a platform built for women that is exactly the wrong signal. A letter has no gender.
- **It is never a stock photo.** Stock-photo defaults are the hallmark of a broken or lazy product and they imply a face the member did not choose.
- **It is identity-bearing and distinct.** The letter is derived from the @handle, which is the identity that leads everywhere in this product, so the default already tells you who you are looking at. Two different members look different at a glance.
- **It looks finished.** A filled accent circle with a clean letter is a deliberate design object, not an absence. The empty profile header reads as a real identity, not a stub (P2 section 9.5 already relies on this).

Deliberate sub-decisions:

- **One tint for everyone, not a per-handle color.** It is tempting to hash the handle into one of several background colors so the wall of defaults has variety. This spec does not do that, for two reasons: it would require introducing a palette of new color tokens (section 14 keeps the token count at zero), and a multi-color scheme is harder to hold to measured contrast in both themes. The single `accent-subtle` fill with the `accent` letter is measured and passes (6.03:1 light, 5.55:1 dark; section 14). If the owner later wants tint variety, it is an additive change that must bring its own measured palette; it is not needed for a good first release.
- **The character is the first character of the @handle, uppercased.** If a handle somehow begins with a non-letter, fall back to the first alphanumeric; if there is none, use a neutral dot glyph rather than an empty circle. (`Avatar.tsx` already uses `?` as the final fallback, which is fine.)
- **The placeholder circle edge is decorative.** The low contrast between the `accent-subtle` fill and the surrounding card (about 1.1:1) is intentional and exempt from the 3:1 non-text rule, because the avatar is identified by the letter inside it, not by its boundary. Where the avatar must separate from a busy background (the profile header over a future banner), the 3px `surface` ring provides the separation.

---

## 6. Upload: entry points, accepted input, limits, and rejection

### 6.1 Entry points

- **Own profile header.** The avatar-xl / avatar-2xl avatar on your own profile gains a small circular **edit affordance**: a `surface-raised` button with a Phosphor `Camera` glyph, pinned to the lower-right of the avatar circle, 32 px, `shadow-e1`, `aria-label` "Change profile photo". Tapping it opens the file picker, then the crop step (section 7).
- **Edit profile dialog.** The existing `EditProfileDialog` (which today edits bio) gains an avatar row at the top: the current avatar at avatar-xl, a "Change photo" button, and, when a photo is set, a "Remove photo" button in `text-secondary` (not danger; removing your own photo is routine, not destructive).
- **First-run nudge, optional and gentle.** The first-session checklist (P2 section 9.6) may include a single "Add a profile photo" step. It is skippable, never blocking, and never implies the account is incomplete without it. The letter default is a legitimate permanent choice, not a gap to be fixed.

### 6.2 The pipeline this reuses, and must not reinvent

Avatar upload rides the exact pipeline in architecture section 3.2: client downsize to 2048 px long edge, `POST /api/media/upload-ticket` (auth, rate-limit, type and size checks), presigned PUT to the **staging** bucket, `POST /api/media/{id}/commit`, then server-side decode, auto-orient, EXIF strip by re-encode, variant generation, PhotoDNA and Hive scanning, write to the **media** bucket, delete staging, mark `scan_status`. Only when `scan_status` becomes `clear` does the avatar become visible; a `blocked` result triggers the CSAM path (auto-suspend, preserve, Owner alert) and nothing is ever served.

The avatar-specific deltas on top of that shared pipeline are only: the crop produces a **square** source (section 7), the stored variants are **small and square** (section 6.6), and the committed key is written to `profiles.avatar_media_key` rather than to `post_media`.

### 6.3 Accepted formats, and why

- **Accepted for upload:** JPEG, PNG, and WebP. These cover every phone and desktop source once the client has re-encoded (below), and `sharp` handles all three natively on the Vercel runtime.
- **HEIC and other phone-native formats:** the client **canvas re-encode step converts them to JPEG or WebP before upload.** iPhones commonly produce HEIC; rather than require server HEIC decoding, the client draws the chosen crop to a canvas and exports a supported format. A side benefit is that the canvas export already drops most metadata on the client, before it ever leaves the device, though the server re-encode in section 2.1 remains the authoritative strip.
- **Static only. No animated avatars.** An uploaded GIF or animated WebP is flattened to its first frame, or rejected with a reason, at the builder's choice; the recommendation is to flatten to the first frame so the upload still succeeds. Animated avatars are declined deliberately: they are a persistent low-grade abuse and distraction vector (flashing, bait-and-switch, seizure risk), and they clash with the product's calm posture. The same decision keeps accessibility simple (no motion to suppress under reduced-motion).
- **Not accepted:** SVG (script and external-reference vector is an upload XSS and SSRF vector and must never be accepted as user image input), TIFF, BMP, and raw camera formats. If one arrives, reject with a reason.
- **Validation is by detected content type, not by the filename extension.** The server sniffs the actual bytes; a `.jpg` that is really something else is rejected. The filename is used only as a weak cross-check and then discarded (section 2.2).

### 6.4 Dimensions and file-size limits

- **Maximum upload size: 8 MB.** Generous for a modern phone photo, small enough to bound abuse. Enforced at the upload-ticket step so an oversized file is refused before it is stored.
- **Minimum source dimensions: 256 by 256 px** (after the client crop). Smaller than that and even the small variants look soft. Rejected with a reason.
- **Maximum pixel count: a hard ceiling (recommend ~50 megapixels) to defuse decompression bombs.** A small file can decode to an enormous raster and exhaust server memory; `sharp` should be configured with a pixel limit and the upload rejected above it. This is a safety limit, not a quality one.
- **The client pre-downsizes to 2048 px long edge** before upload (architecture 3.2 step 1) as a bandwidth courtesy; the server does not depend on it.

### 6.5 Rejection, always with a stated reason

A rejected upload never fails silently or with a generic "error." The crop surface shows an inline message in `danger` on `surface` (measured 5.31:1, section 14) naming the specific problem and the fix:

- Too large: "That image is larger than 8 MB. Try a smaller photo."
- Too small: "That image is too small. Use one at least 256 by 256 pixels."
- Wrong format: "That file type is not supported. Use a JPG, PNG, or WebP image."
- Corrupt or undecodable: "We could not read that image. Try a different file."
- Scan-blocked (the sensitive one): the member is **not** told "your image matched known illegal content." That would both tip off a bad actor and mislabel a false positive. A scan block routes to the CSAM path (auto-suspend, section 2.7 and architecture 3.4); from the member's point of view the upload simply does not complete and their account enters the suspended state with the standard suspended interstitial. Do not surface the scan verdict to the uploader.
- A general soft failure (network, timeout): "Something went wrong uploading that. Please try again." with a retry.

The rejection message appears where the member is looking (in the crop modal or sheet), is announced to assistive technology via a live region, and never blames the member.

### 6.6 Variants produced and stored

The avatar is stored **square** (the crop guarantees this) and served as a circle via CSS. Produce three variants plus a blurhash, sized to the display scale times a 2x to 3x device pixel ratio:

| Variant | Pixels | Serves |
| --- | --- | --- |
| avatar-small | 96 x 96 | xs, sm, md displays (24 to 40 px) at up to 2.4x |
| avatar-medium | 192 x 192 | lg displays (48 px) at up to 4x, and md at 3x |
| avatar-large | 400 x 400 | xl and 2xl profile headers (96 to 128 px) at up to 3x |

Plus a **blurhash** string stored for the avatar, reusing the existing blurhash convention, to paint a soft colored placeholder in the exact average color while the real image loads, so the circle never flashes empty or jumps layout. Encode variants as WebP with a JPEG fallback if the build wants maximum compatibility; at these dimensions each variant is a few kilobytes, so storage and egress are trivial. Keys for each variant derive from the one random avatar key by an opaque suffix (section 2.3), never by anything guessable.

---

## 7. The crop and position step

Every uploaded avatar passes through a crop step. The frame is square (the stored shape), with a circular mask drawn on top so the member previews exactly the circle everyone will see. This resolves the classic surprise where a square crop looks wrong once masked to a circle.

### 7.1 Desktop

A modal (`radius-xl`, `shadow-e3`, scrim `--scrim`) titled "Position your photo":

- The chosen image fills a square crop viewport. A **circular mask** dims everything outside the circle so the member sees the final shape.
- **Drag to reposition** inside the frame; **a zoom slider** (and scroll-to-zoom) to scale the image within the circle. An optional 90-degree **rotate** button handles sideways phone photos that the auto-orient did not catch.
- Controls: "Cancel" (text button, `accent`) and "Save photo" (`accent-fill`, `on-accent`), minimum 44 px targets, in the modal footer. A "Choose a different photo" link re-opens the picker without leaving the modal.
- On Save, the client renders the visible circle's bounding square to a canvas, exports a supported format (section 6.3), and that square becomes the upload source.

### 7.2 Mobile

A full-screen bottom sheet (top corners `radius-2xl`, the sheet-slide-up motion at 320 ms per the motion tokens):

- The same square viewport with circular mask, filling the width.
- **Pinch to zoom and drag to reposition** with touch; a zoom slider is also present for accessibility and for users who cannot pinch.
- A top bar with "Cancel" on the left and "Save" on the right (both 44 px targets), matching the platform's mobile editing pattern, so there is no hunting for the confirm action with a thumb.

### 7.3 What the client produces versus what the server guarantees

The client produces a square, downsized, re-encoded image reflecting the crop. This is a **convenience and a bandwidth optimization, not a security boundary.** The server still performs the authoritative decode, auto-orient, metadata strip by re-encode (section 2.1), and variant generation. A member on a hostile or modified client who bypasses the crop UI and posts arbitrary bytes gets the same server treatment as everyone else: re-encoded, stripped, scanned, or rejected. Never trust the client to have cropped, stripped, or sized anything.

---

## 8. The Avatar component, evolved

The existing `Avatar.tsx` grows from "letter only" to "photo with letter fallback," keeping its current API shape so the dozen call sites do not churn.

- **Props:** it continues to take `handle`, `size`, and `link`. It additionally takes the resolved avatar source (the serving URL or the media key plus variant hint) and the `blurhash`, both optional. When the source is absent, null (self-removed), or withheld (blocked viewer, suspended or banned owner, scan not yet clear), it renders the **letter placeholder** exactly as today. The fallback chain is: served photo if present and permitted and `scan_status = 'clear'`, otherwise the letter placeholder.
- **The photo render is an `<img>`**, circular via `radius-full`, with `width` and `height` set to the chosen pixel size so the layout never shifts, `loading="lazy"` off the first viewport, the blurhash painted underneath (as a tiny background) so the swap is a soft resolve rather than a flash, and `object-fit: cover` as a belt-and-braces guard even though the source is already square.
- **Alt and accessible name.** The avatar's accessible name is the **@handle**, and it is carried once, on the link, exactly as today (`aria-label={`@${handle}`}`). The inner `<img>` therefore gets `alt=""` so a screen reader announces the link as "@handle, link" and not "@handle, image, @handle." When `link={false}` (the surrounding row is the link), the `<img>` is `aria-hidden`, again as today. There is deliberately **no user-provided alt text for avatars**: an avatar's meaning is "this is @handle," and the @handle already says that. (This is different from post images, which carry a real `alt_text` column because their content is arbitrary.)
- **Failure to load.** If the `<img>` errors (network, purged object), the component falls back to the letter placeholder rather than showing a broken-image glyph. A broken image in a thousand feed rows would look like a product failure; the letter never does.
- **Reduced motion.** The blurhash-to-photo transition is a short opacity resolve and is suppressed under `prefers-reduced-motion` (the image simply appears), consistent with the global reduced-motion rule already in `globals.css`.

---

## 9. Reporting an avatar

An avatar is reported through the **report-the-member** flow that already exists (`ReportDialog`, filed via `POST /api/reports`), not through a new parallel flow, because that flow already handles reason selection, optional detail, the calm confirmation, the offer to block on the way out, and the server-computed routing that is identical whoever the accused is (P2 section 10.4 and 10.5). Avatars plug into it like this:

- **Entry.** The profile overflow menu's "Report" item (P2 section 10.1) is the entry point when the thing being reported is the person's photo. When the reported profile has a photo set, the report flow's first screen gains a small line making clear what is in scope: "Reporting @handle. If this is about their profile photo, we will include it." No new menu item; the avatar is simply part of reporting the member.
- **The reason set is the existing one.** The avatar-relevant reasons already exist in the enum and the dialog: `ncii` (sexual content or intimate images without consent), `csam` (sexual content involving a minor), `hate` (a hateful image or symbol), `harassment` (an image used to target someone), `impersonation` (someone else's face used to pose as them), and `other`. No new reason value is needed.
- **Freeze the specific image as evidence.** This is the one real build addition. An avatar can be changed or removed between the report and the review, which would erase the evidence. So at the moment a report is filed against a member who has an avatar, the server **captures the current `avatar_media_key` into the report** and ensures that specific object is **retained and not garbage-collected** while the report is open or actioned, even if the member swaps or removes the avatar afterward. Concretely this means the report needs a reference to the reported avatar object (a column on `reports`, or an evidence row analogous to `message_report_evidence` for DMs), and the cleanup logic in section 2.7 must respect an open report as a retention hold. Flag this to the schema pass; it is the avatar analogue of the DM evidence-freeze that already exists.
- **Subject typing.** The report is filed with `subject_type = 'user'` (the accused is always `subject_user_id`), carrying the frozen avatar reference. A dedicated `report_subject` value for avatars is not required; the frozen-image reference is what distinguishes "I am reporting their photo" from "I am reporting their conduct," and a single report can legitimately be about both.
- **Confidentiality and routing are unchanged.** The accused is never told who reported them; routing is computed server-side; the flow looks identical whether the accused is an ordinary member, a moderator, an admin, or the Owner (P2B, and the owner override that routes Owner-accused reports to the normal admin panel plus the safety@ email copy). Avatars add nothing new here and must not.

---

## 10. How a reported avatar appears to a moderator

Showing a potentially-abusive image to a human is itself a harm, both to the moderator and, for CSAM, a legal-exposure and evidence-handling matter. So the console treats a reported image carefully. This extends the P2B case view; it does not redesign it.

- **Identity strips never show the live photo.** In the moderation console (the case identity strip, the reporter reveal, the in-case thread context) and in the Owner directory, the accused and everyone else are shown with the **letter placeholder**, as stated in section 4. Staff recognize members by @handle, which is the only identity these surfaces carry anyway (the legal-name-never-in-any-mod-surface rule, P2B constraint 0.1). Putting live member photos into enforcement tooling would add a face to a surveillance-adjacent surface for no enforcement benefit and would risk rendering an unreviewed, possibly-illegal image in the chrome.
- **The reported image lives in one dedicated panel, blurred, behind a click-to-reveal.** When a report concerns an avatar, the case detail shows a single "Reported profile photo" panel. The image is rendered **blurred** (using its stored blurhash, so no clear pixels are painted until the moderator acts) with a content-warning line naming the report category ("Reported as: sexual content or harassment"), and a deliberate **"Reveal image" button.** The moderator consents to viewing by clicking; the blur is the default, not an afterthought. This mirrors the calm-console principle from P2B (do not ambush the reviewer) and the founder-welfare concern that human review of harmful imagery is a real occupational hazard (the CSAM-compliance memory).
- **A CSAM-class report never renders the image in the console at all.** A `csam` report (or a PhotoDNA `blocked` result) does not go to the ordinary moderator queue and does not get a reveal button. It auto-escalates to Owner-only, the account is auto-suspended, the media is preserved, and the Owner's NCMEC filing path handles it behind AAL2 step-up (architecture section 3.4, P2B CSAM handling). The ordinary moderator never sees it. This is the existing CSAM posture; avatars route into it unchanged.
- **The franking-style trust marker does not apply.** Avatars are public content, not franked DMs, so there is no "cryptographically verified" badge; the moderator is simply looking at the public image the member published, frozen at report time (section 9).

---

## 11. The moderation removal path for a disallowed avatar

- **Who can remove.** Removing an avatar is a **content removal**, which sits at the `remove_content` rung of the enforcement ladder. Moderators and above can do it (moderators already hold warn / remove content / restrict up to 7 days / escalate). Removing a face image is not a ban; it does not require admin. If the avatar violation also warrants suspension or a ban, those are separate, higher rungs applied by the roles already entitled to them (suspend: moderator up to 7 days, admin beyond; ban: admin only, with the typed-@handle confirmation gate). Removing the avatar and banning the account are distinct actions and the console keeps them distinct.
- **What the member sees afterward.** Their avatar reverts to the **letter placeholder**, and they receive a **system notification** (reusing the notification body mechanism the moderation build added) that states which guideline the image broke and what the consequence is, in the plain, non-lecturing tone of the community guidelines. For example: "Your profile photo was removed because it violated our rule on hateful imagery. You can upload a different photo that follows the guidelines." The member can **upload a new, compliant avatar** immediately; removal of one image does not bar them from having an avatar (unless a suspension or ban independently limits the account).
- **Is removal reversible.** Yes, for an honest mistake. The ladder already includes `reinstate_content`; a wrongly removed avatar can be reinstated by staff, which re-points `avatar_media_key` at the preserved object. This matters because image judgment calls (is this harassment, is this an impersonation) are exactly the kind that get appealed and sometimes overturned, and the appeal path (appeals@unitedfeminist.com, human-reviewed) already exists.
- **The removed image is preserved, never hard-deleted.** A moderator removal is an evidence event. The removed avatar object is retained for the moderation-records window (2 years), and a CSAM-class object is preserved on its 1-year-minimum clock and reported, never deleted. This is the same anti-pattern warning that governs all moderation in this product: the intuitive "detect it and delete it" destroys evidence and, for CSAM, breaks a legal preservation duty. Removal means **remove from public view plus preserve in a locked store**, not purge. The member reverts to the placeholder; the bytes are retained out of their reach.
- **Every removal is audited.** The action writes `moderation_actions` and `append_audit`, as all enforcement does, so the hash-chained log and the daily WORM export cover avatar removals like any other action. No special-casing.

---

## 12. Accessibility

- **Accessible name strategy** is in section 8: the avatar's name is the @handle, carried once on the link, with the inner image `alt=""` to avoid a double announcement, and `aria-hidden` when the row is the link. Avatars carry no user-authored alt text by design, because their meaning is fully captured by the @handle.
- **Placeholder contrast passes AA.** The `accent` letter on the `accent-subtle` fill measures 6.03:1 in light and 5.55:1 in dark (section 14), clearing the 4.5:1 normal-text threshold in both themes at every size on the scale. The placeholder is legible, not decorative mush.
- **Focus state.** An avatar that is a link or button receives the global focus treatment already in `globals.css`: a 2px `--focus-ring` outline at 2px offset on `:focus-visible`. Around a circular avatar this reads as a clean ring and needs no per-component styling. The profile nav avatar's active state (a 2px `accent` ring) is visually distinct from the focus ring (offset, and only on keyboard focus), so selection and focus do not collide.
- **Touch targets.** Bare avatar links are padded to at least 44 by 44 px (section 3), so a 24 or 32 px circle is still comfortably tappable.
- **The edit affordance** (section 6.1) is a real button with an `aria-label` ("Change profile photo"), a 44 px target, and the focus ring; it is not a click-only image overlay.
- **Motion.** There is no avatar animation. The only movement is the blurhash-to-photo opacity resolve, suppressed under `prefers-reduced-motion`. Declining animated avatars (section 6.3) keeps this simple: there is never motion inside an avatar to pause or suppress.
- **The crop step** is operable without a pointer: the zoom slider is a real range input, drag has a keyboard-reachable alternative (arrow-key nudge on the focused frame), and Save and Cancel are focusable buttons. Rejection messages are announced via a live region (section 6.5).
- **Loading** uses the blurhash placeholder rather than a spinner, consistent with the skeletons-not-spinners rule (P2 section 11.1), so nothing flashes and the layout never jumps.

---

## 13. Recommendation: PhotoDNA and automated scanning

This is a recommendation for the owner to decide, not a decision made here.

**Recommendation: adopt scanning before the first avatar goes live. Specifically, Microsoft PhotoDNA plus Cloudflare CSAM scanning (both free) as the known-CSAM layer, with Hive for visual triage of other abuse (nudity, hate symbols), and the whole thing gated so detection and the report-and-preserve path ship together.** Three sentences, as asked: PhotoDNA and Cloudflare CSAM scanning are free and PhotoDNA at upload is the only way to deterministically check every avatar before it is ever servable, which a public, first-ever image feature on a platform that will be probed by bad actors genuinely needs; Hive adds cheap visual triage for the non-CSAM abuse (unsolicited nudity, hateful imagery, impersonation) that avatars will actually attract, metered at about 3 US dollars per thousand images, which at roughly one avatar per member and re-scans only on change is effectively free at founding-cohort scale and single-digit-dollars-per-month for a long time after. The cost read is therefore: PhotoDNA and Cloudflare 0 US dollars, Hive a few dollars a month that scales with upload volume not member count, and the real cost is not money but the engineering and operational obligation that scanning creates.

That obligation is the part the owner must accept with eyes open, and it is why this is a recommendation and not a default:

- **Scanning creates "actual knowledge," which triggers a legal reporting duty.** Under 18 U.S.C. 2258A, proactive scanning is voluntary (verified: the statute does not mandate it), but a positive hit gives the platform actual knowledge, which then triggers the mandatory CyberTipline report. So **detection cannot ship alone.** The avatar feature must not enable scanning until the report-to-NCMEC path and a 1-year-minimum preservation store exist. The good news is that the moderation console and the CSAM event handling the architecture describes are built for exactly this; this feature consumes them, it does not have to build them.
- **Never hard-delete a hit.** The compliant pipeline is remove-from-view, preserve in a locked store, and report. An avatar removal that purges the object is a bug and, for CSAM, a broken legal duty (section 11 states this).
- **Gate the launch of avatars on PhotoDNA approval.** PhotoDNA approval takes roughly a week (two parallel application paths exist: Microsoft directly and the Tech Coalition sublicense). If approval is delayed, do not enable avatar upload with only the Cloudflare cache scan, because cache-based scanning cannot be proven to cover every object; PhotoDNA-at-upload is the control that can.
- **The founder-welfare point is real.** With a small team, a matched or reported image means a human (possibly the owner) looks at harmful content. Design so that human review is rare (automated triage handles the bulk) and, when it happens, is behind the blur-and-reveal and CSAM-never-rendered rules in section 10.

The alternative (ship avatars with no scanning, rely purely on user reports) is not recommended: a public image feature with no proactive layer is below industry standard, "we never looked" is not a defensible posture, and the incremental cost of the recommended stack is close to zero. The honest limit of the recommended stack, stated so it is not oversold: PhotoDNA catches only known hashes, so novel or AI-generated CSAM slips it; Hive is the second visual net for the novel case and is itself imperfect; no stack catches everything, which is why the human report path and the preservation duty remain.

---

## 14. Tokens: zero added, with the measured contrast table

This feature introduces **no new design token.** Confirming each value it touches:

- The placeholder fill is `--accent-subtle` and the letter is `--accent`. Existing.
- The circle mask is `--radius-full`. Existing.
- The profile-header ring is `--surface`. Existing.
- The edit affordance uses `--surface-raised` and `--shadow-e1`. Existing.
- Rejection text is `--danger` on `--surface`. Existing.
- The blurhash placeholder is a per-image computed color, not a token.
- The crop modal and sheet use `--radius-xl`, `--radius-2xl`, `--shadow-e3`, `--scrim`, and the existing motion durations. All existing.
- The size scale in section 3 is a naming layer over pixel values already implemented in `Avatar.tsx`; it is not a set of color or spacing tokens.

**Measured contrast (WCAG 2.x sRGB; method as in P2 section 2.3 and the brand-mark spec section 11):**

| Foreground | Background | Ratio | Threshold | Verdict |
| --- | --- | --- | --- | --- |
| placeholder letter `--accent` light `#6d28d9` | `--accent-subtle` light `#f1e9fd` | 6.03:1 | 4.5 | pass |
| placeholder letter `--accent` dark `#a78bfa` | `--accent-subtle` dark `#2a2140` | 5.55:1 | 4.5 | pass |
| rejection text `--danger` light `#c62828` | `--surface` light `#fbf8f3` | 5.31:1 | 4.5 | pass |
| edit-button glyph `--accent` light | `--surface-raised` light `#ffffff` | 7.10:1 | 3 (graphic) | pass |
| profile-header ring `--surface` light | `--background` light `#f4f0ea` | 1.07:1 | n/a (decorative separator) | the ring separates by lightness step plus the circle edge; it is reinforcement, not the sole identifier |

The placeholder circle edge against a card (about 1.1:1) is decorative and exempt from the 3:1 non-text rule, because the letter inside carries the meaning (section 5).

---

## 15. Build handoff

Context for the later code and schema passes. Not instructions to run now.

**Schema pass must add:**

- A block-aware and status-aware way to resolve `avatar_media_key`, so the real key never reaches a blocked viewer or a viewer of a suspended or banned account (section 2.6, section 2.7). A `SECURITY DEFINER` resolver or an RLS refinement; the UI placeholder fallback is not sufficient alone.
- A reference from `reports` to the reported avatar object, frozen at filing time, plus retention logic that treats an open or actioned report as a hold that blocks cleanup of that object (section 9). This is the avatar analogue of `message_report_evidence`.
- No filename column, ever (section 2.2). No change to `profiles.avatar_media_key` beyond populating it.
- Variant keys and the avatar blurhash: decide whether to extend the avatar record with a blurhash field or compute and store it alongside the key; `post_media` already has a `blurhash` column as the pattern.

**Code pass must build:**

- The avatar-specific upload entry points (section 6.1), the crop modal and sheet (section 7), and the evolved `Avatar` component (section 8), reusing the architecture section 3.2 pipeline for everything server-side.
- The square-source guarantee and the three square variants plus blurhash (section 6.6).
- The staff-surface rule: moderation and owner surfaces render the placeholder, and the case view gets the single blurred click-to-reveal reported-image panel (sections 4 and 10).
- The member-facing removal notice and the self-remove control (sections 6.1 and 11).

**Operational prerequisites (gate avatar launch on these, section 13):** PhotoDNA approval; NCMEC CyberTipline reporting path ready; a 1-year-minimum preservation store; Hive wired for visual triage; Cloudflare CSAM scan enabled on the media zone. These are the same prerequisites the architecture already attaches to Phase 3 media; avatars are the first consumer of them.

---

## 16. What genuinely needs the owner

Short, and only the things this design cannot settle. Each has a marked recommendation.

1. **Adopt the scanning stack for images.** Should the platform turn on PhotoDNA plus Cloudflare CSAM scanning plus Hive triage at upload, accepting the reporting-and-preservation duty that scanning creates?
   - (a) **Yes, the recommended stack, and gate avatar launch on PhotoDNA approval.** [recommended]
   - (b) Known-CSAM scanning only (PhotoDNA plus Cloudflare), skip Hive visual triage for now.
   - (c) No proactive scanning; rely on user reports only. [not recommended]

2. **Avatar serving model.** Serve avatars as public-with-unguessable-key through the Cloudflare edge cache (fast, cheap, matches post media), accepting that someone who already holds the exact URL can fetch the image?
   - (a) **Yes, public-with-unguessable-key.** [recommended]
   - (b) Route avatars through the DM-style signed-token Worker (more private, loses edge caching on the most-rendered image in the product).

Everything else in this document is a design decision already made here, with its reasoning, and does not need the owner's input to proceed.

---

## 17. Out of scope, deliberately

- **Profile banner or cover images.** This spec is avatars only. A banner is a second, larger image surface with its own crop ratio and its own leak profile; it is a separate feature. The profile header's 3px avatar ring already anticipates a banner behind it if one is ever added, but nothing here builds one.
- **Post images, DM images, and any inline media.** Those ride the same architecture section 3.2 pipeline but are separate features with separate UI; the DM-image question in particular is explicitly gated behind the E2E preconditions in P2C and is not reopened here.
- **Per-handle placeholder tint variety, facepile stacks, and avatar decorations or frames.** Named as additive future options in section 5; not needed for a good first release and each would have to bring its own measured tokens.
- **Animated avatars.** Declined on purpose (section 6.3), not deferred.
- **The actual image assets, the component code, the API routes, and the database migration.** This is a design specification; those are the code and schema passes it hands off to in section 15.
- **The GIF-versus-reject micro-decision for animated uploads** is left to the builder with a stated default (flatten to first frame), because it is an implementation detail with no product-visible consequence either way.

Design done.
