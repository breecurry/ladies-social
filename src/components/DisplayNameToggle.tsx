"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Alert, Button } from "@/components/ui";

export function DisplayNameToggle({ showing }: { showing: boolean }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const toggle = async () => {
    setBusy(true);
    setError(null);
    const response = await fetch("/api/settings/display-name", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ show: !showing }),
    });
    const body = (await response.json()) as { ok: boolean; error?: string };
    if (body.ok) {
      router.refresh();
    } else {
      setError(body.error ?? "Could not update your setting.");
    }
    setBusy(false);
  };

  return (
    <div className="flex flex-col gap-3">
      {error ? <Alert tone="danger">{error}</Alert> : null}
      <Button variant={showing ? "secondary" : "primary"} disabled={busy} onClick={toggle}>
        {showing ? "Hide my legal name (show @handle only)" : "Show my legal name publicly"}
      </Button>
    </div>
  );
}
