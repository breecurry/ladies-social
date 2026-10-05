"use client";

import { PencilSimple } from "@phosphor-icons/react";
import { useCompose } from "@/components/shell/ComposeProvider";
import { useViewer } from "@/components/shell/Providers";

/**
 * Collapsed composer entry affordance at the top of the feed
 * (spec §5.1): avatar, prompt, and a compose glyph. Activating it
 * opens the full composer.
 */
export function ComposePrompt() {
  const { openCompose } = useCompose();
  const viewer = useViewer();

  return (
    <button
      type="button"
      onClick={() => openCompose()}
      className="flex min-h-14 w-full items-center gap-3 border-b border-border bg-surface px-4 py-3 text-left transition-colors duration-(--duration-fast) hover:bg-surface-raised"
    >
      <span
        aria-hidden
        className="flex size-10 shrink-0 items-center justify-center rounded-full bg-accent-subtle text-body font-semibold text-accent"
      >
        {viewer.handle.charAt(0).toUpperCase()}
      </span>
      <span className="flex-1 text-body text-text-tertiary">
        Share something with the community
      </span>
      <PencilSimple size={20} aria-hidden className="text-text-tertiary" />
    </button>
  );
}
