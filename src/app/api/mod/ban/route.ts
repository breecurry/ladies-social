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

/** The success branch of requireUser(): a signed-in caller and her RLS-scoped client. */
type AuthedCaller = Exclude<Awaited<ReturnType<typeof requireUser>>, { response: NextResponse }>;

/**
 * Staff gate shared by GET and POST: admin or owner, read from the
 * caller's OWN role_assignments rows through her user-scoped client
 * (self-rows are always readable, so no RLS surprise is possible
 * here). mod_ban() re-enforces the same tier at the database —
 * mod_assert_actionable(p_target, 2) admits exactly admin (2) and
 * owner (3) — this check exists so that NO privileged read below ever
 * runs for a non-staff caller.
 */
async function callerIsAdminOrOwner(auth: AuthedCaller): Promise<boolean> {
  const { data: roles } = await auth.supabase
    .from("role_assignments")
    .select("role")
    .eq("user_id", auth.user.id)
    .is("revoked_at", null);
  return (roles ?? []).some((r) => r.role === "admin" || r.role === "owner");
}

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

  if (!(await callerIsAdminOrOwner(auth))) {
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
 * action. ADMIN AND OWNER ONLY: checked HERE first (so the privileged
 * handle lookup below never runs for a non-staff caller) and enforced
 * again inside mod_ban() at the database (which also refuses the Owner
 * and the system account).
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

  // Authority FIRST, before any privileged read below. Without this,
  // any authenticated member could use the typed-handle gate as an
  // oracle to confirm user_id→handle mappings — including for banned
  // and suspended accounts that profiles_read deliberately hides.
  if (!(await callerIsAdminOrOwner(auth))) {
    return NextResponse.json({ ok: false, error: "Not permitted." }, { status: 403 });
  }

  // The typed gate, verified against the real handle server-side. This
  // read must NOT go through the caller's RLS: profiles_read honours
  // internal.blocked_by (and, since 20261023000001, hides enforced
  // accounts from ordinary readers), so a target who had blocked the
  // acting admin would vanish from a user-scoped read and her ban
  // could never be confirmed by that admin. The service client is safe
  // here only because the admin/owner check above has already passed.
  const admin = createSupabaseAdminClient();
  const { data: profile } = await admin
    .from("profiles")
    .select("handle")
    .eq("user_id", target)
    // profiles_read shows a 'deleted' row to NOBODY, staff included.
    // The service client bypasses RLS, so re-impose that one branch:
    // a deleted account stays exactly as unavailable as it was before.
    .neq("status", "deleted")
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
