import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { rpcError } from "@/lib/api";
import { requireDm } from "@/lib/dm/api";
import { dispatchSafetyEmails } from "@/lib/email/safety";
import type { Json } from "@/lib/database.types";

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
  evidence: z
    .array(
      z.object({
        messageId: z.number().int().positive(),
        plaintext: z.string().min(1).max(4000),
        frankKey: z.string().regex(/^[0-9a-f]{64}$/),
      }),
    )
    .min(1)
    .max(10),
});

/**
 * POST /api/dm/report — client-side report-with-evidence. The
 * reporter's device attaches the decrypted messages she selected; the
 * database verifies each franking commitment (the sender really sent
 * exactly this; the reporter cannot fabricate) and queues the safety@
 * email copy, which is dispatched here like every other report.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireDm();
  if ("response" in auth) return auth.response;

  const parsed = schema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }
  const { conversationId, reason, details, evidence } = parsed.data;

  const { data: reportId, error } = await auth.supabase.rpc("file_dm_report", {
    p_conversation: conversationId,
    p_reason: reason,
    p_details: details && details !== "" ? details : null,
    p_evidence: evidence as unknown as Json,
  });
  if (error) return rpcError(error);

  try {
    await dispatchSafetyEmails();
  } catch {
    // The outbox row persists; the next dispatch retries.
  }

  return NextResponse.json({ ok: true, reportId });
}
