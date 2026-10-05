"use client";

import { useState } from "react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { useToast } from "@/components/shell/ToastProvider";
import { useViewer } from "@/components/shell/Providers";
import { ToggleRow } from "@/components/settings/Toggles";
import type { DmRequestPolicy } from "@/lib/database.types";

interface DmSettingsValue {
  requests_from: DmRequestPolicy;
  dms_enabled: boolean;
  read_receipts: boolean;
}

const POLICY_OPTIONS: Array<{ value: DmRequestPolicy; label: string; helper: string }> = [
  {
    value: "everyone",
    label: "Everyone",
    helper:
      "Anyone can send one quiet request. It never notifies you, and they cannot send more unless you accept.",
  },
  {
    value: "followed",
    label: "People you follow",
    helper: "Only people you follow can reach you, and they already reach your inbox.",
  },
  {
    value: "no_one",
    label: "No one",
    helper: "No requests at all. Only people you follow can ever message you.",
  },
];

/**
 * Messages settings (design §7), in the Safety group. The main inbox
 * is structurally people-you-follow-only — that is not a setting and
 * cannot be loosened. These controls govern the request layer, the
 * global off switch, and read receipts (off by default).
 */
export function DmSettingsCard({ initial }: { initial: DmSettingsValue }) {
  const viewer = useViewer();
  const { showToast } = useToast();
  const [value, setValue] = useState<DmSettingsValue>(initial);
  const [busy, setBusy] = useState(false);

  const save = async (next: DmSettingsValue) => {
    const previous = value;
    setValue(next);
    setBusy(true);
    const supabase = createSupabaseBrowserClient();
    const { error } = await supabase
      .from("dm_settings")
      .upsert({ user_id: viewer.id, ...next });
    setBusy(false);
    if (error) {
      setValue(previous);
      showToast("Could not save the setting. Try again.");
    }
  };

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-1">
        <p className="text-body text-text-primary">Who can message you</p>
        <p className="text-caption text-text-tertiary">
          People you follow. Following someone is what opens your inbox to them; nobody else can
          put a message there.
        </p>
      </div>

      <fieldset className="flex flex-col gap-2" disabled={busy}>
        <legend className="mb-1 text-body text-text-primary">Who can send you a request</legend>
        {POLICY_OPTIONS.map((option) => (
          <label
            key={option.value}
            className="flex min-h-11 cursor-pointer items-start gap-3 rounded-md px-2 py-1.5 hover:bg-accent-subtle"
          >
            <input
              type="radio"
              name="dm-requests-from"
              checked={value.requests_from === option.value}
              onChange={() => void save({ ...value, requests_from: option.value })}
              className="mt-1 size-4 accent-(--color-accent)"
            />
            <span>
              <span className="block text-label text-text-primary">{option.label}</span>
              <span className="block text-caption text-text-tertiary">{option.helper}</span>
            </span>
          </label>
        ))}
      </fieldset>

      <ToggleRow
        label="Direct messages"
        helper="Turn this off and you will not receive any messages or requests while it is off, from anyone. Your existing conversations are kept."
        checked={value.dms_enabled}
        disabled={busy}
        onChange={(next) => void save({ ...value, dms_enabled: next })}
      />

      <ToggleRow
        label="Read receipts"
        helper="Off by default. While off, no one can tell whether you have read their message."
        checked={value.read_receipts}
        disabled={busy}
        onChange={(next) => void save({ ...value, read_receipts: next })}
      />
    </div>
  );
}
