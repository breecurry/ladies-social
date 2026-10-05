import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getViewer } from "@/lib/auth";
import type { DirectoryRow } from "@/lib/database.types";
import {
  PAGE_SIZE,
  parseDirectoryParams,
  toFilterArgs,
  type DirectoryParams,
} from "@/lib/directory";
import { DirectoryControls } from "@/components/owner/DirectoryControls";
import { DirectoryList } from "@/components/owner/DirectoryList";
import { ExportButton } from "@/components/owner/ExportButton";

export const metadata: Metadata = { title: "Members" };

/**
 * The member directory (Phase 2D spec, Part 1). Search-first, not
 * browse-first: it opens on the total member count, a handle search,
 * the filters, and the most recent arrivals — never page one of an
 * endless scroll. Every row is @handle-keyed; no legal name, email, or
 * contact detail has any code path into this surface. Owner-only,
 * enforced in the database (a non-Owner calling the functions gets
 * nothing); the redirect here just keeps the room invisible.
 */
export default async function OwnerMembersPage({
  searchParams,
}: {
  searchParams: Promise<DirectoryParams>;
}) {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  if (!viewer.isOwner) redirect("/home");

  const view = parseDirectoryParams(await searchParams);
  const filters = toFilterArgs(view);

  const supabase = await createSupabaseServerClient();
  const [{ data: total, error: totalError }, { data: rows, error: rowsError }, { data: matches }] =
    await Promise.all([
      supabase.rpc("owner_member_count"),
      supabase.rpc("owner_directory", { ...filters, p_limit: PAGE_SIZE }),
      supabase.rpc("owner_directory_count", filters),
    ]);

  if (totalError || rowsError) {
    return (
      <div className="flex flex-col gap-6">
        <h1 className="text-title">Members</h1>
        <div className="flex flex-col items-center gap-2 rounded-lg border border-border bg-surface px-6 py-16 text-center shadow-e1">
          <h2 className="text-heading text-text-primary">
            Something went wrong loading the directory
          </h2>
          <p className="max-w-sm text-body text-text-secondary">
            Nothing is lost. Reload the page to try again.
          </p>
        </div>
      </div>
    );
  }

  const memberCount = total ?? 0;
  const matchCount = matches ?? 0;
  const initialRows: DirectoryRow[] = rows ?? [];

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="flex flex-col gap-1">
          <h1 className="text-title">Members</h1>
          <p className="text-display text-text-primary">
            {memberCount.toLocaleString("en-US")}
            <span className="ml-2 text-body text-text-secondary">
              member{memberCount === 1 ? "" : "s"}
            </span>
          </p>
        </div>
        <ExportButton filters={filters} matchCount={matchCount} />
      </div>

      <DirectoryControls view={view} />

      {view.hasIntent ? (
        <p className="text-body text-text-secondary" aria-live="polite">
          {matchCount === 0
            ? null
            : matchCount < 5
              ? "Fewer than 5 members match"
              : `${matchCount.toLocaleString("en-US")} members match`}
        </p>
      ) : null}

      <section
        aria-label="Member directory"
        className="overflow-hidden rounded-lg border border-border bg-surface shadow-e1"
      >
        <DirectoryList
          key={JSON.stringify(filters)}
          initialRows={initialRows}
          filters={filters}
          hasIntent={view.hasIntent}
          matchCount={matchCount}
        />
      </section>
    </div>
  );
}
