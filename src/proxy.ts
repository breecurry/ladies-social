import { type NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

/**
 * Generate a cryptographically random nonce for CSP, using the Web Crypto
 * API (Edge-compatible — no Node.js crypto required).
 */
function generateNonce(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...Array.from(bytes)));
}

/**
 * Build the Content-Security-Policy header value for this request.
 *
 * Policy rationale, directive by directive:
 *
 *   default-src 'self'
 *     Catch-all: anything not covered by a more specific directive falls
 *     back to same-origin only.
 *
 *   script-src 'self' 'nonce-{nonce}' https://challenges.cloudflare.com
 *     'self' — Next.js JS chunks served from the app.
 *     'nonce-{nonce}' — the theme-init inline script in layout.tsx.
 *     challenges.cloudflare.com — Cloudflare Turnstile bot check (used on
 *       /login and /signup). The Turnstile component creates a <script> via
 *       document.createElement, which cannot receive a nonce; an allowlisted
 *       host is the only correct way to permit it without 'unsafe-inline'.
 *
 *   style-src 'self' 'unsafe-inline'
 *     Six components use style={{ ... }} for dynamically computed values
 *     (blurhash-derived background colours, crop overlay). Inline style=
 *     attributes require 'unsafe-inline'; nonces only apply to <style>
 *     elements, not to style= attributes. This is a documented tradeoff —
 *     see KNOWLEDGE/app.md, CSP section.
 *
 *   img-src 'self' https://media.hersciety.com data: blob:
 *     media.hersciety.com — profile pictures served via Cloudflare R2.
 *     data: — Supabase auth.mfa.enroll() returns the TOTP QR code as a
 *       data:image/svg+xml URI (confirmed in @supabase/auth-js source).
 *     blob: — AvatarEditor creates a blob: URL for the in-browser crop
 *       preview (URL.createObjectURL on the picked file).
 *
 *   font-src 'self'
 *     Hanken Grotesk is loaded via next/font/google, which downloads and
 *     self-hosts the font at build time — no external font origin needed.
 *
 *   connect-src 'self' https://hiphjzhlwiztqgezzipf.supabase.co
 *                      https://challenges.cloudflare.com
 *                      https://7f79ff00b7bec4dea299ac9e824cface.r2.cloudflarestorage.com
 *     supabase.co — all Supabase REST, auth and RPC calls from the browser
 *       Supabase client. No realtime WebSocket connections exist in the app.
 *     challenges.cloudflare.com — Turnstile validation calls back to Cloudflare.
 *     r2.cloudflarestorage.com — avatar upload: the ticket API returns a
 *       presigned PUT URL targeting the R2 staging bucket; the browser PUT
 *       goes directly to this host (src/components/avatar/AvatarEditor.tsx).
 *
 *   frame-src https://challenges.cloudflare.com
 *     Turnstile renders its challenge inside a cross-origin iframe hosted on
 *     challenges.cloudflare.com.
 *
 *   frame-ancestors 'none'
 *     Redundant with X-Frame-Options: DENY (set in next.config.ts) but
 *     required by CSP Level 2+ for browsers that prefer CSP over the older
 *     header.
 *
 *   base-uri 'self'    — block <base> injection (could hijack relative URLs).
 *   form-action 'self' — all form POSTs must target the same origin.
 *   object-src 'none'  — no Flash / plugin objects.
 */
function buildCsp(nonce: string): string {
  const supabase = "https://hiphjzhlwiztqgezzipf.supabase.co";
  const turnstile = "https://challenges.cloudflare.com";
  const r2 = "https://7f79ff00b7bec4dea299ac9e824cface.r2.cloudflarestorage.com";
  const media = "https://media.hersciety.com";

  return [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' ${turnstile}`,
    "style-src 'self' 'unsafe-inline'",
    `img-src 'self' ${media} data: blob:`,
    "font-src 'self'",
    `connect-src 'self' ${supabase} ${turnstile} ${r2}`,
    `frame-src ${turnstile}`,
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "object-src 'none'",
  ].join("; ");
}

export async function proxy(request: NextRequest) {
  const nonce = generateNonce();
  const csp = buildCsp(nonce);

  // Forward the nonce to server components via a custom request header.
  // layout.tsx reads this via `import { headers } from 'next/headers'` and
  // applies it as the nonce= attribute on the theme-init inline <script>.
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-nonce", nonce);

  const response = await updateSession(request, requestHeaders);

  // Set the CSP on the response — this is what the browser enforces.
  response.headers.set("Content-Security-Policy", csp);

  return response;
}

export const config = {
  matcher: [
    // Everything except static assets and images.
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)",
  ],
};
