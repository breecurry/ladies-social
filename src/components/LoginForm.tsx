"use client";

import { useRef, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { Alert, Button, Field, Input } from "@/components/ui";
import { Turnstile, type TurnstileHandle } from "@/components/Turnstile";

export function LoginForm() {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Supabase's captcha switch covers sign-in as well as signup, so the
  // login form carries the same Turnstile widget. While the switch is
  // off the token is ignored; without it, enabling captcha would lock
  // every member out at the door.
  const captchaTokenRef = useRef("");
  const turnstileRef = useRef<TurnstileHandle>(null);

  const onSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setSubmitting(true);
    setError(null);

    const form = new FormData(event.currentTarget);
    const supabase = createSupabaseBrowserClient();
    const captchaToken = captchaTokenRef.current;
    const { error: signInError } = await supabase.auth.signInWithPassword({
      email: String(form.get("email") ?? ""),
      password: String(form.get("password") ?? ""),
      options: captchaToken ? { captchaToken } : undefined,
    });
    if (signInError) {
      setError(
        signInError.message.toLowerCase().includes("captcha")
          ? "The security check could not be verified. Please try again."
          : "Email or password is incorrect, or your email isn't confirmed yet.",
      );
      // Tokens are single use; a failed attempt needs a fresh one.
      turnstileRef.current?.reset();
      setSubmitting(false);
      return;
    }
    router.push("/");
    router.refresh();
  };

  return (
    <form onSubmit={onSubmit} noValidate className="flex flex-col gap-5">
      {error ? <Alert tone="danger">{error}</Alert> : null}
      <Field label="Email" htmlFor="email">
        <Input id="email" name="email" type="email" autoComplete="email" required />
      </Field>
      <Field label="Password" htmlFor="password">
        <Input
          id="password"
          name="password"
          type="password"
          autoComplete="current-password"
          required
        />
      </Field>
      <Turnstile
        ref={turnstileRef}
        onToken={(token) => {
          captchaTokenRef.current = token ?? "";
        }}
      />
      <Button type="submit" disabled={submitting}>
        {submitting ? "Signing in…" : "Sign in"}
      </Button>
    </form>
  );
}
