"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { MagnifyingGlass } from "@phosphor-icons/react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { ModTagRow } from "@/lib/database.types";
import type { ModTier } from "@/lib/moderation";
import { ConfirmDialog } from "@/components/ConfirmDialog";
import { useToast } from "@/components/shell/ToastProvider";

/**
 * Staff tag suppression (Phase 2F §7.2): two proportional, reversible,
 * audited tiers. De-trend (moderator and above) pulls a tag out of
 * trending and search suggestions while its posts stay reachable;
 * Block (admin and above) also replaces the tag page with a neutral
 * unavailable state. Neither touches any post or any author.
 *
 * The "spiking from new accounts" line is the §7.3 anomaly signal:
 * calm information for a human to weigh, never an automatic action.
 */
export function TagControls({
  initialRows,
  tier,
}: {
  initialRows: ModTagRow[];
  tier: ModTier;
}) {
  const router = useRouter();
  const { showToast } = useToast();
  const [query, setQuery] = useState("");
  const [rows, setRows] = useState<ModTagRow[]>(initialRows);
  const [busyTag, setBusyTag] = useState<string | null>(null);
  const [confirmBlock, setConfirmBlock] = useState<string | null>(null);
  const timer = useRef<number | null>(null);
  const requestSeq = useRef(0);

  const canDetrend = tier === "moderator" || tier === "admin" || tier === "owner";
  const canBlockTag = tier === "admin" || tier === "owner";

  const refresh = async (term: string) => {
    const supabase = createSupabaseBrowserClient();
    const { data } = await supabase.rpc("mod_tag_lookup", {
      p_query: term === "" ? null : term,
      p_limit: 20,
    });
    setRows(data ?? []);
  };

  const onQueryChange = (value: string) => {
    setQuery(value);
    if (timer.current !== null) window.clearTimeout(timer.current);
    const seq = ++requestSeq.current;
    timer.current = window.setTimeout(() => {
      void refresh(value.trim()).then(() => {
        if (seq !== requestSeq.current) return;
      });
    }, 300);
  };

  const act = async (tag: string, action: "detrend" | "block" | "reinstate") => {
    setBusyTag(tag);
    const supabase = createSupabaseBrowserClient();
    const { error } =
      action === "detrend"
        ? await supabase.rpc("mod_detrend_tag", { p_tag: tag })
        : action === "block"
          ? await supabase.rpc("mod_block_tag", { p_tag: tag })
          : await supabase.rpc("mod_reinstate_tag", { p_tag: tag });
    setBusyTag(null);
    setConfirmBlock(null);
    if (error) {
      showToast(error.message);
      return;
    }
    showToast(
      action === "detrend"
        ? `#${tag} removed from trending and suggestions`
        : action === "block"
          ? `#${tag} blocked`
          : `#${tag} reinstated`,
    );
    await refresh(query.trim());
    router.refresh();
  };

  return (
    <div className="flex flex-col gap-4">
      <label className="flex min-h-11 items-center gap-2 rounded-full border border-border-strong bg-surface-raised px-4">
        <MagnifyingGlass size={20} aria-hidden className="text-text-tertiary" />
        <input
          type="search"
          value={query}
          onChange={(event) => onQueryChange(event.target.value)}
          placeholder="Look up a #topic"
          aria-label="Look up a topic"
          className="w-full bg-transparent text-body text-text-primary outline-none placeholder:text-text-tertiary"
        />
      </label>

      {rows.length === 0 ? (
        <p className="px-1 py-6 text-center text-body text-text-secondary">
          No topics {query.trim() === "" ? "yet" : "match"}.
        </p>
      ) : (
        <div className="flex flex-col overflow-hidden rounded-md border border-border">
          {rows.map((row) => {
            const spiking = row.people_48h >= 3 && row.new_account_share >= 0.5;
            return (
              <div
                key={row.tag}
                className="flex flex-col gap-2 border-b border-border bg-surface px-4 py-3 last:border-b-0"
              >
                <div className="flex items-center gap-2">
                  <span className="text-label font-semibold text-text-primary">#{row.tag}</span>
                  {row.status !== "active" ? (
                    <span className="rounded-full bg-accent-subtle px-2 py-0.5 text-micro text-accent">
                      {row.status === "detrended" ? "De-trended" : "Blocked"}
                    </span>
                  ) : null}
                </div>
                <p className="text-caption text-text-tertiary">
                  {row.post_count} {row.post_count === 1 ? "post" : "posts"} · {row.people_48h}{" "}
                  {row.people_48h === 1 ? "person" : "people"} in the last 48 hours
                  {row.people_48h > 0
                    ? ` · ${Math.round(row.new_account_share * 100)}% from accounts under a week old`
                    : ""}
                </p>
                {spiking ? (
                  <p className="text-caption text-warning">
                    This tag is spiking from new accounts. Worth a look.
                  </p>
                ) : null}
                <div className="flex flex-wrap gap-2">
                  {row.status === "active" && canDetrend ? (
                    <ActionButton
                      label="De-trend"
                      busy={busyTag === row.tag}
                      onClick={() => void act(row.tag, "detrend")}
                    />
                  ) : null}
                  {row.status !== "blocked" && canBlockTag ? (
                    <ActionButton
                      label="Block topic"
                      danger
                      busy={busyTag === row.tag}
                      onClick={() => setConfirmBlock(row.tag)}
                    />
                  ) : null}
                  {(row.status === "detrended" && canDetrend) ||
                  (row.status === "blocked" && canBlockTag) ? (
                    <ActionButton
                      label="Reinstate"
                      busy={busyTag === row.tag}
                      onClick={() => void act(row.tag, "reinstate")}
                    />
                  ) : null}
                </div>
              </div>
            );
          })}
        </div>
      )}

      <ConfirmDialog
        open={confirmBlock !== null}
        title={`Block #${confirmBlock ?? ""}?`}
        body="The topic page becomes unavailable and the tag leaves trending and search. Posts carrying it are untouched and stay on the ordinary per-post ladder. This is reversible."
        confirmLabel="Block topic"
        busy={busyTag !== null}
        onCancel={() => setConfirmBlock(null)}
        onConfirm={() => {
          if (confirmBlock !== null) void act(confirmBlock, "block");
        }}
      />
    </div>
  );
}

function ActionButton({
  label,
  busy,
  danger = false,
  onClick,
}: {
  label: string;
  busy: boolean;
  danger?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      disabled={busy}
      onClick={onClick}
      className={`min-h-9 rounded-full border px-4 text-label transition-colors duration-(--duration-fast) disabled:opacity-50 ${
        danger
          ? "border-danger-fill text-danger hover:bg-danger-fill/10"
          : "border-border-strong text-text-primary hover:bg-surface-raised"
      }`}
    >
      {label}
    </button>
  );
}
