import { createHmac } from "node:crypto";
import { optionalEnv } from "@/lib/env";

/**
 * Keyed hash for ban-evasion identifiers (device fingerprints, emails,
 * phone numbers). HMAC with a server-side pepper so a leaked table of
 * hashes cannot be brute-forced offline against dictionaries of
 * emails/numbers. Raw identifiers are never stored in ban lists.
 *
 * Returned as `\x`-prefixed hex, the PostgREST wire format for bytea.
 */
export function hashIdentifier(value: string): string {
  const pepper = optionalEnv("IDENTIFIER_HASH_PEPPER") ?? "dev-only-pepper";
  const digest = createHmac("sha256", pepper).update(value.trim().toLowerCase()).digest("hex");
  return `\\x${digest}`;
}
