import Link from "next/link";
import { notFound } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { HANDLE_REGEX } from "@/lib/validation";
import { PersonRow } from "@/components/people/PersonRow";

/**
 * Shared follower/following list surface (spec §7.2). Rows come from
 * list_followers()/list_following(), which return handle-only
 * identities and already exclude blocked relationships.
 */
export async function FollowListPage({
  handle,
  kind,
}: {
  handle: string;
  kind: "followers" | "following";
}) {
  const normalized = handle.toLowerCase();
  if (!HANDLE_REGEX.test(normalized)) notFound();

  const supabase = await createSupabaseServerClient();
  const { data: profile } = await supabase
    .from("profiles")
    .select("user_id, handle")
    .eq("handle", normalized)
    .maybeSingle();
  if (!profile) notFound();

  const { data: rows } = await supabase.rpc(
    kind === "followers" ? "list_followers" : "list_following",
    { p_user: profile.user_id, p_limit: 50 },
  );
  const people = rows ?? [];

  return (
    <div className="flex flex-col lg:mt-6 lg:overflow-hidden lg:rounded-lg lg:border lg:border-border lg:shadow-e1">
      <header className="border-b border-border bg-surface px-4 py-3">
        <h1 className="text-heading text-text-primary">
          <Link href={`/u/${profile.handle}`} className="hover:underline">
            @{profile.handle}
          </Link>{" "}
          · {kind === "followers" ? "Followers" : "Following"}
        </h1>
      </header>
      {people.length === 0 ? (
        <div className="px-6 py-12 text-center">
          <p className="text-body text-text-secondary">
            {kind === "followers"
              ? "No followers yet. They will appear here."
              : "Not following anyone yet."}
          </p>
        </div>
      ) : (
        people.map((person) => <PersonRow key={person.user_id} person={person} />)
      )}
    </div>
  );
}
