"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { CaretLeft } from "@phosphor-icons/react";
import type { ThreadPost } from "@/lib/database.types";
import { PostCard } from "@/components/post/PostCard";
import { useCompose } from "@/components/shell/ComposeProvider";
import { useViewer } from "@/components/shell/Providers";

interface ThreadNode {
  post: ThreadPost;
  children: ThreadNode[];
}

/** Visible nesting budget: the root plus two reply levels (spec §6.1).
 *  The author's own chain spine renders FLAT and never consumes this
 *  budget (multi-part threads design §11.2); it applies only to
 *  replies by other people — and the author's non-spine branches —
 *  hanging off any part. */
const MAX_REL_DEPTH = 2;

function buildTree(rows: ThreadPost[], rootId: number): ThreadNode | null {
  const nodes = new Map<number, ThreadNode>();
  for (const row of rows) nodes.set(row.id, { post: row, children: [] });
  let root: ThreadNode | null = null;
  for (const node of nodes.values()) {
    if (node.post.id === rootId) {
      root = node;
      continue;
    }
    const parent =
      node.post.parent_post_id !== null ? nodes.get(node.post.parent_post_id) : undefined;
    parent?.children.push(node);
  }
  return root;
}

/**
 * The thread view (spec §6): three visible levels with indent guide
 * rails, then an explicit "view more replies" re-root. Unavailable
 * posts (deleted, blocked, muted) render as tombstones so the tree
 * never orphans a reply.
 *
 * Multi-part threads (design §11): when the root heads a chain — a run
 * of the author's own connected parts — the spine renders as a flat,
 * connected sequence of full cards, each captioned "Part k of N" with
 * the k over the parts a reader can actually see, joined by the
 * thread-rail connector. Other people's replies nest under the part
 * they answer, with the normal budget. A deleted part leaves a slim
 * honest marker; a chain whose author is unreachable collapses to ONE
 * "This thread is unavailable" — never a stack of blank part cards.
 */
