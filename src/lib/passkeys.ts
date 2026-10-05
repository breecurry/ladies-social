import type { AMREntry } from "@supabase/supabase-js";

/**
 * Shared passkey plumbing: plain-language error copy for the WebAuthn
 * ceremonies and the freshness rule for the Owner's sensitive-action
 * gate. The database is the real gate (the SECURITY DEFINER functions
 * re-derive all of this from the JWT); everything here only decides
 * what the interface shows.
 */

/** How recently a passkey sign-in must have happened to count as a
 *  fresh confirmation for sensitive actions. Mirrors the server-side
 *  window in `owner_sensitive_auth_method()` — change both together. */
export const PASSKEY_FRESHNESS_SECONDS = 5 * 60;

export type SensitiveAuthMethod = "aal2" | "passkey";

/**
 * Which method, if any, currently satisfies the sensitive-action gate:
 * AAL2 (an authenticator-app step-up), or a passkey authentication
 * fresh within {@link PASSKEY_FRESHNESS_SECONDS}.
 *
 * `amr` entries are OBJECTS of shape `{ method, timestamp }` — never
 * match on the array containing the string "passkey". The timestamp is
 * the authentication time in epoch seconds and survives token
 * refreshes, which is what makes the freshness check meaningful.
 */
export function sensitiveAuthMethod(
  currentLevel: string | null | undefined,
  methods: AMREntry[] | string[] | null | undefined,
  nowMs: number = Date.now(),
): SensitiveAuthMethod | null {
  if (currentLevel === "aal2") return "aal2";
  for (const entry of methods ?? []) {
    if (typeof entry === "string") continue; // RFC-8176 string form carries no timestamp
    if (entry.method !== "passkey") continue;
    if (nowMs / 1000 - entry.timestamp <= PASSKEY_FRESHNESS_SECONDS) return "passkey";
  }
  return null;
}

/**
 * True when the person closed or dismissed the browser's passkey
 * prompt. That is a choice, not a failure — show nothing for it.
 * The SDK wraps an `AbortError` as code `ERROR_CEREMONY_ABORTED` and
 * passes `NotAllowedError` (the cancel/timeout bucket) through with
 * the original error as `cause`.
 */
export function passkeyPromptDismissed(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  if (error.name === "AbortError" || error.name === "NotAllowedError") return true;
  const code = (error as { code?: unknown }).code;
  if (code === "ERROR_CEREMONY_ABORTED") return true;
  if (code === "ERROR_PASSTHROUGH_SEE_CAUSE_PROPERTY") {
    const cause = (error as { cause?: unknown }).cause;
    return cause instanceof Error && cause.name === "NotAllowedError";
  }
  return false;
}

export type PasskeyErrorContext = "register" | "manage" | "signin";

/**
 * Plain-language copy for a failed passkey operation, or `null` when
 * the person simply dismissed the prompt and nothing should be shown.
 * Never names a vendor.
 */
export function passkeyErrorMessage(error: unknown, context: PasskeyErrorContext): string | null {
  if (passkeyPromptDismissed(error)) return null;
  const code = error instanceof Error ? (error as { code?: unknown }).code : undefined;
  switch (code) {
    case "webauthn_credential_exists":
    case "ERROR_AUTHENTICATOR_PREVIOUSLY_REGISTERED":
      return "This device already has a passkey for your account.";
    case "webauthn_challenge_expired":
      return "That took too long — try again.";
    case "webauthn_verification_failed":
      return context === "signin"
        ? "That passkey couldn't be verified. Try again, or sign in with your password."
        : "That passkey couldn't be verified. Try again.";
    case "too_many_passkeys":
      return "You've reached the limit on passkeys for your account. Remove one you no longer use, then try again.";
    case "passkey_disabled":
      return "Passkeys aren't available right now. You can use an authenticator app instead.";
    case "insufficient_aal":
      return "Because your account has two-step verification, managing passkeys needs a stepped-up session. Verify with your authenticator app first, then try again.";
    case "email_not_confirmed":
      return "Confirm your email address first, then sign in.";
    case "phone_not_confirmed":
      return "Confirm your phone number first, then sign in.";
    case "user_banned":
      return "This account can't sign in right now.";
    default:
      return context === "signin"
        ? "Couldn't sign you in with a passkey. Try again, or use your password."
        : "Something went wrong with that passkey. Try again.";
  }
}
