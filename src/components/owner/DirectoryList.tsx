"use client";

import { useState } from "react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { DirectoryFilterArgs, DirectoryRow } from "@/lib/database.types";
import { FILTERED_WINDOW, PAGE_SIZE, RECENT_WINDOW } from "@/lib/directory";
import { MemberRow } from "@/components/owner/MemberRow";

/**
 * The directory list (Phase 2D spec §4.3): keyset-paged on
 * (created_at, user_id), newest join first. The unfiltered, no-intent
 * view is capped at the recent window and closes with a card that
 * points to search and filter — the directory deliberately refuses to
 * be an endless scroll of everyone. A filtered view loads its bounded
 * set, with a "too many results" note past the working window.
 */
export function DirectoryList({
  initialRows,
  filters,
  hasIntent,
  matchCount,
}: {
  initialRows: DirectoryRow[];
  filters: DirectoryFilterArgs;
  hasIntent: boolean;
  matchCount: number;
}) {
  const [rows, setRows] = useState<DirectoryRow[]>(initialRows);
  const [exhausted, setExhausted] = useState(initialRows.length < PAGE_SIZE);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(false);

  const cap = hasIntent ? FILTERED_WINDOW : RECENT_WINDOW;
  const capped = rows.length >= cap;

  const loadMore = async () => {
    setLoading(true);
    setError(false);
    const last = rows[rows.length - 1];
    const supabase = createSupabaseBrowserClient();
    const { data, error: rpcError } = await supabase.rpc("owner_directory", {
      ...filters,
      p_before_created: last?.joined_at ?? null,
      p_before_user: last?.user_id ?? null,
      p_limit: PAGE_SIZE,
    });
    setLoading(false);
    if (rpcError || !data) {
      setError(true);
      return;
    }
    setRows((current) => {
      const seen = new Set(current.map((row) => row.user_id));
      return [...current, ...data.filter((row) => !seen.has(row.user_id))];
    });
    if (data.length < PAGE_SIZE) setExhausted(true);
  };

  if (rows.length === 0) {
    return (
      <p className="px-4 py-10 text-center text-body text-text-secondary">
        {hasIntent ? "No one matches this view right now." : "No members yet. You are the first."}
      </p>
    );
  }

  return (
    <div className="flex flex-col">
      <ul>
        {rows.map((row) => (
          <MemberRow key={row.user_id} row={row} />
        ))}
      </ul>

      {error ? (
        <p className="px-4 py-4 text-center text-body text-text-secondary">
          Something went wrong loading the directory.{" "}
          <button type="button" onClick={() => void loadMore()} className="text-accent underline">
            Retry
          </button>
        </p>
      ) : capped && !exhausted ? (
        <p className="px-4 py-8 text-center text-body text-text-secondary">
          {hasIntent
            ? `Showing the first ${rows.length} of ${matchCount} matches. Narrow your search or add a filter to see fewer.`
            : `This is the most recent ${rows.length} members. To find anyone else, search their @handle or add a filter above.`}
        </p>
      ) : exhausted ? (
        <p className="px-4 py-8 text-center text-body text-text-secondary">
          {hasIntent ? "That is everyone who matches." : "That is everyone, for now."}
        </p>
      ) : (
        <button
          type="button"
          onClick={() => void loadMore()}
          disabled={loading}
          className="min-h-11 border-t border-border px-4 text-label text-accent hover:bg-accent-subtle disabled:opacity-50"
        >
          {loading ? "Loading…" : "Load more"}
        </button>
      )}
    </div>
  );
}
