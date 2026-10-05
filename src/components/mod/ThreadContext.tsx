import type { ModContextPost } from "@/lib/database.types";
import { relativeTime } from "@/lib/format";

/**
 * A reported post rendered in its thread context (design doc §3.2):
 * the parent chain above, a small window of replies below, the
 * reported item marked unmistakably — for assistive tech by its label,
 * not only by its colour band. This is a READ rendering: there are no
 * reply/like affordances, because the console is for judging, not
 * participating. Content a colleague already removed shows as a
 * neutral stub, never its original text.
 */
export function ThreadContext({ posts }: { posts: ModContextPost[] }) {
  return (
    <ul>
      {posts.map((post) => {
        const removed = post.body === "";
        return (
          <li
            key={post.id}
            className={`border-b border-border px-4 py-3 last:border-b-0 ${
              post.is_subject ? "border-l-2 border-l-accent bg-accent-subtle/40" : ""
            }`}
            style={post.depth > 0 ? { paddingLeft: `${16 + Math.min(post.depth, 3) * 16}px` } : undefined}
          >
            {post.is_subject ? (
              <p className="mb-1 text-caption text-accent">Reported {post.parent_post_id === null ? "post" : "reply"}</p>
            ) : null}
            <p className="text-caption text-text-tertiary">
              {removed ? "—" : `@${post.author_handle}`} · {relativeTime(post.created_at)}
            </p>
            {removed ? (
              <p className="text-body text-text-tertiary">
                {post.visibility === "removed_moderation"
                  ? "Removed by moderation"
                  : post.author_deleted || post.visibility === "removed_author"
                    ? "Removed by its author"
                    : "Unavailable"}
              </p>
            ) : (
              <p className="whitespace-pre-wrap break-words text-body text-text-primary">
                {post.body}
              </p>
            )}
          </li>
        );
      })}
    </ul>
  );
}
