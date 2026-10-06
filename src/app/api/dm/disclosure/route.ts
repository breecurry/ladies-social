import { NextResponse } from "next/server";
import { rpcError } from "@/lib/api";
import { requireDm } from "@/lib/dm/api";
import { DM_DISCLOSURE_VERSION } from "@/lib/dm/disclosure";

/**
 * POST /api/dm/disclosure — record that the signed-in member
 * dismissed the DM disclosure banner. The version is taken from the
 * server-side constant, never from the request body, and the
 * timestamp is the database's now(): a member (or her clock) cannot
 * extend her own quiet period. dm_dismiss_disclosure() writes only
 * the caller's own dm_settings row.
 *
 * The client treats any failure here as "it will simply show again" —
 * no error UI, by design (the failure direction is toward showing).
 */
export async function POST(): Promise<NextResponse> {
  const auth = await requireDm();
  if ("response" in auth) return auth.response;

  const { error } = await auth.supabase.rpc("dm_dismiss_disclosure", {
    p_version: DM_DISCLOSURE_VERSION,
  });
  if (error) return rpcError(error);
  return NextResponse.json({ ok: true });
}
