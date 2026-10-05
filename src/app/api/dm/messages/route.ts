import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { rpcError } from "@/lib/api";
import { requireDm, isBytea } from "@/lib/dm/api";
import type { Json } from "@/lib/database.types";

const headerSchema = z.object({
  dh: z.string().regex(/^[0-9a-f]{64}$/),
  pn: z.number().int().min(0),
  n: z.number().int().min(0),
  x3dh: z
    .object({
      ik: z.string().regex(/^[0-9a-f]{128}$/),
      ek: z.string().regex(/^[0-9a-f]{64}$/),
      spk: z.string().regex(/^[0-9a-f]{64}$/),
      opk: z.string().regex(/^[0-9a-f]{64}$/).nullable(),
    })
    .optional(),
});

const sendSchema = z.object({
  recipientId: z.string().uuid(),
  recipientDeviceId: z.string().uuid(),
  header: headerSchema,
  ciphertext: z.string().max(33000),
  frankHash: z.string(),
});

/**
 * POST /api/dm/messages — store one end-to-end encrypted message. The
 * body is ciphertext plus public header values; every inbox and
 * permission rule (block, DMs off, request policy, the one-message
 * request cap) is enforced inside dm_send_message(), never here.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireDm();
  if ("response" in auth) return auth.response;

  const parsed = sendSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }
  const { recipientId, recipientDeviceId, header, ciphertext, frankHash } = parsed.data;
  if (!isBytea(ciphertext) || !isBytea(frankHash, 32)) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }

  const { data, error } = await auth.supabase.rpc("dm_send_message", {
    p_recipient: recipientId,
    p_recipient_device: recipientDeviceId,
    p_header: header as Json,
    p_ciphertext: ciphertext,
    p_frank_hash: frankHash,
  });
  if (error) {
    // The one retryable case: her security code changed (new device).
    if (error.message.includes("RECIPIENT_DEVICE_CHANGED")) {
      return NextResponse.json(
        { ok: false, error: "RECIPIENT_DEVICE_CHANGED" },
        { status: 409 },
      );
    }
    return rpcError(error);
  }
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
 * GET /api/dm/messages?conversationId=&afterId= — ciphertext rows for
 * a conversation the caller participates in. Decryption happens on the
 * member's device; the server cannot read what it returns.
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
