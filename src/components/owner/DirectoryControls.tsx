"use client";

import { useEffect, useRef, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { MagnifyingGlass } from "@phosphor-icons/react/dist/ssr";
import type { DirectoryView } from "@/lib/directory";
import { ACTIVITY_OPTIONS, JOINED_OPTIONS, STATUS_OPTIONS, DEFAULT_STATUSES } from "@/lib/directory";

/**
 * The directory's search field and filter bar (Phase 2D spec §4.1,
 * §4.2). The URL is the source of truth: every change is written to
 * the search params, so the server re-renders the list and a scoped
 * view ("all suspended accounts") survives a refresh.
 *
 * Search is exact-and-prefix @handle only — the locked people-search
 * rule. It never searches legal names, emails, or bios; those are not
 * in this surface's reach at all.
 */
export function DirectoryControls({ view }: { view: DirectoryView }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [query, setQuery] = useState(view.query);
  const debounce = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (debounce.current) clearTimeout(debounce.current);
    };
  }, []);

  const replaceParams = (mutate: (params: URLSearchParams) => void) => {
    const params = new URLSearchParams(searchParams.toString());
    mutate(params);
    const qs = params.toString();
    router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false });
  };

  const onQueryChange = (value: string) => {
    setQuery(value);
    if (debounce.current) clearTimeout(debounce.current);
    debounce.current = setTimeout(() => {
      replaceParams((params) => {
        if (value.trim()) params.set("q", value.trim());
        else params.delete("q");
      });
    }, 300);
  };

  const selectedStatuses = view.statuses.length > 0 ? view.statuses : [...DEFAULT_STATUSES];

  const toggleStatus = (status: string) => {
    const next = selectedStatuses.includes(status as (typeof selectedStatuses)[number])
      ? selectedStatuses.filter((s) => s !== status)
      : [...selectedStatuses, status];
    replaceParams((params) => {
      const isDefault =
        next.length === DEFAULT_STATUSES.length && DEFAULT_STATUSES.every((s) => next.includes(s));
      if (isDefault || next.length === 0) params.delete("status");
      else params.set("status", next.join(","));
    });
  };

  const toggleActivity = (value: string) => {
    const next = view.activity.includes(value)
      ? view.activity.filter((a) => a !== value)
      : [...view.activity, value];
    replaceParams((params) => {
      if (next.length > 0) params.set("activity", next.join(","));
      else params.delete("activity");
    });
  };

  const toggleJoined = (value: string) => {
    replaceParams((params) => {
      if (view.joined === value) params.delete("joined");
      else params.set("joined", value);
    });
  };

  const toggleStaff = () => {
    replaceParams((params) => {
      if (view.staffOnly) params.delete("staff");
      else params.set("staff", "1");
    });
  };

  return (
    <div className="flex flex-col gap-3">
      <div className="relative">
        <MagnifyingGlass
          size={18}
          aria-hidden
          className="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-text-tertiary"
        />
        <input
          type="search"
          value={query}
          onChange={(event) => onQueryChange(event.target.value)}
          aria-label="Find a member by @handle"
          placeholder="Find a member by @handle"
          autoComplete="off"
          spellCheck={false}
          className="min-h-11 w-full rounded-md border border-border-strong bg-surface-raised pl-10 pr-3 text-body text-text-primary placeholder:text-text-tertiary focus-visible:outline-2 focus-visible:outline-focus-ring"
        />
      </div>

      <fieldset className="flex flex-wrap items-center gap-1.5">
        <legend className="sr-only">Filter by account status</legend>
        <span aria-hidden className="text-caption text-text-tertiary">
          Status
        </span>
        {STATUS_OPTIONS.map((option) => (
          <FilterPill
            key={option.value}
            label={option.label}
            pressed={selectedStatuses.includes(option.value)}
            onToggle={() => toggleStatus(option.value)}
          />
        ))}
      </fieldset>

      <fieldset className="flex flex-wrap items-center gap-1.5">
        <legend className="sr-only">Filter by role, join date, and activity</legend>
        <FilterPill label="Staff only" pressed={view.staffOnly} onToggle={toggleStaff} />
        {JOINED_OPTIONS.map((option) => (
          <FilterPill
            key={option.value}
            label={option.label}
            pressed={view.joined === option.value}
            onToggle={() => toggleJoined(option.value)}
          />
        ))}
        <span aria-hidden className="text-caption text-text-tertiary">
          · Activity
        </span>
        {ACTIVITY_OPTIONS.map((option) => (
          <FilterPill
            key={option.value}
            label={option.label}
            pressed={view.activity.includes(option.value)}
            onToggle={() => toggleActivity(option.value)}
          />
        ))}
      </fieldset>
    </div>
  );
}

function FilterPill({
  label,
  pressed,
  onToggle,
}: {
  label: string;
  pressed: boolean;
  onToggle: () => void;
}) {
  return (
    <button
      type="button"
      aria-pressed={pressed}
      onClick={onToggle}
      className={`inline-flex min-h-9 items-center rounded-full border px-3 text-caption transition-colors duration-(--duration-fast) ${
        pressed
          ? "border-accent bg-accent-subtle text-accent"
          : "border-border bg-surface text-text-secondary hover:bg-surface-raised"
      }`}
    >
      {label}
    </button>
  );
}
