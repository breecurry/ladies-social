import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { ComposePrompt } from "@/components/feed/ComposePrompt";
import { FeedList } from "@/components/feed/FeedList";
import { EmptyFeed } from "@/components/feed/EmptyFeed";
import { WelcomeCard } from "@/components/feed/WelcomeCard";

export const metadata: Metadata = { title: "Home" };

/**
 * Home: the Following feed (fan-out-on-read, reverse chronological).
 * The Discover tab arrives in Phase 2B alongside its moderation
 * groundwork; until then Home is a single calm stream.
 */
export default async function HomePage() {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");

  const supabase = await createSupabaseServerClient();
  const [{ data: posts }, { count: followCount }, { count: ownPostCount }] = await Promise.all([
    supabase.rpc("feed_following", { p_limit: 20 }),
    supabase
      .from("follows")
      .select("followee_id", { count: "exact", head: true })
      .eq("follower_id", viewer.user.id),
    supabase
      .from("posts")
      .select("id", { count: "exact", head: true })
      .eq("author_id", viewer.user.id),
  ]);

  const feed = posts ?? [];
  const hasFollows = (followCount ?? 0) > 0;
  const isNew = !hasFollows && (ownPostCount ?? 0) === 0;

  return (
    <div className="flex flex-col lg:mt-6 lg:overflow-hidden lg:rounded-lg lg:border lg:border-border lg:shadow-e1">
      <h1 className="sr-only">Home</h1>
      {isNew ? <WelcomeCard /> : null}
      <ComposePrompt />
      {feed.length === 0 ? <EmptyFeed hasFollows={hasFollows} /> : <FeedList initialPosts={feed} />}
    </div>
  );
}
