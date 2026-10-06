import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { dmFeatureOn, shouldShowDmDisclosure } from "@/lib/dm/server";
import { InboxClient } from "@/components/dm/InboxClient";

export const metadata: Metadata = { title: "Messages" };

/**
 * The Messages inbox. Unreachable — a plain 404 — while the DM
 * feature flag is off.
 */
export default async function MessagesPage() {
  if (!(await dmFeatureOn())) notFound();
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  if (!viewer.profile || !viewer.isActiveMember) notFound();

  const showDisclosure = await shouldShowDmDisclosure();
  return (
    <InboxClient
      viewerId={viewer.user.id}
      viewerHandle={viewer.profile.handle}
      showDisclosure={showDisclosure}
    />
  );
}
