"use client";

import { useState, type FormEvent } from "react";
import { Alert, Button, Input } from "@/components/ui";

interface LookupResponse {
  ok: boolean;
  error?: string;
  block?: { code: string; createdAt: string; expiresAt: string } | null;
}

interface ClearResponse {
  ok: boolean;
  error?: string;
  cleared?: boolean;
}

const CODE_PATTERN = /^[2-9A-HJKMNP-Z]{4,8}$/;

function formatDate(value: string): string {
  return new Date(value).toLocaleString(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  });
}

/**
 * Support unlock for the age gate. Someone emails support and quotes
 * the reference code from her blocked screen; the code is looked up
 * and that one device block is cleared. There is nothing personal to
 * display — a block is a code, a created-at and an expiry, by design.
 */
export function AgeGateSupport() {
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [block, setBlock] = useState<LookupResponse["block"]>(null);
  const [searched, setSearched] = useState<string | null>(null);

  const post = async (body: Record<string, string>) => {
    const response = await fetch("/api/owner/age-gate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    return response.json();
  };

  const onLookup = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setError(null);
    setNotice(null);
    setBlock(null);
    setSearched(null);
    const normalized = code.trim().toUpperCase();
    if (!CODE_PATTERN.test(normalized)) {
      setError("Reference codes are 4-8 letters and numbers, like 4F2A.");
      return;
    }
    setBusy(true);
    try {
      const body = (await post({ action: "lookup", code: normalized })) as LookupResponse;
      if (!body.ok) {
        setError(body.error ?? "Could not look that up. Try again.");
      } else {
        setBlock(body.block ?? null);
        setSearched(normalized);
      }
    } catch {
      setError("Could not look that up. Try again.");
    } finally {
      setBusy(false);
    }
  };

  const onClear = async () => {
    if (!searched) return;
    setBusy(true);
    setError(null);
    try {
      const body = (await post({ action: "clear", code: searched })) as ClearResponse;
      if (body.ok && body.cleared) {
        setNotice(`Block ${searched} cleared. That device can try the signup form again.`);
        setBlock(null);
      } else {
        setError(body.error ?? "Could not clear that block. Try again.");
      }
    } catch {
      setError("Could not clear that block. Try again.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="flex flex-col gap-4">
      <form onSubmit={onLookup} className="flex flex-col gap-3 sm:flex-row sm:items-end">
        <div className="flex flex-1 flex-col gap-1.5">
          <label htmlFor="age-gate-code" className="text-label text-text-primary">
            Reference code
          </label>
          <Input
            id="age-gate-code"
            value={code}
            onChange={(e) => setCode(e.target.value.toUpperCase())}
            placeholder="4F2A"
            maxLength={8}
            autoComplete="off"
          />
        </div>
        <Button type="submit" variant="secondary" disabled={busy}>
          Look up
        </Button>
      </form>

      {error ? <Alert tone="danger">{error}</Alert> : null}
      {notice ? <Alert tone="success">{notice}</Alert> : null}

      {searched && !block && !notice && !error ? (
        <p className="text-body text-text-secondary">
          No block found for {searched}. It may have expired (blocks clear themselves after 14 days)
          or already been cleared.
        </p>
      ) : null}

      {block ? (
        <div className="flex flex-col gap-3 rounded-md border border-border px-4 py-3">
          <p className="text-body text-text-primary">
            Block <span className="font-semibold">{block.code}</span>
          </p>
          <p className="text-caption text-text-tertiary">
            Created {formatDate(block.createdAt)} · expires {formatDate(block.expiresAt)}
          </p>
          <div>
            <Button type="button" onClick={() => void onClear()} disabled={busy}>
              Clear this block
            </Button>
          </div>
        </div>
      ) : null}
    </div>
  );
}
