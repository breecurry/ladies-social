import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { dmFeatureOn } from "@/lib/dm/server";
import { ThreadClient } from "@/components/dm/ThreadClient";

export const metadata: Metadata = { title: "Messages" };

/** One conversation. 404 while the feature is off. */
export default async function ConversationPage({ params }: { params: Promise<{ id: string }> }) {
  if (!(await dmFeatureOn())) notFound();
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  if (!viewer.profile || !viewer.isActiveMember) notFound();

  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();

  return <ThreadClient viewerId={viewer.user.id} conversationId={id} />;
}
