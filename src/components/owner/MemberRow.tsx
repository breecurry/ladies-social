import Link from "next/link";
import type { DirectoryRow } from "@/lib/database.types";
import { absoluteDate, STAFF_ROLE_LABEL } from "@/lib/directory";
import { Avatar } from "@/components/Avatar";
import { Badge } from "@/components/ui";
import { AccountStatusChip } from "@/components/mod/chips";

/**
 * One directory row (Phase 2D spec §3.1): the letter avatar, the
 * @handle (the ONLY name in the row — never a legal name), the
 * absolute join date, the status chip, the role chip when staff, and
 * the coarse activity bucket. The whole row links to the member's
 * glance view.
 */
export function MemberRow({ row }: { row: DirectoryRow }) {
  return (
    <li>
      <Link
        href={`/owner/members/${row.handle}`}
        aria-label={`View @${row.handle}`}
        className="flex min-h-16 items-center gap-3 border-b border-border bg-surface px-4 py-3 transition-colors duration-(--duration-fast) hover:bg-surface-raised"
      >
        <Avatar handle={row.handle} size={40} link={false} />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-label text-text-primary">@{row.handle}</span>
            {row.founding ? (
              <span className="rounded-full bg-accent-subtle px-2 py-0.5 text-micro text-accent">
                Founding
              </span>
            ) : null}
            {row.staff_role ? (
              <Badge tone="neutral">{STAFF_ROLE_LABEL[row.staff_role] ?? row.staff_role}</Badge>
            ) : null}
          </div>
          <p className="text-caption text-text-tertiary">
            Joined {absoluteDate(row.joined_at)} · {row.activity_bucket}
          </p>
        </div>
        <AccountStatusChip status={row.status} expiresAt={row.status_expires_at} />
      </Link>
    </li>
  );
}
