import { z } from "zod";

export const HANDLE_REGEX = /^[a-z0-9_]{3,30}$/;

/**
 * Handles reserved for the platform; unavailable regardless of state.
 * Mirrored in the database (reserved_handles table + trigger, migration
 * 0015) — this list gives the polite field-level signup error, the
 * database enforces the floor. Keep the two in sync.
 */
export const RESERVED_HANDLES = new Set([
  "herciety",
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

function isAtLeast18(dob: string): boolean {
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
    .regex(/^\d{4}-\d{2}-\d{2}$/, "Enter your date of birth.")
    .refine(isAtLeast18, "You must be 18 or older to join."),
  deviceFingerprint: z.string().trim().max(128).optional().default(""),
});

export type SignupInput = z.infer<typeof signupSchema>;
