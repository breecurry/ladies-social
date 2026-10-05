"use client";

import { Avatar, type AvatarSize } from "@/components/Avatar";
import { ChangePhotoControl } from "@/components/avatar/AvatarEditor";
import type { AvatarMedia } from "@/lib/media/avatar";

/**
 * The own-profile header avatar (spec P2E section 6.1): the member's
 * avatar with the circular camera edit affordance pinned to its
 * lower-right. Tapping it opens the picker, then the crop step.
 */
export function OwnProfileAvatar({
  handle,
  media,
  size = 96,
}: {
  handle: string;
  media: AvatarMedia | null;
  size?: AvatarSize;
}) {
  return (
    <div className="relative inline-flex">
      <Avatar handle={handle} size={size} link={false} media={media} />
      <ChangePhotoControl variant="camera" hasPhoto={media !== null} />
    </div>
  );
}
