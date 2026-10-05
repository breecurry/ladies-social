import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getViewer } from "@/lib/auth";
import { sensitiveAuthMethod } from "@/lib/passkeys";
import { Card } from "@/components/ui";
import { PasskeyStepUpPrompt } from "@/components/PasskeyStepUpPrompt";
import { AuditVerify } from "@/components/AuditVerify";

export const metadata: Metadata = { title: "Audit log" };

/**
 * Owner-only, behind the sensitive-action gate — AAL2 or a fresh
 * passkey — enforced by RLS (the audit_owner_read policy); this page
 * just renders what the database permits. The log is append-only and
 * hash-chained; no update or delete path exists for any application
 * role.
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

  // The method currently satisfying the sensitive-action gate: AAL2, a
  // fresh passkey, or nothing. UI hint only — the audit_owner_read RLS
  // policy re-derives this server-side from the JWT.
  const authMethod = sensitiveAuthMethod(
    aalData?.currentLevel ?? null,
    aalData?.currentAuthenticationMethods,
  );

  return (
    <div className="flex flex-col gap-6 p-4">
      <div className="flex flex-col gap-2">
        <h1 className="text-title">Audit log</h1>
        <p className="max-w-prose text-body text-text-secondary">
          Every privileged action, with the actor&apos;s role at the time and before/after state.
          Append-only and hash-chained: altering or removing an entry breaks the chain detectably.
        </p>
      </div>

      {authMethod === null ? (
        <PasskeyStepUpPrompt description="Reading the audit log needs a fresh check that it's you — a passkey confirmation, or an authenticator-app step-up." />
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
                          <div className="break-all text-caption text-text-tertiary">
                            {JSON.stringify(entry.detail)}
                          </div>
                        ) : null}
                      </td>
                      <td className="py-2">
                        {entry.target_type ? `${entry.target_type} ${entry.target_id ?? ""}` : "none"}
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
