"use client";

import { Fragment, useMemo } from "react";
import Link from "next/link";
import type { ResolvedMention } from "@/lib/database.types";
import { tokenizeBody } from "@/lib/text";

/**
 * Post body text (Phase 2F §10): body-lg reading size, preserved line
 * breaks, and tappable mentions and hashtags in accent.
 *
 * A mention links ONLY when the server resolved it at post time (the
 * `mentions` rows carry the member id and her CURRENT handle), so a
 * made-up handle is plain text, a mention never silently re-points to
 * whoever later claims the handle, and a suspended or banned account's
 * mention falls back to plain text while that state holds. When
 * `mentions` is null (rows read before the Phase 2F migration is
 * applied), every well-shaped @token links — the pre-2F interim
 * behavior. Identity is the handle only; nothing here ever touches a
 * legal name.
 *
 * A hashtag links to its canonical tag page, with the author's casing
 * preserved in the visible text. A #token that is not a real tag (a
 * pure number, a URL fragment) renders as plain text.
 */
export function PostBody({
  body,
  mentions,
  clamp = false,
}: {
  body: string;
  mentions?: ResolvedMention[] | null;
  clamp?: boolean;
}) {
  const segments = useMemo(() => {
    const resolved =
      mentions === null || mentions === undefined
        ? null
        : new Set(mentions.map((m) => m.handle.toLowerCase()));
    return tokenizeBody(body, resolved);
  }, [body, mentions]);

  return (
    <p
      className={`whitespace-pre-wrap break-words text-body-lg text-text-primary ${
        clamp ? "line-clamp-4" : ""
      }`}
    >
      {segments.map((segment, index) =>
        segment.kind === "mention" ? (
          <Link
            key={index}
            href={`/u/${segment.handle}`}
            className="text-accent hover:underline focus-visible:underline"
            onClick={(event) => event.stopPropagation()}
          >
            {segment.text}
          </Link>
        ) : segment.kind === "hashtag" ? (
          <Link
            key={index}
            href={`/t/${encodeURIComponent(segment.tag)}`}
            aria-label={`hashtag ${segment.tag}`}
            className="text-accent hover:underline focus-visible:underline"
            onClick={(event) => event.stopPropagation()}
          >
            {segment.text}
          </Link>
        ) : (
          <Fragment key={index}>{segment.text}</Fragment>
        ),
      )}
    </p>
  );
}
