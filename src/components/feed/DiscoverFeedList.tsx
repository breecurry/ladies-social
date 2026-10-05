"use client";

import Link from "next/link";
import { useState } from "react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { DiscoverPost } from "@/lib/database.types";
import { PostCard } from "@/components/post/PostCard";
import { useCompose } from "@/components/shell/ComposeProvider";

const PAGE_SIZE = 20;

/**
 * The Discover feed list (design doc §9-§12): server-rendered first
 * page of the lightly-ranked stream, then offset-paged "load more" on
 * the client (a ranked order has no stable keyset cursor). Cards are
 * identical to Following except for the Follow pill, which appears
 * exactly for authors the viewer does not follow (spec §4.7).
 *
 * The end of a thin feed closes with the warm founding-cohort card
 * (design doc §12) — an invitation, never a spinner and never fake
 * liveliness.
 */
export function DiscoverFeedList({ initialPosts }: { initialPosts: DiscoverPost[] }) {
  const { openCompose } = useCompose();
  const [posts, setPosts] = useState<DiscoverPost[]>(initialPosts);
  const [exhausted, setExhausted] = useState(initialPosts.length < PAGE_SIZE);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(false);

  const loadMore = async () => {
    setLoading(true);
    setError(false);
    const supabase = createSupabaseBrowserClient();
    const { data, error: rpcError } = await supabase.rpc("feed_discover", {
      p_limit: PAGE_SIZE,
      p_offset: posts.length,
    });
    setLoading(false);
    if (rpcError || !data) {
      setError(true);
      return;
    }
    setPosts((current) => {
      const seen = new Set(current.map((post) => post.id));
      return [...current, ...data.filter((post) => !seen.has(post.id))];
    });
    if (data.length < PAGE_SIZE) setExhausted(true);
  };

  return (
    <div className="flex flex-col">
      {posts.map((post) => (
        <PostCard key={post.id} post={post} followPill={!post.viewer_follows} />
      ))}
      {exhausted ? (
        <div className="flex flex-col items-center gap-3 px-4 py-10 text-center">
          <p className="text-heading text-text-primary">You are all caught up</p>
          <p className="max-w-sm text-body text-text-secondary">
            Hersciety is new, and you are early. Follow a few people, or be one of the first
            voices here.
          </p>
          <div className="flex flex-wrap justify-center gap-2">
            <button
              type="button"
              onClick={() => openCompose()}
              className="min-h-11 rounded-full bg-accent-fill px-6 text-label text-on-accent hover:bg-accent-hover"
            >
              Write a post
            </button>
            <Link
              href="/search"
              className="inline-flex min-h-11 items-center rounded-full border border-border-strong bg-surface px-6 text-label text-text-primary hover:bg-surface-raised"
            >
              Find people to follow
            </Link>
          </div>
        </div>
      ) : (
        <div className="flex justify-center py-4">
          <button
            type="button"
            disabled={loading}
            onClick={() => void loadMore()}
            className="min-h-11 rounded-full px-5 text-label text-accent hover:bg-accent-subtle disabled:opacity-50"
          >
            {loading ? "Loading…" : error ? "Could not load more. Retry" : "Load more"}
          </button>
        </div>
      )}
    </div>
  );
}
