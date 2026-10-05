import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { ReportReason, ReportStatus } from "@/lib/database.types";
import { relativeTime } from "@/lib/format";
import { Card } from "@/components/ui";
import { UnblockButton } from "@/components/profile/UnblockButton";
import { UnmuteButton, UnhideButton } from "@/components/settings/SafetyActions";

export const metadata: Metadata = { title: "Safety" };

const REASON_LABELS: Record<ReportReason, string> = {
  harassment: "Harassment or bullying",
  hate: "Hate speech",
  violence_threat: "Threat of violence",
  doxxing: "Sharing private information",
  csam: "Content involving a minor",
  ncii: "Sexual content or harassment",
  spam: "Spam or scam",
  impersonation: "Impersonation",
  self_harm: "Self-harm",
  other: "Something else",
};

const STATUS_LABELS: Record<ReportStatus, string> = {
  open: "Open",
  in_review: "In review",
  actioned: "Action taken",
  dismissed: "Reviewed, no action",
  escalated: "Escalated",
};

/**
 * Safety (spec §8.2.3): blocked, muted, and "show me less" lists, each
 * actionable here as well as in context, plus the report history that
 * keeps reporting from feeling like shouting into a void.
 */
export default async function SafetySettingsPage() {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");

  const supabase = await createSupabaseServerClient();
  const [{ data: blocks }, { data: mutes }, { data: hidden }, { data: reports }] =
    await Promise.all([
      supabase.from("blocks").select("blocked_id").eq("blocker_id", viewer.user.id),
      supabase.from("mutes").select("muted_id").eq("muter_id", viewer.user.id),
      supabase.from("hidden_accounts").select("hidden_id").eq("hider_id", viewer.user.id),
      supabase
        .from("reports")
        .select("id, subject_type, reason, status, created_at")
        .order("created_at", { ascending: false })
        .limit(50),
    ]);

  const ids = [
    ...(blocks ?? []).map((row) => row.blocked_id),
    ...(mutes ?? []).map((row) => row.muted_id),
    ...(hidden ?? []).map((row) => row.hidden_id),
  ];
  const handles = new Map<string, string>();
  if (ids.length > 0) {
    const { data: profiles } = await supabase
      .from("profiles")
      .select("user_id, handle")
      .in("user_id", ids);
    for (const row of profiles ?? []) handles.set(row.user_id, row.handle);
  }

  const handleOf = (id: string) => handles.get(id) ?? "unavailable account";

  return (
    <div className="flex flex-col gap-4">
      <h2 className="text-title">Safety</h2>

      <Card className="flex flex-col gap-3">
        <h3 className="text-heading">Blocked accounts</h3>
        {(blocks ?? []).length === 0 ? (
          <p className="text-body text-text-secondary">You have not blocked anyone.</p>
        ) : (
          (blocks ?? []).map((row) => (
            <div key={row.blocked_id} className="flex items-center justify-between gap-3">
              <span className="text-body text-text-primary">@{handleOf(row.blocked_id)}</span>
              <UnblockButton targetUserId={row.blocked_id} targetHandle={handleOf(row.blocked_id)} />
            </div>
          ))
        )}
      </Card>

      <Card className="flex flex-col gap-3">
        <h3 className="text-heading">Muted accounts</h3>
        {(mutes ?? []).length === 0 ? (
          <p className="text-body text-text-secondary">You have not muted anyone.</p>
        ) : (
          (mutes ?? []).map((row) => (
            <div key={row.muted_id} className="flex items-center justify-between gap-3">
              <span className="text-body text-text-primary">@{handleOf(row.muted_id)}</span>
              <UnmuteButton targetUserId={row.muted_id} />
            </div>
          ))
        )}
      </Card>

      <Card className="flex flex-col gap-3">
        <h3 className="text-heading">Seeing less from</h3>
        <p className="text-caption text-text-tertiary">
          Accounts you asked to see less from. This never affects them and they are not told.
        </p>
        {(hidden ?? []).length === 0 ? (
          <p className="text-body text-text-secondary">Nothing here.</p>
        ) : (
          (hidden ?? []).map((row) => (
            <div key={row.hidden_id} className="flex items-center justify-between gap-3">
              <span className="text-body text-text-primary">@{handleOf(row.hidden_id)}</span>
              <UnhideButton targetUserId={row.hidden_id} />
            </div>
          ))
        )}
      </Card>

      <Card className="flex flex-col gap-3">
        <h3 className="text-heading">Report history</h3>
        {(reports ?? []).length === 0 ? (
          <p className="text-body text-text-secondary">
            You have not filed any reports. When you do, their status appears here.
          </p>
        ) : (
          (reports ?? []).map((report) => (
            <div key={report.id} className="flex items-center justify-between gap-3">
              <div>
                <p className="text-body text-text-primary">
                  {REASON_LABELS[report.reason]}{" "}
                  <span className="text-caption text-text-tertiary">
                    · about {report.subject_type === "post" ? "a post" : "an account"} ·{" "}
                    {relativeTime(report.created_at)}
                  </span>
                </p>
              </div>
              <span className="rounded-full bg-background px-3 py-1 text-caption text-text-secondary">
                {STATUS_LABELS[report.status]}
              </span>
            </div>
          ))
        )}
        <p className="text-caption text-text-tertiary">
          Reports are reviewed by our team. See the{" "}
          <Link href="/settings/about" className="text-accent underline">
            Community Guidelines
          </Link>{" "}
          for how reporting works.
        </p>
      </Card>
    </div>
  );
}
