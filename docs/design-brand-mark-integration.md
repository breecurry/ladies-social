# Hersciety: Brand-Mark Integration Spec

**Status:** Design specification. A real logo now exists, committed by the owner as `c5554c2` ("hersciety-logo-v1"). This document defines exactly how that mark enters the product: where the wordmark appears, how it behaves across light and dark themes, how a standalone app icon is derived from it, the full set of asset files to produce, and the metadata wiring to add. It is a specification, not an implementation. A code agent should be able to build the integration from this plus the existing token system without making judgment calls. This document creates no application code and no image assets; it specifies them for a later, separate build pass.

**Date:** 2026-10-08

**Design thesis (inherited, not reopened):** "Calm paper, sharp tools." Warm, low-glare sand neutrals carry content; one Iris-violet accent carries interaction. See `docs/design-phase2-social-core.md`. This spec integrates a brand mark into that system. It does not redesign it.

**Locked context (do not reopen):** Purple is the brand; the owner settled the question by action when she made the logo purple. The warm-neutral plus single-violet-accent palette stays. The app shell (desktop left rail plus centred column; mobile five-slot bottom tabs with a thin top bar) is shipped and is not redesigned here. This spec adds a mark; it changes no layout.

---

## 0. How to read this document

- **Tokens** are the ones implemented in `src/app/globals.css`, named exactly as the CSS custom properties there (for example `--accent`, `--background`, `--surface`, `--accent-subtle`). This spec adds zero new tokens. Section 10 confirms that.
- **Contrast** is the WCAG 2.x method throughout. Every ratio in this document is a computed number, not an assertion. The method and the full measured table are in section 11, so any claim here can be reproduced. Pass thresholds: 4.5:1 for normal text, 3:1 for large text (greater than or equal to 18.66px bold or 24px regular) and for non-text graphics and UI boundaries that are the sole identifier of meaning. A logo is a graphic, so the governing floor for the mark itself is 3:1, but this spec holds the wordmark to the normal-text 4.5:1 bar wherever it can, because the mark should never be the weakest thing on a surface.
- **Colours** are written as lowercase hex. The logo fill is `#6901E2`. The light accent token is `#6d28d9`. These are different values on purpose; section 2 explains why.
- **House style:** plain prose, ASCII only. References to other specs read as "P2 section X" for `design-phase2-social-core.md`.

### 0.1 What exists today, and what does not

Verified against the repository at `c5554c2`:

- The logo file is committed as `hersciety`, with no file extension, at the repository root. It is actually a PNG. Next.js cannot serve a brand asset from that path.
- There is no `public/` directory in the project at all.
- There is no favicon, no `icon.png`, no `apple-icon`, no `opengraph-image` anywhere. The app has never rendered a brand mark.
- The word "Hersciety" currently renders as plain text, not as a mark, in four places: the desktop left rail top (a `text-heading` link to `/home` in `src/components/shell/AppShell.tsx`), the mobile top bar on the home screen (a `text-heading` span, same file), the public signed-out header (a `text-heading` link in `src/components/SiteHeader.tsx`), and the landing page hero (a `text-display` heading in `src/app/(public)/page.tsx`).
- `src/app/layout.tsx` has a `metadata` export with `title`, `description`, and `robots`, but no `icons` block, no `openGraph` block, and no `metadataBase`.

### 0.2 The measured asset facts (do not re-derive)

Confirmed from the committed file this session:

- PNG, 2076 by 758 px, 8-bit RGBA, non-interlaced, 507,009 bytes.
- Aspect ratio 2.7388 to 1 (call it 2.74:1).
- Fully transparent background. Single flat fill plus antialiasing.
- Fill colour sampled from the pixels: `#6901E2`.
- It is a wordmark only: the word "Hersciety" set in a rounded, friendly, bubble-like typeface. There is no separate symbol.
- The dot over the "i" is a small speech bubble (a rounded blob with a tail pointing down-left). This is the only standalone-mark candidate in the asset.

---

## 1. Summary of decisions

For the reader who wants the answers before the reasoning:

