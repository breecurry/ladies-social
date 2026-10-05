import type { Metadata } from "next";
import { FollowListPage } from "@/components/people/FollowListPage";

export const metadata: Metadata = { title: "Followers" };

export default async function FollowersPage({
  params,
}: {
  params: Promise<{ handle: string }>;
}) {
  const { handle } = await params;
  return <FollowListPage handle={handle} kind="followers" />;
}
