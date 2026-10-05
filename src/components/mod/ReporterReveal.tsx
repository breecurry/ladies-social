"use client";

import { useState } from "react";
import type { ModReporterRow } from "@/lib/database.types";

/**
 * Reporter identity is collapsed by default (design doc §3.3): merely
 * reading a case does not expose who reported. Revealing is an
 * intentional act and the database writes an audit entry for every
 * reveal. The 24-hour filing count beside a reporter is the
 * report-abuse tell, shown without punishing good-faith reporters.
 */
export function ReporterReveal({ target, postId }: { target: string; postId: number | null }) {
  const [reporters, setReporters] = useState<ModReporterRow[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reveal = async () => {
    setBusy(true);
    setError(null);
    const response = await fetch("/api/mod/reporters", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ target, postId }),
    });
    const result = (await response.json().catch(() => null)) as
      | { ok: boolean; reporters?: ModReporterRow[]; error?: string }
      | null;
    setBusy(false);
    if (!result?.ok) {
      setError(result?.error ?? "Could not load reporters.");
      return;
    }
    setReporters(result.reporters ?? []);
  };

  if (reporters !== null) {
    return (
      <div className="flex flex-col items-end gap-0.5">
        {reporters.map((row) => (
          <span key={row.report_id} className="text-caption text-text-secondary">
            @{row.reporter_handle}
            {row.reporter_reports_24h >= 10 ? (
              <span className="text-warning">
                {" "}
                · {row.reporter_reports_24h} reports in 24h
              </span>
            ) : null}
          </span>
        ))}
      </div>
    );
  }

  return (
    <div className="flex items-center gap-2">
      {error ? <span className="text-caption text-danger">{error}</span> : null}
      <button
        type="button"
        disabled={busy}
        onClick={() => void reveal()}
        className="min-h-9 rounded-md px-3 text-label text-accent hover:bg-accent-subtle disabled:opacity-50"
      >
        {busy ? "Loading…" : "Show reporters"}
      </button>
    </div>
  );
}
