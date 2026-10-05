"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { useToast } from "@/components/shell/ToastProvider";
import { useViewer } from "@/components/shell/Providers";

/** Accessible switch row used across the settings surfaces. */
export function ToggleRow({
  label,
  helper,
  checked,
  disabled = false,
  onChange,
}: {
  label: string;
  helper?: string;
  checked: boolean;
  disabled?: boolean;
  onChange: (next: boolean) => void;
}) {
  return (
    <div className="flex min-h-11 items-center justify-between gap-4">
    <div>
        <p className="text-body text-text-primary">{label}</p>
        {helper ? <p className="text-caption text-text-tertiary">{helper}</p> : null}
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={label}
        disabled={disabled}
        onClick={() => onChange(!checked)}
        className={`relative h-7 w-12 shrink-0 rounded-full transition-colors duration-(--duration-fast) disabled:opacity-50 ${
          checked ? "bg-accent-fill" : "bg-border-strong"
        }`}
      >
        <span
          aria-hidden
          className={`absolute top-1 size-5 rounded-full bg-white transition-all duration-(--duration-fast) ${
            checked ? "left-6" : "left-1"
          }`}
        />
      </button>
    </div>
  );
}

/** Search-engine discoverability opt-in (profiles.search_indexable). */
export function SearchIndexToggle({ initial }: { initial: boolean }) {
  const router = useRouter();
  const viewer = useViewer();
  const { showToast } = useToast();
  const [on, setOn] = useState(initial);
  const [busy, setBusy] = useState(false);

  const change = async (next: boolean) => {
    setOn(next);
    setBusy(true);
    const supabase = createSupabaseBrowserClient();
    const { error } = await supabase
      .from("profiles")
      .update({ search_indexable: next })
      .eq("user_id", viewer.id);
    setBusy(false);
    if (error) {
      setOn(!next);
      showToast("Could not update the setting. Try again.");
      return;
    }
    router.refresh();
  };

  return (
    <ToggleRow
      label="Allow search engines to index your profile"
      helper="Off by default. Your profile stays out of Google and other search engines unless you choose otherwise."
      checked={on}
      disabled={busy}
      onChange={(next) => void change(next)}
    />
  );
}
