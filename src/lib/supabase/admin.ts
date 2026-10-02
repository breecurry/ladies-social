import { createClient } from "@supabase/supabase-js";
import { requireEnv } from "@/lib/env";
import type { Database } from "@/lib/database.types";

/**
 * Service-role client — server only, never importable from client code
 * (the key read throws in the browser bundle because the variable is
 * not NEXT_PUBLIC). Note what this key can and cannot do: it bypasses
 * RLS for reads, but the security-critical tables (role_assignments,
 * audit_log, user_private) have had their write privileges REVOKEd
 * from service_role at the database, so even code holding this key
 * mutates them only through the SECURITY DEFINER functions.
 */
export function createSupabaseAdminClient() {
  return createClient<Database>(
    requireEnv("NEXT_PUBLIC_SUPABASE_URL"),
    requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
}
