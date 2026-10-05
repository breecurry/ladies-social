"use client";

import { useEffect, useRef, useState, type RefObject } from "react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { PersonRow, TagSearchRow } from "@/lib/database.types";
import { Avatar } from "@/components/Avatar";

export interface ActiveToken {
  sigil: "@" | "#";
  /** Token text after the sigil, 1+ chars. */
  text: string;
  /** Index of the sigil character in the draft. */
  start: number;
  /** End of the token (exclusive) — the caret position. */
  end: number;
}

type Suggestion =
  | { kind: "person"; id: string; userId: string; handle: string }
  | { kind: "tag"; id: string; tag: string; postCount: number };

/**
 * Find the mention/hashtag token the caret is sitting at the end of,
 * applying the same word-boundary rule as the parser: the sigil must
 * open the text or follow a non-word character.
 */
export function activeTokenAt(text: string, caret: number): ActiveToken | null {
  const before = text.slice(0, caret);
  const match = /(^|[^\p{L}\p{N}_])([@#])([\p{L}\p{N}_]{1,64})$/u.exec(before);
  if (!match) return null;
  const sigil = match[2] === "@" ? ("@" as const) : ("#" as const);
  const token = match[3] ?? "";
  if (sigil === "@" && !/^[A-Za-z0-9_]{1,30}$/.test(token)) return null;
  const start = caret - token.length - 1;
  return { sigil, text: token, start, end: caret };
}

/**
 * Mention and hashtag autocomplete for the composer (Phase 2F §9).
 * A listbox tied to the text field: it decorates the field without
 * ever stealing focus; arrow keys move the active option, Enter or
 * Tab selects, Escape dismisses. People rows are the small identity
 * block — avatar and @handle, nothing else, never a legal name — with
 * the people you follow ranked first; blocked accounts never appear
 * because people search already excludes them at the database. Tag
 * rows steer members toward the canonical tag that already exists.
 */
export function ComposerAutocomplete({
  token,
  fieldRef,
  listboxId,
  activeId,
  onActiveIdChange,
  onSelect,
}: {
  token: ActiveToken | null;
  fieldRef: RefObject<HTMLTextAreaElement | null>;
  listboxId: string;
  activeId: string | null;
  onActiveIdChange: (id: string | null) => void;
  onSelect: (token: ActiveToken, insert: string) => void;
}) {
  const [suggestions, setSuggestions] = useState<Suggestion[]>([]);
  const timer = useRef<number | null>(null);
  const requestSeq = useRef(0);

  const key = token === null ? null : `${token.sigil}${token.text.toLowerCase()}`;

  useEffect(() => {
    if (timer.current !== null) window.clearTimeout(timer.current);
    const seq = ++requestSeq.current;
    timer.current = window.setTimeout(
      () => {
        if (key === null) {
          setSuggestions([]);
          onActiveIdChange(null);
          return;
        }
        const sigil = key[0];
        const text = key.slice(1);
        const supabase = createSupabaseBrowserClient();
        if (sigil === "@") {
          void supabase.rpc("search_people", { p_query: text, p_limit: 8 }).then(({ data }) => {
            if (seq !== requestSeq.current) return;
            const rows = [...((data ?? []) as PersonRow[])].sort(
              (a, b) => Number(b.viewer_follows) - Number(a.viewer_follows),
            );
            const next = rows.map(
              (row): Suggestion => ({
                kind: "person",
                id: `ac-p-${row.handle}`,
                userId: row.user_id,
                handle: row.handle,
              }),
            );
            setSuggestions(next);
            onActiveIdChange(next[0]?.id ?? null);
          });
        } else {
          void supabase
            .rpc("search_tags", { p_query: `#${text}`, p_limit: 8 })
            .then(({ data }) => {
              if (seq !== requestSeq.current) return;
              const next = ((data ?? []) as TagSearchRow[]).map(
                (row): Suggestion => ({
                  kind: "tag",
                  id: `ac-t-${row.tag}`,
                  tag: row.tag,
                  postCount: row.post_count,
                }),
              );
              setSuggestions(next);
              onActiveIdChange(next[0]?.id ?? null);
            });
        }
      },
      key === null ? 0 : 300,
    );
    return () => {
      if (timer.current !== null) window.clearTimeout(timer.current);
    };
    // onActiveIdChange is a stable setter from the parent.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  useEffect(() => {
    const field = fieldRef.current;
    if (!field || token === null || suggestions.length === 0) return;
    const onKeyDown = (event: KeyboardEvent) => {
      const index = suggestions.findIndex((s) => s.id === activeId);
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        const delta = event.key === "ArrowDown" ? 1 : -1;
        const next = suggestions[(index + delta + suggestions.length) % suggestions.length];
        onActiveIdChange(next?.id ?? null);
      } else if ((event.key === "Enter" || event.key === "Tab") && index >= 0) {
        event.preventDefault();
        const chosen = suggestions[index];
        if (chosen) {
          onSelect(token, chosen.kind === "person" ? `@${chosen.handle}` : `#${chosen.tag}`);
        }
      } else if (event.key === "Escape") {
        event.stopPropagation();
        onActiveIdChange(null);
        setSuggestions([]);
      }
    };
    field.addEventListener("keydown", onKeyDown);
    return () => field.removeEventListener("keydown", onKeyDown);
  }, [fieldRef, token, suggestions, activeId, onActiveIdChange, onSelect]);

  if (token === null || suggestions.length === 0) return null;

  return (
    <div
      id={listboxId}
      role="listbox"
      aria-label={token.sigil === "@" ? "Mention suggestions" : "Topic suggestions"}
      className="max-h-56 overflow-y-auto rounded-md bg-surface-raised py-1 shadow-e2"
    >
      {suggestions.map((suggestion) => (
        <div
          key={suggestion.id}
          id={suggestion.id}
          role="option"
          aria-selected={suggestion.id === activeId}
          onPointerDown={(event) => {
            // pointerdown, not click: the field must keep focus.
            event.preventDefault();
            onSelect(
              token,
              suggestion.kind === "person" ? `@${suggestion.handle}` : `#${suggestion.tag}`,
            );
          }}
          onPointerEnter={() => onActiveIdChange(suggestion.id)}
          className={`flex min-h-11 cursor-pointer items-center gap-3 px-4 ${
            suggestion.id === activeId ? "bg-accent-subtle" : ""
          }`}
        >
          {suggestion.kind === "person" ? (
            <>
              <Avatar handle={suggestion.handle} size={24} link={false} userId={suggestion.userId} />
              <span className="text-label text-text-primary">@{suggestion.handle}</span>
            </>
          ) : (
            <>
              <span className="text-label text-accent">#{suggestion.tag}</span>
              {suggestion.postCount > 0 ? (
                <span className="text-caption text-text-tertiary">
                  {suggestion.postCount} {suggestion.postCount === 1 ? "post" : "posts"}
                </span>
              ) : null}
            </>
          )}
        </div>
      ))}
    </div>
  );
}
