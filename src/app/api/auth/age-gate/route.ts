import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import {
  AGE_GATE_COOKIE,
  fingerprintHashOf,
  getActiveAgeGateBlock,
  parseAgeGateCookie,
  recordAgeGateBlock,
  setAgeGateCookie,
  type AgeGateBlock,
} from "@/lib/age-gate";

/**
 * POST /api/auth/age-gate — the device half of the age gate (spec §17).
 *
 *   action "check": is this device under an active block? Used by the
 *   signup form on mount so a device whose cookie was cleared still
 *   meets the blocked screen (matched by fingerprint hash).
 *
 *   action "block": the form determined the entered date of birth is
 *   under 18 and routed to the rejection screen. The ONLY thing the
 *   client sends on that path is the device fingerprint — never the
 *   date, never the email, never the name. The visitor may be a child;
 *   the platform keeps nothing about her (§17.4, the COPPA line). The
 *   block row is a hashed fingerprint, timestamps and a reference code.
 *
 * Both answers set the block cookie so the next visit to /signup
 * renders the blocked screen server-side.
 */

const bodySchema = z.object({
  action: z.enum(["check", "block"]),
  deviceFingerprint: z.string().trim().max(128).optional().default(""),
});

function getClientIp(request: NextRequest): string | null {
  const forwarded = request.headers.get("x-forwarded-for");
  if (forwarded) {
    const first = forwarded.split(",")[0]?.trim();
    if (first) return first;
  }
  return request.headers.get("x-real-ip");
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }
  const input = parsed.data;

  try {
    const admin = createSupabaseAdminClient();
    const fingerprintHash = fingerprintHashOf(input.deviceFingerprint);
    const cookieCode = parseAgeGateCookie(request.cookies.get(AGE_GATE_COOKIE)?.value);

    // Same per-IP budget as the signup form itself (recorded with no
    // email hash — this endpoint never sees one), so the block store
    // cannot be flooded from one network.
    const ip = getClientIp(request);
    await admin.rpc("record_signup_attempt", { p_ip: ip, p_email_hash: null });
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
        return NextResponse.json(
          { ok: false, error: "Too many attempts from this network. Try again later." },
          { status: 429 },
        );
      }
    }

    let block: AgeGateBlock | null = null;
    if (input.action === "block") {
      block = await recordAgeGateBlock(admin, fingerprintHash);
    } else {
      block = await getActiveAgeGateBlock(admin, fingerprintHash, cookieCode);
    }

    const response = NextResponse.json(
      block ? { ok: true, blocked: true, code: block.referenceCode } : { ok: true, blocked: false },
      { status: 200 },
    );
    if (block) setAgeGateCookie(response, block);
    return response;
  } catch {
    return NextResponse.json(
      { ok: false, error: "Something went wrong. Please try again." },
      { status: 500 },
    );
  }
}
