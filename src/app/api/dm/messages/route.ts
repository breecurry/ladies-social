import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { rpcError } from "@/lib/api";
import { requireDm } from "@/lib/dm/api";

const sendSchema = z.object({
  recipientId: z.string().uuid(),
  body: z.string().min(1).max(2000),
});

/**
 * POST /api/dm/messages — send one message. The body is stored
 * readable on the server (DMs are not end-to-end encrypted — a fact
 * every Messages surface discloses); every inbox and permission rule
 * (block, DMs off, request policy, the one-message request cap) is
 * enforced inside dm_send_message(), never here.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireDm();
  if ("response" in auth) return auth.response;

  const parsed = sendSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }
  const { recipientId, body } = parsed.data;

  const { data, error } = await auth.supabase.rpc("dm_send_message", {
    p_recipient: recipientId,
    p_body: body,
  });
  if (error) return rpcError(error);
  const row = data?.[0];
  if (!row) {
    return NextResponse.json({ ok: false, error: "Could not send." }, { status: 400 });
  }
  return NextResponse.json({
    ok: true,
    messageId: row.message_id,
    conversationId: row.conversation_id,
    state: row.conversation_state,
    sentAt: row.sent_at,
  });
}

/**
 * GET /api/dm/messages?conversationId=&afterId= — the messages of a
 * conversation the caller participates in. Participation is verified
 * inside dm_fetch_messages(); the caller's own "delete for me"
 * horizon applies.
 */
export async function GET(request: NextRequest): Promise<NextResponse> {
  const auth = await requireDm();
  if ("response" in auth) return auth.response;

  const conversationId = request.nextUrl.searchParams.get("conversationId") ?? "";
  const afterRaw = request.nextUrl.searchParams.get("afterId");
  if (!/^[0-9a-f-]{36}$/i.test(conversationId)) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }
  const afterId = afterRaw === null ? null : Number(afterRaw);
  if (afterId !== null && (!Number.isInteger(afterId) || afterId < 0)) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }

  const { data, error } = await auth.supabase.rpc("dm_fetch_messages", {
    p_conversation: conversationId,
    p_after_id: afterId === 0 ? null : afterId,
    p_limit: 200,
  });
  if (error) return rpcError(error);
  return NextResponse.json({ ok: true, messages: data ?? [] });
}
