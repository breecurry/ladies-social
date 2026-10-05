import type { Metadata } from "next";
import { FollowListPage } from "@/components/people/FollowListPage";

export const metadata: Metadata = { title: "Following" };

export default async function FollowingPage({
  params,
}: {
  params: Promise<{ handle: string }>;
}) {
  const { handle } = await params;
  return <FollowListPage handle={handle} kind="following" />;
}
