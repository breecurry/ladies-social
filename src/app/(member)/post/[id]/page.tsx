import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { ThreadView } from "@/components/thread/ThreadView";

export const metadata: Metadata = { title: "Post" };

/**
 * Thread view for a post (or a re-rooted focused view of any reply:
 * the same route serves both, which is how arbitrary depth stays
 * readable, spec §6.1).
 *
 * Multi-part threads (design §11.1): a chain is always read from part
 * 1, so a link to a mid-chain part first resolves to the chain head
 * via chain_head() and the tapped part is scrolled to and highlighted.
 * Until migration 20261024000001 applies, chain_head() does not exist
 * and the resolver falls back to the old behavior — nothing breaks.
 */
export default async function PostPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const postId = Number(id);
  if (!Number.isInteger(postId) || postId <= 0) notFound();

  const supabase = await createSupabaseServerClient();

  let threadRoot = postId;
  const { data: headId, error: headError } = await supabase.rpc("chain_head", {
    p_post: postId,
  });
  if (!headError && typeof headId === "number" && headId > 0) threadRoot = headId;

  const { data: rows, error } = await supabase.rpc("get_thread", { p_post: threadRoot });
  if (error || !rows || rows.length === 0) notFound();

  return (
    <>
      <h1 className="sr-only">Thread</h1>
      <ThreadView
        rows={rows}
        rootId={threadRoot}
        focusPostId={threadRoot !== postId ? postId : undefined}
      />
    </>
  );
}
