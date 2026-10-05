import type { NextResponse } from "next/server";
import { hashIdentifier } from "@/lib/crypto";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";

/**
 * Server-side half of the age gate (spec §17): the 14-day soft block
 * on a device that submitted an under-18 date of birth.
 *
 * The block is keyed to a hashed device fingerprint PLUS this cookie,
 * so clearing cookies alone does not defeat it — and a device with no
 * computable fingerprint is still covered by the cookie. The cookie
 * value is only the short reference code the blocked screen displays;
 * it identifies the block row, never the person. Nothing here stores
 * or transmits anything about who was turned away.
 */
export const AGE_GATE_COOKIE = "hs_age_gate";

const CODE_PATTERN = /^[2-9A-HJKMNP-Z]{4,8}$/;

export interface AgeGateBlock {
  referenceCode: string;
  expiresAt: string;
}

/** Normalise an untrusted cookie value to a plausible reference code. */
export function parseAgeGateCookie(value: string | undefined): string | null {
  if (!value) return null;
  const code = value.trim().toUpperCase();
  return CODE_PATTERN.test(code) ? code : null;
}

/** Hash the client-supplied fingerprint, or null when absent. */
export function fingerprintHashOf(deviceFingerprint: string): string | null {
  return deviceFingerprint ? hashIdentifier(deviceFingerprint) : null;
}

type Admin = ReturnType<typeof createSupabaseAdminClient>;

/**
 * Active block for this device, matched by fingerprint hash or by the
 * reference code carried in its cookie. Null when the device is clear.
 */
export async function getActiveAgeGateBlock(
  admin: Admin,
  fingerprintHash: string | null,
  cookieCode: string | null,
): Promise<AgeGateBlock | null> {
  if (!fingerprintHash && !cookieCode) return null;
  const { data } = await admin.rpc("get_age_gate_block", {
    p_fingerprint_hash: fingerprintHash,
    p_code: cookieCode,
  });
  const row = data?.[0];
  return row ? { referenceCode: row.reference_code, expiresAt: row.expires_at } : null;
}

/**
 * Record a 14-day block for this device. Idempotent per fingerprint:
 * a device that is already blocked keeps its existing code and expiry.
 */
export async function recordAgeGateBlock(
  admin: Admin,
  fingerprintHash: string | null,
): Promise<AgeGateBlock | null> {
  const { data, error } = await admin.rpc("record_age_gate_block", {
    p_fingerprint_hash: fingerprintHash,
  });
  if (error) return null;
  const row = data?.[0];
  return row ? { referenceCode: row.reference_code, expiresAt: row.expires_at } : null;
}

/** Attach the block cookie to a response, expiring with the block. */
export function setAgeGateCookie(response: NextResponse, block: AgeGateBlock): void {
  const maxAge = Math.max(
    0,
    Math.floor((new Date(block.expiresAt).getTime() - Date.now()) / 1000),
  );
  response.cookies.set(AGE_GATE_COOKIE, block.referenceCode, {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/",
    maxAge,
  });
}
