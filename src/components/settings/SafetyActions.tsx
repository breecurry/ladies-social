"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { useToast } from "@/components/shell/ToastProvider";
import { useViewer } from "@/components/shell/Providers";

function RemoveButton({
  label,
  onRemove,
}: {
  label: string;
  onRemove: () => Promise<{ error: { message: string } | null }>;
}) {
  const router = useRouter();
  const { showToast } = useToast();
  const [busy, setBusy] = useState(false);

  return (
    <button
      type="button"
      disabled={busy}
      onClick={() => {
        setBusy(true);
        void onRemove().then(({ error }) => {
          setBusy(false);
          if (error) {
            showToast("Could not update. Try again.");
            return;
          }
          router.refresh();
        });
      }}
      className="min-h-11 rounded-full border border-border-strong bg-surface px-4 text-label text-text-primary hover:bg-surface-raised disabled:opacity-50"
    >
      {label}
    </button>
  );
}

export function UnmuteButton({ targetUserId }: { targetUserId: string }) {
  const viewer = useViewer();
  return (
    <RemoveButton
      label="Unmute"
      onRemove={async () => {
        const supabase = createSupabaseBrowserClient();
        return supabase
          .from("mutes")
          .delete()
          .eq("muter_id", viewer.id)
          .eq("muted_id", targetUserId);
      }}
    />
  );
}

export function UnhideButton({ targetUserId }: { targetUserId: string }) {
  const viewer = useViewer();
  return (
    <RemoveButton
      label="Undo"
      onRemove={async () => {
        const supabase = createSupabaseBrowserClient();
        return supabase
          .from("hidden_accounts")
          .delete()
          .eq("hider_id", viewer.id)
          .eq("hidden_id", targetUserId);
      }}
    />
  );
}
