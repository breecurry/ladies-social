import { z } from "zod";

export const HANDLE_REGEX = /^[a-z0-9_]{3,30}$/;

/**
 * Handles reserved for the platform; unavailable regardless of state.
 * Mirrored in the database (reserved_handles table + trigger, migrations
 * 0015/0016) — this list gives the polite field-level signup error, the
 * database enforces the floor. Keep the two in sync.
 * "herciety" (no S) is a misspelling of the brand and stays reserved
 * permanently as an impersonation guard.
 */
export const RESERVED_HANDLES = new Set([
  "hersciety",
  "herciety",
  "her_society",
  "unitedfeminist",
  "united_feminist",
  "admin",
  "administrator",
  "moderator",
  "support",
  "help",
  "safety",
  "legal",
  "appeals",
  "official",
  "system",
  "owner",
  "staff",
]);

/**
 * True when the ISO date is a real calendar date (no 2026-02-30) in a
 * plausible range (1900 onward, not in the future).
 */
export function isRealBirthDate(dob: string): boolean {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dob);
  if (!match) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (year < 1900 || month < 1 || month > 12 || day < 1 || day > 31) return false;
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return false;
  }
  return date.getTime() <= Date.now();
}

/**
 * Compose Month/Day/Year field values into an ISO date, or null when
 * they do not form a real birth date. Shared by the three-field date
 * group on the signup form and anything else that gathers parts.
 */
export function composeBirthDate(month: string, day: string, year: string): string | null {
  const m = month.trim();
  const d = day.trim();
  const y = year.trim();
  if (!/^\d{1,2}$/.test(m) || !/^\d{1,2}$/.test(d) || !/^\d{4}$/.test(y)) return null;
  const iso = `${y}-${m.padStart(2, "0")}-${d.padStart(2, "0")}`;
  return isRealBirthDate(iso) ? iso : null;
}

/**
 * The 18+ gate check. Deliberately NOT part of signupSchema: an
 * under-18 date is a VALID submission that routes to the rejection
 * screen and records a device block (spec §17.1-17.3) — it is not a
 * field-level form error.
 */
export function isAtLeast18(dob: string): boolean {
  const birth = new Date(`${dob}T00:00:00Z`);
  if (Number.isNaN(birth.getTime())) return false;
  const cutoff = new Date();
  cutoff.setUTCFullYear(cutoff.getUTCFullYear() - 18);
  return birth.getTime() <= cutoff.getTime();
}

export const signupSchema = z.object({
  email: z
    .string()
    .trim()
    .toLowerCase()
    .pipe(z.email("Enter a valid email address."))
    .refine((v) => v.length <= 254, "Email is too long."),
  password: z
    .string()
    .min(10, "Password must be at least 10 characters.")
    .max(128, "Password is too long."),
  legalName: z.string().trim().min(1, "Your legal name is required.").max(100, "Name is too long."),
  handle: z
    .string()
    .trim()
    .toLowerCase()
    .regex(
      HANDLE_REGEX,
      "Handles are 3-30 characters: lowercase letters, numbers and underscores.",
    ),
  dob: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "Enter your full date of birth.")
    .refine(isRealBirthDate, "Enter your full date of birth."),
  ageAttested: z.literal(true, "Please confirm that you are 18 or older."),
  // A separate, independently required agreement — deliberately not
  // bundled with the 18+ attestation. The literal(true) means a signup
  // POSTed straight to the API without it (or with false) is rejected
  // server-side, whatever the client did.
  tosAgreed: z.literal(true, "Please agree to the Terms of Service to create an account."),
  deviceFingerprint: z.string().trim().max(128).optional().default(""),
  // Cloudflare Turnstile token (absent until the widget solves, and in
  // environments without a site key). Supabase verifies it when captcha
  // is enabled in auth config; until then it is passed through and
  // ignored, so this field must never be required here.
  captchaToken: z.string().trim().max(2048).optional().default(""),
});

export type SignupInput = z.infer<typeof signupSchema>;
