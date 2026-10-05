"use client";

import { useRef, useState } from "react";
import { MagnifyingGlass } from "@phosphor-icons/react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { PersonRow as PersonRowType } from "@/lib/database.types";
import { PersonRow } from "@/components/people/PersonRow";

/**
 * People search (spec §9.4). Matches handles only: profiles are found
 * by @handle, never by a legal name, consistent with the identity rule.
 */
export function SearchClient() {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<PersonRowType[] | null>(null);
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
      void supabase.rpc("search_people", { p_query: term, p_limit: 30 }).then(({ data }) => {
        if (seq !== requestSeq.current) return; // a newer query superseded this one
        setResults(data ?? []);
        setSearching(false);
      });
    }, 300);
  };

  return (
    <div className="flex flex-col">
      <div className="border-b border-border bg-surface p-4">
        <label className="flex min-h-11 items-center gap-2 rounded-full border border-border-strong bg-surface-raised px-4">
          <MagnifyingGlass size={20} aria-hidden className="text-text-tertiary" />
          <input
            type="search"
            value={query}
            onChange={(event) => onQueryChange(event.target.value)}
            placeholder="Search by @handle"
            aria-label="Search people by handle"
            className="w-full bg-transparent text-body text-text-primary outline-none placeholder:text-text-tertiary"
          />
        </label>
      </div>

      {results === null ? (
        <div className="flex flex-col items-center gap-2 px-6 py-16 text-center">
          <MagnifyingGlass size={48} aria-hidden className="text-text-tertiary" />
          <h2 className="text-title text-text-primary">Find your people</h2>
          <p className="text-body text-text-secondary">Search by @handle.</p>
        </div>
      ) : searching ? (
        <div className="flex flex-col gap-3 p-4" aria-label="Searching">
          {[0, 1, 2].map((i) => (
            <div key={i} className="flex items-center gap-3">
              <span className="skeleton size-10 rounded-full" />
              <span className="skeleton h-4 w-40" />
            </div>
          ))}
        </div>
      ) : results.length === 0 ? (
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
          {results.map((person) => (
            <PersonRow key={person.user_id} person={person} />
          ))}
        </div>
      )}
    </div>
  );
}
