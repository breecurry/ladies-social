import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { requireUser, rpcError } from "@/lib/api";

const bodySchema = z.object({
  target: z.string().uuid(),
  postId: z.number().int().positive().nullish(),
});

/**
 * POST /api/mod/reporters — reveal who reported a case. Revealing
 * reporters is an intentional act, separate from reading the case, and
 * mod_view_reporters() writes an audit entry for every reveal: the
 * power to see who reports whom is itself a logged power. The response
 * also carries each reporter's 24-hour filing count, the report-abuse
 * tell. The accused is never told who reported — this surface is
 * staff-only and reporter identity never leaves it.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireUser();
  if ("response" in auth) return auth.response;

  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }

  const { data, error } = await auth.supabase.rpc("mod_view_reporters", {
    p_target: parsed.data.target,
    p_post: parsed.data.postId ?? null,
  });
  if (error) return rpcError(error);
  return NextResponse.json({ ok: true, reporters: data ?? [] });
}
