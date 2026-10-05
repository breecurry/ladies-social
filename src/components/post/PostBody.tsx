"use client";

import { Fragment } from "react";
import Link from "next/link";

const MENTION_SPLIT = /(@[a-z0-9_]{3,30})/gi;

/**
 * Post body text: body-lg reading size, preserved line breaks, and
 * tappable @mentions in accent. Mentions link to the profile by
 * HANDLE only; nothing here ever touches a legal name.
 */
export function PostBody({ body, clamp = false }: { body: string; clamp?: boolean }) {
  const parts = body.split(MENTION_SPLIT);
  return (
    <p
      className={`whitespace-pre-wrap break-words text-body-lg text-text-primary ${
        clamp ? "line-clamp-4" : ""
      }`}
    >
      {parts.map((part, index) =>
        index % 2 === 1 ? (
          <Link
            key={index}
            href={`/u/${part.slice(1).toLowerCase()}`}
            className="text-accent hover:underline"
            onClick={(event) => event.stopPropagation()}
          >
            {part}
          </Link>
        ) : (
          <Fragment key={index}>{part}</Fragment>
        ),
      )}
    </p>
  );
}
