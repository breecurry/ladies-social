import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import {
  CaretRight,
  ChartBar,
  ClockCounterClockwise,
  IdentificationCard,
  UsersThree,
  Hourglass,
} from "@phosphor-icons/react/dist/ssr";
import { getViewer } from "@/lib/auth";
import { Card } from "@/components/ui";

export const metadata: Metadata = { title: "Owner tools" };

const TOOLS = [
  {
    href: "/owner/members",
    icon: UsersThree,
    label: "Members",
    description: "Every member, by @handle — search, filter, and account for the community.",
  },
  {
    href: "/owner/insights",
    icon: ChartBar,
    label: "Insights",
    description: "The numbers: membership, growth, content, and safety operations.",
  },
  {
    href: "/owner/roles",
    icon: IdentificationCard,
    label: "Roles",
    description: "Grant and revoke staff roles. Owner-only, AAL2, audited.",
  },
  {
    href: "/owner/audit",
    icon: ClockCounterClockwise,
    label: "Audit log",
    description: "Every privileged action, append-only and hash-chained.",
  },
  {
    href: "/owner/age-gate",
    icon: Hourglass,
    label: "Age gate",
    description: "Under-18 signup blocks and the support review flow.",
  },
] as const;

/**
 * The Owner-tools hub (Phase 2D spec §1): one owner surface gaining
 * rooms, not a second admin area. Owner-only: a non-owner is
 * redirected and never learns it exists, exactly like /owner/roles.
 */
export default async function OwnerHubPage() {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  if (!viewer.isOwner) redirect("/home");

  return (
    <div className="flex flex-col gap-6 p-4">
      <div className="flex flex-col gap-2">
        <h1 className="text-title">Owner tools</h1>
        <p className="max-w-prose text-body text-text-secondary">
          The surfaces only you can see. Everything here is enforced in the database, not just in
          this interface.
        </p>
      </div>

      <Card className="flex flex-col divide-y divide-border p-0">
        {TOOLS.map(({ href, icon: Icon, label, description }) => (
          <Link
            key={href}
            href={href}
            className="flex min-h-11 items-center gap-4 px-6 py-4 hover:bg-accent-subtle"
          >
            <Icon size={24} aria-hidden className="shrink-0 text-accent" />
            <span className="flex min-w-0 flex-1 flex-col">
              <span className="text-label text-text-primary">{label}</span>
              <span className="text-caption text-text-tertiary">{description}</span>
            </span>
            <CaretRight size={16} aria-hidden className="shrink-0 text-text-tertiary" />
          </Link>
        ))}
      </Card>
    </div>
  );
}
