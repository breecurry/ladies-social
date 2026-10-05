import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getViewer } from "@/lib/auth";
import { Alert, Badge, Card } from "@/components/ui";
import { RoleManager } from "@/components/RoleManager";

export const metadata: Metadata = { title: "Roles" };

export default async function OwnerRolesPage() {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  if (!viewer.isOwner) redirect("/home");

  const supabase = await createSupabaseServerClient();
  const [{ data: aalData }, { data: roleRows }] = await Promise.all([
    supabase.auth.mfa.getAuthenticatorAssuranceLevel(),
    supabase
      .from("role_assignments")
      .select("id, user_id, role, granted_at")
      .is("revoked_at", null)
      .order("granted_at", { ascending: true }),
  ]);

  const subjectIds = [...new Set((roleRows ?? []).map((r) => r.user_id))];
  const { data: subjectProfiles } = subjectIds.length
    ? await supabase.from("profiles").select("user_id, handle").in("user_id", subjectIds)
    : { data: [] as { user_id: string; handle: string }[] };
  const handles = new Map((subjectProfiles ?? []).map((p) => [p.user_id, p.handle]));

  const needsStepUp = aalData?.currentLevel !== "aal2";

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-2">
        <h1 className="text-title">Roles</h1>
        <p className="max-w-prose text-body text-text-secondary">
          Only you can grant or revoke roles, enforced in the database itself, not just in this
          interface. The owner role is never grantable.
        </p>
        <p className="text-caption text-text-tertiary">
          Part of{" "}
          <Link className="text-accent underline-offset-4 hover:underline" href="/owner">
            Owner tools
          </Link>
          .
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

      <Card>
        <RoleManager />
      </Card>
    </div>
  );
}
