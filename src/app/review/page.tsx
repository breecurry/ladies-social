import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getViewer } from "@/lib/auth";
import { Alert, Badge, Card } from "@/components/ui";
import { ReviewActions } from "@/components/ReviewActions";
import type { Json } from "@/lib/database.types";

export const metadata: Metadata = { title: "Review queue" };

function signalReasons(signals: Json): string[] {
  if (signals && typeof signals === "object" && !Array.isArray(signals)) {
    const reasons = (signals as { reasons?: Json }).reasons;
    if (Array.isArray(reasons)) return reasons.filter((r): r is string => typeof r === "string");
  }
  return [];
}

/**
 * The human review queue (Lane 2). Ordered clean-first, flagged last; a
 * confirmed vouch raises priority within its bucket. The automated-
 * abuse bucket is excluded by Row Level Security — it does not appear
 * here for anyone, the Owner included. There are no photographs
 * anywhere in this flow, deliberately.
 */
export default async function ReviewPage() {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  if (!viewer.isReviewer) redirect("/home");

  const supabase = await createSupabaseServerClient();
  const { data: applications } = await supabase
    .from("admission_applications")
    .select("*")
    .in("status", ["queued", "info_requested"])
    .order("triage_bucket", { ascending: true })
    .order("vouch_confirmed", { ascending: false })
    .order("created_at", { ascending: true })
    .limit(100);

  const userIds = (applications ?? []).map((a) => a.user_id);
  const [{ data: profileRows }, { data: privateRows }] = await Promise.all([
    userIds.length
      ? supabase.from("profiles").select("user_id, handle").in("user_id", userIds)
      : Promise.resolve({ data: [] as { user_id: string; handle: string }[] }),
    // Owner-only at AAL2 (RLS): others simply receive no rows.
    userIds.length
      ? supabase
          .from("user_private")
          .select("user_id, legal_name, email, phone_e164")
          .in("user_id", userIds)
      : Promise.resolve({
          data: [] as {
            user_id: string;
            legal_name: string;
            email: string;
            phone_e164: string | null;
          }[],
        }),
  ]);
  const handles = new Map((profileRows ?? []).map((p) => [p.user_id, p.handle]));
  const privateInfo = new Map((privateRows ?? []).map((p) => [p.user_id, p]));

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-2">
        <h1 className="text-title">Review queue</h1>
        <p className="max-w-prose text-body text-text-secondary">
          Clean signals first, flagged last; a confirmed vouch from a member raises priority.
          Signals are about automation and ban evasion only — never appearance or identity.
        </p>
        {viewer.isOwner && privateInfo.size === 0 && (applications ?? []).length > 0 ? (
          <Alert tone="info">
            Contact details are hidden until you step up to AAL2 under Settings → Security.
          </Alert>
        ) : null}
      </div>

      {(applications ?? []).length === 0 ? (
        <Card>
          <p className="text-body text-text-secondary">The queue is empty.</p>
        </Card>
      ) : (
        (applications ?? []).map((application) => {
          const contact = privateInfo.get(application.user_id);
          const reasons = signalReasons(application.triage_signals);
          return (
            <Card key={application.id} className="flex flex-col gap-4">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <h2 className="text-heading">@{handles.get(application.user_id) ?? "unknown"}</h2>
                <div className="flex flex-wrap gap-2">
                  <Badge tone={application.triage_bucket === "clean" ? "success" : "warning"}>
                    {application.triage_bucket}
                  </Badge>
                  {application.vouch_confirmed ? <Badge tone="accent">vouched</Badge> : null}
                  {application.status === "info_requested" ? (
                    <Badge tone="neutral">info requested</Badge>
                  ) : null}
                </div>
              </div>

              <dl className="grid grid-cols-1 gap-x-6 gap-y-1 text-body sm:grid-cols-2">
                <div>
                  <dt className="text-caption text-text-tertiary">Applied</dt>
                  <dd>{new Date(application.created_at).toLocaleString()}</dd>
                </div>
                <div>
                  <dt className="text-caption text-text-tertiary">Named an inviter</dt>
                  <dd>{application.inviter_named ? "yes" : "no"}</dd>
                </div>
                {contact ? (
                  <>
                    <div>
                      <dt className="text-caption text-text-tertiary">Legal name</dt>
                      <dd>{contact.legal_name}</dd>
                    </div>
                    <div>
                      <dt className="text-caption text-text-tertiary">Email · phone</dt>
                      <dd>
                        {contact.email} · {contact.phone_e164 ?? "—"}
                      </dd>
                    </div>
                  </>
                ) : null}
              </dl>

              {reasons.length > 0 ? (
                <div className="flex flex-col gap-1">
                  <h3 className="text-caption text-text-tertiary">Signals</h3>
                  <ul className="list-inside list-disc text-body text-text-secondary">
                    {reasons.map((reason) => (
                      <li key={reason}>{reason}</li>
                    ))}
                  </ul>
                </div>
              ) : null}

              {application.info_response ? (
                <div className="flex flex-col gap-1">
                  <h3 className="text-caption text-text-tertiary">Applicant&apos;s reply</h3>
                  <p className="text-body text-text-secondary">{application.info_response}</p>
                </div>
              ) : null}

              {viewer.isAdminOrOwner ? (
                <ReviewActions applicationId={application.id} />
              ) : (
                <p className="text-caption text-text-tertiary">
                  Read-only access — decisions are made by the Owner or an Admin.
                </p>
              )}
            </Card>
          );
        })
      )}
    </div>
  );
}
