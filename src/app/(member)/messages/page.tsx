import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { dmFeatureOn } from "@/lib/dm/server";
import { InboxClient } from "@/components/dm/InboxClient";
import { DmBootstrap } from "@/components/dm/DmBootstrap";

export const metadata: Metadata = { title: "Messages" };

/**
 * The Messages inbox (design §9, §10). Unreachable — a plain 404 —
 * while the DM feature flag is off.
 */
export default async function MessagesPage() {
  if (!(await dmFeatureOn())) notFound();
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  if (!viewer.profile || !viewer.isActiveMember) notFound();

  return (
    <>
      <DmBootstrap />
      <InboxClient viewerId={viewer.user.id} viewerHandle={viewer.profile.handle} />
    </>
  );
}
