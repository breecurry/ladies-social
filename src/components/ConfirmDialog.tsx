"use client";

import type { ReactNode } from "react";
import { Dialog } from "@/components/Dialog";

/**
 * Confirmation step for heavier actions (block, unfollow, delete).
 * Cancel is the default focus so an accidental Enter does nothing
 * destructive (spec §10.2).
 */
export function ConfirmDialog({
  open,
  title,
  body,
  confirmLabel,
  busy = false,
  onCancel,
  onConfirm,
}: {
  open: boolean;
  title: string;
  body: ReactNode;
  confirmLabel: string;
  busy?: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  return (
    <Dialog open={open} onClose={onCancel} label={title} sheet={false} maxWidth="max-w-sm">
      <div className="flex flex-col gap-3 p-5">
        <h2 className="text-heading">{title}</h2>
        <p className="text-body text-text-secondary">{body}</p>
        <div className="flex justify-end gap-2 pt-2">
          <button
            type="button"
            data-autofocus
            onClick={onCancel}
            className="min-h-11 rounded-md px-4 text-label text-accent hover:bg-accent-subtle"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={busy}
            onClick={onConfirm}
            className="min-h-11 rounded-md bg-danger-fill px-4 text-label text-white hover:bg-danger-hover disabled:opacity-50"
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </Dialog>
  );
}
