"use client";

import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";

export function LogoutButton() {
  const router = useRouter();
  const signOut = async () => {
    const supabase = createSupabaseBrowserClient();
    await supabase.auth.signOut();
    router.push("/");
    router.refresh();
  };
  return (
    <button
      onClick={signOut}
      className="min-h-11 rounded-md px-3 text-label text-text-secondary transition-colors duration-(--duration-fast) hover:bg-accent-subtle hover:text-accent"
    >
      Sign out
    </button>
  );
}
