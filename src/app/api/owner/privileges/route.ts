import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { requireUser, rpcError } from "@/lib/api";
import { HANDLE_REGEX } from "@/lib/validation";

const bodySchema = z.object({
  action: z.enum(["grant", "revoke"]),
  handle: z
    .string()
    .trim()
    .toLowerCase()
    .transform((v) => v.replace(/^@/, ""))
    .refine((v) => HANDLE_REGEX.test(v), "Invalid handle."),
  privilege: z.enum(["auto_admit"]),
});

/**
 * POST /api/owner/privileges — grant or revoke auto_admit. Same
 * database-layer enforcement as roles: Owner-only, AAL2, trigger +
 * REVOKEd table privileges. The vouch statistics on the owner page
 * INFORM this decision; nothing grants automatically.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireUser();
  if ("response" in auth) return auth.response;

  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }
  const { action, handle, privilege } = parsed.data;

  const { data: target } = await auth.supabase
    .from("profiles")
    .select("user_id")
    .eq("handle", handle)
    .maybeSingle();
  if (!target) {
    return NextResponse.json({ ok: false, error: "No member with that handle." }, { status: 404 });
  }

  const { error } =
    action === "grant"
      ? await auth.supabase.rpc("grant_privilege", {
          p_target: target.user_id,
          p_privilege: privilege,
        })
      : await auth.supabase.rpc("revoke_privilege", {
          p_target: target.user_id,
          p_privilege: privilege,
        });
  if (error) return rpcError(error);
  return NextResponse.json({ ok: true });
}
