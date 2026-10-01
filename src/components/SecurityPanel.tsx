"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { Alert, Badge, Button, Card, Field, Input } from "@/components/ui";

interface FactorInfo {
  id: string;
  type: string;
  name: string;
  verified: boolean;
}

/**
 * Two-factor management: WebAuthn (passkey / hardware security key —
 * the required factor for privileged accounts) plus TOTP as the stable
 * fallback. Privileged database functions demand AAL2, so the Owner
 * must enroll and step up here before granting any role.
 */
export function SecurityPanel() {
  const router = useRouter();
  const [aal, setAal] = useState<string | null>(null);
  const [factors, setFactors] = useState<FactorInfo[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [totpEnroll, setTotpEnroll] = useState<{ factorId: string; qr: string } | null>(null);
  const [totpCode, setTotpCode] = useState("");

  const refresh = useCallback(async () => {
    const supabase = createSupabaseBrowserClient();
    const [{ data: aalData }, { data: factorData }] = await Promise.all([
      supabase.auth.mfa.getAuthenticatorAssuranceLevel(),
      supabase.auth.mfa.listFactors(),
    ]);
    return {
      aal: aalData?.currentLevel ?? null,
      factors: (factorData?.all ?? []).map((f) => ({
        id: f.id,
        type: f.factor_type,
        name: f.friendly_name ?? f.factor_type,
        verified: f.status === "verified",
      })),
    };
  }, []);

  const applyRefresh = useCallback(async () => {
    const state = await refresh();
    setAal(state.aal);
    setFactors(state.factors);
  }, [refresh]);

  useEffect(() => {
    let active = true;
    void refresh().then((state) => {
      if (!active) return;
      setAal(state.aal);
      setFactors(state.factors);
    });
    return () => {
      active = false;
    };
  }, [refresh]);

  const enrollWebauthn = async () => {
    setBusy(true);
    setError(null);
    setNotice(null);
    const supabase = createSupabaseBrowserClient();
    const { error: registerError } = await supabase.auth.mfa.webauthn.register({
      friendlyName: `Security key (${new Date().toLocaleDateString()})`,
    });
    if (registerError) {
      setError(
        "Could not register the security key. If this persists, the WebAuthn factor may not be enabled on the Supabase project yet (it is in beta) — use an authenticator app meanwhile.",
      );
    } else {
      setNotice("Security key registered. You are now at AAL2.");
      await applyRefresh();
      router.refresh();
    }
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
    if (factor.type === "webauthn") {
      const { error: authError } = await supabase.auth.mfa.webauthn.authenticate({
        factorId: factor.id,
      });
      if (authError) setError("Step-up failed. Try again.");
      else setNotice("Stepped up to AAL2.");
    } else {
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
    }
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
          Privileged actions — granting roles, reading the audit log, viewing contact details —
          require AAL2: a second factor verified in this session.
        </p>
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
                  {factor.verified && aal !== "aal2" ? (
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
          <Button disabled={busy} onClick={enrollWebauthn}>
            Add a passkey / security key
          </Button>
          <Button variant="secondary" disabled={busy} onClick={startTotpEnroll}>
            Add an authenticator app
          </Button>
        </div>
        {totpEnroll ? (
          <div className="flex flex-col gap-3 rounded-md border border-border p-4">
            <p className="text-body text-text-secondary">
              Scan this QR code with your authenticator app, then enter the 6-digit code.
            </p>
            {/* eslint-disable-next-line @next/next/no-img-element -- SVG data URI from Supabase */}
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
    </div>
  );
}
