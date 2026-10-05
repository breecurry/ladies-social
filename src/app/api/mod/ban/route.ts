import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { requireUser, rpcError } from "@/lib/api";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { hashIdentifier } from "@/lib/crypto";
import { HANDLE_REGEX } from "@/lib/validation";

const bodySchema = z.object({
  target: z.string().uuid(),
  rule: z.enum([
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
  note: z.string().trim().min(1).max(2000),
  /** The typed confirmation: must be the exact @handle of the account. */
  confirmHandle: z
    .string()
    .trim()
    .toLowerCase()
    .transform((v) => v.replace(/^@/, ""))
    .refine((v) => HANDLE_REGEX.test(v), "Invalid handle."),
  banEmail: z.boolean(),
  banPhone: z.boolean(),
  banDevice: z.boolean(),
});

/**
 * GET /api/mod/ban?target=<uuid> — which ban-evasion signal CATEGORIES
 * exist for this account (booleans only, never values), so the ban
 * dialog can show de-identified toggles. Admin/Owner only.
 */
export async function GET(request: NextRequest): Promise<NextResponse> {
  const auth = await requireUser();
  if ("response" in auth) return auth.response;

  const target = request.nextUrl.searchParams.get("target") ?? "";
  if (!z.string().uuid().safeParse(target).success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }

  // Role check via the caller's own (RLS-scoped) role assignments.
  const { data: roles } = await auth.supabase
    .from("role_assignments")
    .select("role")
    .eq("user_id", auth.user.id)
    .is("revoked_at", null);
  const isAdminOrOwner = (roles ?? []).some((r) => r.role === "admin" || r.role === "owner");
  if (!isAdminOrOwner) {
    return NextResponse.json({ ok: false, error: "Not permitted." }, { status: 403 });
  }

  const admin = createSupabaseAdminClient();
  const { data: priv } = await admin
    .from("user_private")
    .select("email, phone_e164, device_fingerprint_hash")
    .eq("user_id", target)
    .maybeSingle();

  return NextResponse.json({
    ok: true,
    signals: {
      email: Boolean(priv?.email),
      phone: Boolean(priv?.phone_e164),
      device: Boolean(priv?.device_fingerprint_hash),
    },
  });
}

/**
 * POST /api/mod/ban — permanent ban, the one unrecoverable console
 * action. ADMIN AND OWNER ONLY, enforced inside mod_ban() at the
 * database (which also refuses the Owner and the system account).
 *
 * The typed-@handle gate is re-checked HERE, server-side, so no client
 * bug can submit a ban without the handle having been reproduced.
 *
 * Ban evasion: the chosen identifier signals are written to
 * banned_identifiers as HMAC hashes only. The raw email and phone are
 * read server-side via the service client and hashed with the server
 * pepper IN THIS PROCESS — they never reach the admin's browser, the
 * console, the database function's audit entry, or this response. The
 * device fingerprint is already stored hashed and is read inside
 * mod_ban() itself.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireUser();
  if ("response" in auth) return auth.response;

  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }
  const { target, rule, note, confirmHandle, banEmail, banPhone, banDevice } = parsed.data;

  // The typed gate, verified against the real handle server-side.
  const { data: profile } = await auth.supabase
    .from("profiles")
    .select("handle")
    .eq("user_id", target)
    .maybeSingle();
  if (!profile) {
    return NextResponse.json({ ok: false, error: "That account is unavailable." }, { status: 404 });
  }
  if (profile.handle.toLowerCase() !== confirmHandle) {
    return NextResponse.json(
      { ok: false, error: "The typed handle does not match the account being banned." },
      { status: 400 },
    );
  }

  // Hash the chosen identifiers server-side. Raw values stay in this
  // process and are never logged, returned, or shown.
  let emailHash: string | null = null;
  let phoneHash: string | null = null;
  if (banEmail || banPhone) {
    const admin = createSupabaseAdminClient();
    const { data: priv } = await admin
      .from("user_private")
      .select("email, phone_e164")
      .eq("user_id", target)
      .maybeSingle();
    if (banEmail && priv?.email) emailHash = hashIdentifier(priv.email);
    if (banPhone && priv?.phone_e164) phoneHash = hashIdentifier(priv.phone_e164);
  }

  const { error } = await auth.supabase.rpc("mod_ban", {
    p_target: target,
    p_rule: rule,
    p_note: note,
    p_email_hash: emailHash,
    p_phone_hash: phoneHash,
    p_ban_device: banDevice,
  });
  if (error) return rpcError(error);
  return NextResponse.json({ ok: true });
}
