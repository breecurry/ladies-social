"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Check } from "@phosphor-icons/react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { useToast } from "@/components/shell/ToastProvider";
import { useViewer } from "@/components/shell/Providers";
import { ConfirmDialog } from "@/components/ConfirmDialog";

/**
 * The owner's exact follow mechanics (spec §4.9, §3.6):
 * - Following is one tap; the control then shows a transient
 *   "Following" chip (~2s) and disappears (pill variant).
 * - A "Following @handle" toast with Undo (~6s) catches mis-taps.
 * - Unfollowing is PROFILE-ONLY and confirmed (profile variant).
 */
export function FollowControl({
  targetUserId,
  targetHandle,
  initialFollowing,
  variant,
}: {
  targetUserId: string;
  targetHandle: string;
  initialFollowing: boolean;
  variant: "pill" | "profile";
}) {
  const router = useRouter();
  const viewer = useViewer();
  const { showToast } = useToast();
  const [following, setFollowing] = useState(initialFollowing);
  const [chip, setChip] = useState(false);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [busy, setBusy] = useState(false);

  if (targetUserId === viewer.id) return null;

  const unfollow = async () => {
    const supabase = createSupabaseBrowserClient();
    setFollowing(false);
    const { error } = await supabase
      .from("follows")
      .delete()
      .eq("follower_id", viewer.id)
      .eq("followee_id", targetUserId);
    if (error) {
      setFollowing(true);
      showToast("Could not unfollow. Try again.");
    }
    router.refresh();
  };

  const follow = async () => {
    const supabase = createSupabaseBrowserClient();
    setFollowing(true);
    setChip(true);
    window.setTimeout(() => setChip(false), 2000);
    const { error } = await supabase
      .from("follows")
      .insert({ follower_id: viewer.id, followee_id: targetUserId });
    if (error) {
      setFollowing(false);
      setChip(false);
      showToast("Could not follow. Try again.");
      return;
    }
    showToast(`Following @${targetHandle}`, {
      actionLabel: "Undo",
      onAction: unfollow,
      durationMs: 6000,
    });
    router.refresh();
  };

  if (variant === "pill") {
    if (following && chip) {
      return (
        <span className="inline-flex h-[30px] items-center gap-1 rounded-full bg-accent-subtle px-3 text-label text-accent">
          <Check size={14} aria-hidden /> Following
        </span>
      );
    }
    if (following) return null;
    return (
      <button
        type="button"
        aria-label={`Follow @${targetHandle}`}
        onClick={(event) => {
          event.stopPropagation();
          void follow();
        }}
        className="inline-flex min-h-11 items-center rounded-full px-1"
      >
        <span className="inline-flex h-[30px] items-center rounded-full border border-border-strong bg-surface px-3 text-label text-accent hover:bg-surface-raised">
          Follow
        </span>
      </button>
    );
  }

  // Profile variant: full-size control.
  if (!following) {
    return (
      <button
        type="button"
        onClick={() => void follow()}
        className="min-h-11 rounded-full bg-accent-fill px-6 text-label text-on-accent hover:bg-accent-hover"
      >
        Follow
      </button>
    );
  }
  return (
    <>
      <button
        type="button"
        onClick={() => setConfirmOpen(true)}
        className="min-h-11 rounded-full border border-border-strong bg-surface px-6 text-label text-text-primary hover:bg-surface-raised"
      >
        {chip ? "Following ✓" : "Following"}
      </button>
      <ConfirmDialog
        open={confirmOpen}
        title={`Unfollow @${targetHandle}?`}
        body="Their posts will no longer appear in your Following feed."
        confirmLabel="Unfollow"
        busy={busy}
        onCancel={() => setConfirmOpen(false)}
        onConfirm={() => {
          setBusy(true);
          void unfollow().then(() => {
            setBusy(false);
            setConfirmOpen(false);
          });
        }}
      />
    </>
  );
}
