"use client";

import { useState, type FormEvent } from "react";
import { Alert, Button, Card, Field, Input } from "@/components/ui";

/**
 * Lightweight, non-invasive device signal: stable browser properties
 * hashed client-side. Server HMACs it with a pepper before storage and
 * only ever compares it against banned-account hashes.
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
}

export function SignupForm() {
  const [submitting, setSubmitting] = useState(false);
  const [success, setSuccess] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [field, setField] = useState<string | null>(null);

  const onSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    setField(null);

    const form = new FormData(event.currentTarget);
    const payload = {
      legalName: String(form.get("legalName") ?? ""),
      email: String(form.get("email") ?? ""),
      dob: String(form.get("dob") ?? ""),
      handle: String(form.get("handle") ?? ""),
      password: String(form.get("password") ?? ""),
      deviceFingerprint: await computeDeviceFingerprint().catch(() => ""),
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
      } else {
        setError(body.error ?? "Something went wrong. Please try again.");
        setField(body.field ?? null);
      }
    } catch {
      setError("Something went wrong. Please try again.");
    } finally {
      setSubmitting(false);
    }
  };

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
    <form onSubmit={onSubmit} noValidate className="flex flex-col gap-5">
      {error ? <Alert tone="danger">{error}</Alert> : null}

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

      <Field
        label="Date of birth"
        htmlFor="dob"
        hint="You must be 18 or older."
        error={field === "dob" ? error : null}
      >
        <Input id="dob" name="dob" type="date" autoComplete="bday" required />
      </Field>

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

      <Button type="submit" disabled={submitting}>
        {submitting ? "Creating your account…" : "Join"}
      </Button>

      <p className="text-caption text-text-tertiary">
        Everyone is welcome here. What keeps this space safe is conduct: bullying and harassment
        are not tolerated and lead to removal.
      </p>
    </form>
  );
}
