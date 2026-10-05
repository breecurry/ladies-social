import { redirect } from "next/navigation";
import { Warning } from "@phosphor-icons/react/dist/ssr";
import { getViewer } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/shell/AppShell";
import { dmFeatureOn } from "@/lib/dm/server";
import { Providers, type ModMenuInfo } from "@/components/shell/Providers";
import { SessionHeartbeat } from "@/components/shell/SessionHeartbeat";
import { Card } from "@/components/ui";
import { modTier, TIER_LABEL, REASON_LABEL } from "@/lib/moderation";
import type { MyAccountStatus } from "@/lib/database.types";

/**
 * Every signed-in surface lives inside the application shell. This
 * layout is also where an enforcement state meets the member (design
 * doc §8.3): a suspension is a full interstitial with its end date, a
 * ban is a calm terminal screen with the appeal path, a restriction is
 * a persistent banner inside the working app. The member always learns
 * the RULE and the ACTION, never the reporter.
 */
export default async function MemberLayout({ children }: { children: React.ReactNode }) {
  let viewer = await getViewer();
  if (!viewer) redirect("/login");

  const supabase = await createSupabaseServerClient();

  // Lazy expiry: a restriction/suspension whose clock ran out flips
  // back to active the moment the member arrives.
  if (
    viewer.profile &&
    (viewer.profile.status === "restricted" || viewer.profile.status === "suspended") &&
    viewer.profile.status_expires_at !== null &&
    new Date(viewer.profile.status_expires_at) <= new Date()
  ) {
    const { data: flipped } = await supabase.rpc("refresh_my_status");
    if (flipped) viewer = (await getViewer()) ?? viewer;
  }

  const profile = viewer.profile;
  if (!profile || profile.status === "deactivated" || profile.status === "deleted") {
    return (
      <main className="mx-auto w-full max-w-md px-4 py-16">
        <h1 className="mb-6 text-title">Account unavailable</h1>
        <Card className="flex flex-col gap-3">
          <p className="text-body text-text-secondary">
            This account is currently closed. If you believe this is a mistake, contact{" "}
            <a className="text-accent underline" href="mailto:appeals@unitedfeminist.com">
              appeals@unitedfeminist.com
            </a>
            .
          </p>
        </Card>
      </main>
    );
  }

  if (profile.status === "banned" || profile.status === "suspended") {
    const { data: statusRows } = await supabase.rpc("my_account_status");
    const status = statusRows?.[0] ?? null;
    return profile.status === "banned" ? (
      <BannedScreen handle={profile.handle} status={status} />
    ) : (
      <SuspendedScreen status={status} expiresAt={profile.status_expires_at} />
    );
  }

  const tier = modTier(viewer.roles);
  let mod: ModMenuInfo | null = null;
  if (tier !== "none") {
    const { data: countRows } = await supabase.rpc("mod_queue_counts");
    const counts = countRows?.[0];
    mod = {
      label: TIER_LABEL[tier],
      openCount: counts?.open_count ?? 0,
      criticalCount: counts?.critical_count ?? 0,
    };
  }

  const { count } = await supabase
    .from("notifications")
    .select("id", { count: "exact", head: true })
    .is("read_at", null);

  // The DM feature flag (Phase 2C). Both layers must agree, and any
  // error — including the migration not yet being applied — reads as
  // off, so the shell simply has no Messages entry.
  const dmEnabled = await dmFeatureOn();
  let dmUnread = 0;
  if (dmEnabled) {
    const { data: unreadTotal } = await supabase.rpc("dm_unread_total");
    dmUnread = typeof unreadTotal === "number" ? unreadTotal : 0;
  }

  let restrictionNotice: string | null = null;
  if (profile.status === "restricted" && profile.status_expires_at !== null) {
    const { data: statusRows } = await supabase.rpc("my_account_status");
    const status = statusRows?.[0];
    const until = formatDate(profile.status_expires_at);
    restrictionNotice = `Your account is limited until ${until}. You can read, but you cannot post or reply right now.${
      status?.last_rule ? ` Reason: ${REASON_LABEL[status.last_rule].toLowerCase()}.` : ""
    }`;
  }

  return (
    <Providers
      viewer={{ id: viewer.user.id, handle: profile.handle, isOwner: viewer.isOwner, mod }}
    >
      <SessionHeartbeat />
      <AppShell
        handle={profile.handle}
        initialUnread={count ?? 0}
        dmEnabled={dmEnabled}
        dmUnread={dmUnread}
      >
        {restrictionNotice ? (
          <div
            role="status"
            className="mx-4 mt-3 flex items-start gap-2 rounded-lg bg-surface-raised px-4 py-3 shadow-e1"
          >
            <Warning size={18} weight="fill" aria-hidden className="mt-0.5 shrink-0 text-warning" />
            <p className="text-body text-text-primary">
              {restrictionNotice}{" "}
              <a className="text-accent underline" href="mailto:appeals@unitedfeminist.com">
                Appeal this decision
              </a>
              .
            </p>
          </div>
        ) : null}
        {children}
      </AppShell>
    </Providers>
  );
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

/** §8.3: on login a suspension is explained before anything fails. */
function SuspendedScreen({
  status,
  expiresAt,
}: {
  status: MyAccountStatus | null;
  expiresAt: string | null;
}) {
  return (
    <main className="mx-auto w-full max-w-md px-4 py-16">
      <h1 className="mb-6 text-title">Your account is suspended</h1>
      <Card className="flex flex-col gap-3">
        <p className="text-body text-text-primary">
          Your account is suspended{expiresAt ? ` until ${formatDate(expiresAt)}` : ""}. During
          this time you cannot post, reply, like, or follow. Your profile stays visible.
        </p>
        {status?.last_rule ? (
          <p className="text-body text-text-secondary">
            Reason: {REASON_LABEL[status.last_rule].toLowerCase()}.
          </p>
        ) : null}
        <p className="text-body text-text-secondary">
          If you believe this is wrong, you can appeal within 30 days at{" "}
          <a className="text-accent underline" href="mailto:appeals@unitedfeminist.com">
            appeals@unitedfeminist.com
          </a>
          .
        </p>
      </Card>
    </main>
  );
}

/** §8.3: the terminal screen — calm, non-taunting, with the appeal
 * path and a case reference so support can find the action. */
function BannedScreen({
  handle,
  status,
}: {
  handle: string;
  status: MyAccountStatus | null;
}) {
  const reference = status?.last_action_at
    ? `${handle}-${new Date(status.last_action_at).toISOString().slice(0, 10)}`
    : handle;
  return (
    <main className="mx-auto w-full max-w-md px-4 py-16">
      <h1 className="mb-6 text-title">Your account has been permanently closed</h1>
      <Card className="flex flex-col gap-3">
        {status?.last_rule ? (
          <p className="text-body text-text-primary">
            Reason: {REASON_LABEL[status.last_rule].toLowerCase()}.
          </p>
        ) : null}
        <p className="text-body text-text-secondary">
          You can appeal this decision within 30 days. Email{" "}
          <a
            className="text-accent underline"
            href={`mailto:appeals@unitedfeminist.com?subject=${encodeURIComponent(
              `Appeal — case ${reference}`,
            )}`}
          >
            appeals@unitedfeminist.com
          </a>{" "}
          and include the reference below.
        </p>
        <p className="rounded-md bg-surface-raised px-3 py-2 text-body text-text-primary">
          <span className="text-caption text-text-tertiary">Reference: </span>
          {reference}
        </p>
      </Card>
    </main>
  );
}
