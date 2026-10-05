import type { NextConfig } from "next";

/**
 * Security headers (P1-4, 2026-10-06 hardening pass). The threat-model-
 * critical one is Referrer-Policy: without it, a member who clicks an
 * external link planted in a post or bio sends
 * `Referer: https://unitedfeminist.com/u/alice`, telling the link's
 * owner both that she is a member and whose profile she was viewing.
 *
 * CSP is deliberately NOT set here yet: the theme-init inline script in
 * layout.tsx needs a nonce or hash first. Tracked in PROGRESS.md.
 */
const securityHeaders = [
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  {
    key: "Permissions-Policy",
    value: "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
  },
];

const nextConfig: NextConfig = {
  // Media bytes must never flow through the app host (cost rule in
  // docs/architecture.md §1.4). Disabling the image optimizer enforces it.
  images: { unoptimized: true },
  poweredByHeader: false,
  async headers() {
    return [{ source: "/(.*)", headers: securityHeaders }];
  },
};

export default nextConfig;
