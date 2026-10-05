"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { PersonRow } from "@/lib/database.types";
import { Avatar } from "@/components/Avatar";
import { Dialog } from "@/components/Dialog";

type Route = "inbox" | "request" | "none";

/**
 * The recipient picker (design §12): @handle search only, honest about
 * where the message will land. "none" is identical for a block, DMs
 * off, and "no one" — the picker can never confirm a block.
 */
export function NewMessageDialog({
  open,
  onClose,
  viewerHandle,
}: {
  open: boolean;
  onClose: () => void;
  viewerHandle: string;
}) {
  return (
    <Dialog open={open} onClose={onClose} label="New message">
      {open ? <PickerBody onClose={onClose} viewerHandle={viewerHandle} /> : null}
    </Dialog>
  );
}

/** Mounted fresh on each open; search runs from the change handler. */
function PickerBody({ onClose, viewerHandle }: { onClose: () => void; viewerHandle: string }) {
  const router = useRouter();
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Array<PersonRow & { route: Route }>>([]);
  const [busy, setBusy] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const seq = useRef(0);

  const onQueryChange = (value: string) => {
    setQuery(value);
    if (timer.current) clearTimeout(timer.current);
    const term = value.trim();
    const mySeq = ++seq.current;
    if (term.length < 2) {
      setResults([]);
      setBusy(false);
      return;
    }
    setBusy(true);
    timer.current = setTimeout(() => {
      void (async () => {
        try {
          const supabase = createSupabaseBrowserClient();
          const { data } = await supabase.rpc("search_people", { p_query: term, p_limit: 8 });
          const people = (data ?? []).filter((p) => p.handle !== viewerHandle);
          const withRoutes = await Promise.all(
            people.map(async (person) => {
              try {
                const response = await fetch(
                  `/api/dm/can-message?userId=${encodeURIComponent(person.user_id)}`,
                );
                const body = (await response.json()) as { ok: boolean; route?: string };
                const route: Route =
                  body.ok && (body.route === "inbox" || body.route === "request")
                    ? body.route
                    : "none";
                return { ...person, route };
              } catch {
                return { ...person, route: "none" as Route };
              }
            }),
          );
          if (seq.current === mySeq) setResults(withRoutes);
        } finally {
          if (seq.current === mySeq) setBusy(false);
        }
      })();
    }, 250);
  };

  return (
    <div className="flex flex-col gap-3 p-4">
      <h2 className="text-heading">New message</h2>
      <input
        data-autofocus
        type="search"
        value={query}
        onChange={(event) => onQueryChange(event.target.value)}
        placeholder="Search by @handle"
        aria-label="Search people by handle"
        className="min-h-11 w-full rounded-md border border-border-strong bg-surface px-3 text-body text-text-primary placeholder:text-text-tertiary"
      />
      {busy && results.length === 0 ? (
        <p className="text-caption text-text-tertiary">Searching…</p>
      ) : null}
      <ul className="flex max-h-80 flex-col overflow-y-auto">
        {results.map((person) => (
          <li key={person.user_id}>
            <button
              type="button"
              disabled={person.route === "none"}
              onClick={() => {
                onClose();
                router.push(`/messages/new/${person.user_id}`);
              }}
              className="flex min-h-14 w-full items-center gap-3 rounded-md px-2 text-left hover:bg-accent-subtle disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:bg-transparent"
            >
              <Avatar handle={person.handle} size={40} link={false} userId={person.user_id} />
              <span className="min-w-0 flex-1">
                <span className="block truncate text-label text-text-primary">
                  @{person.handle}
                </span>
                <span className="block truncate text-caption text-text-tertiary">
                  {person.route === "request"
                    ? "Your message will arrive as a request"
                    : person.route === "none"
                      ? "You can't message this account"
                      : (person.bio ?? "")}
                </span>
              </span>
            </button>
          </li>
        ))}
      </ul>
      {query.trim().length >= 2 && !busy && results.length === 0 ? (
        <p className="text-body text-text-secondary">No one found for that handle.</p>
      ) : null}
    </div>
  );
}
