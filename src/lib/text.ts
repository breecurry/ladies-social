/**
 * Post-body tokenization for mentions and hashtags (Phase 2F design
 * §2, §10). These rules MUST agree exactly with the server parser in
 * create_post (migration 20261017000001): what looks like a mention
 * or a tag in the UI is precisely what the server treated as one.
 *
 * Server rules mirrored here:
 * - A mention is '@' at a word boundary (start of text, or after a
 *   character that is not a letter, number, or underscore) followed by
 *   3-30 of [A-Za-z0-9_]. Whether it LINKS is decided by the resolved
 *   mentions stored at post time, never by the raw text.
 * - A hashtag is '#' at the same word boundary followed by Unicode
 *   letters, numbers, and underscores with at least one letter; the
 *   canonical form is the first 64 characters, NFC-normalized and
 *   lowercased. Overflow past 64 characters is ordinary text, as is a
 *   pure-number or pure-underscore token.
 */

export type BodySegment =
  | { kind: "text"; text: string }
  | { kind: "mention"; text: string; handle: string }
  | { kind: "hashtag"; text: string; tag: string };

const TOKEN = /(^|[^\p{L}\p{N}_])(@[A-Za-z0-9_]+|#[\p{L}\p{N}_]+)/gu;
const MENTION_TOKEN = /^[A-Za-z0-9_]{3,30}$/;
const HAS_LETTER = /\p{L}/u;
const TAG_MAX = 64;

/** The one canonical tag fold, matching internal.fold_tag in SQL. */
export function foldTag(raw: string): string {
  return raw.replace(/^#+/, "").normalize("NFC").toLowerCase();
}

/**
 * Split a post body into renderable segments. `resolvedHandles` is the
 * set of lowercased handles the server stored as real mentions for
 * this post; when null (data from before the Phase 2F migration is
 * applied), any well-shaped @token is treated as a mention — the
 * pre-2F interim behavior the design names in §10.
 */
export function tokenizeBody(
  body: string,
  resolvedHandles: ReadonlySet<string> | null,
): BodySegment[] {
  const segments: BodySegment[] = [];
  let cursor = 0;
  TOKEN.lastIndex = 0;
  let match = TOKEN.exec(body);
  while (match !== null) {
    const boundary = match[1] ?? "";
    const sigilToken = match[2] ?? "";
    const sigil = sigilToken[0];
    const token = sigilToken.slice(1);
    const tokenStart = match.index + boundary.length;
    if (sigil === "@") {
      if (MENTION_TOKEN.test(token) && (resolvedHandles?.has(token.toLowerCase()) ?? true)) {
        pushText(segments, body.slice(cursor, tokenStart));
        segments.push({ kind: "mention", text: `@${token}`, handle: token.toLowerCase() });
        cursor = tokenStart + token.length + 1;
      }
    } else {
      const visible = token.slice(0, TAG_MAX);
      if (HAS_LETTER.test(visible)) {
        pushText(segments, body.slice(cursor, tokenStart));
        segments.push({ kind: "hashtag", text: `#${visible}`, tag: foldTag(visible) });
        cursor = tokenStart + visible.length + 1;
      }
    }
    match = TOKEN.exec(body);
  }
  pushText(segments, body.slice(cursor));
  return segments;
}

function pushText(segments: BodySegment[], text: string) {
  if (text.length === 0) return;
  const last = segments[segments.length - 1];
  if (last?.kind === "text") {
    segments[segments.length - 1] = { kind: "text", text: last.text + text };
  } else {
    segments.push({ kind: "text", text });
  }
}

/** A valid /t/ path segment: something that folds to a real tag shape. */
export function isValidTagParam(raw: string): boolean {
  const folded = foldTag(decodeURIComponentSafe(raw));
  return (
    folded.length >= 1 &&
    folded.length <= TAG_MAX &&
    /^[\p{L}\p{N}_]+$/u.test(folded) &&
    HAS_LETTER.test(folded)
  );
}

function decodeURIComponentSafe(raw: string): string {
  try {
    return decodeURIComponent(raw);
  } catch {
    return raw;
  }
}

export { decodeURIComponentSafe };
