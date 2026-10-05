import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { requireEnv } from "@/lib/env";
import { hashIdentifier } from "@/lib/crypto";
import { padToUniformTime } from "@/lib/timing";
import { runSignupTriage } from "@/lib/signup/triage";
import { signupSchema, isAtLeast18, RESERVED_HANDLES } from "@/lib/validation";
import {
  AGE_GATE_COOKIE,
  getActiveAgeGateBlock,
  parseAgeGateCookie,
  recordAgeGateBlock,
  setAgeGateCookie,
  type AgeGateBlock,
} from "@/lib/age-gate";
import type { Database } from "@/lib/database.types";

/**
 * POST /api/auth/signup — open registration behind the age gate.
 *
 * Everyone 18+ is welcome; enforcement is conduct-based and happens
 * after the fact. What this endpoint still defends:
 *
 *   THE AGE GATE (spec §17): an under-18 date of birth is REJECTED,
 *   not recorded — the response routes the client to the rejection
 *   screen, and the device receives a 14-day soft block (hashed
 *   fingerprint + cookie). A blocked device meets the blocked screen
 *   instead of a working form. Nothing about the person is kept: the
 *   block row is a fingerprint hash, timestamps and a reference code.
 *
 *   BAN EVASION: a signup whose email or device-fingerprint hash
 *   matches a banned account is answered with the EXACT same response
 *   as a successful signup, and nothing is created. The banned person
 *   never learns she was detected. Every post-validation response is
 *   padded to a uniform floor (lib/timing.ts) so the refusal is not
 *   measurable from latency either.
 *
 *   BOTS: the pre-filter (disposable email domains, subnet velocity,
 *   profile-coherence heuristics) auto-flags suspicious accounts; the
 *   flags land on the private record and in the audit log. Flags never
 *   block a signup on their own.
 *
 * Email verification is required: Supabase sends the confirmation and
 * the account cannot sign in until it is confirmed.
 */

const SUCCESS_MESSAGE = "Account created. Check your email to confirm your address.";

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

  const uniform = async (
    body: Record<string, unknown>,
    status: number,
    block?: AgeGateBlock | null,
  ) => {
    await padToUniformTime(startedAt);
    const response = NextResponse.json(body, { status });
    if (block) setAgeGateCookie(response, block);
    return response;
  };

  try {
    const admin = createSupabaseAdminClient();
    const ip = getClientIp(request);
    const emailHash = hashIdentifier(input.email);
    const fingerprintHash = input.deviceFingerprint
      ? hashIdentifier(input.deviceFingerprint)
      : null;

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

    // --- The age gate (spec §17) ---
    // A device under an active 14-day block meets the blocked screen,
    // not a working form: matched by fingerprint hash or by the cookie
    // the failing visit set, so clearing cookies alone does not help.
    const cookieCode = parseAgeGateCookie(request.cookies.get(AGE_GATE_COOKIE)?.value);
    const activeBlock = await getActiveAgeGateBlock(admin, fingerprintHash, cookieCode);
    if (activeBlock) {
      return uniform(
        { ok: false, blocked: true, code: activeBlock.referenceCode },
        403,
        activeBlock,
      );
    }

    // An under-18 date of birth REJECTS (it is never silently stored)
    // and soft-blocks the device for 14 days. The response carries no
    // reference code — the rejection screen shows none (§17.2); the
    // code appears only if the device returns (§17.3). Deliberately
    // nothing else about the visitor is recorded, on this branch or
    // anywhere downstream of it.
    if (!isAtLeast18(input.dob)) {
      const block = await recordAgeGateBlock(admin, fingerprintHash);
      return uniform({ ok: false, underage: true }, 403, block);
    }

    // Handle availability. This necessarily reveals whether a HANDLE is
    // taken (any platform with unique handles does); the per-IP rate
    // limit above bounds its use for bulk probing.
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

    // --- Ban evasion + bot signals (never appearance or gender) ---
    const [subnetResult, fpBanned, emailBanned] = await Promise.all([
      ip
        ? admin.rpc("count_signups_from_subnet", { p_ip: ip })
        : Promise.resolve({ data: 0 } as const),
      fingerprintHash
        ? admin.rpc("identifier_is_banned", { p_kind: "device_hash", p_hash: fingerprintHash })
        : Promise.resolve({ data: false } as const),
      admin.rpc("identifier_is_banned", { p_kind: "email_hash", p_hash: emailHash }),
    ]);

    if ((fpBanned.data ?? false) || (emailBanned.data ?? false)) {
      // Banned-account match: create nothing, answer exactly like
      // success. The signup attempt above is already recorded.
      return uniform({ ok: true, message: SUCCESS_MESSAGE }, 200);
    }

    const triage = runSignupTriage({
      email: input.email,
      legalName: input.legalName,
      handle: input.handle,
      subnetSignups24h: (subnetResult.data ?? 1) - 1, // exclude this attempt
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
    // shell): respond EXACTLY like success. No profile is created.
    const user = signUpData.user;
    if (!user || (user.identities ?? []).length === 0) {
      return uniform({ ok: true, message: SUCCESS_MESSAGE }, 200);
    }

    const { error: memberError } = await admin.rpc("create_member", {
      p_user_id: user.id,
      p_email: input.email,
      p_legal_name: input.legalName,
      p_dob: input.dob,
      p_handle: input.handle,
      p_signup_ip: ip,
      p_email_hash: emailHash,
      p_fingerprint_hash: fingerprintHash,
      p_signals: triage.signals,
      p_flagged: triage.flagged,
    });
    if (memberError) {
      // Roll back the orphan auth user so the email can retry cleanly.
      await admin.auth.admin.deleteUser(user.id).catch(() => undefined);
      // Belt-and-braces ban check inside create_member: same silent
      // success shape as the pre-check above.
      if (memberError.message.includes("banned_identifier")) {
        return uniform({ ok: true, message: SUCCESS_MESSAGE }, 200);
      }
      // Handle race on the unique index — same shape as the pre-check.
      if (memberError.code === "23505") {
        return uniform({ ok: false, error: "That handle isn't available.", field: "handle" }, 409);
      }
      return uniform({ ok: false, error: "Could not create your account. Please try again." }, 500);
    }

    return uniform({ ok: true, message: SUCCESS_MESSAGE }, 200);
  } catch {
    return uniform({ ok: false, error: "Something went wrong. Please try again." }, 500);
  }
}
