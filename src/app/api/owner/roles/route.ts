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
  role: z.enum(["admin", "moderator", "ts_reviewer"]),
});

/**
 * POST /api/owner/roles — grant or revoke a role. The endpoint only
 * resolves the handle; authority is enforced at the DATABASE: the
 * grant_role()/revoke_role() SECURITY DEFINER functions re-check Owner
 * + AAL2, a BEFORE trigger rejects non-Owner grants, and no app role —
 * service_role included — holds INSERT/UPDATE on role_assignments.
 * The owner role itself is never grantable, here or anywhere.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireUser();
  if ("response" in auth) return auth.response;

  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }
  const { action, handle, role } = parsed.data;

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
      ? await auth.supabase.rpc("grant_role", { p_target: target.user_id, p_role: role })
      : await auth.supabase.rpc("revoke_role", { p_target: target.user_id, p_role: role });
  if (error) return rpcError(error);
  return NextResponse.json({ ok: true });
}
