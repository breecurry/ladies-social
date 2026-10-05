"use client";

import { useState } from "react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { FeedPost } from "@/lib/database.types";
import { PostCard } from "@/components/post/PostCard";

const PAGE_SIZE = 20;

/**
 * The Following feed list: server-rendered first page, then
 * cursor-paged "load more" on the client. When there is genuinely no
 * more to load, a calm end-of-feed card closes the stream — never a
 * spinner (spec §9.2).
 */
export function FeedList({ initialPosts }: { initialPosts: FeedPost[] }) {
  const [posts, setPosts] = useState<FeedPost[]>(initialPosts);
  const [exhausted, setExhausted] = useState(initialPosts.length < PAGE_SIZE);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(false);

  const loadMore = async () => {
    const last = posts[posts.length - 1];
    if (!last) return;
    setLoading(true);
    setError(false);
    const supabase = createSupabaseBrowserClient();
    const { data, error: rpcError } = await supabase.rpc("feed_following", {
      p_before: last.created_at,
      p_limit: PAGE_SIZE,
      // Composite cursor: id breaks created_at ties so posts sharing a
      // timestamp are never skipped across a page boundary.
      p_before_id: last.id,
    });
    setLoading(false);
    if (rpcError || !data) {
      setError(true);
      return;
    }
    setPosts((current) => [...current, ...data]);
    if (data.length < PAGE_SIZE) setExhausted(true);
  };

  return (
    <div className="flex flex-col">
      {posts.map((post) => (
        <PostCard key={post.id} post={post} />
      ))}
      {exhausted ? (
        <div className="flex flex-col items-center gap-1 px-4 py-10 text-center">
          <p className="text-heading text-text-primary">You are all caught up</p>
          <p className="text-body text-text-secondary">
            Herciety is brand new, so this is everything for now. More arrives as the
            community grows.
          </p>
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
