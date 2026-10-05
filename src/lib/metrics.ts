import type { Json } from "@/lib/database.types";

/**
 * The metrics foundation (Phase 2D spec, Part 2). A metric is declared
 * as data — a descriptor in the registry below — and rendered by one
 * component, the MetricCard. Adding the twentieth metric is adding a
 * twentieth descriptor; it is never designing a twentieth card.
 *
 * 🚨 THE REFUSED METRICS STAY REFUSED (spec §15, owner-confirmed):
 * time on site / session length, DAU / MAU / stickiness, streaks and
 * daily-return mechanics, per-member engagement rankings and
 * leaderboards, "who is online now" / precise per-member presence,
 * and virality coefficients. Do not add a descriptor for any of them.
 * The dashboard measures the community in aggregate; it does not rank
 * or watch the women in it.
 */

export type MetricRange = "today" | "7d" | "30d" | "all";

export const RANGE_OPTIONS: readonly { value: MetricRange; label: string }[] = [
  { value: "today", label: "Today" },
  { value: "7d", label: "7 days" },
  { value: "30d", label: "30 days" },
  { value: "all", label: "All time" },
];

export function parseRange(value: string | undefined): MetricRange {
  return RANGE_OPTIONS.some((option) => option.value === value)
    ? (value as MetricRange)
    : "30d";
}

/** One point of an aggregate time series (a count per time bucket —
 * never a per-member fact). */
export type SeriesPoint = { t: string; v: number };

/** One segment of a breakdown. `count` is null when the server
 * suppressed a sub-floor value (spec §16). */
export type BreakdownEntry = {
  status?: string;
  action?: string;
  count: number | null;
  suppressed: boolean;
};

/** The owner_metrics() payload, shaped by the database function. */
export type OwnerMetricsPayload = {
  range: string;
  suppression_floor: number;
  total_members: {
    value: number;
    deactivated: number;
    joined_in_range: number;
    breakdown: BreakdownEntry[];
  };
  signups: { value: number; previous: number | null; series: SeriesPoint[] };
  active_members: { value: number; window_days: number; total: number };
  posts: { value: number; previous: number | null; series: SeriesPoint[] };
  reports_filed: { value: number; previous: number | null };
  reports_resolved: { value: number; filed: number; median_hours: number | null };
  enforcement_actions: { value: number; breakdown: BreakdownEntry[] };
};

/** The payload is built by jsonb_build_object with exactly this shape;
 * the cast narrows the generic Json the client sees. */
export function parseMetricsPayload(data: Json): OwnerMetricsPayload | null {
  if (typeof data !== "object" || data === null || Array.isArray(data)) return null;
  return data as unknown as OwnerMetricsPayload;
}

/** Below this comparison base a percentage is misleading and the card
 * shows the absolute change only (spec §14). */
export const PERCENT_BASE_THRESHOLD = 20;

/** The dashboard says it is early while the community is genuinely
 * tiny (spec §13). */
export const FOUNDING_POSTURE_THRESHOLD = 25;

export type MetricGroup = "membership" | "growth" | "content" | "safety";

export const GROUP_ORDER: readonly MetricGroup[] = ["membership", "growth", "content", "safety"];

/** What one card needs to render, selected from the payload. */
export type MetricValue = {
  value: number;
  /** Previous equal period, when the metric compares (null = no prior
   * period, e.g. the all-time range: no fake trend). */
  previous?: number | null;
  series?: SeriesPoint[];
  breakdown?: BreakdownEntry[];
  /** One quiet contextual line under the value. */
  subline?: string;
  /** Framing for an honest zero (spec §11.2). */
  zeroNote?: string;
};

export type MetricDescriptor = {
  id: string;
  label: string;
  group: MetricGroup;
  /** The unit noun beside the value ("members", "posts"). */
  unit?: string;
  /** Whether the metric follows the global range control; a fixed-
   * window metric states its own window instead (spec §14). */
  fixedWindowNote?: string;
  /** Whether "up" is healthy ("up"), or direction carries no default
   * judgement ("neutral" — e.g. reports; spec §11.1). */
  goodDirection: "up" | "neutral";
  select: (payload: OwnerMetricsPayload) => MetricValue;
};

/**
 * The day-one registry (spec §12), in the dashboard's deliberate
 * order: membership, growth, content, then safety and operations.
 */
export const METRIC_REGISTRY: readonly MetricDescriptor[] = [
  {
    id: "total_members",
    label: "Total members",
    group: "membership",
    unit: "members",
    goodDirection: "up",
    select: (payload) => ({
      value: payload.total_members.value,
      previous: null,
      breakdown: payload.total_members.breakdown,
      subline:
        payload.total_members.deactivated > 0
          ? `${payload.total_members.deactivated} deactivated (stepped away, counted)`
          : undefined,
    }),
  },
  {
    id: "signups",
    label: "New members",
    group: "growth",
    unit: "joined",
    goodDirection: "up",
    select: (payload) => ({
      value: payload.signups.value,
      previous: payload.signups.previous,
      series: payload.signups.series,
      zeroNote: "No one joined in this range. Early days.",
    }),
  },
  {
    id: "active_members",
    label: "Active members",
    group: "membership",
    unit: "members",
    fixedWindowNote: "Last 30 days, always — a health reading, not a daily dial.",
    goodDirection: "up",
    select: (payload) => ({
      value: payload.active_members.value,
      previous: null,
      subline: `of ${payload.active_members.total.toLocaleString("en-US")} member${
        payload.active_members.total === 1 ? "" : "s"
      }`,
    }),
  },
  {
    id: "posts",
    label: "Posts",
    group: "content",
    unit: "posts",
    goodDirection: "up",
    select: (payload) => ({
      value: payload.posts.value,
      previous: payload.posts.previous,
      series: payload.posts.series,
      zeroNote: "No posts in this range yet.",
    }),
  },
  {
    id: "reports_filed",
    label: "Reports filed",
    group: "safety",
    unit: "reports",
    goodDirection: "neutral",
    select: (payload) => ({
      value: payload.reports_filed.value,
      previous: payload.reports_filed.previous,
      zeroNote: "No reports filed. That is a good sign.",
    }),
  },
  {
    id: "reports_resolved",
    label: "Reports resolved",
    group: "safety",
    unit: "resolved",
    goodDirection: "up",
    select: (payload) => ({
      value: payload.reports_resolved.value,
      previous: null,
      subline:
        payload.reports_resolved.median_hours !== null
          ? `median time to resolution ${payload.reports_resolved.median_hours}h`
          : undefined,
      zeroNote:
        payload.reports_resolved.filed === 0
          ? "Nothing to resolve. That is a good sign."
          : undefined,
    }),
  },
  {
    id: "enforcement_actions",
    label: "Enforcement actions",
    group: "safety",
    goodDirection: "neutral",
    unit: "actions",
    select: (payload) => ({
      value: payload.enforcement_actions.value,
      previous: null,
      breakdown: payload.enforcement_actions.breakdown,
      zeroNote: "No enforcement needed in this range.",
    }),
  },
];
