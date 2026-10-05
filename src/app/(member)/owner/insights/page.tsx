import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getViewer } from "@/lib/auth";
import {
  FOUNDING_POSTURE_THRESHOLD,
  METRIC_REGISTRY,
  parseMetricsPayload,
  parseRange,
  RANGE_OPTIONS,
} from "@/lib/metrics";
import { MetricCard } from "@/components/owner/MetricCard";

export const metadata: Metadata = { title: "Insights" };

/**
 * Insights (Phase 2D spec, Part 2): the Owner's read-only metrics
 * dashboard. Aggregates only — there is no path from a number here to
 * a person; reaching a person is the directory's job, with its own
 * gates. The range control is URL state, so a view survives refresh.
 * The refused engagement metrics (spec §15) are absent by design and
 * by the database function's header contract.
 */
export default async function OwnerInsightsPage({
  searchParams,
}: {
  searchParams: Promise<{ range?: string }>;
}) {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  if (!viewer.isOwner) redirect("/home");

  const range = parseRange((await searchParams).range);
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("owner_metrics", { p_range: range });
  const payload = error ? null : parseMetricsPayload(data);

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-2">
        <h1 className="text-title">Insights</h1>
        <p className="max-w-prose text-body text-text-secondary">
          The shape of the community, in aggregate. Numbers, never people: reaching a member is
          what the directory is for.
        </p>
      </div>

      {payload && payload.total_members.value < FOUNDING_POSTURE_THRESHOLD ? (
        <p className="rounded-md bg-accent-subtle px-4 py-3 text-body text-text-primary">
          Hersciety is new. These numbers are small because the community is young, and that is
          exactly where you should be.
        </p>
      ) : null}

      <nav
        aria-label="Time range"
        className="flex max-w-md gap-1 rounded-md border border-border-strong p-1"
      >
        {RANGE_OPTIONS.map((option) => (
          <Link
            key={option.value}
            href={`/owner/insights?range=${option.value}`}
            aria-current={range === option.value ? "page" : undefined}
            className={`flex min-h-9 flex-1 items-center justify-center rounded-sm px-2 text-label transition-colors duration-(--duration-fast) ${
              range === option.value
                ? "bg-accent-subtle text-accent"
                : "text-text-secondary hover:bg-surface-raised"
            }`}
          >
            {option.label}
          </Link>
        ))}
      </nav>

      {!payload ? (
        <div className="flex flex-col items-center gap-2 rounded-lg border border-border bg-surface px-6 py-16 text-center shadow-e1">
          <h2 className="text-heading text-text-primary">Could not load the numbers</h2>
          <p className="max-w-sm text-body text-text-secondary">
            Nothing is lost. Reload the page to try again.
          </p>
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
          {METRIC_REGISTRY.map((descriptor) => (
            <MetricCard
              key={descriptor.id}
              descriptor={descriptor}
              payload={payload}
              range={range}
            />
          ))}
        </div>
      )}
    </div>
  );
}
