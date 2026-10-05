"use client";

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

/** Visible nesting budget: the root plus two reply levels (spec §6.1). */
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
 */
export function ThreadView({ rows, rootId }: { rows: ThreadPost[]; rootId: number }) {
  const { openCompose } = useCompose();
  const viewer = useViewer();
  const root = buildTree(rows, rootId);
  if (!root) return null;

  const replyTarget = (post: ThreadPost) => ({
    id: post.id,
    handle: post.author_handle,
    excerpt: post.body.length > 80 ? `${post.body.slice(0, 80)}…` : post.body,
    replyControl: post.reply_control,
  });

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
          <button
            type="button"
            onClick={() => openCompose(replyTarget(root.post))}
            className="flex min-h-12 w-full items-center gap-3 border-b border-border bg-surface px-4 text-left transition-colors duration-(--duration-fast) hover:bg-surface-raised"
          >
            <span
              aria-hidden
              className="flex size-8 shrink-0 items-center justify-center rounded-full bg-accent-subtle text-caption font-semibold text-accent"
            >
              {viewer.handle.charAt(0).toUpperCase()}
            </span>
            <span className="text-body text-text-tertiary">
              Reply to @{root.post.author_handle}
            </span>
          </button>
        </>
      )}

      <Replies nodes={root.children} relDepth={1} />
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
