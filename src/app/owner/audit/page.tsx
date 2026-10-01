import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getViewer } from "@/lib/auth";
import { Alert, Card } from "@/components/ui";
import { AuditVerify } from "@/components/AuditVerify";

export const metadata: Metadata = { title: "Audit log" };

/**
 * Owner-only, AAL2-gated (enforced by RLS — this page just renders what
 * the database permits). The log is append-only and hash-chained; no
 * update or delete path exists for any application role.
 */
export default async function OwnerAuditPage() {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  if (!viewer.isOwner) redirect("/home");

  const supabase = await createSupabaseServerClient();
  const [{ data: aalData }, { data: entries }] = await Promise.all([
    supabase.auth.mfa.getAuthenticatorAssuranceLevel(),
    supabase
      .from("audit_log")
      .select(
        "seq, occurred_at, actor_id, actor_role, action, target_type, target_id, before_state, after_state, detail",
      )
      .order("seq", { ascending: false })
      .limit(200),
  ]);

  const needsStepUp = aalData?.currentLevel !== "aal2";

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-2">
        <h1 className="text-title">Audit log</h1>
        <p className="max-w-prose text-body text-text-secondary">
          Every privileged action, with the actor&apos;s role at the time and before/after state.
          Append-only and hash-chained: altering or removing an entry breaks the chain detectably.
        </p>
      </div>

      {needsStepUp ? (
        <Alert tone="warning">
          Reading the audit log requires AAL2.{" "}
          <Link className="underline" href="/settings/security">
            Step up first
          </Link>
          .
        </Alert>
      ) : (
        <>
          <Card>
            <AuditVerify />
          </Card>

          <Card className="overflow-x-auto">
            {(entries ?? []).length === 0 ? (
              <p className="text-body text-text-secondary">No entries yet.</p>
            ) : (
              <table className="w-full text-body">
                <thead>
                  <tr className="text-left text-caption text-text-tertiary">
                    <th className="py-2 pr-4 font-medium">#</th>
                    <th className="py-2 pr-4 font-medium">When</th>
                    <th className="py-2 pr-4 font-medium">Actor role</th>
                    <th className="py-2 pr-4 font-medium">Action</th>
                    <th className="py-2 font-medium">Target</th>
                  </tr>
                </thead>
                <tbody>
                  {(entries ?? []).map((entry) => (
                    <tr key={entry.seq} className="border-t border-border align-top">
                      <td className="py-2 pr-4 text-text-tertiary">{entry.seq}</td>
                      <td className="py-2 pr-4 whitespace-nowrap">
                        {new Date(entry.occurred_at).toLocaleString()}
                      </td>
                      <td className="py-2 pr-4">{entry.actor_role}</td>
                      <td className="py-2 pr-4">
                        <code className="text-caption">{entry.action}</code>
                        {entry.detail && Object.keys(entry.detail as object).length > 0 ? (
                          <div className="text-caption text-text-tertiary">
                            {JSON.stringify(entry.detail)}
                          </div>
                        ) : null}
                      </td>
                      <td className="py-2">
                        {entry.target_type ? `${entry.target_type} ${entry.target_id ?? ""}` : "—"}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </Card>
        </>
      )}
    </div>
  );
}
