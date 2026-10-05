import type { Metadata } from "next";
import Link from "next/link";
import { ShieldCheck } from "@phosphor-icons/react/dist/ssr";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { caseKey, REASON_LABEL } from "@/lib/moderation";
import { relativeTime } from "@/lib/format";
import { dispatchSafetyEmailsInBackground } from "@/lib/email/safety";
import { PriorityChip, StateChip } from "@/components/mod/chips";

export const metadata: Metadata = { title: "Moderation" };

const STATES = [
  { value: "open", label: "Open" },
  { value: "in_review", label: "In review" },
  { value: "escalated", label: "Escalated" },
  { value: "resolved", label: "Resolved" },
] as const;

/**
 * The report queue (design doc §2). The unit is the CASE — all open
 * reports grouped by accused account (and subject post), so a brigade
 * reads as what it is: many reports, one target. Sorted priority then
 * newest; there is deliberately no sort by raw report count, because
 * that would reward brigading. Queue volume is stated as information,
 * never as alarm (§2.4).
 */
export default async function ModQueuePage({
  searchParams,
}: {
  searchParams: Promise<{ state?: string }>;
}) {
  const params = await searchParams;
  const state = STATES.some((s) => s.value === params.state) ? (params.state as string) : "open";

  // Retry any queued safety@ email copies whenever staff arrive.
  dispatchSafetyEmailsInBackground();

  const supabase = await createSupabaseServerClient();
  const [{ data: cases }, { data: countRows }] = await Promise.all([
    supabase.rpc("mod_queue", { p_state: state, p_limit: 100 }),
    supabase.rpc("mod_queue_counts"),
  ]);
  const counts = countRows?.[0];

  return (
    <div className="flex flex-col">
      <header className="flex flex-col gap-3 border-b border-border bg-surface px-4 py-4">
        <div className="flex items-center justify-between">
          <h1 className="text-title text-text-primary">Reports</h1>
          <Link href="/mod/tags" className="text-label text-accent hover:underline">
            Topics
          </Link>
        </div>
        {counts ? (
          <p className="text-body text-text-secondary">
            {counts.open_count} open, {counts.critical_count} critical, {counts.in_review_count} in
            review.
          </p>
        ) : null}
        <nav aria-label="Queue state" className="flex gap-1 rounded-md border border-border-strong p-1">
          {STATES.map((item) => (
            <Link
              key={item.value}
              href={`/mod?state=${item.value}`}
              aria-current={state === item.value ? "page" : undefined}
              className={`flex min-h-9 flex-1 items-center justify-center rounded-sm px-2 text-label transition-colors duration-(--duration-fast) ${
                state === item.value
                  ? "border-b-2 border-accent bg-accent-subtle text-accent"
                  : "text-text-secondary hover:bg-surface-raised"
              }`}
            >
              {item.label}
            </Link>
          ))}
        </nav>
      </header>

      {!cases || cases.length === 0 ? (
        <div className="flex flex-col items-center gap-2 px-6 py-16 text-center">
          <ShieldCheck size={48} aria-hidden className="text-success" />
          <h2 className="text-heading text-text-primary">
            {state === "open" ? "Clear" : "Nothing here"}
          </h2>
          <p className="max-w-sm text-body text-text-secondary">
            {state === "open"
              ? "No open cases. An empty queue is a good state."
              : "No cases in this view right now."}
          </p>
        </div>
      ) : (
        <ul>
          {cases.map((item) => (
            <li key={caseKey(item.accused_id, item.subject_post_id)}>
              <Link
                href={`/mod/case/${caseKey(item.accused_id, item.subject_post_id)}`}
                className="flex min-h-[72px] items-center gap-3 border-b border-border bg-surface px-4 py-4 transition-colors duration-(--duration-fast) hover:bg-surface-raised"
              >
                <PriorityChip priority={item.priority} />
                <div className="min-w-0 flex-1">
                  <p className="text-label text-text-primary">@{item.accused_handle}</p>
                  <p className="text-body text-text-secondary">
                    {REASON_LABEL[item.top_reason]}
                    {item.subject_post_id === null ? " · account" : " · post"}
                  </p>
                  {item.report_count > 1 || item.reporter_count > 1 ? (
                    <p className="text-caption text-text-tertiary">
                      {item.report_count} report{item.report_count === 1 ? "" : "s"} from{" "}
                      {item.reporter_count} {item.reporter_count === 1 ? "person" : "people"}
                    </p>
                  ) : null}
                </div>
                <StateChip state={item.case_state} />
                <span className="text-caption text-text-tertiary">
                  {relativeTime(item.newest_at)}
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
