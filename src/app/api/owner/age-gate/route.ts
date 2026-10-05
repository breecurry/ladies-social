import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { requireUser, rpcError } from "@/lib/api";

const bodySchema = z.object({
  action: z.enum(["lookup", "clear"]),
  code: z
    .string()
    .trim()
    .toUpperCase()
    .regex(/^[2-9A-HJKMNP-Z]{4,8}$/, "That does not look like a reference code."),
});

/**
 * POST /api/owner/age-gate — support unlock for the age-gate device
 * block (spec §17.3). Pull, not push: the Owner consults this only
 * when someone emails support and quotes the code from her blocked
 * screen. Authority is enforced at the DATABASE: both functions
 * re-check the Owner inside SECURITY DEFINER, and no app role can
 * touch age_gate_blocks directly. The unlock is friction relief, not
 * a security boundary — clearing a block only lets a device type a
 * date again. There is nothing personal to show: a block is a code,
 * a created-at and an expiry.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireUser();
  if ("response" in auth) return auth.response;

  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }
  const { action, code } = parsed.data;

  if (action === "lookup") {
    const { data, error } = await auth.supabase.rpc("lookup_age_gate_block", { p_code: code });
    if (error) return rpcError(error);
    const row = data?.[0];
    return NextResponse.json({
      ok: true,
      block: row
        ? { code: row.reference_code, createdAt: row.created_at, expiresAt: row.expires_at }
        : null,
    });
  }

  const { data: cleared, error } = await auth.supabase.rpc("clear_age_gate_block", {
    p_code: code,
  });
  if (error) return rpcError(error);
  return NextResponse.json({ ok: true, cleared: cleared ?? false });
}
