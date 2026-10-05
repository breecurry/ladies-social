"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { stepUpWithPasskey } from "@/lib/passkeys";
import { Alert } from "@/components/ui";

/**
 * The in-place step-up offer shown when a sensitive Owner surface
 * finds the session without a fresh verification (neither AAL2 nor a
 * passkey used within the freshness window). Mirrors IdentityPanel:
 * "Confirm with your passkey" runs the shared ceremony — including the
 * switched-account refusal in stepUpWithPasskey — and refreshes the
 * page so the server re-reads the gate; the authenticator app remains
 * available alongside. The database enforces the real gate either way;
 * this component is only the polite front of it.
 */
export function PasskeyStepUpPrompt({ description }: { description: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const confirmWithPasskey = async () => {
    setBusy(true);
    setError(null);
    const supabase = createSupabaseBrowserClient();
    const result = await stepUpWithPasskey(supabase);
    setBusy(false);
    if (!result.ok) {
      // A dismissed prompt maps to null — a choice, not an error. A
      // switched account means someone else is now signed in; refresh
      // so the page re-renders as whoever that is.
      setError(result.message);
      if (result.switchedAccount) router.refresh();
      return;
    }
    router.refresh();
  };

  return (
    <div className="flex flex-col gap-3">
      <Alert tone="warning">{description}</Alert>
      {error ? (
        <p role="alert" className="text-caption text-danger">
          {error}
        </p>
      ) : null}
      <div className="flex flex-wrap items-center gap-3">
        <button
          type="button"
          disabled={busy}
          onClick={() => void confirmWithPasskey()}
          className="min-h-11 rounded-md border border-border-strong bg-surface px-4 text-label text-text-primary hover:bg-surface-raised disabled:cursor-not-allowed disabled:opacity-50"
        >
          {busy ? "Waiting for your passkey…" : "Confirm with your passkey"}
        </button>
        <Link
          className="text-label text-accent underline-offset-4 hover:underline"
          href="/settings/security"
        >
          Use your authenticator app instead
        </Link>
      </div>
    </div>
  );
}
