import { NextResponse } from "next/server";
import type { PostgrestError } from "@supabase/supabase-js";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { User } from "@supabase/supabase-js";

type ServerSupabase = Awaited<ReturnType<typeof createSupabaseServerClient>>;

export async function requireUser(): Promise<
  { supabase: ServerSupabase; user: User } | { response: NextResponse }
> {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return { response: NextResponse.json({ ok: false, error: "Not signed in." }, { status: 401 }) };
  }
  return { supabase, user };
}

/**
 * Map a database exception raised by a SECURITY DEFINER function to a
 * clean JSON error. The raised messages are deliberately user-safe.
 */
export function rpcError(error: PostgrestError): NextResponse {
  const denied = error.message.includes("Only the Owner") || error.code === "42501";
  const stepUp = error.message.includes("Re-authentication");
  return NextResponse.json(
    { ok: false, error: error.message },
    { status: stepUp ? 403 : denied ? 403 : 400 },
  );
}
