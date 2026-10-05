import type { Metadata } from "next";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { SearchClient } from "@/components/people/SearchClient";

export const metadata: Metadata = { title: "Search" };

export default async function SearchPage() {
  // Trending lives on the pre-query Search screen (Phase 2F §6.2).
  // Before the Phase 2F migration is applied the RPC does not exist;
  // an error reads as "no topics yet", never a crash.
  const supabase = await createSupabaseServerClient();
  const { data } = await supabase.rpc("get_trending_tags", { p_limit: 5 });

  return (
    <div className="flex flex-col lg:mt-6 lg:overflow-hidden lg:rounded-lg lg:border lg:border-border lg:shadow-e1">
      <h1 className="sr-only">Search</h1>
      <SearchClient trending={data ?? []} />
    </div>
  );
}
