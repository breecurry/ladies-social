import { ArrowDown, ArrowUp, Minus } from "@phosphor-icons/react/dist/ssr";
import type { MetricDescriptor, MetricRange, OwnerMetricsPayload } from "@/lib/metrics";

/**
 * THE metric card: one component renders every descriptor. The value
 * is the literal value — a zero is 0, a one is 1, a real change on a
 * small base is a real percentage. No counting-up animations, no
 * gauges: a calm number on calm paper.
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
      <h3 className="text-label text-text-secondary">{descriptor.label}</h3>
      <p className="text-display text-text-primary">
        {metric.value.toLocaleString("en-US")}
        {descriptor.unit ? (
          <span className="ml-2 text-body text-text-secondary">{descriptor.unit}</span>
        ) : null}
      </p>

      {metric.subline ? <p className="text-caption text-text-secondary">{metric.subline}</p> : null}

      <Comparison previous={metric.previous} value={metric.value} good={descriptor.goodDirection} range={range} />

      {descriptor.note ? (
        <p className="text-caption text-text-tertiary">{descriptor.note}</p>
      ) : null}

      {points.length > 0 ? <Sparkline points={points.map((point) => point.v)} /> : null}

      {metric.rows && metric.rows.length > 0 ? (
        <dl className="mt-1 flex flex-col gap-1 border-t border-border pt-2">
          {metric.rows.map((row) => (
            <div key={row.label} className="flex items-baseline justify-between gap-2">
              <dt className="text-caption text-text-tertiary capitalize">
                {row.label.replace(/_/g, " ")}
              </dt>
              <dd className="text-caption text-text-secondary">{row.detail}</dd>
            </div>
          ))}
        </dl>
      ) : null}
    </section>
  );
}

/**
 * The comparison line: the signed absolute change and the real
 * percentage, at any base. No prior period (the all-time range) means
 * no comparison line; a prior period of zero shows the absolute
 * change alone, because a percentage of zero is undefined, not
 * withheld.
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
  if (previous === undefined || previous === null || range === "all") return null;
  const delta = value - previous;
  const Glyph = delta > 0 ? ArrowUp : delta < 0 ? ArrowDown : Minus;
  const tone =
    delta === 0 || good === "neutral"
      ? "text-text-tertiary"
      : delta > 0
        ? "text-success"
        : "text-text-tertiary";
  const percent =
    previous > 0 ? ` (${delta >= 0 ? "+" : ""}${Math.round((delta / previous) * 100)}%)` : "";
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
 * The single-series sparkline: drawn in accent with marked data
 * points, no draw-in animation. Any two or more points draw the real
 * line through the real values.
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
      {coords.length >= 2 ? (
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
