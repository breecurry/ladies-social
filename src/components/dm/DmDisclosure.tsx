"use client";

import { useState } from "react";
import { Eye, X } from "@phosphor-icons/react";
import { DM_DISCLOSURE_QUIET_DAYS } from "@/lib/dm/disclosure";

/**
 * The honest DM disclosure (owner decision, 2026-10-05). Rendered on
 * every surface where a member starts or reads a direct message — the
 * inbox and every thread. Never a tooltip, and the copy is not
 * softened. Members deserve to know exactly who can read what before
 * they type.
 *
 * Dismissible since 2026-10-06 (owner decision): the X hides it for a
 * minimum of DM_DISCLOSURE_QUIET_DAYS (45) days, after which it
 * returns at full prominence — the re-show is rendered by this same
 * component, exactly as prominent as the first show. A dismissal is
 * stored per ACCOUNT in dm_settings (not in the browser), so the
 * quiet period holds across devices and cookie clears. The server
 * decides visibility (dm_disclosure_should_show) and passes
 * `initiallyVisible` down; every failure path — migration not applied,
 * query error, persist failure — resolves to SHOWING the banner.
 */
export function DmDisclosure({ initiallyVisible }: { initiallyVisible: boolean }) {
  const [visible, setVisible] = useState(initiallyVisible);
  if (!visible) return null;

  const dismiss = () => {
    // Optimistic hide; persistence is fire-and-forget. If the write
    // fails for any reason the banner simply reappears on the next
    // load — the failure direction is always toward showing it.
    setVisible(false);
    void fetch("/api/dm/disclosure", { method: "POST" }).catch(() => undefined);
  };

  return (
    <div
      role="note"
      aria-label="How private your messages are"
      className="flex items-start gap-2.5 border-b border-border bg-surface-raised py-3 pl-4 pr-2"
    >
      <Eye size={18} aria-hidden className="mt-0.5 shrink-0 text-warning" />
      {/*
       * 🔒 THE COPY BELOW IS LOAD-BEARING. It matches the published
       * Privacy Policy §5 word for word in substance and must not be
       * softened or reworded casually. If it ever materially changes
       * (for example, staff access behaviour changes), BUMP
       * DM_DISCLOSURE_VERSION in src/lib/dm/disclosure.ts in the same
       * commit so every member sees the new text immediately,
       * overriding any running quiet period.
       */}
      <p className="text-caption text-text-secondary">
        <strong className="text-text-primary">Your messages are not private from Hersciety.</strong>{" "}
        Direct messages are not end-to-end encrypted. The platform owner and moderators can read
        them, and every one of those reads is logged. Messages may be disclosed to authorities in
        matters involving trafficking or sexual exploitation, including of minors.
      </p>
      <button
        type="button"
        aria-label={`Dismiss this notice (it will return in ${DM_DISCLOSURE_QUIET_DAYS} days)`}
        title={`Dismiss — this notice returns in ${DM_DISCLOSURE_QUIET_DAYS} days`}
        onClick={dismiss}
        className="flex size-11 shrink-0 items-center justify-center self-center rounded-md text-text-secondary hover:bg-surface hover:text-text-primary focus-visible:outline-2 focus-visible:outline-focus-ring"
      >
        <X size={18} aria-hidden />
      </button>
    </div>
  );
}
