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

const target = { target: z.string().uuid(), postId: z.number().int().positive().nullish() };
const note = z.string().trim().max(2000).nullish();

const bodySchema = z.discriminatedUnion("action", [
  z.object({ action: z.literal("claim"), ...target }),
  z.object({ action: z.literal("dismiss"), ...target, note }),
  z.object({ action: z.literal("reopen"), ...target }),
  z.object({
    action: z.literal("warn"),
    ...target,
    rule: reasonSchema,
    message: z.string().trim().min(1).max(1000),
    removeContent: z.boolean().optional(),
    note,
  }),
  z.object({
    action: z.literal("remove_post"),
    postId: z.number().int().positive(),
    rule: reasonSchema,
    note,
  }),
  z.object({ action: z.literal("restore_post"), postId: z.number().int().positive(), note }),
  z.object({
    action: z.literal("restrict"),
    ...target,
    days: z.number().int().min(1).max(30),
    rule: reasonSchema,
    note,
  }),
  z.object({
    action: z.literal("suspend"),
    ...target,
    days: z.number().int().min(1).max(30),
    rule: reasonSchema,
    note,
  }),
  z.object({ action: z.literal("lift"), ...target, note }),
  z.object({ action: z.literal("escalate"), ...target, note }),
  z.object({ action: z.literal("unban"), ...target, note }),
]);

/**
 * POST /api/mod/action — the enforcement ladder, minus Ban (which has
 * its own route and its own gate). The endpoint only shapes the call;
 * AUTHORITY IS ENFORCED AT THE DATABASE: every mod_* function
 * re-checks the caller's role, the 7-day moderator boundary, the
 * 30-day ceiling, the Owner/system/self protections, and the
 * Owner-only handling of child-safety cases, and every action appends
 * to the hash-chained audit log. Ban is deliberately absent here.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireUser();
  if ("response" in auth) return auth.response;

  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }
  const input = parsed.data;
  const { supabase } = auth;

  const { error } = await (() => {
    switch (input.action) {
      case "claim":
        return supabase.rpc("mod_claim", { p_target: input.target, p_post: input.postId ?? null });
      case "dismiss":
        return supabase.rpc("mod_dismiss", {
          p_target: input.target,
          p_post: input.postId ?? null,
          p_note: input.note ?? null,
        });
      case "reopen":
        return supabase.rpc("mod_reopen", { p_target: input.target, p_post: input.postId ?? null });
      case "warn":
        return supabase.rpc("mod_warn", {
          p_target: input.target,
          p_rule: input.rule,
          p_message: input.message,
          p_post: input.postId ?? null,
          p_remove: input.removeContent ?? false,
          p_note: input.note ?? null,
        });
      case "remove_post":
        return supabase.rpc("mod_remove_post", {
          p_post: input.postId,
          p_rule: input.rule,
          p_note: input.note ?? null,
        });
      case "restore_post":
        return supabase.rpc("mod_restore_post", {
          p_post: input.postId,
          p_note: input.note ?? null,
        });
      case "restrict":
        return supabase.rpc("mod_restrict", {
          p_target: input.target,
          p_days: input.days,
          p_rule: input.rule,
          p_note: input.note ?? null,
        });
      case "suspend":
        return supabase.rpc("mod_suspend", {
          p_target: input.target,
          p_days: input.days,
          p_rule: input.rule,
          p_note: input.note ?? null,
        });
      case "lift":
        return supabase.rpc("mod_lift", { p_target: input.target, p_note: input.note ?? null });
      case "escalate":
        return supabase.rpc("mod_escalate", {
          p_target: input.target,
          p_post: input.postId ?? null,
          p_note: input.note ?? null,
        });
      case "unban":
        return supabase.rpc("owner_unban", { p_target: input.target, p_note: input.note ?? null });
    }
  })();
  if (error) return rpcError(error);
  return NextResponse.json({ ok: true });
}