1. **Logo fill versus UI token:** leave them different. Keep `--accent #6d28d9` exactly as it is. Let the wordmark carry its own `#6901E2`. The logo fill is more legible on light surfaces than the token it sits near, and reconciling them would force a re-measurement of the entire contrast table for no benefit. See section 2.
2. **Dark mode:** `#6901E2` is unreadable on the dark background (2.38:1). The wordmark must appear in dark mode as a lighter variant rendered in the existing dark accent `#a78bfa` (6.80:1). See section 3.
3. **The icon:** the speech-bubble dot works as a standalone mark. Render it as a white bubble on a filled `#6901E2` tile (7.77:1 internal contrast). It reads at 16, 32, and 180 px. See section 4.
4. **Placement:** the wordmark replaces the four text instances listed in 0.1, at specified sizes, with defined clear-space and a minimum rendered width. Empty states keep their contextual Phosphor glyphs; the brand mark does not appear in them. See section 5.
5. **Asset manifest:** two wordmark PNGs, three to four icon files, one Open Graph image, plus metadata wiring. See sections 6 and 7.
6. **Format and weight:** 507 KB is roughly ten to fifty times heavier than necessary. Per-asset weight targets are specified. A vector source is desirable but not required; the spec works either way, and the lines that change if an SVG arrives are marked. See section 8.
7. **Accessibility:** alt text per placement; no logo animation; a forced-colors note. See section 9.

---

## 2. Logo fill versus the UI accent token

**The question.** The wordmark PNG is filled with `#6901E2`. The design system's interactive accent is `--accent #6d28d9` (light) and `--accent #a78bfa` (dark). Should these be reconciled to a single value, or allowed to differ?

**The decision: allow them to differ. Do not touch any token.**

A logo fill and a UI token are two different kinds of object. The logo fill is a fixed property of a brand asset; it is baked into the PNG and is rendered by the asset, not produced by the CSS. The UI token is a system variable that drives dozens of composed pairings whose contrast has already been measured and tuned. There is no technical need for the asset's baked colour to equal the token, and there is a real cost to forcing it.

