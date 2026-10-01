"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Alert, Button } from "@/components/ui";

export function VouchActions({ requestId }: { requestId: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const act = async (verb: "confirm" | "decline") => {
    setBusy(true);
    setError(null);
    const response = await fetch(`/api/vouches/${requestId}/${verb}`, { method: "POST" });
    const body = (await response.json()) as { ok: boolean; error?: string };
    if (body.ok) {
      router.refresh();
    } else {
      setError(body.error ?? "Something went wrong.");
      setBusy(false);
    }
  };

  return (
    <div className="flex flex-col gap-3">
      {error ? <Alert tone="danger">{error}</Alert> : null}
      <div className="flex flex-wrap gap-3">
        <Button disabled={busy} onClick={() => act("confirm")}>
          I know her — I vouch for her
        </Button>
        <Button variant="secondary" disabled={busy} onClick={() => act("decline")}>
          Decline
        </Button>
      </div>
    </div>
  );
}
