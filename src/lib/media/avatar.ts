/**
 * Avatar constants and pure helpers, shared by server and client.
 * Spec: docs/design-phase2e-profile-pictures.md sections 2, 3 and 6.
 *
 * Keys are opaque 48-hex CSPRNG strings minted by the server. Variant
 * objects live at `av/{key}/{variant}.webp` on the media zone and are
 * immutable: a new upload mints a NEW key, nothing is ever overwritten.
 * No filename, handle, user id, counter or timestamp appears anywhere
 * in a key or URL.
 */

/** Upload ceiling (spec 6.4): generous for a phone photo, bounded for abuse. */
export const AVATAR_MAX_BYTES = 8 * 1024 * 1024;

/** Minimum source dimensions after crop (spec 6.4). */
export const AVATAR_MIN_DIM = 256;

/** Decompression-bomb ceiling: refuse anything decoding past ~50 MP (spec 6.4). */
export const AVATAR_MAX_PIXELS = 50_000_000;

/** Stored square variants (spec 6.6): sized for display scale x device pixel ratio. */
export const AVATAR_VARIANTS = [96, 192, 400] as const;
export type AvatarVariant = (typeof AVATAR_VARIANTS)[number];

/** Static JPEG, PNG and WebP only (spec 6.3). Never SVG, never animated. */
export const AVATAR_ACCEPTED_TYPES = ["image/jpeg", "image/png", "image/webp"] as const;

/** A resolved avatar as returned by the avatar_keys RPC. */
export interface AvatarMedia {
  key: string;
  blurhash: string | null;
}

/** Rejections always carry a stated reason (spec 6.5). */
export const AVATAR_REJECTION_MESSAGE = {
  too_large: "That image is larger than 8 MB. Try a smaller photo.",
  too_small: "That image is too small. Use one at least 256 by 256 pixels.",
  wrong_format: "That file type is not supported. Use a JPG, PNG, or WebP image.",
  unreadable: "We could not read that image. Try a different file.",
} as const;
export type AvatarRejection = keyof typeof AVATAR_REJECTION_MESSAGE;

/**
 * Which stored variant a rendered size wants (spec 3): small circles up
 * to 40 px read from the 96 variant (sharp at 2.4x), the 48 px row
 * avatar from 192, and the profile headers from 400.
 */
export function avatarVariantForSize(px: number): AvatarVariant {
  if (px <= 40) return 96;
  if (px <= 64) return 192;
  return 400;
}

/**
 * The public serving URL on the Cloudflare media zone, or null when the
 * zone is not configured yet (the letter placeholder renders instead —
 * the feature degrades to exactly what shipped before it existed).
 */
export function avatarUrl(key: string, variant: AvatarVariant): string | null {
  const base = process.env.NEXT_PUBLIC_MEDIA_URL;
  if (!base) return null;
  return `${base.replace(/\/$/, "")}/av/${key}/${variant}.webp`;
}

const BASE83 =
  "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~";

/**
 * The average color of a blurhash, as a CSS hex color. The DC component
 * of a blurhash is literally the image's average color in sRGB, stored
 * in the four characters after the size flag, so no canvas decode is
 * needed — this runs identically on server and client and paints the
 * circle in the photo's own color while the image loads (spec 6.6).
 */
export function blurhashAverageColor(blurhash: string | null): string | null {
  if (!blurhash || blurhash.length < 6) return null;
  let value = 0;
  for (const char of blurhash.slice(2, 6)) {
    const index = BASE83.indexOf(char);
    if (index === -1) return null;
    value = value * 83 + index;
  }
  return `#${value.toString(16).padStart(6, "0")}`;
}
