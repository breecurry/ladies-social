import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { Card } from "@/components/ui";

export const metadata: Metadata = { title: "Account" };

function maskEmail(email: string | undefined): string {
  if (!email) return "not set";
  const [local = "", domain = ""] = email.split("@");
  const head = local.slice(0, 1);
  return `${head}***@${domain}`;
}

export default async function AccountSettingsPage() {
  const viewer = await getViewer();
  if (!viewer || !viewer.profile) redirect("/login");

  return (
    <div className="flex flex-col gap-4">
      <h2 className="text-title">Account</h2>
      <Card className="flex flex-col gap-4">
        <div className="flex flex-col gap-1">
          <span className="text-label text-text-primary">Handle</span>
          <p className="text-body text-text-secondary">@{viewer.profile.handle}</p>
          <p className="text-caption text-text-tertiary">
            Your handle is your public identity everywhere on United Feminist.
          </p>
        </div>
        <div className="flex flex-col gap-1">
          <span className="text-label text-text-primary">Email</span>
          <p className="text-body text-text-secondary">{maskEmail(viewer.user.email)}</p>
        </div>
      </Card>
      <Card className="flex flex-col gap-2">
        <h3 className="text-heading">Security</h3>
        <p className="max-w-prose text-body text-text-secondary">
          Add a passkey/security key or an authenticator app. Required for privileged actions.
        </p>
        <Link className="text-body text-accent underline" href="/settings/security">
          Manage two-factor authentication
        </Link>
      </Card>
      <Card className="flex flex-col gap-2">
        <h3 className="text-heading">Leaving United Feminist</h3>
        <p className="max-w-prose text-body text-text-secondary">
          Account deactivation and deletion controls are coming before launch. Until then, email{" "}
          <a className="text-accent underline" href="mailto:support@unitedfeminist.com">
            support@unitedfeminist.com
          </a>{" "}
          and we will handle it for you promptly.
        </p>
      </Card>
    </div>
  );
}
