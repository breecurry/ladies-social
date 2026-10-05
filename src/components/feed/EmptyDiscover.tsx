"use client";

import { Sparkle } from "@phosphor-icons/react";
import { useCompose } from "@/components/shell/ComposeProvider";

/**
 * Discover, genuinely empty (spec §9.6): the true cold-start state for
 * the very first sessions of the founding cohort. An invitation to
 * found something, never a server error.
 */
export function EmptyDiscover() {
  const { openCompose } = useCompose();

  return (
    <div className="flex flex-col items-center gap-3 px-6 py-16 text-center">
      <Sparkle size={48} aria-hidden className="text-text-tertiary" />
      <h2 className="text-title text-text-primary">Be the first voice</h2>
      <p className="max-w-sm text-body text-text-secondary">
        Nothing has been posted yet. Write the first post and set the tone.
      </p>
      <button
        type="button"
        onClick={() => openCompose()}
        className="mt-2 min-h-11 rounded-full bg-accent-fill px-6 text-label text-on-accent hover:bg-accent-hover"
      >
        Write a post
      </button>
    </div>
  );
}
