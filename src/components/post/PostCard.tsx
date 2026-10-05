"use client";

import { useState, type KeyboardEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ChatCircle, Heart } from "@phosphor-icons/react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { ReplyControl } from "@/lib/database.types";
import { relativeTime, fullTimestamp } from "@/lib/format";
import { Avatar, type AvatarSize } from "@/components/Avatar";
import { PostBody } from "@/components/post/PostBody";
import { OverflowMenu } from "@/components/post/OverflowMenu";
import { useToast } from "@/components/shell/ToastProvider";
import { useViewer } from "@/components/shell/Providers";
import { useCompose } from "@/components/shell/ComposeProvider";

export interface PostCardData {
  id: number;
  author_id: string | null;
  author_handle: string;
  author_founding: boolean;
  body: string;
  reply_control: ReplyControl;
  like_count: number;
  reply_count: number;
  viewer_liked: boolean;
  created_at: string;
}

/**
 * The post card (spec §4.2): avatar, handle-forward identity block,
 * body, reply-control note, and the Reply/Like action row with ZERO
 * COUNTS HIDDEN. The identity block renders the @handle only — never
 * a legal name; the data shape makes anything else impossible.
 */
export function PostCard({
  post,
  variant = "feed",
  avatarSize = 48,
  parentContext,
}: {
  post: PostCardData;
  /** feed = clickable card; root = thread hero with full timestamp. */
  variant?: "feed" | "root";
  avatarSize?: AvatarSize;
  /** One-line parent context for profile Replies rows (spec §7.3). */
  parentContext?: { handle: string; excerpt: string } | null;
}) {
  const router = useRouter();
  const viewer = useViewer();
  const { showToast } = useToast();
  const { openCompose } = useCompose();
  const [liked, setLiked] = useState(post.viewer_liked);
  const [likeCount, setLikeCount] = useState(post.like_count);
  const [hiddenUndo, setHiddenUndo] = useState<(() => Promise<void>) | null>(null);

  const isOwn = post.author_id === viewer.id;

  if (hiddenUndo) {
    return (
      <div
        aria-live="polite"
        className="flex items-center justify-between gap-3 border-b border-border bg-surface px-4 py-3"
      >
        <p className="text-body text-text-secondary">
          Thanks. You will see less from @{post.author_handle}.
        </p>
        <button
          type="button"
          className="min-h-11 rounded-md px-3 text-label text-accent hover:bg-accent-subtle"
          onClick={() => {
            void hiddenUndo().then(() => setHiddenUndo(null));
          }}
        >
          Undo
        </button>
      </div>
    );
  }

  const toggleLike = async () => {
    const supabase = createSupabaseBrowserClient();
    if (liked) {
      setLiked(false);
      setLikeCount((n) => Math.max(n - 1, 0));
      const { error } = await supabase
        .from("likes")
        .delete()
        .eq("user_id", viewer.id)
        .eq("post_id", post.id);
      if (error) {
        setLiked(true);
        setLikeCount((n) => n + 1);
        showToast("Could not remove the like. Try again.");
      }
    } else {
      setLiked(true);
      setLikeCount((n) => n + 1);
      const { error } = await supabase
        .from("likes")
        .insert({ user_id: viewer.id, post_id: post.id });
      if (error) {
        setLiked(false);
        setLikeCount((n) => Math.max(n - 1, 0));
        showToast("Could not like that. Try again.");
      }
    }
  };

  const openThread = () => {
    if (variant === "feed") router.push(`/post/${post.id}`);
  };

  const onCardKeyDown = (event: KeyboardEvent<HTMLElement>) => {
    if (variant === "feed" && (event.key === "Enter" || event.key === " ") && event.target === event.currentTarget) {
      event.preventDefault();
      openThread();
    }
  };

  const reply = () =>
    openCompose({
      id: post.id,
      handle: post.author_handle,
      excerpt: post.body.length > 80 ? `${post.body.slice(0, 80)}…` : post.body,
      replyControl: post.reply_control,
    });

  return (
    <article
      aria-label={`Post by @${post.author_handle}, ${relativeTime(post.created_at)}`}
      onClick={openThread}
      onKeyDown={onCardKeyDown}
      tabIndex={variant === "feed" ? 0 : undefined}
      className={`flex flex-col gap-3 border-b border-border bg-surface p-4 ${
        variant === "feed" ? "cursor-pointer transition-colors duration-(--duration-fast) hover:bg-surface-raised" : ""
      }`}
    >
      {parentContext ? (
        <p className="text-caption text-text-tertiary">
          Replying to @{parentContext.handle}: {parentContext.excerpt}
        </p>
      ) : null}
      <div className="flex items-start gap-3">
        <Avatar handle={post.author_handle} size={avatarSize} />
        <div className="flex min-w-0 flex-1 items-center gap-1.5">
          <Link
            href={`/u/${post.author_handle}`}
            onClick={(event) => event.stopPropagation()}
            className="truncate text-label font-semibold text-text-primary hover:underline"
          >
            @{post.author_handle}
          </Link>
          <span className="text-caption text-text-tertiary">
            · {relativeTime(post.created_at)}
          </span>
          {post.author_founding ? (
            <span className="rounded-full bg-accent-subtle px-2 py-0.5 text-micro text-accent">
              Founding
            </span>
          ) : null}
        </div>
        {post.author_id ? (
          <OverflowMenu
            targetUserId={post.author_id}
            targetHandle={post.author_handle}
            postId={post.id}
            isOwn={isOwn}
            onHidden={variant === "feed" ? (undo) => setHiddenUndo(() => undo) : undefined}
          />
        ) : null}
      </div>

      <PostBody body={post.body} />

      {variant === "root" ? (
        <p className="text-caption text-text-tertiary">{fullTimestamp(post.created_at)}</p>
      ) : null}

      {post.reply_control !== "everyone" ? (
        <p className="text-caption text-text-tertiary">
          {post.reply_control === "followed"
            ? `People @${post.author_handle} follows can reply`
            : "Only mentioned people can reply"}
        </p>
      ) : null}

      <div className="flex items-center gap-8" onClick={(event) => event.stopPropagation()}>
        <button
          type="button"
          aria-label={`Reply${post.reply_count > 0 ? `, ${post.reply_count} replies` : ""}`}
          onClick={reply}
          className="flex min-h-11 items-center gap-1.5 rounded-md px-2 text-text-secondary hover:text-text-primary"
        >
          <ChatCircle size={20} aria-hidden />
          {post.reply_count > 0 ? (
            <span className="text-caption text-text-tertiary">{post.reply_count}</span>
          ) : null}
        </button>
        <button
          type="button"
          aria-pressed={liked}
          aria-label={liked ? `Liked${likeCount > 0 ? `, ${likeCount} likes` : ""}` : `Like${likeCount > 0 ? `, ${likeCount} likes` : ""}`}
          onClick={() => void toggleLike()}
          className={`flex min-h-11 items-center gap-1.5 rounded-md px-2 ${
            liked ? "text-accent" : "text-text-secondary hover:text-text-primary"
          }`}
        >
          <Heart size={20} weight={liked ? "fill" : "regular"} aria-hidden />
          {likeCount > 0 ? (
            <span className={`text-caption ${liked ? "text-accent" : "text-text-tertiary"}`}>
              {likeCount}
            </span>
          ) : null}
        </button>
      </div>
    </article>
  );
}
