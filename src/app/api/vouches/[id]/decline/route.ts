import { NextResponse, type NextRequest } from "next/server";
import { requireUser, rpcError } from "@/lib/api";

/**
 * POST /api/vouches/[id]/decline — declining never rejects the
 * applicant; she continues in the review queue.
 */
export async function POST(
  _request: NextRequest,
  context: { params: Promise<{ id: string }> },
): Promise<NextResponse> {
  const auth = await requireUser();
  if ("response" in auth) return auth.response;
  const { id } = await context.params;
  const { error } = await auth.supabase.rpc("decline_vouch", { p_request: id });
  if (error) return rpcError(error);
  return NextResponse.json({ ok: true });
}
