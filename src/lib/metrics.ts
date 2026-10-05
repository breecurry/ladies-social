import type { Json } from "@/lib/database.types";

/**
 * The metrics foundation (Phase 2D, corrected by the owner's
 * full-analytics decision). A metric is declared as data — a
 * descriptor in the registry below — and rendered by one component,
 * the MetricCard. Adding the fiftieth metric is adding a fiftieth
 * descriptor; it is never designing a fiftieth card.
 *
 * Every number is the literal number: it starts at zero, goes up by
 * one when it increases by one, and down by one when it decreases by
 * one. Nothing is suppressed, floored, bucketed, or withheld on this
 * surface. Per-member figures are keyed to @handle — never a legal
 * name; the audited identity reveal remains the only path to one.
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

/** One point of a time series (a count per time bucket). */
export type SeriesPoint = { t: string; v: number };

/** One exact segment of a breakdown. */
export type BreakdownEntry = { label: string; count: number };

/** One per-member figure, @handle-keyed. */
export type LeaderboardEntry = { handle: string; value: number };

/** One member's precise last-seen moment. */
export type PresenceEntry = { handle: string; last_seen: string };

/** One retention checkpoint: the real cohort share. */
export type RetentionPoint = {
  eligible: number;
  returned: number;
  rate: number | null;
};

/** The owner_metrics() payload, shaped by the database function. */
export type OwnerMetricsPayload = {
  range: string;
  total_members: {
    value: number;
    deactivated: number;
    joined_in_range: number;
    departed_in_range: number;
    returned_in_range: number;
    net_change: number;
    departures_tracked_since: string | null;
    breakdown: BreakdownEntry[];
  };
  signups: { value: number; previous: number | null; series: SeriesPoint[] };
  active_members: { value: number; window_days: number; total: number };
  posts: { value: number; previous: number | null; series: SeriesPoint[] };
  reports_filed: { value: number; previous: number | null };
  reports_resolved: { value: number; filed: number; median_hours: number | null };
  enforcement_actions: { value: number; breakdown: BreakdownEntry[] };
  engagement: { dau: number; wau: number; mau: number; stickiness: number | null };
  sessions: {
    count: number;
    total_minutes: number;
    average_minutes: number;
    median_minutes: number;
    tracked_since: string | null;
  };
  presence: {
    online_now: number;
    online: PresenceEntry[];
    last_seen: PresenceEntry[];
  };
  leaderboards: {
    top_posters: LeaderboardEntry[];
    likes_given: LeaderboardEntry[];
    likes_received: LeaderboardEntry[];
    by_sessions: LeaderboardEntry[];
    follower_growth: LeaderboardEntry[];
  };
  streaks: { longest_current: number; members: LeaderboardEntry[] };
  virality: {
    posts_per_member: number | null;
    likes_per_post: number | null;
    avg_reply_depth: number;
    max_reply_depth: number;
    likes_in_range: number;
    follows_in_range: number;
  };
  retention: { d1: RetentionPoint; d7: RetentionPoint; d30: RetentionPoint };
};

/** The payload is built by jsonb_build_object with exactly this shape;
 * the cast narrows the generic Json the client sees. */
export function parseMetricsPayload(data: Json): OwnerMetricsPayload | null {
  if (typeof data !== "object" || data === null || Array.isArray(data)) return null;
  return data as unknown as OwnerMetricsPayload;
}

export type MetricGroup =
  | "membership"
  | "engagement"
  | "growth"
  | "content"
  | "leaderboards"
  | "safety";

export const GROUP_ORDER: readonly MetricGroup[] = [
  "membership",
  "engagement",
  "growth",
  "content",
  "leaderboards",
  "safety",
];

export const GROUP_LABEL: Record<MetricGroup, string> = {
  membership: "Membership",
  engagement: "Engagement",
  growth: "Growth",
  content: "Content",
  leaderboards: "Leaderboards",
  safety: "Safety and operations",
};

/** One labelled line under a card's value (a breakdown segment, a
 * leaderboard row, a member's precise last-seen). */
export type MetricRow = { label: string; detail: string };

/** What one card needs to render, selected from the payload. */
export type MetricValue = {
  value: number;
  /** Previous equal period, when the metric compares (null = no prior
   * period exists, e.g. the all-time range). */
  previous?: number | null;
  series?: SeriesPoint[];
  rows?: MetricRow[];
  /** One contextual line under the value. */
  subline?: string;
};

