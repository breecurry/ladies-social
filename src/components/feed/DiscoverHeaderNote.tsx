"use client";

import { useSyncExternalStore } from "react";
import { X } from "@phosphor-icons/react";

const DISMISSED_KEY = "discover_header_dismissed";
const VIEWS_KEY = "discover_header_views";
const MAX_VIEWS = 5;

/**
 * Visibility is decided once per page load, counting the view at the
 * moment of deciding. localStorage is the external store; the server
 * snapshot is always "hidden" so server and hydration markup agree.
 */
let decision: boolean | null = null;
let notify: (() => void) | null = null;

function decide(): boolean {
  if (decision === null) {
    try {
      if (window.localStorage.getItem(DISMISSED_KEY) === "true") {
        decision = false;
      } else {
        const views = Number(window.localStorage.getItem(VIEWS_KEY) ?? "0");
        decision = views < MAX_VIEWS;
        if (decision) window.localStorage.setItem(VIEWS_KEY, String(views + 1));
      }
    } catch {
      // Storage unavailable (private mode): show nothing rather than nag forever.
      decision = false;
    }
  }
  return decision;
}

function subscribe(onChange: () => void) {
  notify = onChange;
  return () => {
    notify = null;
  };
}

function dismiss() {
  try {
    window.localStorage.setItem(DISMISSED_KEY, "true");
  } catch {
    // Best effort; the note simply reappears next visit.
  }
  decision = false;
  notify?.();
}

/**
 * The honest one-line Discover header (spec §4.7): "Recent posts from
 * across Hersciety." Shown the first few opens, dismissible for good.
 */
export function DiscoverHeaderNote() {
  const visible = useSyncExternalStore(subscribe, decide, () => false);

  if (!visible) return null;

  return (
    <div className="flex items-center justify-between gap-3 border-b border-border bg-surface px-4 py-2">
      <p className="text-caption text-text-secondary">Recent posts from across Hersciety.</p>
      <button
        type="button"
        aria-label="Dismiss"
        onClick={dismiss}
        className="flex size-11 shrink-0 items-center justify-center rounded-full text-text-tertiary hover:bg-surface-raised hover:text-text-primary"
      >
        <X size={16} aria-hidden />
      </button>
    </div>
  );
}
