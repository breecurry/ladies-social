import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { rpcError } from "@/lib/api";
import { requireDm } from "@/lib/dm/api";
import { dispatchSafetyEmails } from "@/lib/email/safety";

const schema = z.object({
  conversationId: z.string().uuid(),
  reason: z.enum([
    "harassment",
    "hate",
    "violence_threat",
    "doxxing",
    "csam",
    "ncii",
    "spam",
    "impersonation",
    "self_harm",
    "other",
  ]),
  details: z.string().trim().max(2000).optional(),
  messageIds: z.array(z.number().int().positive()).min(1).max(10),
});

/**
 * POST /api/dm/report — report messages in a conversation. The
 * reporter selects which messages (1-10); the database snapshots them
 * server-side into the evidence table (the server can read them — no
 * client-supplied content is ever presented as the accused's words)
 * and queues the safety@ email copy, dispatched here like every other
 * report.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireDm();
  if ("response" in auth) return auth.response;

  const parsed = schema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }
  const { conversationId, reason, details, messageIds } = parsed.data;

  const { data: reportId, error } = await auth.supabase.rpc("file_dm_report", {
    p_conversation: conversationId,
    p_reason: reason,
    p_details: details && details !== "" ? details : null,
    p_message_ids: messageIds,
  });
  if (error) return rpcError(error);

  try {
    await dispatchSafetyEmails();
  } catch {
    // The outbox row persists; the next dispatch retries.
  }

  return NextResponse.json({ ok: true, reportId });
}
