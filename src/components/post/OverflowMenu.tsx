"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import {
  DotsThree,
  LinkSimple,
  MinusCircle,
  SpeakerSimpleSlash,
  Prohibit,
  Flag,
  Trash,
} from "@phosphor-icons/react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { useToast } from "@/components/shell/ToastProvider";
import { useViewer } from "@/components/shell/Providers";
import { ConfirmDialog } from "@/components/ConfirmDialog";
import { ReportDialog } from "@/components/post/ReportDialog";

/**
 * The three-dot overflow menu (spec §3.4, §10.1) — the safety home.
 * On someone else's content: Copy link | Show me less, Mute | Block
 * (confirmed), Report (danger, last). On your own: Copy link | Delete
 * (confirmed). Order and grouping are deliberate; do not reorder.
 */
export function OverflowMenu({
  targetUserId,
  targetHandle,
  postId,
  isOwn,
  onHidden,
}: {
  targetUserId: string;
  targetHandle: string;
  /** When present the menu belongs to a post card; Copy link and Report target the post. */
  postId?: number;
  isOwn: boolean;
  /** Feed callback for the in-place "show me less" confirmation panel (spec §4.8). */
  onHidden?: (undo: () => Promise<void>) => void;
}) {
  const router = useRouter();
  const viewer = useViewer();
  const { showToast } = useToast();
  const [open, setOpen] = useState(false);
  const [confirmBlock, setConfirmBlock] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [reportOpen, setReportOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    const onPointerDown = (event: PointerEvent) => {
      if (rootRef.current && !rootRef.current.contains(event.target as Node)) setOpen(false);
    };
    // Escape closes the menu and returns focus to the trigger, matching
    // the Dialog pattern, so keyboard-only members are never stuck in it.
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      event.stopPropagation();
      setOpen(false);
      triggerRef.current?.focus();
    };
    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  const copyLink = async () => {
    const url =
      postId !== undefined
        ? `${window.location.origin}/post/${postId}`
        : `${window.location.origin}/u/${targetHandle}`;
    await navigator.clipboard.writeText(url);
    showToast("Link copied");
    setOpen(false);
  };

  const hide = async () => {
    setOpen(false);
    const supabase = createSupabaseBrowserClient();
    const { error } = await supabase
      .from("hidden_accounts")
      .insert({ hider_id: viewer.id, hidden_id: targetUserId });
    if (error) {
      showToast(error.message);
      return;
    }
    const undo = async () => {
      await supabase
        .from("hidden_accounts")
        .delete()
        .eq("hider_id", viewer.id)
        .eq("hidden_id", targetUserId);
    };
    if (onHidden) {
      onHidden(undo);
    } else {
      showToast(`You will see less from @${targetHandle}`, {
        actionLabel: "Undo",
        onAction: undo,
        durationMs: 6000,
      });
    }
  };

  const mute = async () => {
    setOpen(false);
    const supabase = createSupabaseBrowserClient();
    const { error } = await supabase
      .from("mutes")
      .insert({ muter_id: viewer.id, muted_id: targetUserId });
    if (error) {
      showToast(error.message);
      return;
    }
    showToast(`Muted @${targetHandle}`, {
      actionLabel: "Undo",
      onAction: async () => {
        await supabase
          .from("mutes")
          .delete()
          .eq("muter_id", viewer.id)
          .eq("muted_id", targetUserId);
        router.refresh();
      },
      durationMs: 6000,
    });
    router.refresh();
  };

  const block = async () => {
    setBusy(true);
    const supabase = createSupabaseBrowserClient();
    const { error } = await supabase
      .from("blocks")
      .insert({ blocker_id: viewer.id, blocked_id: targetUserId });
    setBusy(false);
    setConfirmBlock(false);
    if (error) {
      showToast(error.message);
      return;
    }
    showToast(`Blocked @${targetHandle}`, {
      actionLabel: "Undo",
      onAction: async () => {
        await supabase
          .from("blocks")
          .delete()
          .eq("blocker_id", viewer.id)
          .eq("blocked_id", targetUserId);
        router.refresh();
      },
      durationMs: 6000,
    });
    router.refresh();
  };

  const deletePost = async () => {
    if (postId === undefined) return;
    setBusy(true);
    const supabase = createSupabaseBrowserClient();
    const { error } = await supabase.rpc("delete_post", { p_post: postId });
    setBusy(false);
    setConfirmDelete(false);
    if (error) {
      showToast(error.message);
      return;
    }
    showToast("Post deleted");
    router.refresh();
  };

  const itemClass =
    "flex min-h-11 w-full items-center gap-3 px-4 text-left text-body text-text-primary hover:bg-accent-subtle";
  const dangerClass =
    "flex min-h-11 w-full items-center gap-3 px-4 text-left text-body text-danger hover:bg-accent-subtle";

  return (
    <div ref={rootRef} className="relative" onClick={(event) => event.stopPropagation()}>
      <button
        ref={triggerRef}
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label={
          postId !== undefined ? `More options for post by @${targetHandle}` : `More options for @${targetHandle}`
        }
        onClick={() => setOpen((v) => !v)}
        className="flex min-h-11 min-w-11 items-center justify-center rounded-md text-text-secondary hover:bg-surface-raised hover:text-text-primary"
      >
        <DotsThree size={24} weight="bold" aria-hidden />
      </button>
      {open ? (
        <div
          role="menu"
          aria-label="Post options"
          className="absolute right-0 top-full z-30 min-w-60 rounded-md bg-surface-raised py-2 shadow-e2"
        >
          <button type="button" role="menuitem" className={itemClass} onClick={() => void copyLink()}>
            <LinkSimple size={20} aria-hidden /> Copy link
          </button>
          <div role="separator" className="my-1 border-t border-border" />
          {isOwn ? (
            postId !== undefined ? (
              <button
                type="button"
                role="menuitem"
                className={dangerClass}
                onClick={() => {
                  setOpen(false);
                  setConfirmDelete(true);
                }}
              >
                <Trash size={20} aria-hidden /> Delete post
              </button>
            ) : null
          ) : (
            <>
              <button type="button" role="menuitem" className={itemClass} onClick={() => void hide()}>
                <MinusCircle size={20} aria-hidden /> Show me less from @{targetHandle}
              </button>
              <button type="button" role="menuitem" className={itemClass} onClick={() => void mute()}>
                <SpeakerSimpleSlash size={20} aria-hidden /> Mute @{targetHandle}
              </button>
              <div role="separator" className="my-1 border-t border-border" />
              <button
                type="button"
                role="menuitem"
                className={dangerClass}
                onClick={() => {
                  setOpen(false);
                  setConfirmBlock(true);
                }}
              >
                <Prohibit size={20} aria-hidden /> Block @{targetHandle}
              </button>
              <button
                type="button"
                role="menuitem"
                className={dangerClass}
                onClick={() => {
                  setOpen(false);
                  setReportOpen(true);
                }}
              >
                <Flag size={20} aria-hidden /> Report
              </button>
            </>
          )}
        </div>
      ) : null}

      <ConfirmDialog
        open={confirmBlock}
        title={`Block @${targetHandle}?`}
        body="They will not be able to see your profile or posts, follow you, or message you. They will not be told."
        confirmLabel="Block"
        busy={busy}
        onCancel={() => setConfirmBlock(false)}
        onConfirm={() => void block()}
      />
      <ConfirmDialog
        open={confirmDelete}
        title="Delete this post?"
        body="This cannot be undone. Replies from other people stay in the conversation."
        confirmLabel="Delete"
        busy={busy}
        onCancel={() => setConfirmDelete(false)}
        onConfirm={() => void deletePost()}
      />
      <ReportDialog
        open={reportOpen}
        onClose={() => setReportOpen(false)}
        subjectHandle={targetHandle}
        subjectUserId={targetUserId}
        postId={postId}
        canBlock
      />
    </div>
  );
}
