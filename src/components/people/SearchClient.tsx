"use client";

import { useRef, useState, type ReactNode } from "react";
import Link from "next/link";
import { MagnifyingGlass } from "@phosphor-icons/react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type {
  PersonRow as PersonRowType,
  TagSearchRow,
  TrendingTagRow,
} from "@/lib/database.types";
import { PersonRow } from "@/components/people/PersonRow";
import { TrendingModule } from "@/components/tags/TrendingModule";

type Results =
  | { axis: "people"; people: PersonRowType[] }
  | { axis: "tags"; tags: TagSearchRow[] };

/**
 * Search (spec §9.4 + Phase 2F §5): one box, two axes. A query that
 * begins with '#' searches the canonical tag index (prefix match); any
 * other query matches @handles only, exactly as before. The two axes
 * never mix: people are never found by topic, topics never by handle,
 * and people search never touches a legal name. The pre-query screen
 * carries the Trending module so topics are discoverable without
 * knowing to type '#'.
 */
export function SearchClient({ trending }: { trending: TrendingTagRow[] }) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Results | null>(null);
  const [searching, setSearching] = useState(false);
  const timer = useRef<number | null>(null);
  const requestSeq = useRef(0);

  const onQueryChange = (value: string) => {
    setQuery(value);
    if (timer.current !== null) window.clearTimeout(timer.current);
    const term = value.trim();
    const seq = ++requestSeq.current;
    if (term === "") {
      setResults(null);
      setSearching(false);
      return;
    }
    setSearching(true);
    timer.current = window.setTimeout(() => {
      const supabase = createSupabaseBrowserClient();
      if (term.startsWith("#")) {
        void supabase.rpc("search_tags", { p_query: term, p_limit: 30 }).then(({ data }) => {
          if (seq !== requestSeq.current) return; // a newer query superseded this one
          setResults({ axis: "tags", tags: data ?? [] });
          setSearching(false);
        });
      } else {
        void supabase.rpc("search_people", { p_query: term, p_limit: 30 }).then(({ data }) => {
          if (seq !== requestSeq.current) return;
          setResults({ axis: "people", people: data ?? [] });
          setSearching(false);
        });
      }
    }, 300);
  };

  let body: ReactNode;
  if (results === null) {
    body = (
      <div className="flex flex-col items-center gap-6 px-6 py-10 text-center">
        <div className="flex flex-col items-center gap-2">
          <MagnifyingGlass size={48} aria-hidden className="text-text-tertiary" />
          <h2 className="text-title text-text-primary">Find your people</h2>
          <p className="text-body text-text-secondary">
            Search by @handle, or type # to find a topic.
          </p>
        </div>
        <div className="w-full max-w-sm">
          <TrendingModule rows={trending} />
        </div>
      </div>
    );
  } else if (searching) {
    body = (
      <div className="flex flex-col gap-3 p-4" aria-label="Searching">
        {[0, 1, 2].map((i) => (
          <div key={i} className="flex items-center gap-3">
            <span className="skeleton size-10 rounded-full" />
            <span className="skeleton h-4 w-40" />
          </div>
        ))}
      </div>
    );
  } else if (results.axis === "tags") {
    body =
      results.tags.length === 0 ? (
        <div className="flex flex-col items-center gap-2 px-6 py-16 text-center">
          <h2 className="text-title text-text-primary">
            No topics matching &ldquo;{query.trim()}&rdquo;
          </h2>
          <p className="text-body text-text-secondary">
            Use the tag in a post and it becomes a topic.
          </p>
        </div>
      ) : (
        <div className="flex flex-col" aria-live="polite">
          {results.tags.map((row) => (
            <Link
              key={row.tag}
              href={`/t/${encodeURIComponent(row.tag)}`}
              aria-label={`hashtag ${row.tag}, ${row.post_count} ${row.post_count === 1 ? "post" : "posts"}`}
              className="flex min-h-11 items-center justify-between border-b border-border bg-surface px-4 py-3 transition-colors duration-(--duration-fast) hover:bg-surface-raised"
            >
              <span className="text-label text-accent">#{row.tag}</span>
              <span className="text-caption text-text-tertiary">
                {row.post_count} {row.post_count === 1 ? "post" : "posts"}
              </span>
            </Link>
          ))}
        </div>
      );
  } else {
    body =
      results.people.length === 0 ? (
        <div className="flex flex-col items-center gap-2 px-6 py-16 text-center">
          <h2 className="text-title text-text-primary">
            No matches for &ldquo;{query.trim()}&rdquo;
          </h2>
          <p className="text-body text-text-secondary">
            Check the spelling, or try a different handle.
          </p>
        </div>
      ) : (
        <div className="flex flex-col" aria-live="polite">
          {results.people.map((person) => (
            <PersonRow key={person.user_id} person={person} />
          ))}
        </div>
      );
  }

  return (
    <div className="flex flex-col">
      <div className="border-b border-border bg-surface p-4">
        <label className="flex min-h-11 items-center gap-2 rounded-full border border-border-strong bg-surface-raised px-4">
          <MagnifyingGlass size={20} aria-hidden className="text-text-tertiary" />
          <input
            type="search"
            value={query}
            onChange={(event) => onQueryChange(event.target.value)}
            placeholder="Search @handle or #topic"
            aria-label="Search people by handle or topics by hashtag"
            className="w-full bg-transparent text-body text-text-primary outline-none placeholder:text-text-tertiary"
          />
        </label>
      </div>
      {body}
    </div>
  );
}
