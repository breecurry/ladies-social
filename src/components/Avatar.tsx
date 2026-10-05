"use client";

import Link from "next/link";
import { useState } from "react";
import {
  avatarUrl,
  avatarVariantForSize,
  blurhashAverageColor,
  type AvatarMedia,
} from "@/lib/media/avatar";
import { useAvatarMedia } from "@/components/avatar/useAvatarMedia";

const SIZES = {
  24: "size-6 text-micro",
  32: "size-8 text-caption",
  40: "size-10 text-body",
  48: "size-12 text-heading",
  96: "size-24 text-display",
  128: "size-32 text-display",
} as const;

export type AvatarSize = keyof typeof SIZES;

/**
 * The avatar (spec P2E section 8): the member's photo when one is set,
 * permitted and loadable, otherwise the letter placeholder — an
 * accent-subtle circle with the first handle letter in accent, which
 * remains the deliberate default, not an error state.
 *
 * Where the photo may come from:
 *  - `media`: already resolved (server pages call avatar_keys themselves);
 *    pass null to force the placeholder (staff surfaces simply never pass
 *    either prop and can never show a photo).
 *  - `userId`: resolved client-side through the batched avatar_keys hook.
 * BOTH paths go through the block-aware resolver at the database; this
 * component never sees a key a blocked viewer must not have.
 *
 * Accessible name stays on the link (`@handle`), the inner image is
 * alt="" (decorative — the handle already names it), and a failed load
 * falls back to the letter, never a broken-image glyph.
 */
export function Avatar({
  handle,
  size = 48,
  link = true,
  userId,
  media,
}: {
  handle: string;
  size?: AvatarSize;
  link?: boolean;
  userId?: string | null;
  media?: AvatarMedia | null;
}) {
  const resolved = useAvatarMedia(media === undefined ? (userId ?? null) : null);
  const effective = media !== undefined ? media : resolved;
  const [brokenSrc, setBrokenSrc] = useState<string | null>(null);

  const src = effective ? avatarUrl(effective.key, avatarVariantForSize(size)) : null;
  const showPhoto = src !== null && src !== brokenSrc;

  const face = showPhoto ? (
    // Served from the Cloudflare media zone with immutable unguessable
    // keys; next/image would proxy every avatar through Vercel and
    // defeat the edge cache.
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={src}
      alt=""
      aria-hidden={link ? undefined : true}
      width={size}
      height={size}
      loading="lazy"
      onError={() => setBrokenSrc(src)}
      className={`shrink-0 rounded-full object-cover ${SIZES[size].split(" ")[0]}`}
      style={{ backgroundColor: blurhashAverageColor(effective?.blurhash ?? null) ?? undefined }}
    />
  ) : (
    <span
      className={`inline-flex shrink-0 items-center justify-center rounded-full bg-accent-subtle font-semibold text-accent ${SIZES[size]}`}
      aria-hidden={link ? undefined : true}
    >
      {handle.charAt(0).toUpperCase() || "?"}
    </span>
  );
  if (!link) return face;
  return (
    <Link
      href={`/u/${handle}`}
      aria-label={`@${handle}`}
      className="inline-flex shrink-0 rounded-full"
    >
      {face}
    </Link>
  );
}
