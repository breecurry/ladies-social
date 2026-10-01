"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { Alert, Button, Textarea } from "@/components/ui";

export function InfoResponseForm() {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    const form = new FormData(event.currentTarget);
    const response = await fetch("/api/me/info-response", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: String(form.get("text") ?? "") }),
    });
    const body = (await response.json()) as { ok: boolean; error?: string };
    if (body.ok) {
      router.refresh();
    } else {
      setError(body.error ?? "Could not send your reply.");
      setSubmitting(false);
    }
  };

  return (
    <form onSubmit={onSubmit} className="flex flex-col gap-3">
      {error ? <Alert tone="danger">{error}</Alert> : null}
      <label htmlFor="text" className="text-label">
        Your reply
      </label>
      <Textarea id="text" name="text" rows={4} maxLength={2000} required />
      <Button type="submit" disabled={submitting}>
        {submitting ? "Sending…" : "Send reply"}
      </Button>
    </form>
  );
}
