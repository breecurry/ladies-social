"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { PasskeyListItem } from "@supabase/supabase-js";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { passkeyErrorMessage } from "@/lib/passkeys";
import { Alert, Badge, Button, Card, Field, Input } from "@/components/ui";
import { ConfirmDialog } from "@/components/ConfirmDialog";

interface FactorInfo {
  id: string;
  type: string;
  name: string;
  verified: boolean;
}

/**
 * Sign-in and verification management: passkeys (passwordless sign-in,
 * which also acts as a fresh confirmation for the Owner's sensitive
 * actions) plus TOTP authenticator apps as the second factor behind
 * AAL2. The Owner's sensitive operations — role changes, unbans, the
 * audit log, contact details, the identity reveal — accept AAL2 OR a
 * fresh passkey confirmation, so either path enrolled here works.
 */
export function SecurityPanel() {
  const router = useRouter();
  const [aal, setAal] = useState<string | null>(null);
  const [factors, setFactors] = useState<FactorInfo[]>([]);
  const [passkeys, setPasskeys] = useState<PasskeyListItem[]>([]);
  const [passkeyListNote, setPasskeyListNote] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [totpEnroll, setTotpEnroll] = useState<{ factorId: string; qr: string } | null>(null);
  const [totpCode, setTotpCode] = useState("");
  const [renaming, setRenaming] = useState<{ id: string; name: string } | null>(null);
  const [removing, setRemoving] = useState<PasskeyListItem | null>(null);

  const refresh = useCallback(async () => {
    const supabase = createSupabaseBrowserClient();
    const [{ data: aalData }, { data: factorData }, passkeyList] = await Promise.all([
      supabase.auth.mfa.getAuthenticatorAssuranceLevel(),
      supabase.auth.mfa.listFactors(),
      supabase.auth.passkey.list(),
    ]);
    return {
      aal: aalData?.currentLevel ?? null,
      factors: (factorData?.all ?? []).map((f) => ({
        id: f.id,
        type: f.factor_type,
        name: f.friendly_name ?? f.factor_type,
        verified: f.status === "verified",
      })),
      passkeys: passkeyList.data ?? [],
      passkeyListNote: passkeyList.error
        ? passkeyErrorMessage(passkeyList.error, "manage")
        : null,
    };
  }, []);

  const applyRefresh = useCallback(async () => {
    const state = await refresh();
    setAal(state.aal);
    setFactors(state.factors);
    setPasskeys(state.passkeys);
    setPasskeyListNote(state.passkeyListNote);
  }, [refresh]);

  useEffect(() => {
    let active = true;
    void refresh().then((state) => {
      if (!active) return;
      setAal(state.aal);
      setFactors(state.factors);
      setPasskeys(state.passkeys);
      setPasskeyListNote(state.passkeyListNote);
    });
    return () => {
      active = false;
    };
  }, [refresh]);

  const addPasskey = async () => {
    setBusy(true);
    setError(null);
    setNotice(null);
    const supabase = createSupabaseBrowserClient();
    const { error: registerError } = await supabase.auth.registerPasskey();
    if (registerError) {
      // A dismissed prompt maps to null — a choice, not an error.
      setError(passkeyErrorMessage(registerError, "register"));
    } else {
      setNotice("Passkey added. You can now sign in with it.");
      await applyRefresh();
      router.refresh();
    }
    setBusy(false);
  };

  const renamePasskey = async () => {
    if (!renaming || renaming.name.trim().length === 0) return;
    setBusy(true);
    setError(null);
    setNotice(null);
    const supabase = createSupabaseBrowserClient();
    const { error: updateError } = await supabase.auth.passkey.update({
      passkeyId: renaming.id,
      friendlyName: renaming.name.trim().slice(0, 120),
    });
    if (updateError) {
      setError(passkeyErrorMessage(updateError, "manage"));
    } else {
      setRenaming(null);
      await applyRefresh();
    }
    setBusy(false);
  };

  // Removing the last passkey while no verified second factor exists
  // would make the privileged-action gate (AAL2 or a fresh passkey
  // confirmation) permanently unreachable — role changes, unbans, the
  // audit log, and identity reveals would all be locked until a
  // re-enrolment. Refuse that one removal, calmly.
  const removalWouldStrand = passkeys.length <= 1 && !factors.some((f) => f.verified);
  const strandMessage =
    "This is your only passkey, and no other verified sign-in check is enrolled. " +
    "Removing it would leave you with no way to confirm it's you for protected actions. " +
    "Add a replacement passkey first, then remove this one.";

  const requestRemovePasskey = (passkey: PasskeyListItem) => {
    setError(null);
    setNotice(null);
    if (removalWouldStrand) {
      setError(strandMessage);
      return;
    }
    setRemoving(passkey);
  };

  const removePasskey = async () => {
    if (!removing) return;
    if (removalWouldStrand) {
      setError(strandMessage);
      setRemoving(null);
      return;
    }
    setBusy(true);
    setError(null);
    setNotice(null);
    const supabase = createSupabaseBrowserClient();
    const { error: deleteError } = await supabase.auth.passkey.delete({
      passkeyId: removing.id,
    });
    if (deleteError) {
      setError(passkeyErrorMessage(deleteError, "manage"));
    } else {
      setNotice("Passkey removed.");
      await applyRefresh();
    }
    setRemoving(null);
    setBusy(false);
  };

  const startTotpEnroll = async () => {
    setBusy(true);
    setError(null);
    setNotice(null);
    const supabase = createSupabaseBrowserClient();
    const { data, error: enrollError } = await supabase.auth.mfa.enroll({ factorType: "totp" });
    if (enrollError || !data) {
      setError(enrollError?.message ?? "Could not start enrollment.");
    } else {
      setTotpEnroll({ factorId: data.id, qr: data.totp.qr_code });
    }
    setBusy(false);
  };

  const verifyTotpEnroll = async () => {
    if (!totpEnroll) return;
    setBusy(true);
    setError(null);
    const supabase = createSupabaseBrowserClient();
    const { error: verifyError } = await supabase.auth.mfa.challengeAndVerify({
      factorId: totpEnroll.factorId,
      code: totpCode.trim(),
    });
    if (verifyError) {
      setError("That code didn't verify. Check your authenticator app and try again.");
    } else {
      setNotice("Authenticator app enrolled. You are now at AAL2.");
      setTotpEnroll(null);
      setTotpCode("");
      await applyRefresh();
      router.refresh();
    }
    setBusy(false);
  };

  const stepUp = async (factor: FactorInfo) => {
    setBusy(true);
    setError(null);
    setNotice(null);
    const supabase = createSupabaseBrowserClient();
    const code = window.prompt("Enter the 6-digit code from your authenticator app:") ?? "";
    if (!code) {
      setBusy(false);
      return;
    }
    const { error: verifyError } = await supabase.auth.mfa.challengeAndVerify({
      factorId: factor.id,
      code: code.trim(),
    });
    if (verifyError) setError("That code didn't verify.");
    else setNotice("Stepped up to AAL2.");
    await applyRefresh();
    router.refresh();
    setBusy(false);
  };

  return (
    <div className="flex flex-col gap-6">
      {error ? <Alert tone="danger">{error}</Alert> : null}
      {notice ? <Alert tone="success">{notice}</Alert> : null}

      <Card className="flex flex-col gap-3">
        <div className="flex items-center justify-between gap-3">
          <h2 className="text-heading">Current assurance level</h2>
          <Badge tone={aal === "aal2" ? "success" : "warning"}>{aal ?? "…"}</Badge>
        </div>
        <p className="text-body text-text-secondary">
          Privileged actions (granting roles, reading the audit log, viewing contact details)
          need a fresh check that it&apos;s you: a second factor verified in this session, or a
          passkey confirmation made in the moment.
        </p>
      </Card>

      <Card className="flex flex-col gap-4">
        <h2 className="text-heading">Passkeys</h2>
        <p className="text-body text-text-secondary">
          Sign in without a password using Face ID, Touch ID, Windows Hello, or a security key.
          Each passkey stays on the device or password manager that created it.
        </p>
        {passkeyListNote ? <Alert tone="warning">{passkeyListNote}</Alert> : null}
        {passkeys.length === 0 ? (
          <p className="text-body text-text-secondary">No passkeys yet.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {passkeys.map((passkey) => (
              <li
                key={passkey.id}
                className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-border px-3 py-2"
              >
                {renaming?.id === passkey.id ? (
                  <span className="flex flex-1 flex-wrap items-center gap-2">
                    <label htmlFor={`rename-${passkey.id}`} className="sr-only">
                      New passkey name
                    </label>
                    <Input
                      id={`rename-${passkey.id}`}
                      value={renaming.name}
                      maxLength={120}
                      className="max-w-56"
                      onChange={(e) => setRenaming({ id: passkey.id, name: e.target.value })}
                    />
                    <Button
                      variant="ghost"
                      disabled={busy || renaming.name.trim().length === 0}
                      onClick={() => void renamePasskey()}
                    >
                      Save
                    </Button>
                    <Button variant="ghost" disabled={busy} onClick={() => setRenaming(null)}>
                      Cancel
                    </Button>
                  </span>
                ) : (
                  <>
                    <span className="flex min-w-0 flex-col">
                      <span className="text-body">{passkey.friendly_name || "Passkey"}</span>
                      <span className="text-caption text-text-tertiary">
                        Added {new Date(passkey.created_at).toLocaleDateString("en-GB")}
                        {passkey.last_used_at
                          ? ` · last used ${new Date(passkey.last_used_at).toLocaleDateString("en-GB")}`
                          : ""}
                      </span>
                    </span>
                    <span className="flex items-center gap-2">
                      <Button
                        variant="ghost"
                        disabled={busy}
                        onClick={() =>
                          setRenaming({ id: passkey.id, name: passkey.friendly_name ?? "" })
                        }
                      >
                        Rename
                      </Button>
                      <Button
                        variant="ghost"
                        disabled={busy}
                        onClick={() => requestRemovePasskey(passkey)}
                      >
                        Remove
                      </Button>
                    </span>
                  </>
                )}
              </li>
            ))}
          </ul>
        )}
        <div>
          <Button disabled={busy} onClick={() => void addPasskey()}>
            Add a passkey
          </Button>
        </div>
      </Card>

      <Card className="flex flex-col gap-4">
        <h2 className="text-heading">Your second factors</h2>
        {factors.length === 0 ? (
          <p className="text-body text-text-secondary">No second factor enrolled yet.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {factors.map((factor) => (
              <li
                key={factor.id}
                className="flex items-center justify-between gap-3 rounded-md border border-border px-3 py-2"
              >
                <span className="text-body">
                  {factor.name}{" "}
                  <span className="text-caption text-text-tertiary">({factor.type})</span>
                </span>
                <span className="flex items-center gap-2">
                  <Badge tone={factor.verified ? "success" : "warning"}>
                    {factor.verified ? "verified" : "unverified"}
                  </Badge>
                  {factor.verified && factor.type === "totp" && aal !== "aal2" ? (
                    <Button variant="ghost" disabled={busy} onClick={() => stepUp(factor)}>
                      Step up
                    </Button>
                  ) : null}
                </span>
              </li>
            ))}
          </ul>
        )}
        <div className="flex flex-wrap gap-3">
          <Button variant="secondary" disabled={busy} onClick={startTotpEnroll}>
            Add an authenticator app
          </Button>
        </div>
        {totpEnroll ? (
          <div className="flex flex-col gap-3 rounded-md border border-border p-4">
            <p className="text-body text-text-secondary">
              Scan this QR code with your authenticator app, then enter the 6-digit code.
            </p>
            {/* eslint-disable-next-line @next/next/no-img-element -- SVG data URI from the auth service */}
            <img src={totpEnroll.qr} alt="TOTP enrollment QR code" width={176} height={176} />
            <Field label="6-digit code" htmlFor="totp-code">
              <Input
                id="totp-code"
                inputMode="numeric"
                autoComplete="one-time-code"
                value={totpCode}
                onChange={(e) => setTotpCode(e.target.value)}
                maxLength={6}
              />
            </Field>
            <Button disabled={busy || totpCode.trim().length !== 6} onClick={verifyTotpEnroll}>
              Verify and enable
            </Button>
          </div>
        ) : null}
      </Card>

      <ConfirmDialog
        open={removing !== null}
        title="Remove this passkey?"
        body={`"${removing?.friendly_name || "This passkey"}" will no longer work for signing in. The entry on your device or password manager stays there until you delete it yourself.`}
        confirmLabel="Remove passkey"
        busy={busy}
        onCancel={() => setRemoving(null)}
        onConfirm={() => void removePasskey()}
      />
    </div>
  );
}
