import type { NextConfig } from "next";

/**
 * Security headers (P1-4, 2026-10-06 hardening pass). The threat-model-
 * critical one is Referrer-Policy. We ship `no-referrer`: strict-origin-when-
 * cross-origin still sent the bare origin `https://unitedfeminist.com` on
 * every outbound external click, which broadcasts MEMBERSHIP of this platform
 * to any third-party site a member visits — a real exposure for members hiding
 * from someone. `no-referrer` sends nothing at all. There is no analytics or
 * ad-attribution that depends on the Referer header, so nothing breaks.
 *
 * CSP is deliberately NOT set here yet: the theme-init inline script in
 * layout.tsx needs a nonce or hash first. Tracked in PROGRESS.md.
 */
const securityHeaders = [
  { key: "Referrer-Policy", value: "no-referrer" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  {
    key: "Permissions-Policy",
    value: "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
  },
];

// Ship "dark": not search-discoverable until moderation tooling (Phase 2B)
// can action a report. The single flag SITE_INDEXABLE (see src/lib/seo.ts)
// gates this header, /robots.txt, and the per-page robots meta tag together.
// Default/unset = noindex (fail-safe). To go public: set SITE_INDEXABLE=true
// in the host env and redeploy. See PROGRESS.md → "How to go public".
const siteIndexable = process.env.SITE_INDEXABLE === "true";
const responseHeaders = siteIndexable
  ? securityHeaders
  : [...securityHeaders, { key: "X-Robots-Tag", value: "noindex, nofollow" }];

const nextConfig: NextConfig = {
  // Media bytes must never flow through the app host (cost rule in
  // docs/architecture.md §1.4). Disabling the image optimizer enforces it.
  images: { unoptimized: true },
  poweredByHeader: false,
  async headers() {
    return [{ source: "/(.*)", headers: responseHeaders }];
  },
};

export default nextConfig;
