"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { ModAvatarEvidenceRow, ReportReason } from "@/lib/database.types";
import { REASON_LABEL } from "@/lib/moderation";
import { avatarUrl, blurhashAverageColor } from "@/lib/media/avatar";
import { useToast } from "@/components/shell/ToastProvider";

/**
 * The reported-profile-photo panel in a case (spec P2E section 10): the
 * ONE place a live member photo can reach a staff surface, and only
 * deliberately — the image arrives blurred-by-default (no clear pixels
 * are painted until the reviewer acts) behind a content warning naming
 * the report category, with an explicit "Reveal image" consent step.
 * A csam-class image never reaches this panel at all: the database
 * excludes it (mod_avatar_evidence) and it lives behind the Owner's
 * existing escalation path.
 *
 * Removal here PRESERVES the object as evidence (the database refuses
 * to purge a moderation-removed or reported image) and is reversible
 * via Reinstate — the honest-mistake path.
 */
export function AvatarEvidence({
  rows,
  target,
  canAct,
}: {
  rows: ModAvatarEvidenceRow[];
  target: string;
  /** Moderator and up, and never on a child-safety case. */
  canAct: boolean;
}) {
  return (
    <section
      aria-label="Reported profile photo"
      className="rounded-lg border border-border bg-surface"
    >
      <h2 className="border-b border-border px-4 py-2 text-label text-text-secondary">
        Reported profile photo
      </h2>
      <ul>
        {rows.map((row) => (
          <EvidenceRow key={row.avatar_key} row={row} target={target} canAct={canAct} />
        ))}
      </ul>
    </section>
  );
}

const RULE_OPTIONS: ReportReason[] = [
  "harassment",
  "hate",
  "ncii",
  "impersonation",
  "doxxing",
  "spam",
  "other",
];

function EvidenceRow({
  row,
  target,
  canAct,
}: {
  row: ModAvatarEvidenceRow;
  target: string;
  canAct: boolean;
}) {
  const router = useRouter();
  const { showToast } = useToast();
  const [revealed, setRevealed] = useState(false);
  const [rule, setRule] = useState<ReportReason>(row.reason);
  const [busy, setBusy] = useState(false);

  const src = avatarUrl(row.avatar_key, 400);
  const averageColor = blurhashAverageColor(row.blurhash) ?? "var(--accent-subtle)";

  const act = async (action: "remove" | "reinstate") => {
    setBusy(true);
    const response = await fetch("/api/mod/avatar", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(action === "remove" ? { action, target, rule } : { action, target }),
    }).catch(() => null);
    const body = response ? ((await response.json()) as { ok: boolean; error?: string }) : null;
    setBusy(false);
    if (!body?.ok) {
      showToast(body?.error ?? "That did not go through. Try again.");
      return;
    }
    showToast(action === "remove" ? "Profile photo removed" : "Profile photo reinstated");
    router.refresh();
  };

  return (
    <li className="flex flex-wrap items-start gap-4 border-b border-border px-4 py-3 last:border-b-0">
      <div className="flex flex-col items-center gap-2">
        {revealed && src ? (
          // Evidence image from the media zone, deliberately revealed
          // by the reviewer.
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={src}
            alt="Reported profile photo, revealed"
            width={128}
            height={128}
            className="size-32 rounded-md object-cover"
            style={{ backgroundColor: averageColor }}
          />
        ) : (
          <div
            aria-hidden
            className="size-32 rounded-md"
            style={{ backgroundColor: averageColor }}
          />
        )}
        <button
          type="button"
          onClick={() => setRevealed((current) => !current)}
          className="min-h-11 rounded-md border border-border-strong bg-surface px-3 text-label text-text-primary hover:bg-surface-raised"
        >
          {revealed ? "Hide image" : "Reveal image"}
        </button>
      </div>

      <div className="flex min-w-48 flex-1 flex-col gap-1">
        <p className="text-label text-text-primary">Reported as: {REASON_LABEL[row.reason]}</p>
        <p className="text-caption text-text-tertiary">
          {row.is_current
            ? "Currently their profile photo."
            : row.removed
              ? "Removed from their profile; the image is preserved as evidence."
              : "No longer their profile photo; this copy is frozen from the report."}
        </p>
        <p className="text-caption text-text-tertiary">
          The image is blurred until you choose to view it.
        </p>

        {canAct && row.is_current ? (
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <label className="flex items-center gap-2">
              <span className="text-caption text-text-secondary">Rule</span>
              <select
                value={rule}
                onChange={(event) => setRule(event.target.value as ReportReason)}
                className="min-h-11 rounded-md border border-border-strong bg-surface px-2 text-body text-text-primary"
              >
                {RULE_OPTIONS.map((option) => (
                  <option key={option} value={option}>
                    {REASON_LABEL[option]}
                  </option>
                ))}
              </select>
            </label>
            <button
              type="button"
              disabled={busy}
              onClick={() => void act("remove")}
              className="min-h-11 rounded-md bg-danger-fill px-4 text-label text-white hover:bg-danger-hover disabled:opacity-50"
            >
              {busy ? "Working…" : "Remove profile photo"}
            </button>
          </div>
        ) : null}
        {canAct && row.removed ? (
          <div className="mt-2">
            <button
              type="button"
              disabled={busy}
              onClick={() => void act("reinstate")}
              className="min-h-11 rounded-md border border-border-strong bg-surface px-4 text-label text-text-primary hover:bg-surface-raised disabled:opacity-50"
            >
              {busy ? "Working…" : "Reinstate photo"}
            </button>
          </div>
        ) : null}
      </div>
    </li>
  );
}
