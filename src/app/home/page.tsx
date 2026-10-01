import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { Card } from "@/components/ui";

export const metadata: Metadata = { title: "Home" };

export default async function HomePage() {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  if (!viewer.isAdmitted) redirect("/pending");

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-title">Welcome, @{viewer.profile?.handle}</h1>
      <Card className="flex flex-col gap-3">
        <h2 className="text-heading">You&apos;re in</h2>
        <p className="text-body text-text-secondary">
          Posts, replies and the feed arrive in the next phase. For now you can vouch for people who
          name you when applying, and manage how your name appears.
        </p>
        <div className="flex flex-wrap gap-3 pt-1">
          <Link className="text-body text-accent underline" href="/vouches">
            Vouch requests
          </Link>
          <Link className="text-body text-accent underline" href="/settings">
            Settings
          </Link>
        </div>
      </Card>
    </div>
  );
}
