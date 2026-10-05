"use client";

import { useState } from "react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { FeedPost } from "@/lib/database.types";
import { PostCard } from "@/components/post/PostCard";
import { useCompose } from "@/components/shell/ComposeProvider";

const PAGE_SIZE = 20;

/**
 * The tag-page stream (Phase 2F §4): newest first, cursor-paged, the
 * standard post card — including the Follow pill for authors the
 * viewer does not follow. Ends with the calm end-of-stream card.
 */
export function TagFeedList({ tag, initialPosts }: { tag: string; initialPosts: FeedPost[] }) {
  const { openCompose } = useCompose();
  const [posts, setPosts] = useState<FeedPost[]>(initialPosts);
  const [exhausted, setExhausted] = useState(initialPosts.length < PAGE_SIZE);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(false);

  if (posts.length === 0) {
    return (
      <div className="flex flex-col items-center gap-3 px-6 py-16 text-center">
        <h2 className="text-title text-text-primary">Nothing here with #{tag} yet</h2>
        <p className="text-body text-text-secondary">Be the first to post with it.</p>
        <button
          type="button"
          onClick={() => openCompose()}
          className="min-h-11 rounded-full bg-accent-fill px-6 text-label text-on-accent hover:bg-accent-hover"
        >
          Write a post
        </button>
      </div>
    );
  }

  const loadMore = async () => {
    const last = posts[posts.length - 1];
    if (!last) return;
    setLoading(true);
    setError(false);
    const supabase = createSupabaseBrowserClient();
    const { data, error: rpcError } = await supabase.rpc("feed_hashtag", {
      p_tag: tag,
      p_before: last.created_at,
      p_limit: PAGE_SIZE,
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
        <PostCard key={post.id} post={post} followPill={!(post.viewer_follows ?? true)} />
      ))}
      {exhausted ? (
        <div className="flex flex-col items-center gap-1 px-4 py-10 text-center">
          <p className="text-body text-text-secondary">
            That is everything with #{tag} for now.
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
