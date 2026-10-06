"use client";

import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from "react";
import { Dialog } from "@/components/Dialog";
import { Composer, type ReplyTarget, type QuoteTarget } from "@/components/compose/Composer";
import type { ReplyControl } from "@/lib/database.types";

interface ComposeContextValue {
  openCompose: (replyTo?: ReplyTarget, quote?: QuoteTarget) => void;
}

const ComposeContext = createContext<ComposeContextValue | null>(null);

export function useCompose(): ComposeContextValue {
  const ctx = useContext(ComposeContext);
  if (!ctx) throw new Error("useCompose must be used inside ComposeProvider");
  return ctx;
}

/**
 * The session draft (multi-part threads design §1): an ordered list of
 * parts plus the chain-level settings. A fresh draft is one empty
 * part; a member who never taps "Add to thread" sees the single-field
 * composer unchanged. Held here, not in the Composer, so an accidental
 * dismissal never loses a half-written thread.
 */
export interface ComposeDraft {
  parts: string[];
  audience: ReplyControl;
}

const EMPTY_DRAFT: ComposeDraft = { parts: [""], audience: "everyone" };

function draftHasContent(draft: ComposeDraft): boolean {
  return draft.parts.some((part) => part.trim().length > 0);
}

/**
 * Compose modal provider (spec §5): the composer opens as an overlay
 * over whatever surface you are on — for a new post, a reply, or a
 * quote-post (Phase 2F §15). The structured draft survives an
 * accidental dismissal for the session (spec §5.7); closing with
 * unsent content asks before discarding, with copy that scales to the
 * whole thread (multi-part design §8.4).
 */
export function ComposeProvider({
  viewerHandle,
  children,
}: {
  viewerHandle: string;
  children: ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const [replyTo, setReplyTo] = useState<ReplyTarget | undefined>(undefined);
  const [quote, setQuote] = useState<QuoteTarget | undefined>(undefined);
  const [draft, setDraft] = useState<ComposeDraft>(EMPTY_DRAFT);
  const [confirmDiscard, setConfirmDiscard] = useState(false);

  const openCompose = useCallback((replyTarget?: ReplyTarget, quoteTarget?: QuoteTarget) => {
    // A different target means the kept draft no longer applies.
    setReplyTo((previous) => {
      if ((previous?.id ?? null) !== (replyTarget?.id ?? null)) setDraft(EMPTY_DRAFT);
      return replyTarget;
    });
    setQuote((previous) => {
      if ((previous?.id ?? null) !== (quoteTarget?.id ?? null)) setDraft(EMPTY_DRAFT);
      return quoteTarget;
    });
    setOpen(true);
  }, []);

  const requestClose = useCallback(() => {
    if (draftHasContent(draft)) {
      setConfirmDiscard(true);
    } else {
      setOpen(false);
    }
  }, [draft]);

  const value = useMemo(() => ({ openCompose }), [openCompose]);

  const label = replyTo ? "Reply" : quote ? "Quote" : "New post";
  const multiPart = draft.parts.length > 1;

  return (
    <ComposeContext.Provider value={value}>
      {children}
      <Dialog open={open} onClose={requestClose} label={label}>
        <Composer
          viewerHandle={viewerHandle}
          replyTo={replyTo}
          quote={quote}
          draft={draft}
          onDraftChange={setDraft}
          onClose={requestClose}
          onPosted={() => {
            setDraft(EMPTY_DRAFT);
            setOpen(false);
          }}
        />
      </Dialog>
      <Dialog
        open={confirmDiscard}
        onClose={() => setConfirmDiscard(false)}
        label={multiPart ? "Discard this thread?" : "Discard this post?"}
        sheet={false}
        maxWidth="max-w-sm"
      >
        <div className="flex flex-col gap-4 p-5">
          <h2 className="text-heading">
            {multiPart ? "Discard this thread?" : "Discard this post?"}
          </h2>
          {multiPart ? (
            <p className="text-body text-text-secondary">
              All {draft.parts.length} parts will be discarded.
            </p>
          ) : null}
          <div className="flex justify-end gap-2">
            <button
              type="button"
              data-autofocus
              onClick={() => setConfirmDiscard(false)}
              className="min-h-11 rounded-md px-4 text-label text-accent hover:bg-accent-subtle"
            >
              Keep editing
            </button>
            <button
              type="button"
              onClick={() => {
                setDraft(EMPTY_DRAFT);
                setConfirmDiscard(false);
                setOpen(false);
              }}
              className="min-h-11 rounded-md bg-danger-fill px-4 text-label text-white hover:bg-danger-hover"
            >
              Discard
            </button>
          </div>
        </div>
      </Dialog>
    </ComposeContext.Provider>
  );
}
