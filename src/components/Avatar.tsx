import Link from "next/link";

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
 * Letter avatar (spec §3.1): accent-subtle fill with the first handle
 * letter in accent. Media avatars arrive in Phase 3. Links to the
 * profile unless link=false (e.g. when the parent row is the link).
 */
export function Avatar({
  handle,
  size = 48,
  link = true,
}: {
  handle: string;
  size?: AvatarSize;
  link?: boolean;
}) {
  const letter = handle.charAt(0).toUpperCase() || "?";
  const face = (
    <span
      className={`inline-flex shrink-0 items-center justify-center rounded-full bg-accent-subtle font-semibold text-accent ${SIZES[size]}`}
      aria-hidden={link ? undefined : true}
    >
      {letter}
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
