import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { ArrowSquareOut } from "@phosphor-icons/react/dist/ssr";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getViewer } from "@/lib/auth";
import { absoluteDate, STAFF_ROLE_LABEL } from "@/lib/directory";
import { caseKey, REASON_LABEL } from "@/lib/moderation";
import { Avatar } from "@/components/Avatar";
import { Badge, Card } from "@/components/ui";
import { AccountStatusChip } from "@/components/mod/chips";
import { IdentityPanel } from "@/components/owner/IdentityPanel";

export const metadata: Metadata = { title: "Member" };

/**
 * The member-detail glance view (Phase 2D spec §6): everything needed
 * to understand an account's standing and conduct, and nothing that
 * identifies the person behind it. Conduct is at a glance; identity is
 * behind the AAL2 step-up at the foot of the page (spec §7), a
 * different action on the same screen, logged when taken.
 */
export default async function OwnerMemberDetailPage({
  params,
}: {
  params: Promise<{ handle: string }>;
}) {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  if (!viewer.isOwner) redirect("/home");

  const { handle } = await params;
  const supabase = await createSupabaseServerClient();
  const [{ data: aalData }, { data: detailRows }] = await Promise.all([
    supabase.auth.mfa.getAuthenticatorAssuranceLevel(),
    supabase.rpc("owner_member_detail", { p_handle: handle }),
  ]);
  const member = detailRows?.[0];
  if (!member) notFound();

  const { data: enforcement } = await supabase.rpc("mod_enforcement_history", {
    p_target: member.user_id,
  });
  const history = enforcement ?? [];
  const aal2 = aalData?.currentLevel === "aal2";

  const standing: string[] = [
    `Joined ${absoluteDate(member.joined_at)}`,
    member.activity_bucket,
    `${member.post_count.toLocaleString("en-US")} post${member.post_count === 1 ? "" : "s"}`,
    `${member.follower_count.toLocaleString("en-US")} follower${member.follower_count === 1 ? "" : "s"}`,
    `${member.following_count.toLocaleString("en-US")} following`,
  ];

  return (
    <div className="flex flex-col gap-6 p-4">
      <p className="text-caption text-text-tertiary">
        <Link className="text-accent underline-offset-4 hover:underline" href="/owner/members">
          Members
        </Link>{" "}
        / @{member.handle}
      </p>

      <header className="flex items-center gap-4">
        <Avatar handle={member.handle} size={96} link={false} />
        <div className="flex min-w-0 flex-col gap-2">
          <h1 className="text-heading text-text-primary">@{member.handle}</h1>
          <div className="flex flex-wrap items-center gap-2">
            <AccountStatusChip status={member.status} expiresAt={member.status_expires_at} />
            {member.staff_role ? (
              <Badge tone="neutral">
                {STAFF_ROLE_LABEL[member.staff_role] ?? member.staff_role}
              </Badge>
            ) : null}
            {member.founding ? (
              <span className="rounded-full bg-accent-subtle px-2 py-0.5 text-micro text-accent">
                Founding
              </span>
            ) : null}
          </div>
        </div>
      </header>

      <Card className="flex flex-col gap-1 py-4">
        <h2 className="sr-only">Standing</h2>
        <p className="text-body text-text-secondary">{standing.join(" · ")}</p>
      </Card>

      <Card className="flex flex-col gap-3">
        <h2 className="text-heading">Enforcement standing</h2>
        {history.length === 0 ? (
          <p className="text-body text-text-secondary">
            No enforcement history. This account is in good standing.
          </p>
        ) : (
          <ul className="flex flex-col gap-2">
            {history.map((entry, index) => (
              <li
                key={`${entry.created_at}-${index}`}
                className="flex flex-wrap items-baseline gap-x-2 rounded-md border border-border px-3 py-2"
              >
                <span className="text-label text-text-primary capitalize">
                  {entry.action.replace(/_/g, " ")}
                  {entry.duration_days ? ` (${entry.duration_days}d)` : ""}
                </span>
                {entry.rule ? (
                  <span className="text-body text-text-secondary">
                    · {REASON_LABEL[entry.rule]}
                  </span>
                ) : null}
                <span className="text-caption text-text-tertiary">
                  · {absoluteDate(entry.created_at)} · by {entry.actor_role}
                </span>
              </li>
            ))}
          </ul>
        )}
        <Link
          href={`/mod/case/${caseKey(member.user_id, null)}`}
          className="inline-flex items-center gap-1 text-label text-accent underline-offset-4 hover:underline"
        >
          View in moderation <ArrowSquareOut size={16} aria-hidden />
        </Link>
      </Card>

      <IdentityPanel userId={member.user_id} aal2={aal2} />
    </div>
  );
}
