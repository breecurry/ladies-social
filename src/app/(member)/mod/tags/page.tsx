import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { modTier } from "@/lib/moderation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { TagControls } from "@/components/mod/TagControls";

export const metadata: Metadata = { title: "Topics" };

/**
 * The console's topics room (Phase 2F §7): look a tag up, see its real
 * size and its 48-hour participation, and suppress it proportionally.
 * Members never report a tag — they report conduct in posts — so this
 * surface is reached from the console, not from any member flow.
 */
export default async function ModTagsPage() {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  const tier = modTier(viewer.roles);
  if (tier === "none") redirect("/home");

  const supabase = await createSupabaseServerClient();
  const { data } = await supabase.rpc("mod_tag_lookup", { p_query: null, p_limit: 20 });

  return (
    <div className="flex flex-col gap-4 px-4 py-4">
      <header>
        <h1 className="text-title text-text-primary">Topics</h1>
        <p className="max-w-prose text-body text-text-secondary">
          De-trending removes a tag from trending and search suggestions while its posts stay
          reachable. Blocking also makes the topic page unavailable. Both are reversible and
          audited; neither removes a post or actions an account.
        </p>
      </header>
      <TagControls initialRows={data ?? []} tier={tier} />
    </div>
  );
}
