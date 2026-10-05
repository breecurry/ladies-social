"use client";

import { createBrowserClient } from "@supabase/ssr";
import type { Database } from "@/lib/database.types";

export function createSupabaseBrowserClient() {
  return createBrowserClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "",
    {
      auth: {
        // Passkey support (registerPasskey, signInWithPasskey, passkey.*)
        // is a beta surface that historically required this opt-in. The
        // currently installed SDK enables it by default and keeps the flag
        // for compatibility; it stays here so the capability survives SDK
        // version drift within ^2.x.
        experimental: { passkey: true },
      },
    },
  );
}
