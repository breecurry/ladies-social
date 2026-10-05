import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { requireUser, rpcError } from "@/lib/api";

const reasonSchema = z.enum([
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
]);

const bodySchema = z.discriminatedUnion("action", [
  z.object({
    action: z.literal("remove"),
    target: z.string().uuid(),
    rule: reasonSchema,
    note: z.string().trim().max(2000).nullish(),
  }),
  z.object({
    action: z.literal("reinstate"),
    target: z.string().uuid(),
    note: z.string().trim().max(2000).nullish(),
  }),
]);

/**
 * POST /api/mod/avatar — remove or reinstate a member's profile photo
 * (spec 11). The endpoint only shapes the call; AUTHORITY IS ENFORCED
 * AT THE DATABASE: mod_remove_avatar re-checks the caller's tier, the
 * Owner/system/self protections and the Owner-only handling of
 * child-safety cases, PRESERVES the removed object as evidence (never
 * hard-deletes), notifies the member with the rule, and appends to the
 * hash-chained audit log. Reinstatement is the honest-mistake path.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireUser();
  if ("response" in auth) return auth.response;

  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }
  const input = parsed.data;

  const { error } =
    input.action === "remove"
      ? await auth.supabase.rpc("mod_remove_avatar", {
          p_target: input.target,
          p_rule: input.rule,
          p_note: input.note ?? null,
        })
      : await auth.supabase.rpc("mod_reinstate_avatar", {
          p_target: input.target,
          p_note: input.note ?? null,
        });
  if (error) return rpcError(error);
  return NextResponse.json({ ok: true });
}
