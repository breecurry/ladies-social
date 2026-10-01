import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { requireUser, rpcError } from "@/lib/api";

const bodySchema = z.object({ show: z.boolean() });

/**
 * POST /api/settings/display-name — opt in or out of publicly showing
 * the verified legal name. The database trigger guarantees the public
 * display name can only ever be NULL or the verified legal name.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireUser();
  if ("response" in auth) return auth.response;

  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }

  const { error } = await auth.supabase.rpc("set_display_name_visibility", {
    p_show: parsed.data.show,
  });
  if (error) return rpcError(error);
  return NextResponse.json({ ok: true });
}
