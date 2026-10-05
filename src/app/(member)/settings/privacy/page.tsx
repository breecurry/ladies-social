import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { Card } from "@/components/ui";
import { DisplayNameToggle } from "@/components/DisplayNameToggle";
import { SearchIndexToggle } from "@/components/settings/Toggles";

export const metadata: Metadata = { title: "Privacy" };

/**
 * Privacy (spec §8.2.2): the legal-name opt-in sits first. The
 * database trigger guarantees the public display name can only ever
 * be NULL or the verified legal name.
 */
export default async function PrivacySettingsPage() {
  const viewer = await getViewer();
  if (!viewer || !viewer.profile) redirect("/login");

  const showingName = viewer.profile.display_name !== null;
  const handle = viewer.profile.handle;

  return (
    <div className="flex flex-col gap-4">
      <h2 className="text-title">Privacy</h2>

      <Card className="flex flex-col gap-4">
        <div className="flex flex-col gap-2">
          <h3 className="text-heading">Name visibility</h3>
          <p className="max-w-prose text-body text-text-secondary">
            Your legal name was verified when you joined. Members see{" "}
            <strong className="text-text-primary">@{handle}</strong> by default. Showing your legal
            name is your choice and you can turn it off at any time.
          </p>
          <div className="rounded-md border border-border bg-background px-4 py-3">
            <p className="text-caption text-text-tertiary">Your profile currently reads</p>
            <p className="text-label text-text-primary">@{handle}</p>
            {showingName ? (
              <p className="text-body text-text-secondary">{viewer.profile.display_name}</p>
            ) : null}
          </div>
        </div>
        <DisplayNameToggle showing={showingName} />
      </Card>

      <Card className="flex flex-col gap-3">
        <h3 className="text-heading">Search and discoverability</h3>
        <SearchIndexToggle initial={viewer.profile.search_indexable} />
        <p className="text-caption text-text-tertiary">
          Inside Hersciety, members can always find you by your @handle. Never by your legal
          name.
        </p>
      </Card>
    </div>
  );
}
