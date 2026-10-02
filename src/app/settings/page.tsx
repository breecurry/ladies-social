import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { Card } from "@/components/ui";
import { DisplayNameToggle } from "@/components/DisplayNameToggle";

export const metadata: Metadata = { title: "Settings" };

export default async function SettingsPage() {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");

  const showingName = viewer.profile?.display_name !== null;

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-title">Settings</h1>

      <Card className="flex flex-col gap-4">
        <div className="flex flex-col gap-2">
          <h2 className="text-heading">Public name</h2>
          <p className="max-w-prose text-body text-text-secondary">
            Your legal name was collected when you joined, but members see{" "}
            <strong className="text-text-primary">@{viewer.profile?.handle}</strong> by default.
            Showing your legal name is entirely your choice and you can change it at any time.
          </p>
          <p className="text-caption text-text-tertiary">
            Currently showing:{" "}
            {showingName ? viewer.profile?.display_name : `@${viewer.profile?.handle} only`}
          </p>
        </div>
        <DisplayNameToggle showing={showingName} />
      </Card>

      <Card className="flex flex-col gap-2">
        <h2 className="text-heading">Security</h2>
        <p className="max-w-prose text-body text-text-secondary">
          Add a passkey/security key or an authenticator app. Required for privileged actions.
        </p>
        <Link className="text-body text-accent underline" href="/settings/security">
          Manage two-factor authentication
        </Link>
      </Card>
    </div>
  );
}
