"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { useToast } from "@/components/shell/ToastProvider";
import { useViewer } from "@/components/shell/Providers";

/** Unblock control, used on a blocked profile and in Settings, Safety. */
export function UnblockButton({
  targetUserId,
  targetHandle,
}: {
  targetUserId: string;
  targetHandle: string;
}) {
  const router = useRouter();
  const viewer = useViewer();
  const { showToast } = useToast();
  const [busy, setBusy] = useState(false);

  const unblock = async () => {
    setBusy(true);
    const supabase = createSupabaseBrowserClient();
    const { error } = await supabase
      .from("blocks")
      .delete()
      .eq("blocker_id", viewer.id)
      .eq("blocked_id", targetUserId);
    setBusy(false);
    if (error) {
      showToast("Could not unblock. Try again.");
      return;
    }
    showToast(`Unblocked @${targetHandle}`);
    router.refresh();
  };

  return (
    <button
      type="button"
      disabled={busy}
      onClick={() => void unblock()}
      className="min-h-11 rounded-full border border-border-strong bg-surface px-5 text-label text-text-primary hover:bg-surface-raised disabled:opacity-50"
    >
      Unblock
    </button>
  );
}
