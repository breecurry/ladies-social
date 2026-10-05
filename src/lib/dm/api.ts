import { NextResponse } from "next/server";
import { requireUser } from "@/lib/api";
import { dmEnvEnabled } from "@/lib/dm/flag";
import type { User } from "@supabase/supabase-js";
import type { createSupabaseServerClient } from "@/lib/supabase/server";

type ServerSupabase = Awaited<ReturnType<typeof createSupabaseServerClient>>;

/**
 * Gate for every /api/dm/* route: while the DM feature flag is off,
 * the routes do not exist (404, the same as any unknown path) — the
 * surfaces are unreachable, not degraded. The database enforces the
 * same flag inside every DM function, so this is belt and braces.
 */
export async function requireDm(): Promise<
  { supabase: ServerSupabase; user: User } | { response: NextResponse }
> {
  if (!dmEnvEnabled()) {
    return {
      response: NextResponse.json({ ok: false, error: "Not found." }, { status: 404 }),
    };
  }
  return requireUser();
}

/** A bytea wire value from the client: "\x" + hex. */
export function isBytea(value: unknown, bytes?: number): value is string {
  if (typeof value !== "string" || !/^\\x[0-9a-fA-F]+$/.test(value)) return false;
  if ((value.length - 2) % 2 !== 0) return false;
  return bytes === undefined || value.length - 2 === bytes * 2;
}
