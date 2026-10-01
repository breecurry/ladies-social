import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getViewer } from "@/lib/auth";
import { Alert, Badge, Card } from "@/components/ui";
import { RoleManager } from "@/components/RoleManager";

export const metadata: Metadata = { title: "Roles & privileges" };

export default async function OwnerRolesPage() {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  if (!viewer.isOwner) redirect("/home");

  const supabase = await createSupabaseServerClient();
  const [{ data: aalData }, { data: roleRows }, { data: privilegeRows }, { data: stats }] =
    await Promise.all([
      supabase.auth.mfa.getAuthenticatorAssuranceLevel(),
      supabase
        .from("role_assignments")
        .select("id, user_id, role, granted_at")
        .is("revoked_at", null)
        .order("granted_at", { ascending: true }),
      supabase
        .from("privilege_grants")
        .select("id, user_id, privilege, granted_at")
        .is("revoked_at", null),
      supabase.rpc("owner_vouch_stats"),
    ]);

  const subjectIds = [
    ...new Set([
      ...(roleRows ?? []).map((r) => r.user_id),
      ...(privilegeRows ?? []).map((p) => p.user_id),
    ]),
  ];
  const { data: subjectProfiles } = subjectIds.length
    ? await supabase.from("profiles").select("user_id, handle").in("user_id", subjectIds)
    : { data: [] as { user_id: string; handle: string }[] };
  const handles = new Map((subjectProfiles ?? []).map((p) => [p.user_id, p.handle]));

  const needsStepUp = aalData?.currentLevel !== "aal2";

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-2">
        <h1 className="text-title">Roles &amp; privileges</h1>
        <p className="max-w-prose text-body text-text-secondary">
          Only you can grant or revoke roles and auto-admit — enforced in the database itself, not
          just in this interface. The owner role is never grantable.
        </p>
      </div>

      {needsStepUp ? (
        <Alert tone="warning">
          Role changes require AAL2.{" "}
          <Link className="underline" href="/settings/security">
            Step up with your security key or authenticator app
          </Link>{" "}
          first.
        </Alert>
      ) : null}

      <Card className="flex flex-col gap-3">
        <h2 className="text-heading">Active roles</h2>
        {(roleRows ?? []).length === 0 ? (
          <p className="text-body text-text-secondary">No roles assigned yet.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {(roleRows ?? []).map((row) => (
              <li
                key={row.id}
                className="flex items-center justify-between gap-3 rounded-md border border-border px-3 py-2"
              >
                <span className="text-body">@{handles.get(row.user_id) ?? row.user_id}</span>
                <Badge tone={row.role === "owner" ? "accent" : "neutral"}>{row.role}</Badge>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card className="flex flex-col gap-3">
        <h2 className="text-heading">Auto-admit holders</h2>
        {(privilegeRows ?? []).length === 0 ? (
          <p className="text-body text-text-secondary">
            Nobody holds auto-admit. Every confirmed vouch currently routes to your review queue
            with raised priority.
          </p>
        ) : (
          <ul className="flex flex-col gap-2">
            {(privilegeRows ?? []).map((row) => (
              <li
                key={row.id}
                className="flex items-center justify-between gap-3 rounded-md border border-border px-3 py-2"
              >
                <span className="text-body">@{handles.get(row.user_id) ?? row.user_id}</span>
                <Badge tone="accent">{row.privilege}</Badge>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card className="flex flex-col gap-3">
        <h2 className="text-heading">Vouch statistics</h2>
        <p className="text-body text-text-secondary">
          Who vouches, and how their people turn out. This informs your auto-admit decisions; it
          never triggers anything by itself.
        </p>
        {(stats ?? []).length === 0 ? (
          <p className="text-body text-text-secondary">No vouches yet.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-body">
              <thead>
                <tr className="text-left text-caption text-text-tertiary">
                  <th className="py-2 pr-4 font-medium">Member</th>
                  <th className="py-2 pr-4 font-medium">Confirmed</th>
                  <th className="py-2 pr-4 font-medium">Admitted</th>
                  <th className="py-2 pr-4 font-medium">In good standing</th>
                  <th className="py-2 pr-4 font-medium">Removed</th>
                  <th className="py-2 pr-4 font-medium">Pending</th>
                  <th className="py-2 font-medium">Auto-admit</th>
                </tr>
              </thead>
              <tbody>
                {(stats ?? []).map((row) => (
                  <tr key={row.user_id} className="border-t border-border">
                    <td className="py-2 pr-4">@{row.handle}</td>
                    <td className="py-2 pr-4">{row.vouches_confirmed}</td>
                    <td className="py-2 pr-4">{row.vouchees_admitted}</td>
                    <td className="py-2 pr-4">{row.vouchees_in_good_standing}</td>
                    <td className="py-2 pr-4">{row.vouchees_removed}</td>
                    <td className="py-2 pr-4">{row.requests_pending}</td>
                    <td className="py-2">
                      {row.has_auto_admit ? <Badge tone="accent">yes</Badge> : "—"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Card>
        <RoleManager />
      </Card>
    </div>
  );
}
