"use client";

import Link from "next/link";
import { Avatar } from "@/components/Avatar";
import { FollowControl } from "@/components/follow/FollowControl";
import { OverflowMenu } from "@/components/post/OverflowMenu";
import { useViewer } from "@/components/shell/Providers";

export interface PersonRowData {
  user_id: string;
  handle: string;
  founding: boolean;
  bio: string | null;
  viewer_follows: boolean;
}

/**
 * A people row (search results, follower and following lists, spec
 * §7.2): avatar, @handle, one-line bio, a Follow pill when you do not
 * follow them, and the standard overflow. Handle-forward identity only.
 */
export function PersonRow({ person }: { person: PersonRowData }) {
  const viewer = useViewer();
  const isSelf = person.user_id === viewer.id;
  return (
    <div className="flex items-center gap-3 border-b border-border bg-surface px-4 py-3">
      <Avatar handle={person.handle} size={40} userId={person.user_id} />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5">
          <Link
            href={`/u/${person.handle}`}
            className="truncate text-label font-semibold text-text-primary hover:underline"
          >
            @{person.handle}
          </Link>
          {person.founding ? (
            <span className="rounded-full bg-accent-subtle px-2 py-0.5 text-micro text-accent">
              Founding
            </span>
          ) : null}
        </div>
        {person.bio ? (
          <p className="truncate text-caption text-text-tertiary">{person.bio}</p>
        ) : null}
      </div>
      <FollowControl
        targetUserId={person.user_id}
        targetHandle={person.handle}
        initialFollowing={person.viewer_follows}
        variant="pill"
      />
      {isSelf ? null : (
        <OverflowMenu targetUserId={person.user_id} targetHandle={person.handle} isOwn={false} />
      )}
    </div>
  );
}
