import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getViewer } from "@/lib/auth";
import {
  GROUP_LABEL,
  GROUP_ORDER,
  METRIC_REGISTRY,
  parseMetricsPayload,
  parseRange,
  RANGE_OPTIONS,
} from "@/lib/metrics";
import { MetricCard } from "@/components/owner/MetricCard";

export const metadata: Metadata = { title: "Insights" };

/**
 * Insights: the Owner's read-only full-analytics dashboard. Every
 * number is the literal number — membership, engagement, growth,
 * content, per-member leaderboards, and safety operations. Per-member
 * figures are @handle-keyed; reaching an identity stays the
 * directory's audited job. The range control is URL state, so a view
 * survives refresh.
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
          The whole picture, in exact numbers. Everything starts at zero, goes up by one when it
          increases by one, and down by one when it decreases by one.
        </p>
      </div>

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
        GROUP_ORDER.map((group) => (
          <section key={group} aria-labelledby={`metrics-${group}`} className="flex flex-col gap-3">
            <h2 id={`metrics-${group}`} className="text-heading text-text-primary">
              {GROUP_LABEL[group]}
            </h2>
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
              {METRIC_REGISTRY.filter((descriptor) => descriptor.group === group).map(
                (descriptor) => (
                  <MetricCard
                    key={descriptor.id}
                    descriptor={descriptor}
                    payload={payload}
                    range={range}
                  />
                ),
              )}
            </div>
          </section>
        ))
      )}
    </div>
  );
}