export function ThreadView({
  rows,
  rootId,
  focusPostId,
}: {
  rows: ThreadPost[];
  rootId: number;
  /** A mid-chain entry point (a link to part 3): scrolled to and
   *  briefly highlighted after the chain loads from its head. */
  focusPostId?: number;
}) {
  const { openCompose } = useCompose();
  const viewer = useViewer();
  const root = buildTree(rows, rootId);

  // The author's chain spine, in order. spine_seq is structural
  // (hidden parts keep their place); the live "k of N" counts only the
  // parts a reader can see.
  const spineRows = rows
    .filter((row) => typeof row.spine_seq === "number")
    .sort((a, b) => (a.spine_seq ?? 0) - (b.spine_seq ?? 0));
  const chainMode =
    root !== null &&
    root.post.parent_post_id === null &&
    spineRows.length >= 2 &&
    spineRows[0]?.id === root.post.id;

  const focusRef = useRef<HTMLDivElement | null>(null);
  const [highlight, setHighlight] = useState(Boolean(focusPostId));
  useEffect(() => {
    if (!focusPostId) return;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    focusRef.current?.scrollIntoView({
      block: "center",
      behavior: reduced ? "auto" : "smooth",
    });
    const timer = window.setTimeout(() => setHighlight(false), 2000);
    return () => window.clearTimeout(timer);
  }, [focusPostId]);

  if (!root) return null;

  const replyTarget = (post: ThreadPost) => ({
    id: post.id,
    handle: post.author_handle,
    excerpt: post.body.length > 80 ? `${post.body.slice(0, 80)}…` : post.body,
    replyControl: post.reply_control,
  });

  const replyBar = (post: ThreadPost) => (
    <button
      type="button"
      onClick={() => openCompose(replyTarget(post))}
      className="flex min-h-12 w-full items-center gap-3 border-b border-border bg-surface px-4 text-left transition-colors duration-(--duration-fast) hover:bg-surface-raised"
    >
      <span
        aria-hidden
        className="flex size-8 shrink-0 items-center justify-center rounded-full bg-accent-subtle text-caption font-semibold text-accent"
      >
        {viewer.handle.charAt(0).toUpperCase()}
      </span>
      <span className="text-body text-text-tertiary">Reply to @{post.author_handle}</span>
    </button>
  );

  if (!chainMode) {
    return (
      <div className="flex flex-col lg:mt-6 lg:overflow-hidden lg:rounded-lg lg:border lg:border-border lg:shadow-e1">
        {root.post.parent_post_id !== null ? (
          <Link
            href={`/post/${root.post.parent_post_id}`}
            className="flex min-h-11 items-center gap-1 border-b border-border bg-surface px-4 text-label text-accent hover:bg-surface-raised"
          >
            <CaretLeft size={16} aria-hidden />
            View the conversation this reply belongs to
          </Link>
        ) : null}

        {root.post.unavailable ? (
          <Tombstone />
        ) : (
          <>
            <PostCard post={root.post} variant="root" />
            {replyBar(root.post)}
          </>
        )}

        <Replies nodes={root.children} relDepth={1} />
      </div>
    );
  }

  // ----- chain mode -----
  const nodes = new Map<number, ThreadNode>();
  const collect = (node: ThreadNode) => {
    nodes.set(node.post.id, node);
    node.children.forEach(collect);
  };
  collect(root);

  const spineNodes = spineRows
    .map((row) => nodes.get(row.id))
    .filter((node): node is ThreadNode => node !== undefined);
  const spineIds = new Set(spineNodes.map((node) => node.post.id));
  const visibleParts = spineNodes.filter((node) => !node.post.unavailable);
  const partCount = visibleParts.length;
  const allHidden = partCount === 0;
  const lastVisible = visibleParts[visibleParts.length - 1];

  // Live numbering over the visible parts only (design §10.2): deleting
  // part 3 of 5 renumbers the rest to 1..4.
  const liveIndex = new Map<number, number>();
  visibleParts.forEach((node, i) => liveIndex.set(node.post.id, i + 1));

  const branchesOf = (node: ThreadNode) =>
    node.children.filter((child) => !spineIds.has(child.post.id));

  return (
    <div className="flex flex-col lg:mt-6 lg:overflow-hidden lg:rounded-lg lg:border lg:border-border lg:shadow-e1">
      {allHidden ? (
        // The whole spine is unreachable (suspension, ban, a block, or
        // every part deleted): one tombstone for the whole thread, so
        // a reader never sees the shape of what is gone (design §17).
        <div className="border-b border-border bg-surface px-4 py-3">
          <p className="text-body text-text-tertiary">This thread is unavailable.</p>
        </div>
      ) : (
        spineNodes.map((node, i) => {
          const isLast = i === spineNodes.length - 1;
          const focused = node.post.id === focusPostId;
          return (
            <div
              key={node.post.id}
              ref={focused ? focusRef : undefined}
              className="relative"
            >
              {/* The connector: decorative reinforcement of the worded
                  caption, never the only signal (design §11.3). */}
              {spineNodes.length > 1 ? (
                <span
                  aria-hidden
                  className={`absolute left-[39px] w-0.5 bg-thread-rail ${
                    i === 0 ? "top-16 bottom-0" : isLast ? "top-0 h-4" : "top-0 bottom-0"
                  }`}
                />
              ) : null}
              {node.post.unavailable ? (
                <div className="border-b border-border bg-surface py-3 pr-4 pl-14">
                  <p className="text-caption text-text-tertiary">
                    The author removed this part.
                  </p>
                </div>
              ) : (
                <div
                  className={`transition-colors duration-(--duration-base) ${
                    focused && highlight ? "bg-accent-subtle" : ""
                  }`}
                >
                  <PostCard
                    post={node.post}
                    variant={i === 0 ? "root" : "part"}
                    chainPosition={{
                      index: liveIndex.get(node.post.id) ?? 1,
                      count: partCount,
                    }}
                  />
                </div>
              )}
              {node.post.id === lastVisible?.post.id ? replyBar(node.post) : null}
              {branchesOf(node).length > 0 ? (
                <div className="pl-10">
                  <Replies nodes={branchesOf(node)} relDepth={1} />
                </div>
              ) : null}
            </div>
          );
        })
      )}
      {allHidden
        ? spineNodes.map((node) =>
            branchesOf(node).length > 0 ? (
              <div key={node.post.id} className="pl-10">
                <Replies nodes={branchesOf(node)} relDepth={1} />
              </div>
            ) : null,
          )
        : null}
    </div>
  );
}

function Replies({ nodes, relDepth }: { nodes: ThreadNode[]; relDepth: number }) {
  if (nodes.length === 0) return null;
  return (
    <>
      {nodes.map((node) => (
        <div
          key={node.post.id}
          className={relDepth > 1 ? "ml-4 border-l-2 border-thread-rail md:ml-6" : ""}
        >
          {node.post.unavailable ? (
            <Tombstone />
          ) : (
            <PostCard post={node.post} avatarSize={relDepth > 1 ? 32 : 40} />
          )}
          {relDepth < MAX_REL_DEPTH ? (
            <Replies nodes={node.children} relDepth={relDepth + 1} />
          ) : node.children.length > 0 ? (
            <Link
              href={`/post/${node.post.id}`}
              className="ml-4 flex min-h-11 items-center border-b border-border px-4 text-label text-accent hover:bg-surface-raised md:ml-6"
            >
              View {node.children.length} more{" "}
              {node.children.length === 1 ? "reply" : "replies"}
            </Link>
          ) : null}
        </div>
      ))}
    </>
  );
}

function Tombstone() {
  return (
    <div className="border-b border-border bg-surface px-4 py-3">
      <p className="text-body text-text-tertiary">This post is unavailable.</p>
    </div>
  );
}
