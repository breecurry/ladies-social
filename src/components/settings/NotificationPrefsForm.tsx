"use client";

import { useState } from "react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { useToast } from "@/components/shell/ToastProvider";
import { useViewer } from "@/components/shell/Providers";
import { ToggleRow } from "@/components/settings/Toggles";

export type PrefKey = "follow" | "reply" | "mention" | "like";

const ROWS: Array<{ key: PrefKey; label: string; helper: string }> = [
  { key: "reply", label: "Replies", helper: "When someone replies to one of your posts." },
  { key: "mention", label: "Mentions", helper: "When someone mentions your @handle." },
  { key: "follow", label: "New followers", helper: "When someone follows you." },
  { key: "like", label: "Likes", helper: "When someone likes one of your posts." },
];

/**
 * Per-type notification toggles mapped to the notification_prefs
 * JSONB (spec §8.2.4). A missing key means enabled.
 */
export function NotificationPrefsForm({ initial }: { initial: Record<string, boolean> }) {
  const viewer = useViewer();
  const { showToast } = useToast();
  const [prefs, setPrefs] = useState<Record<string, boolean>>(initial);
  const [busy, setBusy] = useState(false);

  const change = async (key: PrefKey, next: boolean) => {
    const previous = prefs;
    const updated = { ...prefs, [key]: next };
    setPrefs(updated);
    setBusy(true);
    const supabase = createSupabaseBrowserClient();
    const { error } = await supabase
      .from("notification_prefs")
      .upsert({ user_id: viewer.id, prefs: updated });
    setBusy(false);
    if (error) {
      setPrefs(previous);
      showToast("Could not save the setting. Try again.");
    }
  };

  return (
    <div className="flex flex-col gap-4">
      {ROWS.map((row) => (
        <ToggleRow
          key={row.key}
          label={row.label}
          helper={row.helper}
          checked={prefs[row.key] ?? true}
          disabled={busy}
          onChange={(next) => void change(row.key, next)}
        />
      ))}
    </div>
  );
}
