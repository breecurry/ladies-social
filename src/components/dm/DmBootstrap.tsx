"use client";

import { useEffect, useRef } from "react";
import { ensureDevice } from "@/lib/dm/client";

/**
 * Makes sure this browser holds registered, current device keys the
 * moment a member enters any Messages surface, so she can receive
 * end-to-end encrypted messages. Renders nothing; failures are silent
 * here (the surfaces show their own honest errors on interaction).
 */
export function DmBootstrap() {
  const started = useRef(false);
  useEffect(() => {
    if (started.current) return;
    started.current = true;
    void ensureDevice().catch(() => {
      // Registration is retried on the next interaction that needs it.
    });
  }, []);
  return null;
}
