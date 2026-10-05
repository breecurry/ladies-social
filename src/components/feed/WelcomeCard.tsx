"use client";

import { useState, useSyncExternalStore } from "react";
import Link from "next/link";
import { useCompose } from "@/components/shell/ComposeProvider";

const DISMISS_KEY = "uf-welcome-dismissed";

const emptySubscribe = () => () => {};

function readDismissed(): boolean {
  try {
    return window.localStorage.getItem(DISMISS_KEY) === "1";
  } catch {
    return false;
  }
}

/**
 * First-session welcome card (spec §9.6, simplified): a dismissible
 * accent-subtle card with the three getting-started actions. Shown
 * while the member has no follows and no posts.
 */
export function WelcomeCard() {
  const { openCompose } = useCompose();
  const [closed, setClosed] = useState(false);
  // Hidden during SSR, shown after hydration unless previously dismissed.
  const dismissed = useSyncExternalStore(emptySubscribe, readDismissed, () => true);

  if (closed || dismissed) return null;

  const dismiss = () => {
    try {
      window.localStorage.setItem(DISMISS_KEY, "1");
    } catch {
      // Storage unavailable; the card simply returns next visit.
    }
    setClosed(true);
  };

  return (
    <section
      aria-label="Getting started"
      className="m-4 flex flex-col gap-3 rounded-lg bg-accent-subtle p-4"
    >
      <div className="flex items-start justify-between gap-2">
        <p className="text-body text-text-primary">
          Welcome. This is a space built for women&apos;s safety and the people who stand with
          them. Here is how to get started.
        </p>
        <button
          type="button"
          aria-label="Dismiss"
          onClick={dismiss}
          className="flex min-h-11 min-w-11 items-center justify-center rounded-md text-text-secondary hover:text-text-primary"
        >
          ✕
        </button>
      </div>
      <ul className="flex flex-col gap-1">
        <li>
          <button
            type="button"
            onClick={() => openCompose()}
            className="min-h-11 rounded-md px-2 text-left text-body text-accent hover:underline"
          >
            Say hello. Write your first post.
          </button>
        </li>
        <li>
          <Link
            href="/search"
            className="inline-flex min-h-11 items-center rounded-md px-2 text-body text-accent hover:underline"
          >
            Find people. Follow a few accounts so your feed fills up.
          </Link>
        </li>
        <li>
          <Link
            href="/settings"
            className="inline-flex min-h-11 items-center rounded-md px-2 text-body text-accent hover:underline"
          >
            Make it yours. Add a line of bio.
          </Link>
        </li>
      </ul>
    </section>
  );
}
