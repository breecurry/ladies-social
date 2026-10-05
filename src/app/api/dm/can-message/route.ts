import { NextResponse, type NextRequest } from "next/server";
import { rpcError } from "@/lib/api";
import { requireDm } from "@/lib/dm/api";

/**
 * GET /api/dm/can-message?userId= — where a message from the caller to
 * this member would land: "inbox", "request", or "none". The database
 * returns the identical "none" for a block, DMs off, and "no one", so
 * nothing here can confirm a block.
 */
export async function GET(request: NextRequest): Promise<NextResponse> {
  const auth = await requireDm();
  if ("response" in auth) return auth.response;

  const userId = request.nextUrl.searchParams.get("userId") ?? "";
  if (!/^[0-9a-f-]{36}$/i.test(userId)) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }

  const { data, error } = await auth.supabase.rpc("dm_can_message", { p_user: userId });
  if (error) return rpcError(error);
  return NextResponse.json({ ok: true, route: data ?? "none" });
}
