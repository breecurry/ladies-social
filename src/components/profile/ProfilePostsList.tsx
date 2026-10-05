"use client";

import { useState } from "react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { ProfilePost } from "@/lib/database.types";
import { PostCard } from "@/components/post/PostCard";
import { useCompose } from "@/components/shell/ComposeProvider";
import { useViewer } from "@/components/shell/Providers";

const PAGE_SIZE = 20;

/**
 * Profile Posts / Replies tab content with cursor paging. When the
 * viewer has muted this account, posts sit behind a reveal so muting
 * is never a trap you cannot see out of (spec §10.3).
 */
export function ProfilePostsList({
  userId,
  handle,
  replies,
  initialPosts,
  mutedByViewer,
  isOwn,
}: {
  userId: string;
  handle: string;
  replies: boolean;
  initialPosts: ProfilePost[];
  mutedByViewer: boolean;
  isOwn: boolean;
}) {
  const { openCompose } = useCompose();
  const viewer = useViewer();
  const [revealed, setRevealed] = useState(!mutedByViewer);
  const [posts, setPosts] = useState<ProfilePost[]>(initialPosts);
  const [exhausted, setExhausted] = useState(initialPosts.length < PAGE_SIZE);
  const [loading, setLoading] = useState(false);

  if (!revealed) {
    return (
      <div className="flex flex-col items-center gap-3 px-6 py-12 text-center">
        <p className="text-body text-text-secondary">You muted @{handle}.</p>
        <button
          type="button"
          onClick={() => setRevealed(true)}
          className="min-h-11 rounded-full border border-border-strong bg-surface px-5 text-label text-text-primary hover:bg-surface-raised"
        >
          Show posts
        </button>
      </div>
    );
  }

  if (posts.length === 0) {
    return (
      <div className="flex flex-col items-center gap-3 px-6 py-12 text-center">
        {isOwn && viewer.id === userId ? (
          <>
            <p className="text-body text-text-secondary">
              {replies ? "You have not replied yet." : "You have not posted yet."}
            </p>
            {!replies ? (
              <button
                type="button"
                onClick={() => openCompose()}
                className="min-h-11 rounded-full bg-accent-fill px-6 text-label text-on-accent hover:bg-accent-hover"
              >
                Write a post
              </button>
            ) : null}
          </>
        ) : (
          <p className="text-body text-text-secondary">
            {replies ? "No replies yet." : "No posts yet."}
          </p>
        )}
      </div>
    );
  }

  const loadMore = async () => {
    const last = posts[posts.length - 1];
    if (!last) return;
    setLoading(true);
    const supabase = createSupabaseBrowserClient();
    const { data } = await supabase.rpc("profile_posts", {
      p_user: userId,
      p_replies: replies,
      p_before: last.created_at,
      p_limit: PAGE_SIZE,
      // Composite cursor: id breaks created_at ties so posts sharing a
      // timestamp are never skipped across a page boundary.
      p_before_id: last.id,
    });
    setLoading(false);
    if (!data) return;
    setPosts((current) => [...current, ...data]);
    if (data.length < PAGE_SIZE) setExhausted(true);
  };

  return (
    <div className="flex flex-col">
      {posts.map((post) => (
        <PostCard
          key={post.id}
          post={post}
          parentContext={
            replies && post.parent_author_handle
              ? { handle: post.parent_author_handle, excerpt: post.parent_excerpt ?? "" }
              : null
          }
        />
      ))}
      {exhausted ? null : (
        <div className="flex justify-center py-4">
          <button
            type="button"
            disabled={loading}
            onClick={() => void loadMore()}
            className="min-h-11 rounded-full px-5 text-label text-accent hover:bg-accent-subtle disabled:opacity-50"
          >
            {loading ? "Loading…" : "Load more"}
          </button>
        </div>
      )}
    </div>
  );
}
