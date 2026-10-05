"use client";

import { useEffect } from "react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";

const HEARTBEAT_MS = 60_000;

/**
 * The session heartbeat (migration 0023): while a signed-in member has
 * the app visible, one cheap RPC a minute records that her session is
 * alive. The server derives sessions, time-on-site, and presence from
 * these beats. Renders nothing; failures are ignored (analytics must
 * never get in a member's way).
 */
export function SessionHeartbeat() {
  useEffect(() => {
    const supabase = createSupabaseBrowserClient();
    let stopped = false;

    const beat = () => {
      if (stopped || document.visibilityState !== "visible") return;
      void supabase.rpc("session_heartbeat").then(
        () => undefined,
        () => undefined,
      );
    };

    beat();
    const interval = window.setInterval(beat, HEARTBEAT_MS);
    const onVisibility = () => {
      if (document.visibilityState === "visible") beat();
    };
    document.addEventListener("visibilitychange", onVisibility);

    return () => {
      stopped = true;
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, []);

  return null;
}
