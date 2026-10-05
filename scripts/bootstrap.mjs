/**
 * One-time setup: creates the Owner account and the "Herciety" system
 * account against a Supabase project with the Phase 1 migrations
 * applied. Idempotence is enforced in the database — bootstrap_owner()
 * and create_system_account() refuse to run twice.
 *
 * Usage (all values via environment, nothing on the command line):
 *   NEXT_PUBLIC_SUPABASE_URL=... \
 *   SUPABASE_SERVICE_ROLE_KEY=... \
 *   OWNER_EMAIL=... OWNER_PASSWORD=... OWNER_HANDLE=... \
 *   OWNER_LEGAL_NAME="..." OWNER_DOB=YYYY-MM-DD [OWNER_PHONE=+1...] \
 *   node scripts/bootstrap.mjs
 *
 * AFTER RUNNING: sign in as the Owner and enroll MFA (Settings →
 * Security) immediately. Privileged actions refuse to run at AAL1, and
 * the Owner account must never rely on email-only recovery.
 */
import { createClient } from "@supabase/supabase-js";

function env(name, fallback) {
  const value = process.env[name] ?? fallback;
  if (value === undefined) {
    console.error(`Missing required environment variable: ${name}`);
    process.exit(1);
  }
  return value;
}

const supabase = createClient(env("NEXT_PUBLIC_SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { autoRefreshToken: false, persistSession: false },
});

async function createAuthUser(email, password) {
  const { data, error } = await supabase.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (error) {
    console.error(`Could not create auth user for ${email}: ${error.message}`);
    process.exit(1);
  }
  return data.user.id;
}

const ownerId = await createAuthUser(env("OWNER_EMAIL"), env("OWNER_PASSWORD"));
const { error: ownerError } = await supabase.rpc("bootstrap_owner", {
  p_user: ownerId,
  p_handle: env("OWNER_HANDLE"),
  p_legal_name: env("OWNER_LEGAL_NAME"),
  p_dob: env("OWNER_DOB"),
  p_email: env("OWNER_EMAIL"),
  p_phone: env("OWNER_PHONE", ""),
});
if (ownerError) {
  console.error(`bootstrap_owner failed: ${ownerError.message}`);
  process.exit(1);
}
console.warn("Owner account bootstrapped.");

// System account: random unguessable password; it is never logged into.
// The address stays on unitedfeminist.com — the company domain owns all
// email (Resend DKIM is verified there, not on herciety.com).
const systemPassword = crypto.randomUUID() + crypto.randomUUID();
const systemId = await createAuthUser(
  env("SYSTEM_EMAIL", "system@unitedfeminist.com"),
  systemPassword,
);
const { error: systemError } = await supabase.rpc("create_system_account", {
  p_user: systemId,
  p_handle: "herciety",
});
if (systemError) {
  console.error(`create_system_account failed: ${systemError.message}`);
  process.exit(1);
}
console.warn("System account created.");
console.warn("NEXT STEP: sign in as the Owner and enroll MFA before granting any role.");
