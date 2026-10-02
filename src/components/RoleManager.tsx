"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { Alert, Button, Field, Input } from "@/components/ui";

/**
 * Owner-only forms for role management. The browser is the least
 * trusted layer here: the database trigger + SECURITY DEFINER
 * functions enforce Owner + AAL2 regardless of what this form submits.
 */
export function RoleManager() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const submit = async (payload: Record<string, string>) => {
    setBusy(true);
    setError(null);
    setNotice(null);
    const response = await fetch("/api/owner/roles", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const body = (await response.json()) as { ok: boolean; error?: string };
    if (body.ok) {
      setNotice("Done.");
      router.refresh();
    } else {
      setError(body.error ?? "Something went wrong.");
    }
    setBusy(false);
  };

  const onRoleSubmit = (action: "grant" | "revoke") => (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void submit({
      action,
      handle: String(form.get("handle") ?? ""),
      role: String(form.get("role") ?? ""),
    });
  };

  const selectClass =
    "min-h-11 w-full rounded-md border border-border-strong bg-surface-raised px-3 text-body text-text-primary";

  return (
    <div className="flex flex-col gap-4">
      {error ? <Alert tone="danger">{error}</Alert> : null}
      {notice ? <Alert tone="success">{notice}</Alert> : null}

      <form onSubmit={onRoleSubmit("grant")} className="flex flex-col gap-3">
        <h3 className="text-heading">Grant a role</h3>
        <Field label="Member handle" htmlFor="grant-handle">
          <Input id="grant-handle" name="handle" placeholder="@handle" required />
        </Field>
        <Field label="Role" htmlFor="grant-role">
          <select id="grant-role" name="role" className={selectClass} defaultValue="moderator">
            <option value="admin">Admin</option>
            <option value="moderator">Moderator</option>
            <option value="ts_reviewer">T&amp;S Reviewer (read-only)</option>
          </select>
        </Field>
        <Button type="submit" disabled={busy}>
          Grant role
        </Button>
      </form>

      <form onSubmit={onRoleSubmit("revoke")} className="flex flex-col gap-3">
        <h3 className="text-heading">Revoke a role</h3>
        <Field label="Member handle" htmlFor="revoke-handle">
          <Input id="revoke-handle" name="handle" placeholder="@handle" required />
        </Field>
        <Field label="Role" htmlFor="revoke-role">
          <select id="revoke-role" name="role" className={selectClass} defaultValue="moderator">
            <option value="admin">Admin</option>
            <option value="moderator">Moderator</option>
            <option value="ts_reviewer">T&amp;S Reviewer</option>
          </select>
        </Field>
        <Button type="submit" variant="danger" disabled={busy}>
          Revoke role (kills her sessions)
        </Button>
      </form>
    </div>
  );
}
