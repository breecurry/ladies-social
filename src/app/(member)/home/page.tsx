import type { Metadata } from "next";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { ComposePrompt } from "@/components/feed/ComposePrompt";
import { FeedList } from "@/components/feed/FeedList";
import { EmptyFeed } from "@/components/feed/EmptyFeed";
import { WelcomeCard } from "@/components/feed/WelcomeCard";
import { HomeTabs, type HomeTab } from "@/components/feed/HomeTabs";
import { DiscoverFeedList } from "@/components/feed/DiscoverFeedList";
import { DiscoverHeaderNote } from "@/components/feed/DiscoverHeaderNote";
import { SuggestedAccounts } from "@/components/feed/SuggestedAccounts";
import { EmptyDiscover } from "@/components/feed/EmptyDiscover";

export const metadata: Metadata = { title: "Home" };

/**
 * Home with its two tabs (spec §4.1, §4.7): Following (fan-out-on-read,
 * reverse chronological) and Discover (recent posts from across
 * Hersciety, lightly ranked on positive signals only — design doc
 * §9-§13). Default tab: zero follows lands on Discover, otherwise
 * Following; after that the last explicit choice is remembered.
 */
export default async function HomePage({
  searchParams,
}: {
  searchParams: Promise<{ tab?: string }>;
}) {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");

  const supabase = await createSupabaseServerClient();
  const [{ tab: tabParam }, cookieStore] = await Promise.all([searchParams, cookies()]);

  const [{ count: followCount }, { count: ownPostCount }] = await Promise.all([
    supabase
      .from("follows")
      .select("followee_id", { count: "exact", head: true })
      .eq("follower_id", viewer.user.id),
    supabase
      .from("posts")
      .select("id", { count: "exact", head: true })
      .eq("author_id", viewer.user.id),
  ]);

  const hasFollows = (followCount ?? 0) > 0;
  const isNew = !hasFollows && (ownPostCount ?? 0) === 0;

  const remembered = cookieStore.get("home_tab")?.value;
  const tab: HomeTab =
    tabParam === "discover" || tabParam === "following"
      ? tabParam
      : remembered === "discover" || remembered === "following"
        ? remembered
        : hasFollows
          ? "following"
          : "discover";

  if (tab === "discover") {
    const fewFollows = (followCount ?? 0) < 3;
    const [{ data: posts }, { data: people }] = await Promise.all([
      supabase.rpc("feed_discover", { p_limit: 20, p_offset: 0 }),
      fewFollows
        ? supabase.rpc("suggested_accounts", { p_limit: 5 })
        : Promise.resolve({ data: null }),
    ]);
    const feed = posts ?? [];
    const suggestions = people ?? [];

    return (
      <div className="flex flex-col lg:mt-6 lg:overflow-hidden lg:rounded-lg lg:border lg:border-border lg:shadow-e1">
        <h1 className="sr-only">Home — Discover</h1>
        {isNew ? <WelcomeCard /> : null}
        <HomeTabs active="discover" />
        <ComposePrompt />
        <DiscoverHeaderNote />
        <SuggestedAccounts people={suggestions} />
        {feed.length === 0 ? (
          suggestions.length === 0 ? (
            <EmptyDiscover />
          ) : (
            <div className="flex flex-col items-center gap-1 px-4 py-10 text-center">
              <p className="text-heading text-text-primary">You are all caught up</p>
              <p className="max-w-sm text-body text-text-secondary">
                Hersciety is new, and you are early. Follow a few people, or be one of the
                first voices here.
              </p>
            </div>
          )
        ) : (
          <DiscoverFeedList initialPosts={feed} />
        )}
      </div>
    );
  }

  const { data: posts } = await supabase.rpc("feed_following", { p_limit: 20 });
  const feed = posts ?? [];

  return (
    <div className="flex flex-col lg:mt-6 lg:overflow-hidden lg:rounded-lg lg:border lg:border-border lg:shadow-e1">
      <h1 className="sr-only">Home — Following</h1>
      {isNew ? <WelcomeCard /> : null}
      <HomeTabs active="following" />
      <ComposePrompt />
      {feed.length === 0 ? <EmptyFeed hasFollows={hasFollows} /> : <FeedList initialPosts={feed} />}
    </div>
  );
}
