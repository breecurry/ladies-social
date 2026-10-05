import type { AccountStatus, ActivityBucket, DirectoryFilterArgs } from "@/lib/database.types";

/**
 * Shared vocabulary and URL-state helpers for the Owner's member
 * directory (Phase 2D spec §3-§4). The URL is the single source of
 * truth for the view, so a scoped view survives a refresh and can be
 * shared; these helpers translate search params to the rpc filter
 * arguments and back.
 */

/** The default status view: "people who are here" (spec §4.2). Seeing
 * banned or deactivated accounts is a deliberate selection. */
export const DEFAULT_STATUSES: readonly AccountStatus[] = ["active", "restricted", "suspended"];

export const STATUS_OPTIONS: readonly { value: AccountStatus; label: string }[] = [
  { value: "active", label: "Active" },
  { value: "restricted", label: "Restricted" },
  { value: "suspended", label: "Suspended" },
  { value: "banned", label: "Banned" },
  { value: "deactivated", label: "Deactivated" },
];

/** URL key → bucket label (spec §3.4). Only labels ever travel. */
export const ACTIVITY_OPTIONS: readonly { value: string; label: ActivityBucket }[] = [
  { value: "recent", label: "Active recently" },
  { value: "month", label: "This month" },
  { value: "earlier", label: "Earlier" },
  { value: "dormant", label: "Dormant" },
  { value: "new", label: "New, not yet active" },
];

export const JOINED_OPTIONS: readonly { value: string; label: string; days: number }[] = [
  { value: "week", label: "Joined this week", days: 7 },
  { value: "month", label: "Joined this month", days: 30 },
];

export const STAFF_ROLE_LABEL: Record<string, string> = {
  owner: "Owner",
  admin: "Admin",
  moderator: "Moderator",
  ts_reviewer: "Reviewer",
};

/** The unfiltered, no-intent view loads at most this many recent rows
 * (the recent-window cap, spec §4.3). */
export const RECENT_WINDOW = 200;
/** A filtered or searched view renders at most this many rows before
 * the "too many results" note (spec §5). */
export const FILTERED_WINDOW = 500;
export const PAGE_SIZE = 50;

export type DirectoryParams = {
  q?: string;
  status?: string;
  staff?: string;
  joined?: string;
  activity?: string;
};

export type DirectoryView = {
  query: string;
  statuses: AccountStatus[];
  staffOnly: boolean;
  joined: string | null;
  activity: string[];
  /** True when the Owner has expressed a specific intent (search or
   * any filter), which lifts the recent-window cap (spec §4.3). */
  hasIntent: boolean;
};

export function parseDirectoryParams(params: DirectoryParams): DirectoryView {
  const query = (params.q ?? "").trim();
  const statuses = (params.status ?? "")
    .split(",")
    .filter((s): s is AccountStatus => STATUS_OPTIONS.some((o) => o.value === s));
  const activity = (params.activity ?? "")
    .split(",")
    .filter((a) => ACTIVITY_OPTIONS.some((o) => o.value === a));
  const joined = JOINED_OPTIONS.some((o) => o.value === params.joined)
    ? (params.joined as string)
    : null;
  const staffOnly = params.staff === "1";
  return {
    query,
    statuses,
    staffOnly,
    joined,
    activity,
    hasIntent:
      query !== "" || statuses.length > 0 || staffOnly || joined !== null || activity.length > 0,
  };
}

export function toFilterArgs(view: DirectoryView): DirectoryFilterArgs {
  const joinedDays = JOINED_OPTIONS.find((o) => o.value === view.joined)?.days;
  return {
    p_query: view.query || null,
    p_statuses: view.statuses.length > 0 ? view.statuses : null,
    p_staff_only: view.staffOnly,
    p_joined_after: joinedDays
      ? new Date(Date.now() - joinedDays * 86_400_000).toISOString()
      : null,
    p_joined_before: null,
    p_activity:
      view.activity.length > 0
        ? view.activity.map(
            (a) => ACTIVITY_OPTIONS.find((o) => o.value === a)?.label as string,
          )
        : null,
  };
}

/** An absolute date for directory rows ("3 Oct 2026"): in a roster the
 * exact arrival date is the useful fact (spec §3.1). */
export function absoluteDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}
