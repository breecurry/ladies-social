/**
 * Post-body tokenization for mentions and hashtags (Phase 2F design
 * §2, §10). These rules MUST agree exactly with the server parser in
 * create_post (migrations 20261017000001 + 20261018000001): what looks
 * like a mention or a tag in the UI is precisely what the server
 * treated as one.
 *
 * Server rules mirrored here:
 * - A mention is '@' at a word boundary (start of text, or after a
 *   character that is not a letter, number, or underscore) followed by
 *   3-30 of [A-Za-z0-9_]. Whether it LINKS is decided by the resolved
 *   mentions stored at post time, never by the raw text; a well-shaped
 *   token the server did not resolve renders as deliberately inert,
 *   muted text.
 * - A hashtag is '#' at the same word boundary followed by Unicode
 *   letters, numbers, and underscores with at least one letter; the
 *   canonical form is NFC-normalized and lowercased. A token longer
 *   than 40 characters is not a hashtag at all: it renders as the same
 *   inert, muted text, is not indexed, and does not link. A pure-number
 *   or pure-underscore token is ordinary text.
 */

export type BodySegment =
  | { kind: "text"; text: string }
  | { kind: "mention"; text: string; handle: string }
  | { kind: "hashtag"; text: string; tag: string }
  /** A recognised token that is intentionally not live: a refused or
   *  unresolvable mention, or a would-be hashtag past the 40-char cap. */
  | { kind: "inert"; text: string };

