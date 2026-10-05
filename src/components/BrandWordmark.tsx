/**
 * The Hersciety brand wordmark (docs/design-brand-mark-integration.md).
 *
 * Two baked raster assets, one per theme: the light asset carries the
 * logo's own #6901E2 and the dark asset the existing dark accent
 * #a78bfa, because the raw logo purple measures 2.38:1 on the dark
 * background and fails legibility (spec section 3). Visibility is
 * toggled by the `.brand-wordmark` rules in globals.css, which mirror
 * the exact theme selectors the colour tokens use so a manual
 * [data-theme] override is honoured, not just the system preference.
 *
 * Rendered as real <img> elements, not a CSS mask or background, so
 * forced-colors mode keeps the mark visible and the alt text always
 * provides a text fallback (spec section 9.3).
 */

/** Native glyph aspect ratio of the wordmark assets (1024 x 265). */
const WORDMARK_RATIO = 1024 / 265;

/** Responsive sizing for the landing hero (spec section 5.4). */
const HERO_STYLE = { height: "clamp(44px, 10vw, 72px)", width: "auto" } as const;

export function BrandWordmark({
  height = 22,
  hero = false,
}: {
  /** Rendered height in px; width follows the native ratio. Ignored when `hero` is set. */
  height?: number;
  /** Landing-hero mode: height clamp(44px, 10vw, 72px) instead of a fixed size. */
  hero?: boolean;
}) {
  const width = Math.round(height * WORDMARK_RATIO);
  const size = hero
    ? { style: HERO_STYLE }
    : { width, height, style: undefined };

  return (
    <span className="brand-wordmark inline-flex">
      {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size, pre-optimised brand asset; no responsive variants needed */}
      <img src="/wordmark-light.png" alt="Hersciety" className="is-light" {...size} />
      {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size, pre-optimised brand asset; no responsive variants needed */}
      <img src="/wordmark-dark.png" alt="Hersciety" className="is-dark" {...size} />
    </span>
  );
}
