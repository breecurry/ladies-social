"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Alert, Button, Textarea } from "@/components/ui";

/**
 * Reviewer decision buttons. Only rendered for Owner/Admin (the
 * database re-checks authority regardless). Every action is written to
 * the audit log by the SECURITY DEFINER functions.
 */
export function ReviewActions({ applicationId }: { applicationId: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [mode, setMode] = useState<"none" | "reject" | "request_info">("none");
  const [text, setText] = useState("");

  const act = async (payload: Record<string, string>) => {
    setBusy(true);
    setError(null);
    const response = await fetch(`/api/review/${applicationId}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
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

      {mode === "none" ? (
        <div className="flex flex-wrap gap-3">
          <Button disabled={busy} onClick={() => act({ action: "approve" })}>
            Approve
          </Button>
          <Button variant="secondary" disabled={busy} onClick={() => setMode("request_info")}>
            Request more info
          </Button>
          <Button variant="danger" disabled={busy} onClick={() => setMode("reject")}>
            Reject
          </Button>
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          <label htmlFor={`note-${applicationId}`} className="text-label">
            {mode === "reject" ? "Reason (kept internally)" : "What do you need from her?"}
          </label>
          <Textarea
            id={`note-${applicationId}`}
            rows={3}
            maxLength={2000}
            value={text}
            onChange={(e) => setText(e.target.value)}
          />
          <div className="flex flex-wrap gap-3">
            <Button
              variant={mode === "reject" ? "danger" : "primary"}
              disabled={busy || (mode === "request_info" && text.trim() === "")}
              onClick={() =>
                act(
                  mode === "reject"
                    ? { action: "reject", note: text }
                    : { action: "request_info", message: text },
                )
              }
            >
              {mode === "reject" ? "Confirm rejection" : "Send request"}
            </Button>
            <Button variant="ghost" disabled={busy} onClick={() => setMode("none")}>
              Cancel
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
