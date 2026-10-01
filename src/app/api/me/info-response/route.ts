import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { requireUser, rpcError } from "@/lib/api";

const bodySchema = z.object({ text: z.string().trim().min(1).max(2000) });

/**
 * POST /api/me/info-response — the applicant's reply to a reviewer's
 * request for more information; returns the application to the queue.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireUser();
  if ("response" in auth) return auth.response;

  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json(
      { ok: false, error: "Reply must be between 1 and 2000 characters." },
      { status: 400 },
    );
  }

  const { error } = await auth.supabase.rpc("submit_info_response", { p_text: parsed.data.text });
  if (error) return rpcError(error);
  return NextResponse.json({ ok: true });
}
