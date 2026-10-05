import { NextResponse, type NextRequest } from "next/server";
import { rpcError } from "@/lib/api";
import { requireDm } from "@/lib/dm/api";

/**
 * GET /api/dm/conversations?tab=primary|requests — the inbox rows.
 * @handle only; no message content (previews are decrypted on-device).
 */
export async function GET(request: NextRequest): Promise<NextResponse> {
  const auth = await requireDm();
  if ("response" in auth) return auth.response;

  const tab = request.nextUrl.searchParams.get("tab") === "requests";
  const { data, error } = await auth.supabase.rpc("dm_list_conversations", {
    p_requests: tab,
  });
  if (error) return rpcError(error);
  return NextResponse.json({ ok: true, conversations: data ?? [] });
}
