/** Formatting helpers for the social surfaces. No locale machinery:
 * the product launches in English and the formats are deliberate. */

const MINUTE = 60_000;
const HOUR = 3_600_000;
const DAY = 86_400_000;

/** Short relative timestamp for feed rows: "now", "5m", "2h", "3d", then a date. */
export function relativeTime(iso: string, now: Date = new Date()): string {
  const then = new Date(iso);
  const diff = now.getTime() - then.getTime();
  if (diff < MINUTE) return "now";
  if (diff < HOUR) return `${Math.floor(diff / MINUTE)}m`;
  if (diff < DAY) return `${Math.floor(diff / HOUR)}h`;
  if (diff < 7 * DAY) return `${Math.floor(diff / DAY)}d`;
  const sameYear = then.getFullYear() === now.getFullYear();
  return then.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    ...(sameYear ? {} : { year: "numeric" }),
  });
}

/** Full timestamp for a thread's root post: "9:41 AM · 2 Oct 2026". */
export function fullTimestamp(iso: string): string {
  const d = new Date(iso);
  const time = d.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
  const date = d.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
  return `${time} · ${date}`;
}

/** Month and year for profile metadata: "Joined October 2026". */
export function joinedDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-US", { month: "long", year: "numeric" });
}