export type MetricDescriptor = {
  id: string;
  label: string;
  group: MetricGroup;
  /** The unit noun beside the value ("members", "posts", "%"). */
  unit?: string;
  /** A fixed-window or collection-start note shown on the card. */
  note?: string;
  /** Whether "up" is healthy ("up"), or direction carries no default
   * judgement ("neutral" — e.g. reports). */
  goodDirection: "up" | "neutral";
  select: (payload: OwnerMetricsPayload) => MetricValue;
};

function formatNumber(value: number): string {
  return value.toLocaleString("en-US");
}

function formatMoment(iso: string): string {
  return new Date(iso).toLocaleString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "UTC",
  });
}

function formatDay(iso: string): string {
  return new Date(iso).toLocaleDateString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
    timeZone: "UTC",
  });
}

function leaderboardValue(entries: LeaderboardEntry[], unit: string): MetricValue {
  const top = entries.length > 0 ? entries[0] : null;
  return {
    value: top ? top.value : 0,
    subline: top ? `@${top.handle} leads` : undefined,
    rows: entries.map((entry) => ({
      label: `@${entry.handle}`,
      detail: `${formatNumber(entry.value)} ${unit}`,
    })),
  };
}

function retentionRow(label: string, point: RetentionPoint): MetricRow {
  return {
    label,
    detail:
      point.eligible === 0
        ? "no cohort old enough yet"
        : `${formatNumber(point.returned)} of ${formatNumber(point.eligible)} (${point.rate ?? 0}%)`,
  };
}

