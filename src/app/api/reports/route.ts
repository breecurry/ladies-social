import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { requireUser, rpcError } from "@/lib/api";
import { dispatchSafetyEmails } from "@/lib/email/safety";

const bodySchema = z
  .object({
    subject: z.enum(["post", "user"]),
    postId: z.number().int().positive().optional(),
    userId: z.string().uuid().optional(),
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
  })
  .refine((v) => (v.subject === "post" ? v.postId !== undefined : v.userId !== undefined), {
    message: "Missing subject.",
  });

/**
 * POST /api/reports — file a report. Validation, routing, rate limits
 * and the duplicate guard are all enforced inside file_report()
 * (SECURITY DEFINER); this route exists so the safety@ email copy —
 * queued durably by the same database transaction — is dispatched at
 * filing time (owner decision: two traceable copies of every report).
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireUser();
  if ("response" in auth) return auth.response;

  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }
  const { subject, postId, userId, reason, details } = parsed.data;

  const { data: reportId, error } = await auth.supabase.rpc("file_report", {
    p_subject: subject,
    p_post: subject === "post" ? (postId ?? null) : null,
    p_user: subject === "post" ? null : (userId ?? null),
    p_reason: reason,
    p_details: details && details !== "" ? details : null,
  });
  if (error) return rpcError(error);

  // Deliver the queued copy now; failures leave it queued for retry.
  try {
    await dispatchSafetyEmails();
  } catch {
    // The outbox row persists; the next dispatch retries.
  }

  return NextResponse.json({ ok: true, reportId });
}
