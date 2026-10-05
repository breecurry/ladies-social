import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { foldTag, isValidTagParam, decodeURIComponentSafe } from "@/lib/text";
import { TagFeedList } from "@/components/tags/TagFeedList";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ tag: string }>;
}): Promise<Metadata> {
  const { tag } = await params;
  return { title: `#${foldTag(decodeURIComponentSafe(tag))}` };
}

/**
 * The tag page (Phase 2F §4): /t/<canonical-tag>. Any other casing
 * redirects to the one canonical URL. Reverse-chronological stream of
 * the posts carrying the tag, served by the block- and mute-aware
 * feed_hashtag read; a staff-blocked tag shows the neutral
 * unavailable state instead of posts.
 */
export default async function TagPage({ params }: { params: Promise<{ tag: string }> }) {
  const { tag: rawParam } = await params;
  const raw = decodeURIComponentSafe(rawParam);
  if (!isValidTagParam(raw)) notFound();
  const canonical = foldTag(raw);
  if (raw !== canonical) redirect(`/t/${encodeURIComponent(canonical)}`);

  const viewer = await getViewer();
  if (!viewer) redirect("/login");

  const supabase = await createSupabaseServerClient();
  const [{ data: headerRows, error: headerError }, { data: posts }] = await Promise.all([
    supabase.rpc("get_tag", { p_tag: canonical }),
    supabase.rpc("feed_hashtag", { p_tag: canonical, p_limit: 20 }),
  ]);
  // Before the Phase 2F migration is applied these RPCs do not exist;
  // a missing-function error reads as "no such tag yet", never a crash.
  if (headerError) notFound();
  const header = headerRows?.[0];
  if (!header) notFound();

  if (header.status === "blocked") {
    return (
      <div className="flex flex-col lg:mt-6 lg:overflow-hidden lg:rounded-lg lg:border lg:border-border lg:shadow-e1">
        <div className="flex flex-col items-center gap-2 px-6 py-16 text-center">
          <h1 className="text-title text-text-primary">This topic is not available</h1>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col lg:mt-6 lg:overflow-hidden lg:rounded-lg lg:border lg:border-border lg:shadow-e1">
      <header className="flex flex-col gap-1 border-b border-border bg-surface px-4 py-4">
        <h1 className="break-words text-title text-text-primary">#{header.tag}</h1>
        {header.post_count > 0 ? (
          <p className="text-caption text-text-tertiary">
            {header.post_count} {header.post_count === 1 ? "post" : "posts"}
          </p>
        ) : null}
      </header>
      <TagFeedList tag={canonical} initialPosts={posts ?? []} />
    </div>
  );
}
