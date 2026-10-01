import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { requireUser, rpcError } from "@/lib/api";

const actionSchema = z.discriminatedUnion("action", [
  z.object({ action: z.literal("approve"), note: z.string().max(2000).optional() }),
  z.object({ action: z.literal("reject"), note: z.string().max(2000).optional() }),
  z.object({ action: z.literal("request_info"), message: z.string().min(1).max(2000) }),
]);

/**
 * POST /api/review/[id] — reviewer decisions: approve / reject /
 * request more info. Authority (Owner or Admin) is enforced inside the
 * SECURITY DEFINER functions, and every action lands in the audit log.
 */
export async function POST(
  request: NextRequest,
  context: { params: Promise<{ id: string }> },
): Promise<NextResponse> {
  const auth = await requireUser();
  if ("response" in auth) return auth.response;
  const { id } = await context.params;

  const parsed = actionSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid action." }, { status: 400 });
  }
  const body = parsed.data;

  const { error } =
    body.action === "approve"
      ? await auth.supabase.rpc("review_approve", { p_app: id, p_note: body.note ?? null })
      : body.action === "reject"
        ? await auth.supabase.rpc("review_reject", { p_app: id, p_note: body.note ?? null })
        : await auth.supabase.rpc("review_request_info", { p_app: id, p_message: body.message });

  if (error) return rpcError(error);
  return NextResponse.json({ ok: true });
}
