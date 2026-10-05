"use client";

import { useState } from "react";
import { DownloadSimple } from "@phosphor-icons/react/dist/ssr";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { DirectoryFilterArgs } from "@/lib/database.types";
import { ConfirmDialog } from "@/components/ConfirmDialog";
import { useToast } from "@/components/shell/ToastProvider";

/**
 * "Export this view" (Phase 2D spec §9.2): the directory's single bulk
 * operation, a deliberate, logged, identity-free READ. It exports
 * exactly the current filtered view, contains only glance-level
 * columns (never a legal name, email, phone, or IP — the database
 * function cannot return them), and every export is written to the
 * audit log with its filter set and row count. The confirmation uses
 * the ordinary distinct-verb pattern; the typed gate stays reserved
 * for the product's one unrecoverable action.
 */
export function ExportButton({
  filters,
  matchCount,
}: {
  filters: DirectoryFilterArgs;
  matchCount: number;
}) {
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const { showToast } = useToast();

  const runExport = async () => {
    setBusy(true);
    const supabase = createSupabaseBrowserClient();
    const { data, error } = await supabase.rpc("owner_directory_export", filters);
    setBusy(false);
    setConfirming(false);
    if (error || !data) {
      showToast("Could not export this view. Try again.");
      return;
    }
    const header = "handle,joined,status,role,activity,founding";
    const lines = data.map((row) =>
      [
        `@${row.handle}`,
        row.joined_at.slice(0, 10),
        row.status,
        row.staff_role ?? "",
        `"${row.activity_bucket}"`,
        row.founding ? "yes" : "",
      ].join(","),
    );
    const blob = new Blob([[header, ...lines].join("\n")], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `hersciety-members-${new Date().toISOString().slice(0, 10)}.csv`;
    anchor.click();
    URL.revokeObjectURL(url);
    showToast(`Exported ${data.length} member${data.length === 1 ? "" : "s"}. Logged.`);
  };

  return (
    <>
      <button
        type="button"
        onClick={() => setConfirming(true)}
        className="inline-flex min-h-11 items-center gap-2 rounded-md border border-border-strong bg-surface px-4 text-label text-text-primary hover:bg-surface-raised"
      >
        <DownloadSimple size={18} aria-hidden /> Export this view
      </button>
      <ConfirmDialog
        open={confirming}
        title="Export this view"
        body={`This exports the ${matchCount} member${matchCount === 1 ? "" : "s"} in the current view — handles, dates, status, role, and activity bucket only, never identity or contact details. The export is recorded in the audit log.`}
        confirmLabel={`Export ${matchCount} member${matchCount === 1 ? "" : "s"}`}
        busy={busy}
        onCancel={() => setConfirming(false)}
        onConfirm={() => void runExport()}
      />
    </>
  );
}
