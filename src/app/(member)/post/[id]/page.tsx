import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { ThreadView } from "@/components/thread/ThreadView";

export const metadata: Metadata = { title: "Post" };

/**
 * Thread view for a post (or a re-rooted focused view of any reply:
 * the same route serves both, which is how arbitrary depth stays
 * readable, spec §6.1).
 */
export default async function PostPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const postId = Number(id);
  if (!Number.isInteger(postId) || postId <= 0) notFound();

  const supabase = await createSupabaseServerClient();
  const { data: rows, error } = await supabase.rpc("get_thread", { p_post: postId });
  if (error || !rows || rows.length === 0) notFound();

  return (
    <>
      <h1 className="sr-only">Thread</h1>
      <ThreadView rows={rows} rootId={postId} />
    </>
  );
}