const TOKEN = /(^|[^\p{L}\p{N}_])(@[A-Za-z0-9_]+|#[\p{L}\p{N}_]+)/gu;
const MENTION_TOKEN = /^[A-Za-z0-9_]{3,30}$/;
const HAS_LETTER = /\p{L}/u;
const TAG_MAX = 40;

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
      if (MENTION_TOKEN.test(token)) {
        pushText(segments, body.slice(cursor, tokenStart));
        if (resolvedHandles?.has(token.toLowerCase()) ?? true) {
          segments.push({ kind: "mention", text: `@${token}`, handle: token.toLowerCase() });
        } else {
          segments.push({ kind: "inert", text: `@${token}` });
        }
        cursor = tokenStart + token.length + 1;
      }
    } else {
      if (HAS_LETTER.test(token)) {
        pushText(segments, body.slice(cursor, tokenStart));
        // Code points, matching the server's char_length(), not UTF-16 units.
        if ([...token].length <= TAG_MAX) {
          segments.push({ kind: "hashtag", text: `#${token}`, tag: foldTag(token) });
        } else {
          segments.push({ kind: "inert", text: `#${token}` });
        }
        cursor = tokenStart + token.length + 1;
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

// ---------------------------------------------------------------
// Multi-part threads (design-multi-part-threads §3, §6): the shared
// code-point counter and the over-limit splitter. Both live here, next
// to the tokenizer, because they must agree with it exactly: the
// counter counts the way Postgres char_length() counts, and the
// splitter never lands inside anything tokenizeBody would draw as a
// token.
// ---------------------------------------------------------------

/** Per-part character limit — the server's char_length(body) <= 500. */
export const PART_LIMIT = 500;

/** Maximum parts in one chain. Derived from the create_post depth cap
 *  of 30: 25 parts put the last part at depth 24 and leave five depth
 *  steps for other people's replies. Do not raise it. */
export const PART_CAP = 25;

/** Code points, matching Postgres char_length() — never UTF-16 units,
 *  so a multi-unit emoji counts as one, exactly as the server counts. */
export function codePointLength(text: string): number {
  return [...text].length;
}

export interface SplitResult {
  /** The text flowed into parts, each at most PART_LIMIT code points —
   *  except, when maxParts stopped the flow early, the final part,
   *  which then carries ALL the remaining text over the limit so
   *  nothing is ever lost (the composer flags it and disables Post
   *  until the member resolves it). */
  parts: string[];
  /** True when a single whitespace-free run longer than the limit
   *  forced a break inside it — the one case the UI names honestly. */
  hardBreak: boolean;
  /** True when maxParts stopped the flow before the text fit. */
  overCap: boolean;
}

/** URL shapes the splitter keeps whole (the renderer does not linkify
 *  URLs today, but a split URL would be broken for anyone copying it). */
const URL_RUN = /\bhttps?:\/\/[^\s]+|\bwww\.[^\s]+/gu;

/** Sentence end: terminal punctuation, optionally closed by quotes or
 *  brackets, that the following character position treats as a seam. */
const SENTENCE_END = /[.!?]+["')\]\u2019\u201d»]*$/u;

/**
 * [start, end) UTF-16 ranges a split must never land strictly inside:
 * every mention, hashtag, and inert token exactly as tokenizeBody
 * segments them, plus URL runs. Shared-tokenizer reuse is the point:
 * if the renderer would draw it as one token, the splitter moves it
 * whole.
 */
function protectedRanges(text: string): Array<[number, number]> {
  const ranges: Array<[number, number]> = [];
  let cursor = 0;
  for (const segment of tokenizeBody(text, null)) {
    const end = cursor + segment.text.length;
    if (segment.kind !== "text") ranges.push([cursor, end]);
    cursor = end;
  }
  URL_RUN.lastIndex = 0;
  let match = URL_RUN.exec(text);
  while (match !== null) {
    ranges.push([match.index, match.index + match[0].length]);
    match = URL_RUN.exec(text);
  }
  return ranges;
}

function insideRange(ranges: Array<[number, number]>, index: number): boolean {
  return ranges.some(([start, end]) => index > start && index < end);
}

/**
 * Flow text that exceeds the per-part limit into connected parts
 * (design §6.2). Split preference, always keeping every part at or
 * under PART_LIMIT code points:
 *
 *   1. the last sentence boundary that fits (terminal punctuation
 *      followed by whitespace);
 *   2. the last whitespace that fits — paragraph break over single
 *      newline over space;
 *   3. never strictly inside an @mention, #hashtag, or URL (tokens
 *      contain no whitespace, so whitespace split points satisfy this
 *      by construction; the guard is enforced against the shared
 *      tokenizer all the same);
 *   4. last resort only: a single whitespace-free run longer than the
 *      limit is broken at the limit and reported via hardBreak so the
 *      UI can say so honestly.
 *
 * All indices are code points. Whitespace at a split seam is dropped
 * (it separated the parts; no words are ever lost).
 */
export function splitForThread(
  text: string,
  limit: number = PART_LIMIT,
  maxParts: number = PART_CAP,
): SplitResult {
  const parts: string[] = [];
  let hardBreak = false;
  let overCap = false;
  let remaining = text.replace(/^\s+/u, "");

  while (codePointLength(remaining) > limit) {
    if (parts.length >= maxParts - 1) {
      // The cap: keep every remaining character in the final part,
      // over the limit, rather than silently dropping anything.
      overCap = true;
      break;
    }
    const cps = [...remaining];
    // The window a part may cover: `limit` code points, plus the next
    // one when it is whitespace (splitting there still yields a part
    // of exactly `limit`).
    const windowEnd =
      cps.length > limit && /\s/u.test(cps[limit] ?? "") ? limit + 1 : limit;
    const windowCps = cps.slice(0, windowEnd);
    const ranges = protectedRanges(remaining);

    // UTF-16 offset of each code-point index, for the range guard.
    const utf16At: number[] = [];
    {
      let offset = 0;
      for (const cp of cps) {
        utf16At.push(offset);
        offset += cp.length;
      }
      utf16At.push(offset);
    }

    let sentenceAt = -1;
    let paragraphAt = -1;
    let newlineAt = -1;
    let spaceAt = -1;
    for (let i = 1; i < windowCps.length; i++) {
      const cp = windowCps[i] ?? "";
      if (!/\s/u.test(cp)) continue;
      if (insideRange(ranges, utf16At[i] ?? 0)) continue;
      if (SENTENCE_END.test(cps.slice(0, i).join(""))) sentenceAt = i;
      if (cp === "\n") {
        if (/^\n[ \t]*\n/u.test(cps.slice(i).join(""))) paragraphAt = i;
        newlineAt = i;
      }
      spaceAt = i;
    }

    const splitAt =
      sentenceAt > 0 ? sentenceAt : paragraphAt > 0 ? paragraphAt : newlineAt > 0 ? newlineAt : spaceAt;

    if (splitAt > 0) {
      const head = cps.slice(0, splitAt).join("").replace(/\s+$/u, "");
      remaining = cps.slice(splitAt).join("").replace(/^\s+/u, "");
      if (head.length > 0) parts.push(head);
    } else {
      // One whitespace-free run longer than the limit: the honest
      // hard break at exactly `limit` code points.
      hardBreak = true;
      parts.push(cps.slice(0, limit).join(""));
      remaining = cps.slice(limit).join("").replace(/^\s+/u, "");
    }
  }

  if (remaining.replace(/\s+$/u, "").length > 0) parts.push(remaining.replace(/\s+$/u, ""));
  if (parts.length === 0) parts.push("");
  return { parts, hardBreak, overCap };
}
