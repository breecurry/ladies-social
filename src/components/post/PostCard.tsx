"use client";

import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ChatCircle, Heart, Repeat, Quotes } from "@phosphor-icons/react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { ReplyControl, ResolvedMention, QuotedCard } from "@/lib/database.types";
import { relativeTime, fullTimestamp } from "@/lib/format";
import { Avatar, type AvatarSize } from "@/components/Avatar";
import { FollowControl } from "@/components/follow/FollowControl";
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
  /** Phase 2F fields; optional so pre-migration rows degrade gracefully. */
  reshare_count?: number;
  viewer_reshared?: boolean;
  mentions?: ResolvedMention[] | null;
  quoted?: QuotedCard | null;
  /** Multi-part threads: live "Part k of N" when the post belongs to a
   * chain of 2+ readable parts; null/absent otherwise (including every
   * row read before migration 20261024000001 applies). */
  chain_index?: number | null;
  chain_count?: number | null;
}

/**
 * The post card (spec §4.2): avatar, handle-forward identity block,
 * body, reply-control note, and the Reply/Repeat/Like action row with
 * ZERO COUNTS HIDDEN. The identity block renders the @handle only —
 * never a legal name; the data shape makes anything else impossible.
 *
 * Phase 2F adds the Repeat action (plain repost and quote-post, both
 * first-class), the repost attribution line, and the nested card a
 * quote-post carries.
 */
