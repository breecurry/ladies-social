/**
 * Single source of truth for search-engine visibility.
 *
 * Hersciety ships "dark": reachable by a direct link but not
 * discoverable by search engines. Registration is open, but there is no
 * moderation action path yet (the reports table has no UPDATE route for any
 * role — moderation tooling is Phase 2B), so the site must not be indexed and
 * surfaced to strangers until a human can action a report.
 *
 * This flag drives all three indexing layers at once:
 *   - the `X-Robots-Tag: noindex, nofollow` response header (next.config.ts)
 *   - `/robots.txt` (src/app/robots.ts)
 *   - the per-page `robots` meta tag (src/app/layout.tsx)
 *
 * Default (unset) is noindex — a fail-safe: a forgotten flag keeps the site
 * hidden rather than accidentally public.
 *
 * TO GO PUBLIC when moderation ships: set the environment variable
 *   SITE_INDEXABLE=true
 * in the host (Vercel → Settings → Environment Variables) and redeploy.
 * See PROGRESS.md → "How to go public".
 */
export const SITE_INDEXABLE = process.env.SITE_INDEXABLE === "true";
