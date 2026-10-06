import { createHmac } from "node:crypto";
import { requireEnv } from "@/lib/env";

/**
 * Keyed hash for ban-evasion identifiers (device fingerprints, emails,
 * phone numbers). HMAC with a server-side pepper so a leaked table of
 * hashes cannot be brute-forced offline against dictionaries of
 * emails/numbers. Raw identifiers are never stored in ban lists.
 *
 * The pepper is REQUIRED, with no fallback: this repository is public,
 * so any default value is a known key, and a deployment that silently
 * used one would let anyone compute identifier hashes offline and test
 * them against `identifier_is_banned` — defeating ban evasion
 * protection outright. A missing variable fails the request loudly
 * instead.
 *
 * Returned as `\x`-prefixed hex, the PostgREST wire format for bytea.
 */
export function hashIdentifier(value: string): string {
  const pepper = requireEnv("IDENTIFIER_HASH_PEPPER");
  const digest = createHmac("sha256", pepper).update(value.trim().toLowerCase()).digest("hex");
  return `\\x${digest}`;
}
