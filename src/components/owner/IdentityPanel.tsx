"use client";

import { useState } from "react";
import Link from "next/link";
import { Lock } from "@phosphor-icons/react/dist/ssr";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { IdentityRevealRow } from "@/lib/database.types";
import { Alert } from "@/components/ui";

/**
 * The identity panel (Phase 2D spec §7): where the browsable surface
 * ends and the identity surface begins. Closed by default, visually
 * unlike everything else on the page, and opening it is an event, not
 * a view: Owner at AAL2, a mandatory stated reason, and an entry in
 * the hash-chained audit log — all enforced by the database function,
 * which writes the log BEFORE returning a byte. This component is
 * only ever the polite front of that gate, never the gate itself.
 *
 * The revealed data lives in local state, so leaving the member
 * detail re-collapses it; nothing is cached or left open.
 */
export function IdentityPanel({ userId, aal2 }: { userId: string; aal2: boolean }) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [identity, setIdentity] = useState<IdentityRevealRow | null>(null);

  const reveal = async () => {
    setBusy(true);
    setError(null);
    const supabase = createSupabaseBrowserClient();
    const { data, error: rpcError } = await supabase.rpc("owner_reveal_identity", {
      p_user: userId,
      p_reason: reason.trim(),
    });
    setBusy(false);
    const row = data?.[0];
    if (rpcError || !row) {
      setError("Could not reveal identity details. Step up to AAL2 and try again.");
      return;
    }
    setIdentity(row);
  };

  return (
    <section
      aria-label="Identity and contact details"
      className="rounded-lg border-2 border-border-strong bg-surface p-6 shadow-e1"
    >
      <div className="flex items-center gap-3">
        <Lock size={24} aria-hidden className="shrink-0 text-text-secondary" />
        <h2 className="text-heading text-text-primary">Identity and contact details</h2>
      </div>
      <p className="mt-2 max-w-prose text-body text-text-secondary">
        Seeing this member&apos;s legal name and contact details is a separate, recorded step. Open
        it only when you have a reason.
      </p>

      {identity ? (
        <div role="region" aria-live="polite" className="mt-4 flex flex-col gap-3">
          <dl className="flex flex-col gap-2 rounded-md bg-surface-raised p-4">
            <IdentityFact label="Legal name" value={identity.legal_name} />
            <IdentityFact label="Email" value={identity.email} />
            {identity.phone ? (
              <IdentityFact
                label="Phone"
                value={`${identity.phone}${identity.phone_verified_at ? " (verified)" : ""}`}
              />
            ) : null}
            {identity.signup_ip ? (
              <IdentityFact label="Signup IP" value={identity.signup_ip} />
            ) : null}
            {identity.last_login_ip ? (
              <IdentityFact label="Last login IP" value={identity.last_login_ip} />
            ) : null}
            {identity.last_login_at ? (
              <IdentityFact
                label="Last login"
                value={new Date(identity.last_login_at).toLocaleString("en-GB")}
              />
            ) : null}
            <IdentityFact
              label="Device signals"
              value={`${identity.device_signal_count} device signature${
                identity.device_signal_count === 1 ? "" : "s"
              } on record`}
            />
          </dl>
          <p className="text-caption text-text-tertiary">
            This access was recorded in the audit log with your stated reason.
          </p>
          <button
            type="button"
            onClick={() => {
              setIdentity(null);
              setOpen(false);
              setReason("");
            }}
            className="self-start rounded-md border border-border-strong px-4 py-2 text-label text-text-primary hover:bg-surface-raised"
          >
            Hide again
          </button>
        </div>
      ) : !open ? (
        <button
          type="button"
          onClick={() => setOpen(true)}
          className="mt-4 rounded-md border border-border-strong px-4 py-2 text-label text-text-primary hover:bg-surface-raised"
        >
          Reveal identity details
        </button>
      ) : !aal2 ? (
        <div className="mt-4">
          <Alert tone="warning">
            Seeing identity details requires your security key or authenticator.{" "}
            <Link className="underline" href="/settings/security">
              Step up first
            </Link>
            .
          </Alert>
        </div>
      ) : (
        <div className="mt-4 flex flex-col gap-3">
          <label htmlFor="identity-reason" className="text-label text-text-primary">
            Why are you accessing this? (recorded in the audit log)
          </label>
          <input
            id="identity-reason"
            type="text"
            value={reason}
            onChange={(event) => setReason(event.target.value)}
            placeholder='e.g. "responding to a law-enforcement request", "member asked me to confirm her account"'
            className="min-h-11 w-full rounded-md border border-border-strong bg-surface-raised px-3 text-body text-text-primary placeholder:text-text-tertiary focus-visible:outline-2 focus-visible:outline-focus-ring"
          />
          {error ? (
            <p role="alert" className="text-caption text-danger">
              {error}
            </p>
          ) : null}
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => {
                setOpen(false);
                setReason("");
                setError(null);
              }}
              className="min-h-11 rounded-md px-4 text-label text-accent hover:bg-accent-subtle"
            >
              Cancel
            </button>
            <button
              type="button"
              disabled={reason.trim().length < 3 || busy}
              onClick={() => void reveal()}
              className="min-h-11 rounded-md border border-border-strong bg-surface px-4 text-label text-text-primary hover:bg-surface-raised disabled:cursor-not-allowed disabled:opacity-50"
            >
              {busy ? "Revealing…" : "Reveal identity details"}
            </button>
          </div>
        </div>
      )}
    </section>
  );
}

function IdentityFact({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-wrap items-baseline gap-x-3">
      <dt className="w-32 shrink-0 text-caption text-text-tertiary">{label}</dt>
      <dd className="text-body text-text-primary">{value}</dd>
    </div>
  );
}
