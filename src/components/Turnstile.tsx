"use client";

import { useEffect, useImperativeHandle, useRef, useState, type Ref } from "react";

/**
 * Cloudflare Turnstile — the bot check on signup and login.
 *
 * Chosen over reCAPTCHA deliberately: this platform exists for people
 * hiding from specific others, and the signup page must not load
 * Google tracking at the most sensitive moment in the product.
 * Turnstile is privacy-preserving, usually invisible, and verified
 * server-side by Supabase auth (the secret lives in Supabase config,
 * never in this codebase).
 *
 * Designed to degrade safely in every direction:
 *  - no NEXT_PUBLIC_TURNSTILE_SITE_KEY (local dev): renders nothing,
 *    the form works untouched;
 *  - script blocked or fails to load: a calm, human notice appears and
 *    the form stays submittable — whether the submission then succeeds
 *    depends on whether captcha enforcement is switched on in Supabase,
 *    which is exactly the right authority for that decision;
 *  - token expired or errored: the token is cleared and the widget
 *    retries, so a stale token is never submitted silently;
 *  - failed submission: the parent calls reset() (tokens are single
 *    use) and the member can simply try again.
 *
 * The widget itself is keyboard-operable and never traps focus
 * (Cloudflare's iframe handles its own accessibility); the error
 * notice is a polite live region.
 */

interface TurnstileRenderParams {
  sitekey: string;
  callback?: (token: string) => void;
  "expired-callback"?: () => void;
  "error-callback"?: () => void;
  theme?: "auto" | "light" | "dark";
  size?: "normal" | "flexible" | "compact";
  "response-field"?: boolean;
}

interface TurnstileApi {
  render: (container: HTMLElement, params: TurnstileRenderParams) => string | undefined;
  reset: (widgetId?: string) => void;
  remove: (widgetId: string) => void;
}

declare global {
  interface Window {
    turnstile?: TurnstileApi;
    hsTurnstileOnload?: () => void;
  }
}

const SCRIPT_ID = "hs-turnstile-script";
const SCRIPT_SRC =
  "https://challenges.cloudflare.com/turnstile/v0/api.js?onload=hsTurnstileOnload&render=explicit";

let scriptPromise: Promise<TurnstileApi> | null = null;

/** Load the Turnstile script once per page, resolving to its API. */
function loadTurnstile(): Promise<TurnstileApi> {
  if (window.turnstile) return Promise.resolve(window.turnstile);
  if (scriptPromise) return scriptPromise;
  scriptPromise = new Promise<TurnstileApi>((resolve, reject) => {
    window.hsTurnstileOnload = () => {
      if (window.turnstile) resolve(window.turnstile);
      else reject(new Error("Turnstile loaded without exposing its API"));
    };
    const existing = document.getElementById(SCRIPT_ID);
    if (existing) return; // onload callback above still fires
    const script = document.createElement("script");
    script.id = SCRIPT_ID;
    script.src = SCRIPT_SRC;
    script.async = true;
    script.onerror = () => {
      scriptPromise = null; // allow a retry on remount
      reject(new Error("Turnstile script failed to load"));
    };
    document.head.appendChild(script);
  });
  return scriptPromise;
}

export interface TurnstileHandle {
  /** Discard the (single-use) token and ask for a fresh one. */
  reset: () => void;
}

interface TurnstileProps {
  /**
   * Receives the fresh token when the check passes, and null whenever
   * the current token stops being valid (expiry, error, reset).
   */
  onToken: (token: string | null) => void;
  ref?: Ref<TurnstileHandle>;
}

export function Turnstile({ onToken, ref }: TurnstileProps) {
  const siteKey = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY;
  const containerRef = useRef<HTMLDivElement | null>(null);
  const widgetIdRef = useRef<string | null>(null);
  const onTokenRef = useRef(onToken);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    onTokenRef.current = onToken;
  }, [onToken]);

  useImperativeHandle(ref, () => ({
    reset: () => {
      onTokenRef.current(null);
      if (widgetIdRef.current !== null) {
        window.turnstile?.reset(widgetIdRef.current);
      }
    },
  }));

  useEffect(() => {
    if (!siteKey) return;
    let cancelled = false;
    loadTurnstile()
      .then((api) => {
        if (cancelled || !containerRef.current) return;
        const id = api.render(containerRef.current, {
          sitekey: siteKey,
          theme: "auto",
          size: "flexible",
          "response-field": false,
          callback: (token) => onTokenRef.current(token),
          "expired-callback": () => {
            onTokenRef.current(null);
            if (widgetIdRef.current !== null) window.turnstile?.reset(widgetIdRef.current);
          },
          "error-callback": () => onTokenRef.current(null),
        });
        if (id === undefined) {
          setFailed(true);
          return;
        }
        widgetIdRef.current = id;
      })
      .catch(() => {
        if (!cancelled) setFailed(true);
      });
    return () => {
      cancelled = true;
      if (widgetIdRef.current !== null) {
        window.turnstile?.remove(widgetIdRef.current);
        widgetIdRef.current = null;
      }
    };
  }, [siteKey]);

  if (!siteKey) return null;

  return (
    <div className="flex flex-col gap-1.5">
      <div ref={containerRef} />
      {failed ? (
        <p role="status" className="text-caption text-text-secondary">
          The quick security check couldn&apos;t load. You can still submit — if it doesn&apos;t go
          through, reload this page and try again.
        </p>
      ) : null}
    </div>
  );
}
