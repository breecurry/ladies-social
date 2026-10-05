"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";

/**
 * Marks every notification read once the list is on screen, then
 * refreshes so the shell's unread badge clears.
 */
export function MarkAllRead({ hasUnread }: { hasUnread: boolean }) {
  const router = useRouter();
  const done = useRef(false);

  useEffect(() => {
    if (!hasUnread || done.current) return;
    done.current = true;
    const supabase = createSupabaseBrowserClient();
    void supabase.rpc("notif_mark_all_read").then(() => router.refresh());
  }, [hasUnread, router]);

  return null;
}
