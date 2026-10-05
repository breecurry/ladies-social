import { ArrowDown, ArrowUp, Minus } from "@phosphor-icons/react/dist/ssr";
import type { MetricDescriptor, MetricRange, OwnerMetricsPayload } from "@/lib/metrics";
import { PERCENT_BASE_THRESHOLD } from "@/lib/metrics";

/**
 * THE metric card (Phase 2D spec §11): one component renders every
 * descriptor, and its states — value, honest zero, not-enough-data,
 * suppressed breakdown — are defined here once so a new metric cannot
 * forget them. No counting-up animations, no gauges: a calm number on
 * calm paper.
 */
export function MetricCard({
  descriptor,
  payload,
  range,
}: {
  descriptor: MetricDescriptor;
  payload: OwnerMetricsPayload;
  range: MetricRange;
}) {
  const metric = descriptor.select(payload);
  const points = metric.series ?? [];

  return (
    <section
      aria-label={descriptor.label}
      className="flex flex-col gap-2 rounded-lg border border-border bg-surface-raised p-5 shadow-e1"
    >
      <h2 className="text-label text-text-secondary">{descriptor.label}</h2>
      <p className="text-display text-text-primary">
        {metric.value.toLocaleString("en-US")}
        {descriptor.unit ? (
          <span className="ml-2 text-body text-text-secondary">{descriptor.unit}</span>
        ) : null}
      </p>

      {metric.value === 0 && metric.zeroNote ? (
        <p className="text-caption text-text-tertiary">{metric.zeroNote}</p>
      ) : null}

      {metric.subline ? <p className="text-caption text-text-secondary">{metric.subline}</p> : null}

      <Comparison
        previous={metric.previous}
        value={metric.value}
        good={descriptor.goodDirection}
        range={range}
      />

      {descriptor.fixedWindowNote ? (
        <p className="text-caption text-text-tertiary">{descriptor.fixedWindowNote}</p>
      ) : null}

      {points.length > 0 ? <Sparkline points={points.map((point) => point.v)} /> : null}

      {metric.breakdown && metric.breakdown.length > 0 ? (
        <dl className="mt-1 flex flex-col gap-1 border-t border-border pt-2">
          {metric.breakdown.map((entry) => {
            const label = entry.status ?? entry.action ?? "";
            return (
              <div key={label} className="flex items-baseline justify-between gap-2">
                <dt className="text-caption text-text-tertiary capitalize">
                  {label.replace(/_/g, " ")}
                </dt>
                <dd className="text-caption text-text-secondary">
                  {entry.suppressed ? (
                    <span className="text-text-tertiary">
                      Fewer than 5 · hidden to protect individuals
                    </span>
                  ) : (
                    (entry.count ?? 0).toLocaleString("en-US")
                  )}
                </dd>
              </div>
            );
          })}
        </dl>
      ) : null}
    </section>
  );
}

/**
 * The comparison line (spec §14): a signed absolute change always; a
 * percentage only above the base threshold, so the dashboard never
 * tells a dramatic percentage story about three people. No prior
 * period means an honest "not enough history", never a fake 0%.
 */
function Comparison({
  previous,
  value,
  good,
  range,
}: {
  previous: number | null | undefined;
  value: number;
  good: "up" | "neutral";
  range: MetricRange;
}) {
  if (previous === undefined) return null;
  if (previous === null) {
    return range === "all" ? null : (
      <p className="text-caption text-text-tertiary">Not enough history yet to show a trend</p>
    );
  }
  const delta = value - previous;
  const Glyph = delta > 0 ? ArrowUp : delta < 0 ? ArrowDown : Minus;
  const tone =
    delta === 0 || good === "neutral"
      ? "text-text-tertiary"
      : delta > 0
        ? "text-success"
        : "text-text-tertiary";
  const percent =
    previous >= PERCENT_BASE_THRESHOLD ? ` (${delta >= 0 ? "+" : ""}${Math.round((delta / previous) * 100)}%)` : "";
  return (
    <p className={`flex items-center gap-1 text-caption ${tone}`}>
      <Glyph size={12} weight="bold" aria-hidden />
      {delta >= 0 ? "+" : ""}
      {delta.toLocaleString("en-US")}
      {percent} vs the previous period
    </p>
  );
}

/**
 * The single-series sparkline (spec §11.1, §21): drawn in accent with
 * marked data points, no draw-in animation. At tiny N it is dots, not
 * a confident curve — two points never imply a trajectory (spec §13).
 */
function Sparkline({ points }: { points: number[] }) {
  const width = 160;
  const height = 36;
  const max = Math.max(...points, 1);
  const step = points.length > 1 ? width / (points.length - 1) : 0;
  const coords = points.map((value, index) => ({
    x: points.length > 1 ? index * step : width / 2,
    y: height - 4 - (value / max) * (height - 8),
  }));
  return (
    <svg
      viewBox={`0 0 ${width} ${height}`}
      className="mt-1 h-9 w-full max-w-40"
      role="img"
      aria-label={`Trend: ${points.join(", ")}`}
    >
      {coords.length >= 3 ? (
        <polyline
          points={coords.map((coord) => `${coord.x},${coord.y}`).join(" ")}
          fill="none"
          stroke="var(--accent)"
          strokeWidth="1.5"
        />
      ) : null}
      {coords.map((coord, index) => (
        <circle key={index} cx={coord.x} cy={coord.y} r="2" fill="var(--accent)" />
      ))}
    </svg>
  );
}
