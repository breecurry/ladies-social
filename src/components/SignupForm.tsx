"use client";

import Link from "next/link";
import { useEffect, useRef, useState, type FormEvent } from "react";
import { Alert, Button, Card, Field, Input } from "@/components/ui";
import { AgeGateRejection } from "@/components/age-gate/AgeGateRejection";
import { AgeGateBlocked } from "@/components/age-gate/AgeGateBlocked";
import { DateOfBirthFields, type DobParts } from "@/components/age-gate/DateOfBirthFields";
import { Turnstile, type TurnstileHandle } from "@/components/Turnstile";
import { composeBirthDate, isAtLeast18 } from "@/lib/validation";

/**
 * Lightweight, non-invasive device signal: stable browser properties
 * hashed client-side. Server HMACs it with a pepper before storage and
 * only ever compares it against banned-account and age-gate-block
 * hashes.
 */
async function computeDeviceFingerprint(): Promise<string> {
  const parts = [
    navigator.userAgent,
    navigator.language,
    String(navigator.hardwareConcurrency ?? ""),
    String(navigator.maxTouchPoints ?? ""),
    `${screen.width}x${screen.height}x${screen.colorDepth}`,
    Intl.DateTimeFormat().resolvedOptions().timeZone ?? "",
  ].join("|");
  const bytes = new TextEncoder().encode(parts);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

interface SignupResponse {
  ok: boolean;
  message?: string;
  error?: string;
  field?: string | null;
  blocked?: boolean;
  underage?: boolean;
  code?: string;
}

interface AgeGateResponse {
  ok: boolean;
  blocked?: boolean;
  code?: string;
}

type GateState = { kind: "form" } | { kind: "rejected" } | { kind: "blocked"; code: string };

export function SignupForm() {
  const [submitting, setSubmitting] = useState(false);
  const [success, setSuccess] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [field, setField] = useState<string | null>(null);
  const [gate, setGate] = useState<GateState>({ kind: "form" });
  const [dob, setDob] = useState<DobParts>({ month: "", day: "", year: "" });
  const [dobError, setDobError] = useState<string | null>(null);
  const [ageAttested, setAgeAttested] = useState(false);
  const [tosAgreed, setTosAgreed] = useState(false);
  // Single-use Turnstile token (empty until the widget solves; stays
  // empty without a site key or when the script cannot load).
  const captchaTokenRef = useRef("");
  const turnstileRef = useRef<TurnstileHandle>(null);

  // A device whose cookie was cleared but whose fingerprint is under an
  // active block still meets the blocked screen (spec §17.3). The form
  // renders immediately; this check swaps it out if the device is known.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const deviceFingerprint = await computeDeviceFingerprint().catch(() => "");
      if (!deviceFingerprint) return;
      try {
        const response = await fetch("/api/auth/age-gate", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ action: "check", deviceFingerprint }),
        });
        const body = (await response.json()) as AgeGateResponse;
        if (!cancelled && body.ok && body.blocked && body.code) {
          setGate({ kind: "blocked", code: body.code });
        }
      } catch {
        // Network trouble on a best-effort check: the form stays; the
        // server re-checks on submit regardless.
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const onSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setError(null);
    setField(null);
    setDobError(null);

    const form = new FormData(event.currentTarget);

    const birthDate = composeBirthDate(dob.month, dob.day, dob.year);
    if (!birthDate) {
      setDobError("Enter your full date of birth.");
      return;
    }
    if (!ageAttested) {
      setError("Please confirm that you are 18 or older.");
      setField("ageAttested");
      return;
    }
    if (!tosAgreed) {
      setError("Please agree to the Terms of Service to create an account.");
      setField("tosAgreed");
      return;
    }

    setSubmitting(true);
    const deviceFingerprint = await computeDeviceFingerprint().catch(() => "");

    // Under 18: route to the rejection screen (§17.2) and record the
    // 14-day device block. The ONLY thing sent is the fingerprint —
    // the date of birth, email, and name never leave this browser on
    // this path. The gate takes in a date and gives back a no; it
    // never takes in a person (§17.4).
    if (!isAtLeast18(birthDate)) {
      try {
        await fetch("/api/auth/age-gate", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ action: "block", deviceFingerprint }),
        });
      } catch {
        // Even if recording fails, the answer is still no.
      }
      setGate({ kind: "rejected" });
      setSubmitting(false);
      return;
    }

    const payload = {
      legalName: String(form.get("legalName") ?? ""),
      email: String(form.get("email") ?? ""),
      dob: birthDate,
      ageAttested,
      tosAgreed,
      handle: String(form.get("handle") ?? ""),
      password: String(form.get("password") ?? ""),
      deviceFingerprint,
      captchaToken: captchaTokenRef.current,
    };

    try {
      const response = await fetch("/api/auth/signup", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const body = (await response.json()) as SignupResponse;
      if (body.ok) {
        setSuccess(body.message ?? "Account created.");
      } else if (body.blocked && body.code) {
        setGate({ kind: "blocked", code: body.code });
      } else if (body.underage) {
        setGate({ kind: "rejected" });
      } else {
        setError(body.error ?? "Something went wrong. Please try again.");
        setField(body.field ?? null);
        // The token (if any) was consumed by this attempt; get a fresh
        // one so retrying can actually succeed.
        turnstileRef.current?.reset();
      }
    } catch {
      setError("Something went wrong. Please try again.");
      turnstileRef.current?.reset();
    } finally {
      setSubmitting(false);
    }
  };

  if (gate.kind === "rejected") return <AgeGateRejection />;
  if (gate.kind === "blocked") return <AgeGateBlocked code={gate.code} />;

  if (success) {
    return (
      <Card className="flex flex-col gap-4">
        <h2 className="text-heading">Check your email</h2>
        <Alert tone="success">{success}</Alert>
        <p className="text-body text-text-secondary">
          Once you confirm your address, you can log in and get started.
        </p>
      </Card>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-2">
        <h1 className="text-title">Create your account</h1>
        <p className="text-body text-text-secondary">
          Joining takes an email address, a handle and your legal name. Your legal name stays
          private unless you choose to show it.
        </p>
      </div>

      <form onSubmit={onSubmit} noValidate className="flex flex-col gap-5">
        {error && !field ? <Alert tone="danger">{error}</Alert> : null}

        <Field
          label="Legal name"
          htmlFor="legalName"
          hint="Required, but never shown publicly unless you choose to show it. Members see your @handle."
          error={field === "legalName" ? error : null}
        >
          <Input id="legalName" name="legalName" autoComplete="name" required maxLength={100} />
        </Field>

        <Field label="Email" htmlFor="email" error={field === "email" ? error : null}>
          <Input id="email" name="email" type="email" autoComplete="email" required />
        </Field>

        <DateOfBirthFields value={dob} onChange={setDob} error={dobError} disabled={submitting} />

        <Field
          label="Handle"
          htmlFor="handle"
          hint="3-30 characters: lowercase letters, numbers, underscores. This is what members see."
          error={field === "handle" ? error : null}
        >
          <Input id="handle" name="handle" autoComplete="off" required maxLength={30} />
        </Field>

        <Field
          label="Password"
          htmlFor="password"
          hint="At least 10 characters."
          error={field === "password" ? error : null}
        >
          <Input
            id="password"
            name="password"
            type="password"
            autoComplete="new-password"
            required
            minLength={10}
          />
        </Field>

        <div className="flex flex-col gap-1.5">
          <p className="text-body text-text-secondary">
            By creating an account you agree to follow the{" "}
            <Link
              href="/community-guidelines"
              target="_blank"
              rel="noopener"
              className="text-accent underline underline-offset-2"
            >
              Community Guidelines
              <span className="sr-only"> (opens in a new tab)</span>
            </Link>
            .
          </p>
          <label className="flex min-h-11 cursor-pointer items-center gap-3">
            <input
              type="checkbox"
              name="ageAttested"
              checked={ageAttested}
              onChange={(e) => setAgeAttested(e.target.checked)}
              aria-invalid={field === "ageAttested" && error ? true : undefined}
              aria-describedby={field === "ageAttested" && error ? "ageAttested-error" : undefined}
              className="size-5 shrink-0 accent-(--accent) focus-visible:outline-2 focus-visible:outline-focus-ring"
            />
            <span className="text-body text-text-primary">I confirm that I am 18 or older.</span>
          </label>
          {field === "ageAttested" && error ? (
            <p id="ageAttested-error" role="alert" className="text-caption text-danger">
              {error}
            </p>
          ) : null}
          <label className="flex min-h-11 cursor-pointer items-center gap-3">
            <input
              type="checkbox"
              name="tosAgreed"
              checked={tosAgreed}
              onChange={(e) => setTosAgreed(e.target.checked)}
              aria-invalid={field === "tosAgreed" && error ? true : undefined}
              aria-describedby={field === "tosAgreed" && error ? "tosAgreed-error" : undefined}
              className="size-5 shrink-0 accent-(--accent) focus-visible:outline-2 focus-visible:outline-focus-ring"
            />
            <span className="text-body text-text-primary">
              I agree to the{" "}
              <Link
                href="/terms-of-service"
                target="_blank"
                rel="noopener"
                className="text-accent underline underline-offset-2"
              >
                Terms of Service
                <span className="sr-only"> (opens in a new tab)</span>
              </Link>
              .
            </span>
          </label>
          {field === "tosAgreed" && error ? (
            <p id="tosAgreed-error" role="alert" className="text-caption text-danger">
              {error}
            </p>
          ) : null}
        </div>

        <Turnstile
          ref={turnstileRef}
          onToken={(token) => {
            captchaTokenRef.current = token ?? "";
          }}
        />

        <Button type="submit" disabled={submitting}>
          {submitting ? "Creating your account…" : "Join"}
        </Button>

        <p className="text-caption text-text-tertiary">
          Everyone is welcome here. What keeps this space safe is conduct: bullying and harassment
          are not tolerated and lead to removal.
        </p>
      </form>
    </div>
  );
}
