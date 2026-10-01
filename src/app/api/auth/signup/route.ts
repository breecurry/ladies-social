import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { requireEnv } from "@/lib/env";
import { hashIdentifier } from "@/lib/crypto";
import { padToUniformTime } from "@/lib/timing";
import { lookupPhone } from "@/lib/admission/phone";
import { runTriage } from "@/lib/admission/triage";
import { signupSchema, RESERVED_HANDLES } from "@/lib/validation";
import type { Database } from "@/lib/database.types";

/**
 * POST /api/auth/signup — the two-lane admission gate.
 *
 * ENUMERATION SAFETY (hard requirement): the "Who invited you?" handle
 * is resolved inside create_application(); whether or not it matches a
 * member, this endpoint returns THE SAME response body and THE SAME
 * status code, and every post-validation response is padded to a
 * uniform floor (see lib/timing.ts) so response time does not leak
 * membership either. A vouch request is only created server-side,
 * invisible to the applicant.
 */

const SUCCESS_BASE = "Application received. Check your email to confirm your address.";
const SUCCESS_INVITER_SUFFIX = " If that member exists, they've been notified.";

function getClientIp(request: NextRequest): string | null {
  const forwarded = request.headers.get("x-forwarded-for");
  if (forwarded) {
    const first = forwarded.split(",")[0]?.trim();
    if (first) return first;
  }
  return request.headers.get("x-real-ip");
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  const startedAt = Date.now();

  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }

  const parsed = signupSchema.safeParse(raw);
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    return NextResponse.json(
      {
        ok: false,
        error: issue?.message ?? "Please check the form and try again.",
        field: issue?.path[0] ?? null,
      },
      { status: 400 },
    );
  }
  const input = parsed.data;

  const uniform = async (body: Record<string, unknown>, status: number) => {
    await padToUniformTime(startedAt);
    return NextResponse.json(body, { status });
  };

  const successMessage = SUCCESS_BASE + (input.inviterHandle !== "" ? SUCCESS_INVITER_SUFFIX : "");

  try {
    const admin = createSupabaseAdminClient();
    const ip = getClientIp(request);
    const emailHash = hashIdentifier(input.email);

    // Per-IP rate limit: makes bulk probing of the signup form (for
    // handles OR emails) expensive. Recorded before counting so the
    // current attempt is included.
    await admin.rpc("record_signup_attempt", { p_ip: ip, p_email_hash: emailHash });
    if (ip) {
      const { data: attemptCount } = await admin.rpc("count_signup_attempts_from_ip", {
        p_ip: ip,
      });
      const { data: capRow } = await admin
        .from("app_config")
        .select("value")
        .eq("key", "signup_attempts_per_ip_per_day")
        .maybeSingle();
      const cap = typeof capRow?.value === "number" ? capRow.value : 10;
      if ((attemptCount ?? 0) > cap) {
        return uniform(
          { ok: false, error: "Too many signup attempts from this network. Try again later." },
          429,
        );
      }
    }

    // Handle availability. This necessarily reveals whether a HANDLE is
    // taken (any platform with unique handles does); the per-IP rate
    // limit above bounds its use for bulk probing, and profiles are not
    // otherwise visible pre-admission.
    if (RESERVED_HANDLES.has(input.handle)) {
      return uniform({ ok: false, error: "That handle isn't available.", field: "handle" }, 409);
    }
    const { data: existingHandle } = await admin
      .from("profiles")
      .select("user_id")
      .eq("handle", input.handle)
      .maybeSingle();
    if (existingHandle) {
      return uniform({ ok: false, error: "That handle isn't available.", field: "handle" }, 409);
    }

    // --- Triage signals (bot/abuse only — never appearance or gender) ---
    const [phoneSignal, subnetResult, fpBanned, emailBanned, phoneBanned] = await Promise.all([
      lookupPhone(input.phone),
      ip
        ? admin.rpc("count_signups_from_subnet", { p_ip: ip })
        : Promise.resolve({ data: 0 } as const),
      input.deviceFingerprint
        ? admin.rpc("identifier_is_banned", {
            p_kind: "device_hash",
            p_hash: hashIdentifier(input.deviceFingerprint),
          })
        : Promise.resolve({ data: false } as const),
      admin.rpc("identifier_is_banned", { p_kind: "email_hash", p_hash: emailHash }),
      admin.rpc("identifier_is_banned", {
        p_kind: "phone_hash",
        p_hash: hashIdentifier(input.phone),
      }),
    ]);

    const triage = runTriage({
      email: input.email,
      legalName: input.legalName,
      handle: input.handle,
      phone: phoneSignal,
      subnetSignups24h: (subnetResult.data ?? 1) - 1, // exclude this attempt
      fingerprintBanned: fpBanned.data ?? false,
      emailBanned: emailBanned.data ?? false,
      phoneBanned: phoneBanned.data ?? false,
    });

    // --- Create the auth user (email confirmation flows from Supabase) ---
    const anonAuth = createClient<Database>(
      requireEnv("NEXT_PUBLIC_SUPABASE_URL"),
      requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY"),
      { auth: { autoRefreshToken: false, persistSession: false } },
    );
    const { data: signUpData, error: signUpError } = await anonAuth.auth.signUp({
      email: input.email,
      password: input.password,
      options: { emailRedirectTo: `${request.nextUrl.origin}/login` },
    });
    if (signUpError) {
      return uniform({ ok: false, error: "Could not create your account. Please try again." }, 400);
    }
    // Existing account (Supabase anti-enumeration returns a userless
    // shell): respond EXACTLY like success. No application is created.
    const user = signUpData.user;
    if (!user || (user.identities ?? []).length === 0) {
      return uniform({ ok: true, message: successMessage }, 200);
    }

    const { error: appError } = await admin.rpc("create_application", {
      p_user_id: user.id,
      p_email: input.email,
      p_legal_name: input.legalName,
      p_dob: input.dob,
      p_handle: input.handle,
      p_phone: input.phone,
      p_inviter_handle: input.inviterHandle === "" ? null : input.inviterHandle,
      p_signup_ip: ip,
      p_fingerprint_hash: input.deviceFingerprint ? hashIdentifier(input.deviceFingerprint) : null,
      p_signals: triage.signals,
      p_bucket: triage.bucket,
    });
    if (appError) {
      // Roll back the orphan auth user so the email can retry cleanly.
      await admin.auth.admin.deleteUser(user.id).catch(() => undefined);
      // Handle race on the unique index — same shape as the pre-check.
      if (appError.code === "23505") {
        return uniform({ ok: false, error: "That handle isn't available.", field: "handle" }, 409);
      }
      return uniform({ ok: false, error: "Could not create your account. Please try again." }, 500);
    }

    return uniform({ ok: true, message: successMessage }, 200);
  } catch {
    return uniform({ ok: false, error: "Something went wrong. Please try again." }, 500);
  }
}