/**
 * The registry, grouped in the dashboard's deliberate order:
 * membership, engagement, growth, content, leaderboards, then safety
 * and operations.
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
      rows: payload.total_members.breakdown.map((entry) => ({
        label: entry.label,
        detail: formatNumber(entry.count),
      })),
      subline:
        payload.total_members.deactivated > 0
          ? `${formatNumber(payload.total_members.deactivated)} deactivated (stepped away, counted)`
          : undefined,
    }),
  },
  {
    id: "net_change",
    label: "Net change",
    group: "membership",
    unit: "members",
    goodDirection: "up",
    select: (payload) => ({
      value: payload.total_members.net_change,
      previous: null,
      subline: `+${formatNumber(payload.total_members.joined_in_range)} joined · −${formatNumber(
        payload.total_members.departed_in_range,
      )} departed · +${formatNumber(payload.total_members.returned_in_range)} reinstated${
        payload.total_members.departures_tracked_since
          ? ` · departures recorded since ${formatDay(payload.total_members.departures_tracked_since)}`
          : ""
      }`,
    }),
  },
  {
    id: "active_members",
    label: "Active members",
    group: "membership",
    unit: "members",
    note: "Last 30 days.",
    goodDirection: "up",
    select: (payload) => ({
      value: payload.active_members.value,
      previous: null,
      subline: `of ${formatNumber(payload.active_members.total)} member${
        payload.active_members.total === 1 ? "" : "s"
      }`,
    }),
  },
  {
    id: "dau",
    label: "Daily active (DAU)",
    group: "engagement",
    unit: "members",
    note: "Last 24 hours, always.",
    goodDirection: "up",
    select: (payload) => ({ value: payload.engagement.dau, previous: null }),
  },
  {
    id: "wau",
    label: "Weekly active (WAU)",
    group: "engagement",
    unit: "members",
    note: "Last 7 days, always.",
    goodDirection: "up",
    select: (payload) => ({ value: payload.engagement.wau, previous: null }),
  },
  {
    id: "mau",
    label: "Monthly active (MAU)",
    group: "engagement",
    unit: "members",
    note: "Last 30 days, always.",
    goodDirection: "up",
    select: (payload) => ({ value: payload.engagement.mau, previous: null }),
  },
  {
    id: "stickiness",
    label: "Stickiness (DAU / MAU)",
    group: "engagement",
    unit: "%",
    goodDirection: "up",
    select: (payload) => ({
      value: payload.engagement.stickiness ?? 0,
      previous: null,
      subline: `${formatNumber(payload.engagement.dau)} daily of ${formatNumber(
        payload.engagement.mau,
      )} monthly active`,
    }),
  },
  {
    id: "sessions",
    label: "Sessions",
    group: "engagement",
    unit: "sessions",
    goodDirection: "up",
    select: (payload) => ({
      value: payload.sessions.count,
      previous: null,
      subline: payload.sessions.tracked_since
        ? `recorded since ${formatDay(payload.sessions.tracked_since)}`
        : undefined,
    }),
  },
  {
    id: "time_on_site",
    label: "Time on site",
    group: "engagement",
    unit: "min",
    goodDirection: "up",
    select: (payload) => ({
      value: payload.sessions.total_minutes,
      previous: null,
      subline: `average ${payload.sessions.average_minutes} min · median ${payload.sessions.median_minutes} min per session`,
    }),
  },
  {
    id: "online_now",
    label: "Online now",
    group: "engagement",
    unit: "members",
    note: "A heartbeat within the last 5 minutes.",
    goodDirection: "up",
    select: (payload) => ({
      value: payload.presence.online_now,
      previous: null,
      rows: payload.presence.online.map((entry) => ({
        label: `@${entry.handle}`,
        detail: formatMoment(entry.last_seen),
      })),
    }),
  },
  {
    id: "last_seen",
    label: "Last seen",
    group: "engagement",
    unit: "members",
    goodDirection: "up",
    select: (payload) => ({
      value: payload.presence.last_seen.length,
      previous: null,
      subline: "each member's most recent moment on the site",
      rows: payload.presence.last_seen.map((entry) => ({
        label: `@${entry.handle}`,
        detail: formatMoment(entry.last_seen),
      })),
    }),
  },
  {
    id: "streaks",
    label: "Longest current streak",
    group: "engagement",
    unit: "days",
    goodDirection: "up",
    select: (payload) => ({
      value: payload.streaks.longest_current,
      previous: null,
      rows: payload.streaks.members.map((entry) => ({
        label: `@${entry.handle}`,
        detail: `${formatNumber(entry.value)} day${entry.value === 1 ? "" : "s"}`,
      })),
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
    }),
  },
  {
    id: "follows",
    label: "New follows",
    group: "growth",
    unit: "follows",
    goodDirection: "up",
    select: (payload) => ({
      value: payload.virality.follows_in_range,
      previous: null,
      rows: payload.leaderboards.follower_growth.map((entry) => ({
        label: `@${entry.handle}`,
        detail: `+${formatNumber(entry.value)} follower${entry.value === 1 ? "" : "s"}`,
      })),
    }),
  },
  {
    id: "retention",
    label: "Retention",
    group: "growth",
    unit: "%",
    note: "The share of each signup cohort active again after 1 / 7 / 30 days.",
    goodDirection: "up",
    select: (payload) => ({
      value: payload.retention.d7.rate ?? 0,
      previous: null,
      subline: "headline: active again 7 days after signup",
      rows: [
        retentionRow("After 1 day", payload.retention.d1),
        retentionRow("After 7 days", payload.retention.d7),
        retentionRow("After 30 days", payload.retention.d30),
      ],
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
    }),
  },
  {
    id: "posts_per_member",
    label: "Posts per member",
    group: "content",
    goodDirection: "up",
    select: (payload) => ({
      value: payload.virality.posts_per_member ?? 0,
      previous: null,
    }),
  },
  {
    id: "likes",
    label: "Likes",
    group: "content",
    unit: "likes",
    goodDirection: "up",
    select: (payload) => ({
      value: payload.virality.likes_in_range,
      previous: null,
      subline:
        payload.virality.likes_per_post !== null
          ? `${payload.virality.likes_per_post} per post`
          : undefined,
    }),
  },
  {
    id: "reply_depth",
    label: "Reply depth",
    group: "content",
    unit: "average",
    goodDirection: "up",
    select: (payload) => ({
      value: payload.virality.avg_reply_depth,
      previous: null,
      subline: `deepest thread: ${formatNumber(payload.virality.max_reply_depth)} level${
        payload.virality.max_reply_depth === 1 ? "" : "s"
      }`,
    }),
  },
  {
    id: "top_posters",
    label: "Most posts",
    group: "leaderboards",
    unit: "posts",
    goodDirection: "up",
    select: (payload) => leaderboardValue(payload.leaderboards.top_posters, "posts"),
  },
  {
    id: "likes_given",
    label: "Most likes given",
    group: "leaderboards",
    unit: "likes",
    goodDirection: "up",
    select: (payload) => leaderboardValue(payload.leaderboards.likes_given, "likes"),
  },
  {
    id: "likes_received",
    label: "Most likes received",
    group: "leaderboards",
    unit: "likes",
    goodDirection: "up",
    select: (payload) => leaderboardValue(payload.leaderboards.likes_received, "likes"),
  },
  {
    id: "by_sessions",
    label: "Most active by sessions",
    group: "leaderboards",
    unit: "sessions",
    goodDirection: "up",
    select: (payload) => leaderboardValue(payload.leaderboards.by_sessions, "sessions"),
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
      rows: payload.enforcement_actions.breakdown.map((entry) => ({
        label: entry.label,
        detail: formatNumber(entry.count),
      })),
    }),
  },
];