**The measured case for leaving the token alone.** The two values are the same indigo-violet hue family; `#6901E2` is simply more saturated (its green channel is 1 versus the token's 40) and marginally more blue. On the surfaces where the wordmark actually sits, the logo fill is not merely acceptable, it is slightly stronger than the token it neighbours:

| Foreground | Background | Ratio | Verdict |
| --- | --- | --- | --- |
| logo `#6901E2` | background `#f4f0ea` | 6.84:1 | pass (exceeds the token's 6.26 on the same background) |
| logo `#6901E2` | surface `#fbf8f3` | 7.33:1 | pass |
| logo `#6901E2` | surface-raised `#ffffff` | 7.77:1 | pass |
| logo `#6901E2` | accent-subtle `#f1e9fd` | 6.59:1 | pass |
| token `#6d28d9` | background `#f4f0ea` | 6.26:1 | pass (for comparison) |

So in light mode the wordmark clears the normal-text 4.5:1 bar on every surface it can land on, with headroom, and it is actually a touch more legible than the accent token. There is no legibility reason to change the token to match the logo.

**The cost of changing the token, stated plainly.** If `--accent` were swapped to `#6901E2`, every pairing that token participates in would have to be re-measured in both themes, because contrast depends on the token's luminance and `#6901E2` has a different luminance than `#6d28d9`. The affected pairings include, at minimum: accent on surface, accent on background, accent on surface-raised, accent on accent-subtle, white on the accent fill (buttons), the focus ring, and the `--thread-rail` derived value. Several of these were tuned to pass; a silent luminance change risks pushing one under its threshold without anyone noticing. That is a large, system-wide re-verification for a change that buys nothing, because the wordmark already passes as-is. **Recommendation: leave `--accent`, `--accent-hover`, `--accent-fill`, `--accent-subtle`, and `--focus-ring` exactly as they are in both themes.**

**The one place the two violets sit side by side.** In the desktop left rail, the wordmark (`#6901E2`) will sit a few pixels above nav items whose active state uses `--accent #6d28d9`. Two near-identical violets are adjacent. This reads as brand richness, not as a bug: the saturation difference is small, and a user is rarely looking at the wordmark and an active nav label with enough acuity to compare them at the same instant. Keep the wordmark at its true `#6901E2`; brand integrity is worth more than making two purples identical. If, at build time, the adjacency genuinely looks like a rendering error, the correct remedy is not a token swap but rendering the chrome wordmark through an alpha mask filled with `--accent` so it matches exactly; that remedy sacrifices the brand colour, so it is a fallback of last resort, not the plan.

---

## 3. Dark mode

**The risk.** A saturated violet on a near-black background is a known legibility failure. The dark background token is `#16130f`.

**The verdict: the raw logo fill is unreadable in dark mode and must not be rendered there.**

| Foreground | Background | Ratio | Verdict |
| --- | --- | --- | --- |
| logo `#6901E2` | dark background `#16130f` | 2.38:1 | fail (below the 3:1 large-text floor) |
| logo `#6901E2` | dark surface `#201c17` | 2.18:1 | fail |
| logo `#6901E2` | dark surface-raised `#2a251f` | 1.95:1 | fail |
| logo `#6901E2` | dark accent-subtle `#2a2140` | 1.94:1 | fail |

`#6901E2` fails on every dark surface, and fails badly: at 2.38:1 it is below even the relaxed 3:1 threshold that large text and graphics are allowed. The baked violet wordmark would be a dim smudge in dark mode. It cannot be used there.

**The specification for dark mode: render the wordmark in the existing dark accent.**

In dark mode the wordmark appears in `#a78bfa`, which is the system's existing dark `--accent` value. No new colour is introduced.

| Foreground | Background | Ratio | Verdict |
| --- | --- | --- | --- |
| `#a78bfa` | dark background `#16130f` | 6.80:1 | pass |
| `#a78bfa` | dark surface `#201c17` | 6.22:1 | pass |

Choosing `#a78bfa` is deliberate, not arbitrary. At 6.80:1 on the dark background it matches the light wordmark's 6.84:1 on the light background almost exactly, so the mark carries the same perceived strength in both themes. And because `#a78bfa` is the exact value the rest of the dark UI already uses for its interactive accent, the wordmark reads as native to dark mode rather than pasted on top of it.

If the owner later wants the logo to pop harder in dark mode, the brighter alternative is `#c4b5fd` (the existing dark `--accent-hover`), which measures 10.03:1 on the dark background. That is an optional taste choice, not a correctness requirement; the default is `#a78bfa`.

**How the dark variant is produced.** Because the source is a flat single fill on transparency, its alpha channel is a clean silhouette of the wordmark. The dark asset is generated by taking that alpha channel and filling it with `#a78bfa`, which preserves the antialiasing perfectly. This is a deterministic image operation, not a redraw. If a vector source arrives, the recolour is trivial (`fill` or `currentColor`) and no second raster is needed; see section 8.

**How the theme swap is wired (no new tokens).** The app already supports both a system preference and a manual override: `globals.css` applies dark values under `@media (prefers-color-scheme: dark) :root:not([data-theme="light"])` and under `[data-theme="dark"]`, and `layout.tsx` sets `data-theme` from `localStorage` before first paint. The wordmark swap must mirror those exact selectors so a manual override is honoured, not just the system preference. Ship both `wordmark-light.png` and `wordmark-dark.png` and toggle their visibility with CSS that copies the token logic:

```css
/* To be added to globals.css by the code pass. These are display rules,
   not colour tokens; no new design token is introduced. */
.brand-wordmark .is-dark { display: none; }
.brand-wordmark .is-light { display: inline-block; }

@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) .brand-wordmark .is-light { display: none; }
  :root:not([data-theme="light"]) .brand-wordmark .is-dark { display: inline-block; }
}
[data-theme="dark"] .brand-wordmark .is-light { display: none; }
[data-theme="dark"] .brand-wordmark .is-dark { display: inline-block; }
```

Do not use `<picture>` with only a `prefers-color-scheme` media query for this; it would ignore the manual `[data-theme]` override and show the wrong wordmark for anyone who has toggled the theme by hand.

---

## 4. The standalone mark: the speech bubble

**The problem.** A 2.74:1 wordmark is unreadable at favicon and app-icon sizes. A browser tab favicon is 16 to 32 px square; the word "Hersciety" squeezed into a 32 px-wide, roughly 12 px-tall strip is illegible mush. The product needs a square-ish standalone mark, and the asset contains exactly one candidate: the speech-bubble dot over the "i".

**The verdict: yes, the speech bubble works as the standalone mark. Use it.**

It is the right choice for three reasons. It is square-ish, so it survives square icon frames where the wordmark cannot. It is meaningful: a speech bubble reads instantly as "social" and "conversation", which is precisely what this product is. And it is already part of the owner's own logo, so the icon and the wordmark are visibly one family rather than two unrelated marks.

**Construction.** Isolate the speech-bubble blob (the rounded body plus its down-left tail) from the wordmark glyphs. This is a dedicated small render, authored at icon scale; it is not a crop-and-downscale of the full wordmark, because downscaling the 2.74:1 wordmark to icon size would drag the rest of the word along and defeat the purpose. The bubble is the whole icon.

**Tile, not transparency.** The mark sits as a white bubble knocked out of a filled `#6901E2` square tile. Filled, not transparent, for concrete reasons: a transparent favicon disappears against browser chrome of a similar colour; a transparent Apple touch icon is composited onto black by iOS and looks broken; and a filled tile gives the mark a consistent, recognisable brand colour everywhere it appears. The internal contrast of the mark is excellent:

| Foreground | Background | Ratio | Verdict |
| --- | --- | --- | --- |
| white bubble | `#6901E2` tile | 7.77:1 | pass, far above the 3:1 graphic floor |
| cream `#f4f0ea` bubble | `#6901E2` tile | 6.84:1 | pass (alternative knockout colour) |

Use white for the knockout; it is the stronger and cleaner reading, and white on `#6901E2` is the same 7.77:1 as the wordmark on white, so the two assets feel measured the same way. The tile colour is the logo's own `#6901E2`, not the `#6d28d9` token, so the icon and the wordmark share one brand fill.

**Padding and safe area.** The bubble occupies a centred safe area of roughly 62 percent of the tile for the browser favicon (`icon.png`), and roughly 60 percent for the Apple touch icon, which iOS further insets when it rounds the corners. The tail points down-left, so optical centring will nudge the bubble very slightly up and to the right of geometric centre so the composition does not look bottom-heavy. Do not pre-round the tile's corners and do not pre-pad it to simulate rounding: deliver a full-bleed square tile and let each platform apply its own masking (iOS rounds; Android may apply a maskable shape; browsers show the square as-is).

**Does it read at 16, 32, and 180 px?** Yes, with one proviso at the smallest size. At 180 px (Apple touch icon) the bubble and its tail are unmistakable. At 32 px (standard favicon) the silhouette is crisp and clearly a chat bubble. At 16 px (small favicon) the live area is only about 10 px and the fine tail nub can merge into the body. A favicon is permitted to be a simplified rendition of the mark, so for the 16 px size the tail should be thickened and the corner radius slightly enlarged so the shape stays a legible bubble rather than a rounded square. This is a normal favicon practice and is why the manifest includes a multi-resolution `favicon.ico` whose 16 px frame is drawn a little heavier than a naive downscale. With that proviso, the mark reads at all three sizes.

**If the bubble ever failed (it does not, but for completeness).** The only reason to abandon it would be if it could not be distinguished from a generic rounded square at 16 px. The thickened-tail rendition resolves that, so no alternative mark is needed. If a future review disagreed, the fallback would be a monogram tile (a single bubble-face "H" knocked out of the `#6901E2` tile), which carries the same colours and the same construction and would measure identically. Do not build the fallback now; the bubble is the mark.

---

## 5. Placement

The wordmark replaces the four plain-text instances of "Hersciety" identified in 0.1. Sizes are given as rendered height; width follows from the 2.74:1 aspect ratio (width equals 2.74 times height). The shell is not changed; only the text node inside each existing slot becomes the mark.

**5.1 Desktop left rail (greater than or equal to lg).** Today a `text-heading` link to `/home` sits at the top of the rail with `px-3` and `mb-4`. Replace the text with the wordmark at **22 px tall (about 60 px wide)**, still linking to `/home`, still left-aligned at the existing 12 px inset. The rail is 240 px wide, so there is ample room. Keep the existing 16 px gap below it to the first nav item; that satisfies the clear-space rule below.

**5.2 Mobile top bar on the home screen.** Today a `text-heading` span shows "Hersciety" on the home screen only (other screens show a back affordance). Replace it with the wordmark at **20 px tall (about 55 px wide)**, vertically centred in the 48 px bar, at the existing 8 px inset. The bar's other screens are unchanged. Do not place the wordmark on non-home screens; the back affordance and screen title stay as specified in P2 section 1.3.

**5.3 Public signed-out header.** Today a `text-heading` link to `/` sits in `SiteHeader`. Replace it with the wordmark at **22 px tall (about 60 px wide)**, linking to `/`. This header is the primary brand surface for logged-out visitors on `/`, `/login`, `/signup`, and the legal pages, all of which render inside the public layout and share this header.

**5.4 Landing hero (`/`).** Today the landing page opens with a `text-display` (34 px) heading reading "Hersciety". Replace that heading's text with the wordmark rendered large and responsive: **height `clamp(44px, 10vw, 72px)`**, which is about 120 to 197 px wide. This is the single largest rendering of the mark and the brand's loudest statement on the site. The accessible heading is preserved by placing the mark inside the `<h1>` as an image whose `alt` is "Hersciety" (section 9), so the page keeps exactly one `h1` and loses no SEO or screen-reader value.

**5.5 Login and signup pages.** These sit inside the public layout and already carry the wordmark through the shared header (5.3). They need no additional mark of their own. The login page keeps its `text-title` "Log in" heading and the signup page keeps its form; do not add a second wordmark to the page body.

**5.6 Empty states.** Empty states (for example the empty feed) use contextual Phosphor glyphs today, such as `ChatsCircle`. Keep them that way. The brand mark does not belong in generic empty states; putting it there would be branding noise and would compete with the contextual glyph that is doing the real communicative work. This is a deliberate decision, not an omission: the standalone speech-bubble mark lives in the icon and metadata assets, and the wordmark lives in chrome and marketing, and neither appears inside product empty states.

**5.7 Clear-space.** Maintain clear space around the wordmark equal to at least half its rendered height on every side, and never less than 12 px in chrome or 24 px around the landing hero. At the 22 px chrome size that is about 11 px, which the existing layout spacing already provides.

**5.8 Minimum rendered width.** Do not render the wordmark below **52 px wide (about 19 px tall)** anywhere; below that the rounded bubble letterforms close up and the word stops reading. The chrome sizes above (55 to 60 px) sit just above that floor on purpose. For any marketing or hero use, prefer 88 px wide or more.

---

## 6. Asset manifest

Every file to produce, with exact name, pixel dimensions, format, destination, and weight target. All colours are baked into the asset as specified; none are produced by CSS. The wordmark assets go in a new `public/` directory (which does not exist yet and must be created). The icon and Open Graph assets use the Next.js App Router file conventions inside `src/app`, where Next detects them automatically.

**Wordmark (chrome and marketing):**

| File | Dimensions | Format | Fill | Background | Weight target |
| --- | --- | --- | --- | --- | --- |
| `public/wordmark-light.png` | 1024 x 374 | PNG, 8-bit alpha | `#6901E2` | transparent | 40 KB or less |
| `public/wordmark-dark.png` | 1024 x 374 | PNG, 8-bit alpha | `#a78bfa` | transparent | 40 KB or less |

Both are the full wordmark, trimmed tightly to the glyph bounds (no baked padding; clear-space is handled in layout, section 5.7), at the native 2.74:1 ratio. The 1024 px width is a generous master: the largest on-screen render is the landing hero at about 197 px, so 1024 px over-samples it comfortably and stays sharp at every placement. The dark asset is the light asset's alpha channel filled with `#a78bfa` (section 3).

**Icon set (standalone speech-bubble mark):**

| File | Dimensions | Format | Composition | Weight target |
| --- | --- | --- | --- | --- |
| `src/app/icon.png` | 512 x 512 | PNG | white bubble in 62% centred safe area on a full-bleed `#6901E2` tile, no baked corner rounding | 15 KB or less |
| `src/app/apple-icon.png` | 180 x 180 | PNG, no alpha | white bubble in 60% safe area on a full-bleed `#6901E2` tile, no transparency, no pre-rounding | 10 KB or less |
| `src/app/favicon.ico` | 16, 32, 48 (multi-res) | ICO | white bubble on `#6901E2`; the 16 px frame drawn with a thickened tail and larger corner radius (section 4) | 15 KB or less |

The `favicon.ico` is recommended rather than strictly required (modern browsers use `icon.png`), but it is cheap and it covers legacy browsers and the exact 16 px case that needs the heavier rendition, so include it.

**Social sharing:**

| File | Dimensions | Format | Composition | Weight target |
| --- | --- | --- | --- | --- |
| `src/app/opengraph-image.png` | 1200 x 630 | PNG | warm cream `#f4f0ea` field, the `#6901E2` wordmark centred with generous clear-space, optional one-line tagline below in `#5a5247` (text-secondary) | 150 KB or less |

1200 by 630 is the universal Open Graph and `summary_large_image` Twitter card size and works across every major platform. Next.js detects `opengraph-image.png` and emits both the `og:image` and the Twitter image tags from it, so no separate `twitter-image` file is needed. The tagline, if used, should be short and can draw from the existing site description ("A safe space for women and their allies"); it is editable copy, not a design dependency. The wordmark on cream measures 6.84:1 and the optional tagline in text-secondary on cream is well above 4.5:1 (section 11).

**Optional, deferred (PWA installability):**

| File | Dimensions | Format | Composition | Weight target |
| --- | --- | --- | --- | --- |
| `public/icon-maskable-512.png` | 512 x 512 | PNG | white bubble inside the 80% (about 409 px) maskable safe zone on a full-bleed `#6901E2` tile | 15 KB or less |

This plus a web app manifest would let the app be installed to a home screen with a correctly masked icon. It is a nice-to-have, not part of the core integration; build it only if home-screen installability becomes a goal. If it is built, add a `src/app/manifest.ts` (Next.js manifest convention) referencing this icon, `#f4f0ea` as `background_color`, and `#16130f` or `#6901E2` as `theme_color`. Do not add it now without that decision.

---

## 7. Metadata wiring in `src/app/layout.tsx`

Written so a code agent can implement it without judgment calls.

**What Next.js wires automatically.** Because `src/app/icon.png`, `src/app/apple-icon.png`, `src/app/opengraph-image.png`, and `src/app/favicon.ico` use the App Router file conventions, Next.js emits the corresponding `<link rel="icon">`, `<link rel="apple-touch-icon">`, `og:image`, and Twitter image tags on its own. Do not add an `icons` object or an `openGraph.images` array to the `metadata` export for these; that would duplicate what the file convention already produces. Just creating the files is enough for those tags.

**What to add by hand.** Three things the file conventions do not supply: a `metadataBase` so relative OG and icon URLs resolve to absolute ones, the non-image Open Graph fields, and the Twitter card type. Add them to the existing `metadata` export; leave `title`, `description`, and the `robots`/`SITE_INDEXABLE` logic exactly as they are.

```ts
export const metadata: Metadata = {
  metadataBase: new URL("https://www.hersciety.com"),
  title: {
    default: "Hersciety",
    template: "%s · Hersciety",
  },
  description:
    "A social platform built as a safe space for women and their allies. Open to everyone 18 and over; bullying and harassment are never tolerated.",
  openGraph: {
    type: "website",
    siteName: "Hersciety",
    title: "Hersciety",
    description:
      "A social platform built as a safe space for women and their allies. Open to everyone 18 and over; bullying and harassment are never tolerated.",
    url: "https://www.hersciety.com",
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
    title: "Hersciety",
    description:
      "A social platform built as a safe space for women and their allies. Open to everyone 18 and over; bullying and harassment are never tolerated.",
  },
  robots: SITE_INDEXABLE ? undefined : { index: false, follow: false },
};
```

**An accessible name for the Open Graph image (optional but recommended).** Alongside `src/app/opengraph-image.png`, a sibling `src/app/opengraph-image.alt.txt` (or an `alt` export in a `opengraph-image.tsx`) lets Next.js emit `og:image:alt`. Set it to "Hersciety: a safe space for women and their allies." This is the accessible description of the share card.

**The `viewport.themeColor` block stays as it is.** It already declares `#f4f0ea` for light and `#16130f` for dark, which is correct and unrelated to the mark.

**Do not confuse `metadataBase` with search visibility.** Setting `metadataBase` and the Open Graph fields does not make the site indexable; the existing `SITE_INDEXABLE` flag and the robots logic continue to govern that, untouched. These additions only make share cards and icons resolve correctly if and when the site is shared or indexed.

---

## 8. Format and weight

**507 KB is far too heavy.** A flat two-colour wordmark on transparency should be tens of kilobytes at most. The per-asset targets in section 6 (40 KB for each wordmark, 10 to 15 KB per icon, up to 150 KB for the larger Open Graph canvas) are what a correctly exported PNG of this content weighs. The committed 507 KB file is an unoptimised export; none of the delivered assets should inherit its size. Running the produced PNGs through a lossless optimiser (the kind of pass that strips metadata and re-encodes the palette) will reach these targets comfortably.

**The "raster softens on retina" premise needs correcting, honestly.** The source is 2076 px wide. Every on-screen placement in this spec is a downscale of that master (the largest, the landing hero, is about 197 px, roughly a ten-times reduction). Downscaling raster is sharp; it is upscaling that softens, and nothing here upscales past the source width. So for the wordmark at all its placements, raster is not a sharpness problem. The genuine costs of raster are two, and they are narrower than "it will look soft everywhere": first, file weight, addressed above; and second, the icon, which is a separately authored small render where clean edges at 16 and 32 px are easier to control from a vector master than from a downscaled raster.

**Is a vector (SVG) source needed?** It is desirable but not required. What an SVG source would buy: a file weight of a few kilobytes instead of hundreds; a single themeable wordmark asset (one SVG recoloured per theme with `currentColor` or `fill`, replacing the two PNGs); and a clean vector master from which to author the icon crisply at the smallest sizes. What it would not buy: meaningfully sharper chrome rendering, because the 2076 px raster already over-samples every placement. So the honest framing is: SVG is a convenience and a weight win, not a correctness requirement. The product looks right with raster assets.

**The spec works either way. What changes if an SVG arrives:**

- The two wordmark PNGs (`public/wordmark-light.png`, `public/wordmark-dark.png`) collapse to one `public/wordmark.svg` using `currentColor`. The per-theme colour is then set in the component: `#6901E2` in light and `#a78bfa` in dark, applied through the same selector logic in section 3. The two-PNG swap is no longer needed.
- The icon set (`icon.png`, `apple-icon.png`, `favicon.ico`, and any maskable icon) is authored from the vector master rather than from the raster, which makes the thickened-tail 16 px rendition cleaner, but the delivered files and their dimensions are unchanged (platforms still want PNG and ICO; Next.js can also take an SVG `icon.svg`, but PNG is the safe, universal choice and is what this manifest specifies).
- Everything else in this document, placement, sizes, clear-space, contrast, and metadata, is identical.

**One cleanup to flag for the code pass (not part of this doc).** Once the real assets exist, the committed `hersciety` file at the repository root (507 KB, no extension, unservable) should be removed or relocated. That is a code-pass action in `src/`-adjacent territory and is explicitly out of scope for this document; it is noted here so it is not forgotten.

---

## 9. Accessibility

**9.1 Alt text per placement.**

| Placement | Element | Alt or accessible name |
| --- | --- | --- |
| Desktop left rail | wordmark image inside the link to `/home` | `alt="Hersciety"` |
| Mobile top bar (home) | wordmark image | `alt="Hersciety"` |
| Public header | wordmark image inside the link to `/` | `alt="Hersciety"` |
| Landing hero | wordmark image inside the `<h1>` | `alt="Hersciety"` (this is the page's `h1` text; do not add a second visible or hidden heading) |
| Standalone icon used in UI (if ever) | image or SVG | `aria-label="Hersciety"` |
| Favicon, Apple touch icon | n/a | not applicable; favicons have no alt mechanism |
| Open Graph image | `og:image:alt` via the Next.js alt convention | "Hersciety: a safe space for women and their allies." |

Where the wordmark is a link (rail, header, hero), `alt="Hersciety"` serves as both the brand name and the link's accessible name; that is correct and should not be padded with "logo" or "home". Do not mark the wordmark image `aria-hidden` on the hero, because then the `h1` would have no accessible text.

**9.2 Reduced motion.** The mark does not animate. There is no spin-in, no shimmer, no pulse on load, in any placement. This is a deliberate rule: a brand mark that moves on every page load is noise, and the product's whole posture is calm. Because the mark adds no animation, there is nothing for `prefers-reduced-motion` to suppress here; the existing global reduced-motion rule in `globals.css` remains sufficient and the logo contributes no exception to it.

**9.3 Forced colors and high contrast.** This is the one accessibility nuance worth specifying. Rendering the wordmark and icon as `<img>` elements (the path this spec recommends) is the safe choice for Windows High Contrast and other `forced-colors` modes: user-agents leave raster images alone in forced-colors, so the white-on-`#6901E2` icon keeps its 7.77:1 internal contrast and the wordmark keeps its shape, and the `alt` text is always available to anyone whose setup suppresses the image. The alternative of painting the mark with a CSS `mask-image` or `background-image` is explicitly not recommended, because `forced-colors: active` strips CSS background images and the mark could vanish with no text fallback. If, for the SVG single-asset path, a `currentColor` inline SVG is used, keep it as inline SVG (which forced-colors maps to the user's colours and keeps visible) rather than a CSS background, and keep the `alt`/`aria-label` on it regardless. The practical rule: the mark must always have a text equivalent, and it must never be painted in a way that a forced-colors user cannot see.

---

## 10. Tokens: zero added

This integration introduces no new design token. Confirming each colour it touches:

- The light wordmark colour `#6901E2` is baked into the asset. Not a token.
- The dark wordmark colour `#a78bfa` is the existing dark `--accent`. Reused, baked into the dark asset. Not new.
- The icon tile `#6901E2` and the white knockout are baked into the icon assets. Not tokens.
- The Open Graph background `#f4f0ea` is the existing `--background` light value; the optional tagline uses `#5a5247`, the existing text-secondary light value. Reused.
- The theme-swap CSS in section 3 is display rules (which image shows), not colour tokens.

So the manifest can be built, and the metadata wired, without editing the token block in `globals.css` at all beyond the small display-rule CSS block in section 3, which adds no `--` colour variable.

---

## 11. Contrast method and full measured table

**Method.** All ratios use the WCAG 2.x relative-luminance formula on sRGB. For each 8-bit channel value `c`, compute the channel fraction `cs = c / 255`, then linearise: `lin = cs / 12.92` when `cs <= 0.03928`, otherwise `lin = ((cs + 0.055) / 1.055) ^ 2.4`. Relative luminance is `L = 0.2126*R_lin + 0.7152*G_lin + 0.0722*B_lin`. The contrast ratio between two colours is `(L_lighter + 0.05) / (L_darker + 0.05)`. A ratio is reported to two decimals. Pass thresholds: 4.5:1 normal text, 3:1 large text and non-text graphics.

**Every pairing claimed in this document:**

| Foreground | Background | Ratio | Threshold | Verdict |
| --- | --- | --- | --- | --- |
| logo `#6901E2` | background `#f4f0ea` | 6.84:1 | 4.5 | pass |
| logo `#6901E2` | surface `#fbf8f3` | 7.33:1 | 4.5 | pass |
| logo `#6901E2` | surface-raised `#ffffff` | 7.77:1 | 4.5 | pass |
| logo `#6901E2` | accent-subtle `#f1e9fd` | 6.59:1 | 4.5 | pass |
| logo `#6901E2` | dark background `#16130f` | 2.38:1 | 3 | fail |
| logo `#6901E2` | dark surface `#201c17` | 2.18:1 | 3 | fail |
| logo `#6901E2` | dark surface-raised `#2a251f` | 1.95:1 | 3 | fail |
| logo `#6901E2` | dark accent-subtle `#2a2140` | 1.94:1 | 3 | fail |
| dark wordmark `#a78bfa` | dark background `#16130f` | 6.80:1 | 4.5 | pass |
| dark wordmark `#a78bfa` | dark surface `#201c17` | 6.22:1 | 4.5 | pass |
| brighter dark `#c4b5fd` | dark background `#16130f` | 10.03:1 | 4.5 | pass |
| white | `#6901E2` icon tile | 7.77:1 | 3 | pass |
| cream `#f4f0ea` | `#6901E2` icon tile | 6.84:1 | 3 | pass |
| accent token `#6d28d9` | background `#f4f0ea` | 6.26:1 | 4.5 | pass (reference) |

The dark-mode fails in the table are the reason the wordmark is not rendered in `#6901E2` on dark surfaces; the `#a78bfa` row is what it uses instead. Every value a produced asset actually relies on passes its threshold.

---

## 12. What genuinely needs the owner

Checked against the locked decisions, with everything already settled stripped out. Do not re-raise purple as the brand, the palette, or the shell; those are closed.

1. **Does a vector source exist?** The single real question. If the owner has an SVG, AI, Figma, or Canva source for the wordmark, it collapses the two wordmark PNGs to one themeable asset, drops the weight to a few kilobytes, and gives a clean master for the icon (section 8). This was already asked on 2026-10-08. The spec is complete and buildable without it; this only improves the result.

2. **Open Graph tagline wording (minor, taste).** The share card can carry a one-line tagline under the wordmark. A sensible default drawn from the existing site copy is "A safe space for women and their allies." If the owner prefers different words, they slot straight in; this is editable copy, not a design dependency.

3. **PWA installability (optional, deferred).** Whether the app should be installable to a phone home screen with a maskable icon (section 6, optional row). This is a product decision, not a design blocker. Default is to skip it until there is a reason.

Everything else in this document is a design decision already made here, with its reasoning and its measured numbers, and does not need the owner's input to proceed.

---

## 13. Handoff notes for the code pass

Not instructions to execute now; context for whoever implements the integration later.

- This integration touches the app shell header and the left rail (`src/components/shell/AppShell.tsx`), the public header (`src/components/SiteHeader.tsx`), the landing page (`src/app/(public)/page.tsx`), and `src/app/layout.tsx`, and it creates `public/` and several asset files. Per the project's file-ownership separation, that is a single focused code change and should not run concurrently with another agent editing the same shell files.
- The committed root `hersciety` PNG (507 KB, no extension) is unservable from its location. Once the real assets exist, remove or relocate it (section 8). This spec does not touch it.
- Build order within the code pass: produce the assets first (wordmark pair, icon set, Open Graph image), then wire `layout.tsx` metadata (section 7), then replace the four text wordmarks with the mark (section 5) and add the theme-swap CSS (section 3). Verify the 16 px favicon rendition visually before considering the icon done (section 4).
- Nothing in this spec requires a database migration, an API change, or a token change. It is assets, markup, and metadata only.
