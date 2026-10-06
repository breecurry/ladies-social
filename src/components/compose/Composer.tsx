"use client";

import { useCallback, useEffect, useId, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Globe, Users, At, CaretDown, CaretUp, Plus, X } from "@phosphor-icons/react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { ReplyControl } from "@/lib/database.types";
import { codePointLength, splitForThread, PART_CAP, PART_LIMIT } from "@/lib/text";
import { Button } from "@/components/ui";
import { useToast } from "@/components/shell/ToastProvider";
import type { ComposeDraft } from "@/components/shell/ComposeProvider";
import {
  ComposerAutocomplete,
  activeTokenAt,
  type ActiveToken,
} from "@/components/compose/ComposerAutocomplete";

export interface ReplyTarget {
  id: number;
  handle: string;
  excerpt: string;
  replyControl: ReplyControl;
}

/** The post being quoted when the composer opens in quote mode. */
export interface QuoteTarget {
  id: number;
  handle: string;
  excerpt: string;
}

const LIMIT = PART_LIMIT;
const SOFT_BAND = 60;

const AUDIENCE: Array<{ value: ReplyControl; label: string }> = [
  { value: "everyone", label: "Everyone can reply" },
  { value: "followed", label: "People you follow can reply" },
  { value: "mentioned", label: "Only mentioned people can reply" },
];

function audienceLabel(value: ReplyControl): string {
  return AUDIENCE.find((a) => a.value === value)?.label ?? "Everyone can reply";
}

function AudienceIcon({ value, size = 16 }: { value: ReplyControl; size?: number }) {
  if (value === "followed") return <Users size={size} aria-hidden />;
  if (value === "mentioned") return <At size={size} aria-hidden />;
  return <Globe size={size} aria-hidden />;
}

/**
 * Feature probe for multi-part threads: the composer must never offer
 * what the database cannot yet do (code deploys before the migration
 * applies). chain_head() ships with migration 20261024000001; a cheap
 * call tells us whether it exists. A positive result is cached for the
 * page's life; a negative one is retried on the next composer mount so
 * a transient network error does not hide the feature all session.
 */
let multiPartProbe: Promise<boolean> | null = null;
function probeMultiPart(): Promise<boolean> {
  multiPartProbe ??= (async () => {
    try {
      const supabase = createSupabaseBrowserClient();
      const { error } = await supabase.rpc("chain_head", { p_post: 0 });
      if (error) multiPartProbe = null;
      return !error;
    } catch {
      multiPartProbe = null;
      return false;
    }
  })();
  return multiPartProbe;
}

/** Below lg the composer collapses unfocused parts to chips and docks
 *  the key actions above the keyboard (design §9). */
function useIsDesktop(): boolean {
  const [isDesktop, setIsDesktop] = useState(
    () => typeof window !== "undefined" && window.matchMedia("(min-width: 1024px)").matches,
  );
  useEffect(() => {
    const query = window.matchMedia("(min-width: 1024px)");
    const onChange = () => setIsDesktop(query.matches);
    query.addEventListener("change", onChange);
    return () => query.removeEventListener("change", onChange);
  }, []);
  return isDesktop;
}

/** Trailing empty parts are dropped silently at publish (design §7);
 *  what remains is what will actually post. */
function effectiveParts(parts: string[]): string[] {
  let end = parts.length;
  while (end > 1 && (parts[end - 1] ?? "").trim().length === 0) end--;
  return parts.slice(0, end);
}

/**
 * The post composer: one component for new posts, replies, and
 * quote-posts. A fresh draft is one part and renders exactly as the
 * single composer always has; "Add to thread" (the multi-part threads
 * design, Part 1) turns it into a connected stack of parts, each its
 * own post of up to 500 characters, published atomically as one chain.
 * Replies stay single-part: a chain starts at a top-level post by
 * definition (design §10).
 */
