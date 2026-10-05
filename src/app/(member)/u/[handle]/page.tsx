import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { joinedDate } from "@/lib/format";
import { HANDLE_REGEX } from "@/lib/validation";
import { Avatar } from "@/components/Avatar";
import { FollowControl } from "@/components/follow/FollowControl";
import { OverflowMenu } from "@/components/post/OverflowMenu";
import { EditProfileDialog } from "@/components/profile/EditProfileDialog";
import { ProfilePostsList } from "@/components/profile/ProfilePostsList";
import { UnblockButton } from "@/components/profile/UnblockButton";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ handle: string }>;
}): Promise<Metadata> {
  const { handle } = await params;
  return { title: `@${handle}` };
}

/**
 * Profile (spec §7): handle-forward identity. This page is the ONE
 * surface that may show a legal name, and only when the member opted
 * in (profiles.display_name is trigger-locked to NULL or the verified
 * legal name). When absent, nothing hints a name exists.
 */
export default async function ProfilePage({
  params,
  searchParams,
}: {
  params: Promise<{ handle: string }>;
  searchParams: Promise<{ tab?: string }>;
}) {
  const [{ handle }, { tab }] = await Promise.all([params, searchParams]);
  const normalized = handle.toLowerCase();
  if (!HANDLE_REGEX.test(normalized)) notFound();

  const viewer = await getViewer();
  if (!viewer) redirect("/login");

  const supabase = await createSupabaseServerClient();
  const { data: profile } = await supabase
    .from("profiles")
    .select("user_id, handle, display_name, bio, founding_member, created_at")
    .eq("handle", normalized)
    .maybeSingle();
  if (!profile) notFound();

  const isOwn = profile.user_id === viewer.user.id;
  const replies = tab === "replies";

  const [
    { count: followerCount },
    { count: followingCount },
    { data: followRow },
    { data: muteRow },
    { data: blockRow },
    { data: posts },
  ] = await Promise.all([
    supabase
      .from("follows")
      .select("follower_id", { count: "exact", head: true })
      .eq("followee_id", profile.user_id),
    supabase
      .from("follows")
      .select("followee_id", { count: "exact", head: true })
      .eq("follower_id", profile.user_id),
    supabase
      .from("follows")
      .select("followee_id")
      .eq("follower_id", viewer.user.id)
      .eq("followee_id", profile.user_id)
      .maybeSingle(),
    supabase
      .from("mutes")
      .select("muted_id")
      .eq("muter_id", viewer.user.id)
      .eq("muted_id", profile.user_id)
      .maybeSingle(),
    supabase
      .from("blocks")
      .select("blocked_id")
      .eq("blocker_id", viewer.user.id)
      .eq("blocked_id", profile.user_id)
      .maybeSingle(),
    supabase.rpc("profile_posts", {
      p_user: profile.user_id,
      p_replies: replies,
      p_limit: 20,
    }),
  ]);

  const blockedByViewer = blockRow !== null;

  return (
    <div className="flex flex-col lg:mt-6 lg:overflow-hidden lg:rounded-lg lg:border lg:border-border lg:shadow-e1">
      <header className="flex flex-col gap-3 border-b border-border bg-surface p-4">
        <div className="flex items-start justify-between gap-3">
          <Avatar handle={profile.handle} size={96} link={false} />
          <div className="flex items-center gap-2 pt-2">
            {isOwn ? (
              <EditProfileDialog initialBio={profile.bio} />
            ) : blockedByViewer ? (
              <UnblockButton targetUserId={profile.user_id} targetHandle={profile.handle} />
            ) : (
              <FollowControl
                targetUserId={profile.user_id}
                targetHandle={profile.handle}
                initialFollowing={followRow !== null}
                variant="profile"
              />
            )}
            {isOwn ? null : (
              <OverflowMenu
                targetUserId={profile.user_id}
                targetHandle={profile.handle}
                isOwn={false}
              />
            )}
          </div>
        </div>
        <div className="flex flex-col gap-1">
          <div className="flex items-center gap-2">
            <h1 className="text-title text-text-primary">@{profile.handle}</h1>
            {profile.founding_member ? (
              <span className="rounded-full bg-accent-subtle px-2 py-0.5 text-micro text-accent">
                Founding
              </span>
            ) : null}
          </div>
          {profile.display_name ? (
            <p className="text-body text-text-secondary">{profile.display_name}</p>
          ) : null}
          {profile.bio ? <p className="text-body text-text-secondary">{profile.bio}</p> : null}
          <p className="text-caption text-text-tertiary">Joined {joinedDate(profile.created_at)}</p>
          <div className="flex gap-4 pt-1">
            <Link href={`/u/${profile.handle}/followers`} className="hover:underline">
              <span className="text-label text-text-primary">{followerCount ?? 0}</span>{" "}
              <span className="text-caption text-text-tertiary">Followers</span>
            </Link>
            <Link href={`/u/${profile.handle}/following`} className="hover:underline">
              <span className="text-label text-text-primary">{followingCount ?? 0}</span>{" "}
              <span className="text-caption text-text-tertiary">Following</span>
            </Link>
          </div>
        </div>
      </header>

      {blockedByViewer ? (
        <div className="flex flex-col items-center gap-2 px-6 py-12 text-center">
          <p className="text-body text-text-secondary">
            You blocked @{profile.handle}. Their posts are hidden and they cannot see yours.
          </p>
        </div>
      ) : (
        <>
          <nav aria-label="Profile sections" className="flex border-b border-border bg-surface">
            <TabLink href={`/u/${profile.handle}`} label="Posts" active={!replies} />
            <TabLink href={`/u/${profile.handle}?tab=replies`} label="Replies" active={replies} />
          </nav>
          <ProfilePostsList
            userId={profile.user_id}
            handle={profile.handle}
            replies={replies}
            initialPosts={posts ?? []}
            mutedByViewer={muteRow !== null && !isOwn}
            isOwn={isOwn}
          />
        </>
      )}
    </div>
  );
}

function TabLink({ href, label, active }: { href: string; label: string; active: boolean }) {
  return (
    <Link
      href={href}
      aria-current={active ? "page" : undefined}
      className={`flex min-h-11 flex-1 items-center justify-center border-b-2 text-label ${
        active
          ? "border-accent text-accent"
          : "border-transparent text-text-secondary hover:text-text-primary"
      }`}
    >
      {label}
    </Link>
  );
}
