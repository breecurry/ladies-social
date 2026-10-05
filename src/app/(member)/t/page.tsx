import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { TrendUp } from "@phosphor-icons/react/dist/ssr";
import { getViewer } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { ComposeLink } from "@/components/tags/TrendingModule";

export const metadata: Metadata = { title: "Trending" };

/**
 * The full trending page (Phase 2F §6.3): up to twenty tags from the
 * 48-hour window, ranked by recency-weighted DISTINCT-PERSON score.
 * Counts are real and literal however small; an empty window shows the
 * honest zero framed as an invitation, never "not enough data".
 */
export default async function TrendingPage() {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");

  const supabase = await createSupabaseServerClient();
  const { data } = await supabase.rpc("get_trending_tags", { p_limit: 20 });
  const rows = data ?? [];

  return (
    <div className="flex flex-col lg:mt-6 lg:overflow-hidden lg:rounded-lg lg:border lg:border-border lg:shadow-e1">
      <header className="border-b border-border bg-surface px-4 py-4">
        <h1 className="text-title text-text-primary">Trending</h1>
        <p className="text-caption text-text-tertiary">
          Topics people are talking about over the last two days.
        </p>
      </header>
      {rows.length === 0 ? (
        <div className="flex flex-col items-center gap-3 px-6 py-16 text-center">
          <TrendUp size={48} aria-hidden className="text-text-tertiary" />
          <h2 className="text-title text-text-primary">No topics yet</h2>
          <p className="text-body text-text-secondary">
            Add a #hashtag to a post and start one.
          </p>
          <ComposeLink />
        </div>
      ) : (
        <div className="flex flex-col">
          {rows.map((row) => (
            <Link
              key={row.tag}
              href={`/t/${encodeURIComponent(row.tag)}`}
              aria-label={`hashtag ${row.tag}, ${row.distinct_people} ${row.distinct_people === 1 ? "person" : "people"}`}
              className="flex min-h-11 items-center justify-between border-b border-border bg-surface px-4 py-3 transition-colors duration-(--duration-fast) hover:bg-surface-raised"
            >
              <span className="text-label text-accent">#{row.tag}</span>
              <span className="text-caption text-text-tertiary">
                {row.distinct_people} {row.distinct_people === 1 ? "person" : "people"}
              </span>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
