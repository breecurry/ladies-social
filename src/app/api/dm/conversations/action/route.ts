import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { rpcError } from "@/lib/api";
import { requireDm } from "@/lib/dm/api";

const schema = z.object({
  action: z.enum(["accept", "decline", "delete", "mute", "unmute", "read"]),
  conversationId: z.string().uuid(),
});

/**
 * POST /api/dm/conversations/action — accept or decline a request,
 * delete-for-me, mute/unmute, mark read. Participant checks live in
 * the database functions.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireDm();
  if ("response" in auth) return auth.response;

  const parsed = schema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }
  const { action, conversationId } = parsed.data;

  const call =
    action === "accept"
      ? auth.supabase.rpc("dm_accept_request", { p_conversation: conversationId })
      : action === "decline"
        ? auth.supabase.rpc("dm_decline_request", { p_conversation: conversationId })
        : action === "delete"
          ? auth.supabase.rpc("dm_delete_conversation", { p_conversation: conversationId })
          : action === "read"
            ? auth.supabase.rpc("dm_mark_read", { p_conversation: conversationId })
            : auth.supabase.rpc("dm_set_muted", {
                p_conversation: conversationId,
                p_muted: action === "mute",
              });

  const { error } = await call;
  if (error) return rpcError(error);
  return NextResponse.json({ ok: true });
}
