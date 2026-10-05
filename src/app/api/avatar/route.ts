import { NextResponse } from "next/server";
import { requireUser, rpcError } from "@/lib/api";
import { deleteMediaVariants } from "@/lib/media/r2";

/**
 * DELETE /api/avatar — the member removes her own photo (spec 2.7:
 * routine, not destructive; she reverts to the letter placeholder).
 * A clean, unreported object is hard-deleted from storage; anything
 * under a report hold or legal hold is preserved out of reach — the
 * database makes that call, this route only executes it.
 */
export async function DELETE(): Promise<NextResponse> {
  const auth = await requireUser();
  if ("response" in auth) return auth.response;

  const { data, error } = await auth.supabase.rpc("remove_avatar");
  if (error) return rpcError(error);

  const removed = data?.[0];
  if (removed?.old_key && removed.old_purgeable) {
    try {
      await deleteMediaVariants(removed.old_key);
      await auth.supabase.rpc("avatar_mark_purged", { p_key: removed.old_key });
    } catch {
      // Best-effort: a missed purge is storage noise, never a leak.
    }
  }

  return NextResponse.json({ ok: true });
}
