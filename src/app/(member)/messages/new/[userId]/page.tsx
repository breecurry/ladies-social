import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { dmFeatureOn } from "@/lib/dm/server";
import { ThreadClient } from "@/components/dm/ThreadClient";
import { DmBootstrap } from "@/components/dm/DmBootstrap";

export const metadata: Metadata = { title: "New message" };

/**
 * A conversation that does not exist yet: the composer against a
 * member picked in the recipient picker. The first send creates the
 * conversation server-side and the client replaces the URL with the
 * real thread. 404 while the feature is off.
 */
export default async function NewConversationPage({
  params,
}: {
  params: Promise<{ userId: string }>;
}) {
  if (!(await dmFeatureOn())) notFound();
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  if (!viewer.profile || !viewer.isActiveMember) notFound();

  const { userId } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(userId) || userId === viewer.user.id) notFound();

  // Handle lookup under RLS: invisible (blocked/deleted) profiles 404,
  // which reveals nothing beyond what every profile page reveals.
  const supabase = await createSupabaseServerClient();
  const { data: peer } = await supabase
    .from("profiles")
    .select("user_id, handle")
    .eq("user_id", userId)
    .maybeSingle();
  if (!peer) notFound();

  return (
    <>
      <DmBootstrap />
      <ThreadClient
        viewerId={viewer.user.id}
        viewerHandle={viewer.profile.handle}
        peerId={peer.user_id}
        peerHandle={peer.handle}
      />
    </>
  );
}
