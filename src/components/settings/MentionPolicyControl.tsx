"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { MentionPolicy } from "@/lib/database.types";
import { useToast } from "@/components/shell/ToastProvider";
import { useViewer } from "@/components/shell/Providers";

const OPTIONS: Array<{ value: MentionPolicy; label: string; helper: string }> = [
  {
    value: "everyone",
    label: "Everyone",
    helper: "Any member can mention you and you are notified.",
  },
  {
    value: "followed",
    label: "People you follow",
    helper: "Only people you follow can mention you. Mentions from anyone else do nothing.",
  },
  {
    value: "no_one",
    label: "No one",
    helper: "Mentions of your @handle never reach you.",
  },
];

/**
 * "Who can mention you" (Phase 2F §12). Default: Everyone — the owner's
 * decision — with the stricter options one tap away for anyone being
 * targeted. The policy is enforced at post time in the database: it
 * gates both the mention notification and mentioned-participant
 * status, alongside the block wall and mute suppression that always
 * apply.
 */
export function MentionPolicyControl({ initial }: { initial: MentionPolicy }) {
  const router = useRouter();
  const viewer = useViewer();
  const { showToast } = useToast();
  const [policy, setPolicy] = useState<MentionPolicy>(initial);
  const [busy, setBusy] = useState(false);

  const change = async (next: MentionPolicy) => {
    const previous = policy;
    setPolicy(next);
    setBusy(true);
    const supabase = createSupabaseBrowserClient();
    const { error } = await supabase
      .from("profiles")
      .update({ mention_policy: next })
      .eq("user_id", viewer.id);
    setBusy(false);
    if (error) {
      setPolicy(previous);
      showToast("Could not update the setting. Try again.");
      return;
    }
    router.refresh();
  };

  return (
    <fieldset className="flex flex-col gap-1" disabled={busy}>
      <legend className="text-body text-text-primary">Who can mention you</legend>
      {OPTIONS.map((option) => (
        <label
          key={option.value}
          className="flex min-h-11 cursor-pointer items-start gap-3 rounded-md px-2 py-2 hover:bg-surface-raised"
        >
          <input
            type="radio"
            name="mention-policy"
            value={option.value}
            checked={policy === option.value}
            onChange={() => void change(option.value)}
            className="mt-1 size-4 accent-(--accent)"
          />
          <span className="flex flex-col">
            <span className="text-body text-text-primary">{option.label}</span>
            <span className="text-caption text-text-tertiary">{option.helper}</span>
          </span>
        </label>
      ))}
    </fieldset>
  );
}
