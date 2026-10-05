import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { CaretLeft } from "@phosphor-icons/react/dist/ssr";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getViewer } from "@/lib/auth";
import { modTier, parseCaseKey, REASON_LABEL } from "@/lib/moderation";
import { relativeTime, joinedDate } from "@/lib/format";
import { AccountStatusChip, PriorityChip, StateChip } from "@/components/mod/chips";
import { CaseActions } from "@/components/mod/CaseActions";
import { ReporterReveal } from "@/components/mod/ReporterReveal";
import { ThreadContext } from "@/components/mod/ThreadContext";

export const metadata: Metadata = { title: "Case" };

/**
 * The report detail view (design doc §3): everything a moderator needs
 * in one place — the reported content in its thread context, the
 * reports, the account's history — without leaving the console and
 * without a legal name anywhere. Every person here is an @handle.
 */
export default async function ModCasePage({ params }: { params: Promise<{ key: string }> }) {
  const { key } = await params;
  const parsed = parseCaseKey(key);
  if (!parsed) notFound();

  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  const tier = modTier(viewer.roles);
  if (tier === "none") redirect("/home");

  const supabase = await createSupabaseServerClient();
  const [{ data: reports }, { data: contextRows }, { data: history }] = await Promise.all([
    supabase.rpc("mod_case", { p_target: parsed.accusedId, p_post: parsed.postId }),
    supabase.rpc("mod_account_context", { p_target: parsed.accusedId }),
    supabase.rpc("mod_enforcement_history", { p_target: parsed.accusedId }),
  ]);
  const account = contextRows?.[0];
  if (!account || !reports || reports.length === 0) notFound();

  const [{ data: thread }, { data: accountPosts }] = await Promise.all([
    parsed.postId !== null
      ? supabase.rpc("mod_post_context", { p_post: parsed.postId })
      : Promise.resolve({ data: null }),
    parsed.postId === null
      ? supabase.rpc("mod_account_posts", { p_target: parsed.accusedId, p_limit: 10 })
      : Promise.resolve({ data: null }),
  ]);

  const worst = [...reports].sort((a, b) => severity(a.reason) - severity(b.reason))[0];
  const priority =
    worst && ["csam", "ncii", "violence_threat"].includes(worst.reason)
      ? "critical"
      : worst && ["doxxing", "self_harm", "hate"].includes(worst.reason)
        ? "high"
        : "normal";
  const caseState = reports.some((r) => r.status === "open")
    ? "open"
    : reports.some((r) => r.status === "in_review")
      ? "in_review"
      : reports.some((r) => r.status === "escalated")
        ? "escalated"
        : reports.some((r) => r.status === "actioned")
          ? "actioned"
          : "dismissed";
  const hasCsam = reports.some((r) => r.reason === "csam");
  const subjectPost = thread?.find((p) => p.is_subject) ?? null;

  return (
    <div className="flex flex-col gap-4 px-4 py-4">
      <Link
        href="/mod"
        className="flex min-h-11 items-center gap-1 self-start text-label text-accent hover:underline"
      >
        <CaretLeft size={16} aria-hidden /> Queue
      </Link>

      {/* Case header (§3.1): handle, standing, priority, state. */}
      <header className="flex flex-wrap items-center gap-2">
        <h1 className="text-heading text-text-primary">
          <Link href={`/u/${account.handle}`} className="hover:underline">
            @{account.handle}
          </Link>
        </h1>
        <AccountStatusChip status={account.status} expiresAt={account.status_expires_at} />
        <PriorityChip priority={priority} />
        <StateChip state={caseState} />
        {account.is_staff ? (
          <span className="inline-flex items-center rounded-full border border-border bg-surface px-2 py-0.5 text-caption text-text-secondary">
            Staff
          </span>
        ) : null}
      </header>

      {/* Account context strip (§3.1.4): the pattern, de-identified. */}
      <p className="text-caption text-text-tertiary">
        Joined {joinedDate(account.joined_at)} · {account.post_count} post
        {account.post_count === 1 ? "" : "s"} ·{" "}
        {account.prior_actions === 0
          ? "no prior enforcement"
          : `actioned ${account.prior_actions} time${account.prior_actions === 1 ? "" : "s"} before`}
      </p>

      {/* The reported content, in context (§3.2). */}
      {thread && thread.length > 0 ? (
        <section aria-label="Reported content in context" className="rounded-lg border border-border bg-surface">
          <ThreadContext posts={thread} />
        </section>
      ) : null}
      {accountPosts && accountPosts.length > 0 ? (
        <section aria-label="Recent posts" className="rounded-lg border border-border bg-surface">
          <h2 className="border-b border-border px-4 py-2 text-label text-text-secondary">
            Recent posts
          </h2>
          <ul>
            {accountPosts.map((post) => (
              <li key={post.id} className="border-b border-border px-4 py-3 last:border-b-0">
                {post.body === "" ? (
                  <p className="text-body text-text-tertiary">
                    {post.visibility === "removed_moderation"
                      ? "Removed by moderation"
                      : "Removed"}
                  </p>
                ) : (
                  <p className="whitespace-pre-wrap break-words text-body text-text-primary">
                    {post.body}
                  </p>
                )}
                <p className="mt-1 text-caption text-text-tertiary">
                  {post.is_reply ? "Reply" : "Post"} · {relativeTime(post.created_at)}
                </p>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {/* The reports themselves (§3.3): reporter identity collapsed
          behind an audited reveal. */}
      <section aria-label="Reports" className="rounded-lg border border-border bg-surface">
        <div className="flex items-center justify-between border-b border-border px-4 py-2">
          <h2 className="text-label text-text-secondary">
            {reports.length} report{reports.length === 1 ? "" : "s"}
          </h2>
          <ReporterReveal target={parsed.accusedId} postId={parsed.postId} />
        </div>
        <ul>
          {reports.map((report) => (
            <li key={report.report_id} className="border-b border-border px-4 py-3 last:border-b-0">
              <div className="flex items-center gap-2">
                <span className="text-label text-text-primary">{REASON_LABEL[report.reason]}</span>
                <StateChip state={report.status} />
                <span className="ml-auto text-caption text-text-tertiary">
                  {relativeTime(report.created_at)}
                </span>
              </div>
              {report.details ? (
                <p className="mt-1 whitespace-pre-wrap break-words text-body text-text-secondary">
                  {report.details}
                </p>
              ) : null}
              {report.assigned_handle ? (
                <p className="mt-1 text-caption text-text-tertiary">
                  In review by @{report.assigned_handle}
                </p>
              ) : null}
            </li>
          ))}
        </ul>
      </section>

      {/* The enforcement trail on this account (§8.1). */}
      {history && history.length > 0 ? (
        <section aria-label="Enforcement history" className="rounded-lg border border-border bg-surface">
          <h2 className="border-b border-border px-4 py-2 text-label text-text-secondary">
            Enforcement history
          </h2>
          <ul>
            {history.map((row, index) => (
              <li key={index} className="border-b border-border px-4 py-2 text-body text-text-secondary last:border-b-0">
                {row.actor_role}
                {row.actor_handle ? ` (@${row.actor_handle})` : ""}: {row.action.replace("_", " ")}
                {row.rule ? ` — ${REASON_LABEL[row.rule]}` : ""}
                {row.duration_days ? `, ${row.duration_days} days` : ""}
                <span className="text-caption text-text-tertiary">
                  {" "}
                  · {relativeTime(row.created_at)}
                </span>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {/* The action rail (§4): absent entirely for reviewers. */}
      <CaseActions
        tier={tier}
        target={parsed.accusedId}
        accusedHandle={account.handle}
        accusedStatus={account.status}
        postId={parsed.postId}
        postVisibility={subjectPost?.visibility ?? null}
        caseState={caseState}
        hasCsam={hasCsam}
      />
    </div>
  );
}

function severity(reason: string): number {
  const order = [
    "csam",
    "ncii",
    "violence_threat",
    "doxxing",
    "self_harm",
    "hate",
    "harassment",
    "impersonation",
    "spam",
    "other",
  ];
  const index = order.indexOf(reason);
  return index === -1 ? order.length : index;
}
