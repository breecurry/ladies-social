"use client";

import Link from "next/link";
import { ChatsCircle } from "@phosphor-icons/react";
import { useCompose } from "@/components/shell/ComposeProvider";

/**
 * Empty states for the Following feed (spec §9.2). With zero follows
 * the primary way out is Discover, where the community already is.
 */
export function EmptyFeed({ hasFollows }: { hasFollows: boolean }) {
  const { openCompose } = useCompose();

  return (
    <div className="flex flex-col items-center gap-3 px-6 py-16 text-center">
      <ChatsCircle size={48} aria-hidden className="text-text-tertiary" />
      {hasFollows ? (
        <>
          <h2 className="text-title text-text-primary">Quiet in here for now</h2>
          <p className="max-w-sm text-body text-text-secondary">
            The people you follow have not posted yet. Be the one who starts.
          </p>
          <button
            type="button"
            onClick={() => openCompose()}
            className="mt-2 min-h-11 rounded-full bg-accent-fill px-6 text-label text-on-accent hover:bg-accent-hover"
          >
            Write a post
          </button>
        </>
      ) : (
        <>
          <h2 className="text-title text-text-primary">Your feed is waiting</h2>
          <p className="max-w-sm text-body text-text-secondary">
            Follow a few people and their posts show up here. In the meantime, see what the
            community is sharing.
          </p>
          <div className="mt-2 flex flex-wrap justify-center gap-2">
            <Link
              href="/home?tab=discover"
              className="inline-flex min-h-11 items-center rounded-full bg-accent-fill px-6 text-label text-on-accent hover:bg-accent-hover"
            >
              See Discover
            </Link>
            <Link
              href="/search"
              className="inline-flex min-h-11 items-center rounded-full border border-border-strong bg-surface px-6 text-label text-text-primary hover:bg-surface-raised"
            >
              Find people to follow
            </Link>
          </div>
        </>
      )}
    </div>
  );
}