export function Composer({
  viewerHandle,
  replyTo,
  quote,
  draft,
  onDraftChange,
  onClose,
  onPosted,
}: {
  viewerHandle: string;
  replyTo?: ReplyTarget;
  quote?: QuoteTarget;
  draft: ComposeDraft;
  onDraftChange: (value: ComposeDraft) => void;
  onClose: () => void;
  onPosted: () => void;
}) {
  const router = useRouter();
  const { showToast } = useToast();
  const isDesktop = useIsDesktop();
  const [audienceOpen, setAudienceOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [focusedIndex, setFocusedIndex] = useState(0);
  const [multiPartOk, setMultiPartOk] = useState(false);
  const [announcement, setAnnouncement] = useState("");
  const fieldRefs = useRef(new Map<number, HTMLTextAreaElement>());
  /** The focused part's field, for the shared autocomplete listbox. */
  const activeFieldRef = useRef<HTMLTextAreaElement | null>(null);
  /** One idempotency key per publish attempt: minted at the first Post
   *  tap, kept for retries of that same attempt, discarded the moment
   *  the draft changes — so a retry can never double-post and an edit
   *  always posts fresh (design §14). */
  const idemKeyRef = useRef<string | null>(null);

  const parts = draft.parts;
  const audience = draft.audience;
  const multiPart = parts.length > 1;
  const canThread = multiPartOk && !replyTo;

  useEffect(() => {
    let active = true;
    void probeMultiPart().then((ok) => {
      if (active) setMultiPartOk(ok);
    });
    return () => {
      active = false;
    };
  }, []);

  // Mention/hashtag autocomplete (Phase 2F §9) follows the focused part.
  const [token, setToken] = useState<ActiveToken | null>(null);
  const [activeOptionId, setActiveOptionId] = useState<string | null>(null);
  const listboxId = useId();
  const reasonId = useId();

  const syncToken = useCallback((value: string, caret: number | null) => {
    setToken(caret === null ? null : activeTokenAt(value, caret));
  }, []);

  const setParts = useCallback(
    (next: string[]) => {
      idemKeyRef.current = null;
      onDraftChange({ parts: next, audience });
    },
    [onDraftChange, audience],
  );

  const setAudience = useCallback(
    (next: ReplyControl) => {
      idemKeyRef.current = null;
      onDraftChange({ parts, audience: next });
    },
    [onDraftChange, parts],
  );

  const focusPart = useCallback((index: number, caret?: number) => {
    setFocusedIndex(index);
    requestAnimationFrame(() => {
      const field = fieldRefs.current.get(index);
      if (!field) return;
      field.focus();
      if (caret !== undefined) field.setSelectionRange(caret, caret);
      field.scrollIntoView({ block: "center", behavior: "auto" });
    });
  }, []);

  const addPart = useCallback(() => {
    if (!canThread || parts.length >= PART_CAP) return;
    const next = [...parts, ""];
    setParts(next);
    setAnnouncement(`Part added, ${next.length} parts total`);
    focusPart(next.length - 1);
  }, [canThread, parts, setParts, focusPart]);

  const removePart = useCallback(
    (index: number) => {
      if (parts.length <= 1) return;
      const removed = parts[index] ?? "";
      const next = parts.filter((_, i) => i !== index);
      setParts(next);
      setAnnouncement(`Part removed, ${next.length === 1 ? "1 part" : `${next.length} parts`} total`);
      focusPart(Math.min(index, next.length - 1));
      if (removed.trim().length > 0) {
        const snapshot = parts;
        showToast("Part removed.", {
          actionLabel: "Undo",
          onAction: () => {
            setParts(snapshot);
            focusPart(index);
          },
          durationMs: 6000,
        });
      }
    },
    [parts, setParts, focusPart, showToast],
  );

  const movePart = useCallback(
    (index: number, delta: -1 | 1) => {
      const target = index + delta;
      if (target < 0 || target >= parts.length) return;
      const next = [...parts];
      const a = next[index] ?? "";
      next[index] = next[target] ?? "";
      next[target] = a;
      setParts(next);
      setAnnouncement(
        `Part ${index + 1} moved ${delta < 0 ? "up" : "down"}, now part ${target + 1}`,
      );
      focusPart(target);
    },
    [parts, setParts, focusPart],
  );

  const handleChange = useCallback(
    (index: number, value: string, caret: number | null) => {
      const previous = parts[index] ?? "";
      const nextLength = codePointLength(value);
      if (nextLength <= LIMIT) {
        const next = [...parts];
        next[index] = value;
        setParts(next);
        syncToken(value, caret);
        return;
      }
      // Over the limit. A single typed character is simply not
      // inserted (design §3); a larger insert — a paste — auto-flows
      // into connected parts with one Undo (design §6).
      if (!canThread || nextLength - codePointLength(previous) <= 1) return;
      const snapshot = parts;
      const room = PART_CAP - (parts.length - 1);
      const { parts: pieces, hardBreak, overCap } = splitForThread(value, LIMIT, room);
      const next = [...parts.slice(0, index), ...pieces, ...parts.slice(index + 1)];
      setParts(next);
      setToken(null);
      setAnnouncement(`Pasted text added as ${pieces.length} parts, ${next.length} parts total`);
      let message =
        pieces.length === 1
          ? "That is too long for this thread."
          : `Added as ${pieces.length} parts.`;
      if (overCap && pieces.length > 1)
        message = `Added as ${pieces.length} parts. The rest is too long for this thread.`;
      if (hardBreak) message += " One long stretch did not fit in a single post and was split.";
      showToast(message, {
        actionLabel: "Undo",
        onAction: () => {
          setParts(snapshot);
          focusPart(index);
        },
        durationMs: 8000,
      });
    },
    [parts, canThread, setParts, syncToken, showToast, focusPart],
  );

  const insertCompletion = useCallback(
    (target: ActiveToken, insert: string) => {
      const field = activeFieldRef.current;
      const current = field?.value ?? "";
      const next = `${current.slice(0, target.start)}${insert} ${current.slice(target.end)}`;
      const updated = [...parts];
      updated[focusedIndex] = next;
      setParts(updated);
      setToken(null);
      setActiveOptionId(null);
      if (field) {
        const caret = target.start + insert.length + 1;
        requestAnimationFrame(() => {
          field.focus();
          field.setSelectionRange(caret, caret);
        });
      }
    },
    [parts, focusedIndex, setParts],
  );

  // ----- publish state -----
  const effective = effectiveParts(parts);
  const allEmpty = effective.every((part) => part.trim().length === 0);
  const interiorEmpty = effective.some((part) => part.trim().length === 0) && !allEmpty;
  const overLimit = parts.some((part) => codePointLength(part) > LIMIT);
  const disabledReason = allEmpty
    ? "Add something to post"
    : interiorEmpty
      ? "Fill or remove the empty part"
      : overLimit
        ? "One part is over the limit"
        : null;
  const postLabel = effective.length > 1 ? `Post all ${effective.length}` : "Post";
  /** The blank-composer "Add something to post" state matches the old
   *  silent disable; the other reasons are shown and read aloud. */
  const showReason = disabledReason !== null && !allEmpty;

  const post = async () => {
    if (disabledReason || busy) return;
    setBusy(true);
    setError(null);
    const supabase = createSupabaseBrowserClient();
    if (effective.length === 1) {
      const { error: rpcError } = await supabase.rpc("create_post", {
        p_body: effective[0] ?? "",
        p_parent: replyTo?.id ?? null,
        p_reply_control: replyTo ? "everyone" : audience,
        p_quote: quote?.id ?? null,
      });
      setBusy(false);
      if (rpcError) {
        setError(rpcError.message);
        return;
      }
      onPosted();
      showToast(replyTo ? "Reply posted" : "Posted");
      router.refresh();
      return;
    }
    // Multi-part: atomic, never optimistically closed (design §14).
    idemKeyRef.current ??= crypto.randomUUID();
    const { error: rpcError } = await supabase.rpc("create_thread", {
      p_bodies: effective,
      p_reply_control: audience,
      p_quote: quote?.id ?? null,
      p_key: idemKeyRef.current,
    });
    setBusy(false);
    if (rpcError) {
      setError("Could not post your thread. Nothing was posted, so your draft is safe. Try again.");
      return;
    }
    idemKeyRef.current = null;
    onPosted();
    showToast("Thread posted");
    router.refresh();
  };

  const atCap = parts.length >= PART_CAP;
  const focusedRemaining = LIMIT - codePointLength(parts[focusedIndex] ?? "");

  const addToThreadButton = (compact: boolean) => (
    <button
      type="button"
      onClick={addPart}
      disabled={atCap}
      aria-label={
        atCap ? `This thread is at its limit of ${PART_CAP} parts` : "Add to thread"
      }
      title={atCap ? `This thread is at its limit of ${PART_CAP} parts` : undefined}
      className={`flex min-h-11 items-center gap-2 rounded-md text-label text-accent hover:bg-accent-subtle disabled:opacity-50 disabled:hover:bg-transparent ${
        compact ? "px-3" : "w-full px-2 text-left"
      }`}
    >
      <Plus size={18} aria-hidden />
      Add to thread
    </button>
  );

  return (
    <div className="flex flex-col gap-3 p-4">
      <p aria-live="polite" className="sr-only">
        {announcement}
      </p>

      <div className="flex items-center justify-between">
        <button
          type="button"
          aria-label="Close composer"
          onClick={onClose}
          className="flex min-h-11 min-w-11 items-center justify-center rounded-md text-text-secondary hover:bg-surface hover:text-text-primary"
        >
          ✕
        </button>
        <h2 className="text-heading">{replyTo ? "Reply" : quote ? "Quote" : "New post"}</h2>
        <Button
          onClick={() => void post()}
          disabled={disabledReason !== null || busy}
          aria-describedby={showReason ? reasonId : undefined}
          className={multiPart ? "hidden lg:inline-flex" : ""}
        >
          {busy ? "Posting…" : postLabel}
        </Button>
      </div>

      {showReason ? (
        <p id={reasonId} className="text-right text-caption text-text-tertiary">
          {disabledReason}
        </p>
      ) : null}

      {replyTo ? (
        <p className="text-caption text-text-tertiary">
          Replying to @{replyTo.handle}: {replyTo.excerpt}
        </p>
      ) : null}

      {quote ? (
        <div className="rounded-md border border-border bg-background px-3 py-2">
          <p className="text-caption text-text-tertiary">@{quote.handle}</p>
          <p className="line-clamp-3 whitespace-pre-wrap break-words text-body text-text-secondary">
            {quote.excerpt}
          </p>
        </div>
      ) : null}

      <div className="flex flex-col">
        {parts.map((part, index) => {
          const collapsed = multiPart && !isDesktop && index !== focusedIndex;
          return collapsed ? (
            <PartChip
              key={index}
              index={index}
              total={parts.length}
              text={part}
              onExpand={() => focusPart(index)}
              onMove={(delta) => movePart(index, delta)}
              onRemove={() => removePart(index)}
            />
          ) : (
            <PartField
              key={index}
              index={index}
              total={parts.length}
              text={part}
              viewerHandle={viewerHandle}
              replyTo={replyTo}
              canThread={canThread}
              atCap={atCap}
              listboxId={listboxId}
              tokenOpen={token !== null && index === focusedIndex}
              activeOptionId={activeOptionId}
              registerField={(el) => {
                if (el) fieldRefs.current.set(index, el);
                else fieldRefs.current.delete(index);
              }}
              onFocusPart={(el) => {
                activeFieldRef.current = el;
                setFocusedIndex(index);
              }}
              onChange={(value, caret) => handleChange(index, value, caret)}
              onSelectEvent={(value, caret) => syncToken(value, caret)}
              onBlurField={() => {
                setToken(null);
                setActiveOptionId(null);
              }}
              onMove={(delta) => movePart(index, delta)}
              onRemove={() => removePart(index)}
              onAddPart={addPart}
            />
          );
        })}
      </div>

      {canThread ? addToThreadButton(false) : null}

      <ComposerAutocomplete
        token={token}
        fieldRef={activeFieldRef}
        listboxId={listboxId}
        activeId={activeOptionId}
        onActiveIdChange={setActiveOptionId}
        onSelect={insertCompletion}
      />

      {error ? (
        <p role="alert" className="text-caption text-danger">
          {error}
        </p>
      ) : null}

      <div className="flex items-center justify-between border-t border-border pt-3">
        {replyTo ? (
          <span className="inline-flex items-center gap-1.5 text-caption text-text-tertiary">
            <AudienceIcon value={replyTo.replyControl} />
            {replyTo.replyControl === "everyone"
              ? "Everyone can reply"
              : replyTo.replyControl === "followed"
                ? `People @${replyTo.handle} follows can reply`
                : "Only mentioned people can reply"}
          </span>
        ) : (
          <div className="relative">
            <button
              type="button"
              aria-haspopup="menu"
              aria-expanded={audienceOpen}
              onClick={() => setAudienceOpen((v) => !v)}
              className={`inline-flex min-h-11 items-center gap-1.5 rounded-full px-3 text-label ${
                audience === "everyone"
                  ? "text-text-secondary hover:bg-surface"
                  : "bg-accent-subtle text-accent"
              }`}
            >
              <AudienceIcon value={audience} />
              {audienceLabel(audience)}
              <CaretDown size={12} aria-hidden />
            </button>
            {audienceOpen ? (
              <div
                role="menu"
                aria-label="Who can reply"
                className="absolute bottom-full left-0 z-10 mb-1 min-w-60 rounded-md bg-surface-raised py-2 shadow-e2"
              >
                {AUDIENCE.map((option) => (
                  <button
                    key={option.value}
                    type="button"
                    role="menuitem"
                    onClick={() => {
                      setAudience(option.value);
                      setAudienceOpen(false);
                      fieldRefs.current.get(focusedIndex)?.focus();
                    }}
                    className="flex min-h-11 w-full items-center gap-3 px-4 text-left text-body text-text-primary hover:bg-accent-subtle"
                  >
                    <AudienceIcon value={option.value} size={20} />
                    {option.label}
                  </button>
                ))}
              </div>
            ) : null}
          </div>
        )}
        {!multiPart && focusedRemaining <= SOFT_BAND ? (
          <span
            aria-live="polite"
            className={`text-caption ${focusedRemaining <= 0 ? "text-danger" : "text-warning"}`}
          >
            {focusedRemaining}
          </span>
        ) : null}
      </div>

      {multiPart ? (
        <div className="sticky bottom-0 -mx-4 -mb-4 flex items-center justify-between gap-2 border-t border-border bg-surface-raised px-4 py-2 shadow-sticky lg:hidden">
          {addToThreadButton(true)}
          <div className="flex items-center gap-3">
            {focusedRemaining <= SOFT_BAND ? (
              <span
                aria-live="polite"
                className={`text-caption ${focusedRemaining <= 0 ? "text-danger" : "text-warning"}`}
              >
                {focusedRemaining}
              </span>
            ) : null}
            <Button
              onClick={() => void post()}
              disabled={disabledReason !== null || busy}
              aria-describedby={showReason ? reasonId : undefined}
            >
              {busy ? "Posting…" : postLabel}
            </Button>
          </div>
        </div>
      ) : null}
    </div>
  );
}

/**
 * One expanded part: the avatar (part 1) or connector column, the
 * field, and — once the draft has two or more parts — the caption row
 * with "Part k of N", reorder, remove, and the per-part late-reveal
 * counter (design §1-§5).
 */
function PartField({
  index,
  total,
  text,
  viewerHandle,
  replyTo,
  canThread,
  atCap,
  listboxId,
  tokenOpen,
  activeOptionId,
  registerField,
  onFocusPart,
  onChange,
  onSelectEvent,
  onBlurField,
  onMove,
  onRemove,
  onAddPart,
}: {
  index: number;
  total: number;
  text: string;
  viewerHandle: string;
  replyTo?: ReplyTarget;
  canThread: boolean;
  atCap: boolean;
  listboxId: string;
  tokenOpen: boolean;
  activeOptionId: string | null;
  registerField: (el: HTMLTextAreaElement | null) => void;
  onFocusPart: (el: HTMLTextAreaElement) => void;
  onChange: (value: string, caret: number | null) => void;
  onSelectEvent: (value: string, caret: number | null) => void;
  onBlurField: () => void;
  onMove: (delta: -1 | 1) => void;
  onRemove: () => void;
  onAddPart: () => void;
}) {
  const multiPart = total > 1;
  const remaining = LIMIT - codePointLength(text);
  const full = remaining <= 0;
  const emptyInterior = multiPart && text.trim().length === 0 && index < total - 1;

  return (
    <div className="flex gap-3">
      {/* Avatar on part 1; the thread-rail connector joins the stack
          (decorative — the caption carries the meaning). */}
      <div aria-hidden className="flex w-10 shrink-0 flex-col items-center">
        {index === 0 ? (
          <span className="inline-flex size-10 shrink-0 items-center justify-center rounded-full bg-accent-subtle text-body font-semibold text-accent">
            {viewerHandle.charAt(0).toUpperCase()}
          </span>
        ) : null}
        {multiPart && index < total - 1 ? (
          <span className="w-0.5 flex-1 bg-thread-rail" />
        ) : multiPart && index > 0 ? (
          <span className="h-5 w-0.5 bg-thread-rail" />
        ) : null}
      </div>
      <div className="flex min-w-0 flex-1 flex-col">
        <textarea
          ref={registerField}
          data-autofocus={index === 0 ? true : undefined}
          value={text}
          // In single-part mode (and for replies) the browser cap is
          // the old behavior; multi-part needs the raw paste so the
          // splitter can flow it (maxLength would truncate it first).
          maxLength={canThread ? undefined : LIMIT}
          onChange={(event) => onChange(event.target.value, event.target.selectionStart)}
          onSelect={(event) =>
            onSelectEvent(event.currentTarget.value, event.currentTarget.selectionStart)
          }
          onFocus={(event) => onFocusPart(event.currentTarget)}
          onBlur={onBlurField}
          role="combobox"
          aria-expanded={tokenOpen}
          aria-controls={listboxId}
          aria-activedescendant={tokenOpen ? (activeOptionId ?? undefined) : undefined}
          aria-autocomplete="list"
          placeholder={
            replyTo
              ? `Reply to @${replyTo.handle}`
              : index === 0
                ? "Share something with the community"
                : "Keep writing…"
          }
          aria-label={
            replyTo
              ? `Reply to @${replyTo.handle}`
              : multiPart
                ? `Part ${index + 1} of ${total}`
                : "New post"
          }
          rows={multiPart ? 3 : 4}
          className={`w-full resize-none bg-transparent text-body-lg text-text-primary outline-none placeholder:text-text-tertiary ${
            multiPart ? "min-h-20" : "min-h-28"
          }`}
        />
        {full ? (
          <p className="text-caption text-danger">
            This part is full.{" "}
            {canThread && !atCap ? (
              <button type="button" onClick={onAddPart} className="text-accent hover:underline">
                Add another part
              </button>
            ) : null}
            {canThread && !atCap ? " to keep writing." : ""}
          </p>
        ) : null}
        {emptyInterior ? (
          <p className="text-caption text-warning">This part is empty. Add something, or remove it.</p>
        ) : null}
        {multiPart ? (
          <div className="flex items-center gap-1">
            <span className="mr-auto text-caption text-text-tertiary">
              Part {index + 1} of {total}
            </span>
            {remaining <= SOFT_BAND ? (
              <span
                aria-live="polite"
                className={`px-1 text-caption ${remaining <= 0 ? "text-danger" : "text-warning"}`}
              >
                {remaining}
              </span>
            ) : null}
            <PartControls
              index={index}
              total={total}
              onMove={onMove}
              onRemove={onRemove}
            />
          </div>
        ) : null}
      </div>
    </div>
  );
}

/** Reorder and remove, 44px targets, explicit accessible names
 *  (design §5.2, §5.3, §19). Buttons are the canonical reorder
 *  mechanism — fully keyboard and screen-reader operable. */
function PartControls({
  index,
  total,
  onMove,
  onRemove,
}: {
  index: number;
  total: number;
  onMove: (delta: -1 | 1) => void;
  onRemove: () => void;
}) {
  const controlClass =
    "flex min-h-11 min-w-11 items-center justify-center rounded-md text-text-secondary hover:bg-surface hover:text-text-primary disabled:opacity-40 disabled:hover:bg-transparent";
  return (
    <>
      <button
        type="button"
        aria-label={`Move part ${index + 1} up`}
        disabled={index === 0}
        onClick={() => onMove(-1)}
        className={controlClass}
      >
        <CaretUp size={16} aria-hidden />
      </button>
      <button
        type="button"
        aria-label={`Move part ${index + 1} down`}
        disabled={index === total - 1}
        onClick={() => onMove(1)}
        className={controlClass}
      >
        <CaretDown size={16} aria-hidden />
      </button>
      <button
        type="button"
        aria-label={`Remove part ${index + 1}`}
        onClick={onRemove}
        className={controlClass}
      >
        <X size={16} aria-hidden />
      </button>
    </>
  );
}

/**
 * The collapsed summary chip (design §9.3): on a phone, only the
 * focused part is full height; the rest show their position, a line
 * of text, a full marker, and their controls. Tapping the summary
 * expands the part and collapses whichever was focused.
 */
function PartChip({
  index,
  total,
  text,
  onExpand,
  onMove,
  onRemove,
}: {
  index: number;
  total: number;
  text: string;
  onExpand: () => void;
  onMove: (delta: -1 | 1) => void;
  onRemove: () => void;
}) {
  const full = codePointLength(text) >= LIMIT;
  const preview = text.trim().length === 0 ? "Empty" : text;
  return (
    <div className="flex gap-3">
      <div aria-hidden className="flex w-10 shrink-0 justify-center">
        <span className="w-0.5 self-stretch bg-thread-rail" />
      </div>
      <div className="flex min-w-0 flex-1 items-center gap-1 border-b border-border py-1">
        <button
          type="button"
          onClick={onExpand}
          aria-label={`Edit part ${index + 1} of ${total}${full ? ", full" : ""}`}
          className="flex min-h-11 min-w-0 flex-1 flex-col justify-center rounded-md px-1 text-left hover:bg-surface"
        >
          <span className="text-caption text-text-tertiary">
            Part {index + 1} of {total}
            {full ? " · full" : ""}
          </span>
          <span className="truncate text-body text-text-secondary">{preview}</span>
        </button>
        <PartControls index={index} total={total} onMove={onMove} onRemove={onRemove} />
      </div>
    </div>
  );
}
