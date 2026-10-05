import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";

/**
 * The legal documents live as markdown in docs/ — the single source of
 * truth. Pages render them from disk so a change to the document is a
 * change to the page, with no copy drift.
 *
 * `published` is the publication switch for each document. The Terms of
 * Service and Privacy Policy are still being finalised with counsel
 * (they contain unresolved owner decisions — see the bracketed notes in
 * the markdown), so their routes show an interim notice instead of
 * draft legal text. When a document receives sign-off, flipping its
 * `published` flag to `true` here is the ONLY change needed to put the
 * real text live at its existing URL.
 */
export type LegalSlug = "terms-of-service" | "privacy-policy" | "community-guidelines";

export const LEGAL_DOCS: Record<LegalSlug, { title: string; published: boolean }> = {
  "terms-of-service": { title: "Terms of Service", published: false },
  "privacy-policy": { title: "Privacy Policy", published: false },
  "community-guidelines": { title: "Community Guidelines", published: true },
};

export interface LegalDocument {
  /** The document's own H1, rendered as the page heading. */
  title: string;
  /** Text of the `*Effective date: …*` line, when present. */
  effectiveDate: string | null;
  /** Text of the `*Last updated: …*` line, when present. */
  lastUpdated: string | null;
  /** Markdown body: everything after the title/date metadata block. */
  body: string;
}

const cache = new Map<LegalSlug, LegalDocument>();

/**
 * Reads and parses a legal document from docs/<slug>.md.
 *
 * The header metadata (H1 title, effective date, last-updated date) is
 * extracted and rendered by the page chrome; the body is everything
 * AFTER the last metadata line. Anything between the title and the date
 * lines — such as an internal pre-publication review note — is
 * deliberately not part of the public body.
 */
export async function loadLegalDocument(slug: LegalSlug): Promise<LegalDocument> {
  const cached = cache.get(slug);
  if (cached) return cached;

  const raw = await readFile(path.join(process.cwd(), "docs", `${slug}.md`), "utf8");
  const lines = raw.split(/\r?\n/);

  const titleIndex = lines.findIndex((line) => /^#\s+\S/.test(line));
  const effectiveIndex = lines.findIndex((line) => /^\*Effective date:\s*.+\*\s*$/.test(line));
  const updatedIndex = lines.findIndex((line) => /^\*Last updated:\s*.+\*\s*$/.test(line));

  const title =
    titleIndex >= 0
      ? (lines[titleIndex] ?? "").replace(/^#\s+/, "").trim()
      : LEGAL_DOCS[slug].title;
  const effectiveDate =
    effectiveIndex >= 0
      ? ((lines[effectiveIndex] ?? "").match(/^\*Effective date:\s*(.+?)\*\s*$/)?.[1] ?? null)
      : null;
  const lastUpdated =
    updatedIndex >= 0
      ? ((lines[updatedIndex] ?? "").match(/^\*Last updated:\s*(.+?)\*\s*$/)?.[1] ?? null)
      : null;

  let bodyStart = Math.max(titleIndex, effectiveIndex, updatedIndex) + 1;
  // Skip the horizontal rule / blank lines that separate the metadata
  // block from the first real section.
  while (bodyStart < lines.length && /^(---\s*|\s*)$/.test(lines[bodyStart] ?? "")) {
    bodyStart += 1;
  }

  const doc: LegalDocument = {
    title,
    effectiveDate,
    lastUpdated,
    body: lines.slice(bodyStart).join("\n"),
  };
  cache.set(slug, doc);
  return doc;
}

let termsVersionCache: string | null = null;

/**
 * Identifier for the exact Terms of Service text on disk, recorded
 * with each member's signup consent (user_private.tos_version).
 *
 * Derived from the document itself — the parsed "Last updated" date
 * plus a hash of the file's full contents — so it can never silently
 * go stale: any change to docs/terms-of-service.md produces a new
 * identifier with no human having to remember to bump anything. While
 * the document is unpublished (its route shows the interim notice),
 * the identifier carries an `interim:` prefix; when the `published`
 * flag flips, new consents automatically record the clean version.
 *
 * Never throws: the consent write must not be able to break a signup,
 * so a read failure degrades to a sentinel (the consent timestamp
 * still gets recorded).
 */
export async function termsOfServiceVersion(): Promise<string> {
  if (termsVersionCache) return termsVersionCache;
  try {
    const raw = await readFile(path.join(process.cwd(), "docs", "terms-of-service.md"), "utf8");
    const hash = createHash("sha256").update(raw).digest("hex").slice(0, 16);
    const doc = await loadLegalDocument("terms-of-service");
    const date = doc.lastUpdated ?? doc.effectiveDate ?? "undated";
    const prefix = LEGAL_DOCS["terms-of-service"].published ? "" : "interim:";
    termsVersionCache = `${prefix}${date}#sha256:${hash}`;
  } catch {
    termsVersionCache = "unresolved";
  }
  return termsVersionCache;
}