export function PostCard({
  post,
  variant = "feed",
  avatarSize = 48,
  parentContext,
  followPill = false,
  attribution,
  chainPosition,
}: {
  post: PostCardData;
  /** feed = clickable card; root = thread hero with full timestamp;
   * part = a chain part in the thread view (not clickable, no hero
   * timestamp — the flat spine of the multi-part threads design §11). */
  variant?: "feed" | "root" | "part";
  avatarSize?: AvatarSize;
  /** One-line parent context for profile Replies rows (spec §7.3). */
  parentContext?: { handle: string; excerpt: string } | null;
  /**
   * Discover cards only (spec §4.2, §4.7): show the compact Follow
   * pill after the identity block for an author the viewer does not
   * yet follow. The pill's presence IS the "you do not follow this
   * person" signal, so Following cards never pass this.
   */
  followPill?: boolean;
  /** Handles of the people whose reposts surfaced this card, newest
   * first — the "@handle reposted" line (Phase 2F §16). */
  attribution?: string[] | null;
  /** Thread view only: this card's live position in its chain, shown
   * as the worded caption and read in the card's accessible name —
   * never colour or the connector alone (design §11.3, §19). */
  chainPosition?: { index: number; count: number } | null;
}) {
  const router = useRouter();
  const viewer = useViewer();
  const { showToast } = useToast();
  const { openCompose } = useCompose();
  const [liked, setLiked] = useState(post.viewer_liked);
  const [likeCount, setLikeCount] = useState(post.like_count);
  const [reshared, setReshared] = useState(post.viewer_reshared ?? false);
  const [reshareCount, setReshareCount] = useState(post.reshare_count ?? 0);
  const [repeatOpen, setRepeatOpen] = useState(false);
  const [hiddenUndo, setHiddenUndo] = useState<(() => Promise<void>) | null>(null);
  const repeatRef = useRef<HTMLDivElement>(null);
  const repeatTriggerRef = useRef<HTMLButtonElement>(null);

  const isOwn = post.author_id === viewer.id;

  useEffect(() => {
    if (!repeatOpen) return;
    const onPointerDown = (event: PointerEvent) => {
      if (repeatRef.current && !repeatRef.current.contains(event.target as Node)) {
        setRepeatOpen(false);
      }
    };
    const onKeyDown = (event: globalThis.KeyboardEvent) => {
      if (event.key !== "Escape") return;
      event.stopPropagation();
      setRepeatOpen(false);
      repeatTriggerRef.current?.focus();
    };
    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [repeatOpen]);

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

  // A plain repost is one optimistic tap with an undo toast (Phase 2F
  // §15) — the like/follow treatment, no confirmation dialog. Undoing
  // later is the same control again.
  const removeRepost = async () => {
    setReshared(false);
    setReshareCount((n) => Math.max(n - 1, 0));
    const supabase = createSupabaseBrowserClient();
    const { error } = await supabase
      .from("reshares")
      .delete()
      .eq("user_id", viewer.id)
      .eq("post_id", post.id);
    if (error) {
      setReshared(true);
      setReshareCount((n) => n + 1);
      showToast("Could not undo the repost. Try again.");
    }
    router.refresh();
  };

  const repost = async () => {
    setRepeatOpen(false);
    setReshared(true);
    setReshareCount((n) => n + 1);
    const supabase = createSupabaseBrowserClient();
    const { error } = await supabase
      .from("reshares")
      .insert({ user_id: viewer.id, post_id: post.id });
    if (error) {
      setReshared(false);
      setReshareCount((n) => Math.max(n - 1, 0));
      showToast("Could not repost that. Try again.");
      return;
    }
    showToast("Reposted", {
      actionLabel: "Undo",
      onAction: removeRepost,
      durationMs: 6000,
    });
    router.refresh();
  };

  const quote = () => {
    setRepeatOpen(false);
    openCompose(undefined, {
      id: post.id,
      handle: post.author_handle,
      excerpt: post.body.length > 200 ? `${post.body.slice(0, 200)}…` : post.body,
    });
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

  const repeatLabelBase = reshared ? "Reposted" : "Repost";
  const repeatLabel =
    reshareCount > 0
      ? `${repeatLabelBase}, ${reshareCount} ${reshareCount === 1 ? "repost" : "reposts"}`
      : repeatLabelBase;

  // The feed/profile data path carries chain_index/chain_count; the
  // thread view passes chainPosition. Either way the reader learns
  // "this is part k of a thread of N" in words.
  const chain =
    chainPosition ??
    (typeof post.chain_count === "number" &&
    post.chain_count >= 2 &&
    typeof post.chain_index === "number"
      ? { index: post.chain_index, count: post.chain_count }
      : null);

  return (
    <article
      aria-label={`Post by @${post.author_handle}${
        chain ? `, part ${chain.index} of ${chain.count}` : ""
      }, ${relativeTime(post.created_at)}`}
      onClick={openThread}
      onKeyDown={onCardKeyDown}
      tabIndex={variant === "feed" ? 0 : undefined}
      className={`flex flex-col gap-3 border-b border-border bg-surface p-4 ${
        variant === "feed" ? "cursor-pointer transition-colors duration-(--duration-fast) hover:bg-surface-raised" : ""
      }`}
    >
      {attribution && attribution.length > 0 ? (
        <p className="flex items-center gap-1.5 text-caption text-text-tertiary">
          <Repeat size={14} aria-hidden />
          {attributionLine(attribution, viewer.handle)}
        </p>
      ) : null}
      {parentContext ? (
        <p className="text-caption text-text-tertiary">
          Replying to @{parentContext.handle}: {parentContext.excerpt}
        </p>
      ) : null}
      <div className="flex items-start gap-3">
        <Avatar handle={post.author_handle} size={avatarSize} userId={post.author_id} />
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
          {followPill && post.author_id && !isOwn ? (
            <FollowControl
              targetUserId={post.author_id}
              targetHandle={post.author_handle}
              initialFollowing={false}
              variant="pill"
            />
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

      {chainPosition ? (
        <p className="text-caption text-text-tertiary">
          Part {chainPosition.index} of {chainPosition.count}
        </p>
      ) : null}

      <PostBody body={post.body} mentions={post.mentions ?? null} />

      {post.quoted ? <QuotedPreview quoted={post.quoted} /> : null}

      {chain && !chainPosition ? (
        <Link
          href={`/post/${post.id}`}
          onClick={(event) => event.stopPropagation()}
          aria-label={`${
            chain.index > 1 ? `Part ${chain.index} of ${chain.count}. ` : ""
          }Show this thread, ${chain.count} parts`}
          className="flex min-h-11 items-center gap-1.5 text-label text-accent hover:underline"
        >
          {chain.index > 1 ? `Part ${chain.index} of ${chain.count} · ` : ""}Show this thread
          <span aria-hidden className="text-caption font-normal text-text-tertiary">
            · {chain.count} parts
          </span>
        </Link>
      ) : null}

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
        <div ref={repeatRef} className="relative">
          <button
            ref={repeatTriggerRef}
            type="button"
            aria-haspopup="menu"
            aria-expanded={repeatOpen}
            aria-label={repeatLabel}
            onClick={() => setRepeatOpen((v) => !v)}
            className={`flex min-h-11 items-center gap-1.5 rounded-md px-2 ${
              reshared ? "text-accent" : "text-text-secondary hover:text-text-primary"
            }`}
          >
            <Repeat size={20} weight={reshared ? "bold" : "regular"} aria-hidden />
            {reshareCount > 0 ? (
              <span className={`text-caption ${reshared ? "text-accent" : "text-text-tertiary"}`}>
                {reshareCount}
              </span>
            ) : null}
          </button>
          {repeatOpen ? (
            <div
              role="menu"
              aria-label="Repost options"
              className="absolute bottom-full left-0 z-30 mb-1 min-w-44 rounded-md bg-surface-raised py-2 shadow-e2"
            >
              {isOwn ? null : reshared ? (
                <button
                  type="button"
                  role="menuitem"
                  className="flex min-h-11 w-full items-center gap-3 px-4 text-left text-body text-text-primary hover:bg-accent-subtle"
                  onClick={() => {
                    setRepeatOpen(false);
                    void removeRepost();
                  }}
                >
                  <Repeat size={20} aria-hidden /> Undo repost
                </button>
              ) : (
                <button
                  type="button"
                  role="menuitem"
                  className="flex min-h-11 w-full items-center gap-3 px-4 text-left text-body text-text-primary hover:bg-accent-subtle"
                  onClick={() => void repost()}
                >
                  <Repeat size={20} aria-hidden /> Repost
                </button>
              )}
              <button
                type="button"
                role="menuitem"
                className="flex min-h-11 w-full items-center gap-3 px-4 text-left text-body text-text-primary hover:bg-accent-subtle"
                onClick={quote}
              >
                <Quotes size={20} aria-hidden /> Quote
              </button>
            </div>
          ) : null}
        </div>
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

/** "@handle reposted" / "@a and N others reposted" / "You reposted". */
function attributionLine(handles: string[], viewerHandle: string): string {
  const first = handles[0];
  if (first === undefined) return "";
  const name = first === viewerHandle ? "You" : `@${first}`;
  if (handles.length === 1) return `${name} reposted`;
  return `${name} and ${handles.length - 1} ${handles.length === 2 ? "other" : "others"} reposted`;
}

/**
 * The nested compact card inside a quote-post (Phase 2F §16): the
 * quoted author's identity and body, linking to the original thread.
 * When the original is deleted, removed, its author unreachable, or a
 * block stands between any of the people involved, the server sends
 * only the unavailable stub — no author, no text, no reason.
 */
function QuotedPreview({ quoted }: { quoted: QuotedCard }) {
  if (quoted.unavailable) {
    return (
      <div className="rounded-md border border-border bg-background px-3 py-2">
        <p className="text-body text-text-tertiary">This post is unavailable.</p>
      </div>
    );
  }
  return (
    <Link
      href={`/post/${quoted.id}`}
      onClick={(event) => event.stopPropagation()}
      className="block rounded-md border border-border bg-background p-3 transition-colors duration-(--duration-fast) hover:bg-surface-raised"
    >
      <span className="flex items-center gap-2">
        <Avatar handle={quoted.handle} size={24} link={false} userId={quoted.author_id} />
        <span className="truncate text-label font-semibold text-text-primary">
          @{quoted.handle}
        </span>
        <span className="text-caption text-text-tertiary">
          · {relativeTime(quoted.created_at)}
        </span>
        {quoted.founding ? (
          <span className="rounded-full bg-accent-subtle px-2 py-0.5 text-micro text-accent">
            Founding
          </span>
        ) : null}
      </span>
      <span className="mt-1 block line-clamp-4 whitespace-pre-wrap break-words text-body text-text-primary">
        {quoted.body}
      </span>
    </Link>
  );
}
