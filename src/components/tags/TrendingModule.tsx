"use client";

import Link from "next/link";
import { useCompose } from "@/components/shell/ComposeProvider";
import type { TrendingTagRow } from "@/lib/database.types";

/**
 * The compact Trending module (Phase 2F §6): up to five rows, each the
 * tag in accent plus its honest distinct-person count — 1 is 1, and an
 * empty window is a real zero framed as an invitation, never a
 * "not enough data" message. Lives on the pre-query Search screen; the
 * See-more link opens the full /t trending page.
 */
export function TrendingModule({ rows }: { rows: TrendingTagRow[] }) {
  const { openCompose } = useCompose();

  return (
    <section aria-label="Trending" className="flex w-full flex-col gap-1 text-left">
      <div className="flex items-center justify-between px-1">
        <h3 className="text-heading text-text-primary">Trending</h3>
        {rows.length > 0 ? (
          <Link href="/t" className="text-label text-accent hover:underline">
            See more
          </Link>
        ) : null}
      </div>
      {rows.length === 0 ? (
        <div className="flex flex-col gap-2 rounded-md border border-border bg-surface px-4 py-4">
          <p className="text-body text-text-primary">No topics yet</p>
          <p className="text-caption text-text-tertiary">
            Add a #hashtag to a post and start one.
          </p>
          <button
            type="button"
            onClick={() => openCompose()}
            className="self-start text-label text-accent hover:underline"
          >
            Write a post
          </button>
        </div>
      ) : (
        <div className="flex flex-col overflow-hidden rounded-md border border-border bg-surface">
          {rows.slice(0, 5).map((row) => (
            <Link
              key={row.tag}
              href={`/t/${encodeURIComponent(row.tag)}`}
              aria-label={`hashtag ${row.tag}, ${row.distinct_people} ${row.distinct_people === 1 ? "person" : "people"}`}
              className="flex min-h-11 items-center justify-between gap-3 px-4 py-2 transition-colors duration-(--duration-fast) hover:bg-surface-raised"
            >
              <span className="min-w-0 truncate text-label text-accent">#{row.tag}</span>
              <span className="shrink-0 text-caption text-text-tertiary">
                {row.distinct_people} {row.distinct_people === 1 ? "person" : "people"}
              </span>
            </Link>
          ))}
        </div>
      )}
    </section>
  );
}

/** The trending empty state's compose action, shared with the /t page. */
export function ComposeLink() {
  const { openCompose } = useCompose();
  return (
    <button
      type="button"
      onClick={() => openCompose()}
      className="min-h-11 rounded-full bg-accent-fill px-6 text-label text-on-accent hover:bg-accent-hover"
    >
      Write a post
    </button>
  );
}
