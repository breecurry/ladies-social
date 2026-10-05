"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Globe, Users, At, CaretDown } from "@phosphor-icons/react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { ReplyControl } from "@/lib/database.types";
import { Button } from "@/components/ui";
import { useToast } from "@/components/shell/ToastProvider";

export interface ReplyTarget {
  id: number;
  handle: string;
  excerpt: string;
  replyControl: ReplyControl;
}

const LIMIT = 500;
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
 * The post composer (spec §5): one component for new posts and replies.
 * Late-revealing character counter, inline audience control, optimistic
 * close on success. The surrounding modal/sheet lives in ComposeProvider.
 */
export function Composer({
  viewerHandle,
  replyTo,
  draft,
  onDraftChange,
  onClose,
  onPosted,
}: {
  viewerHandle: string;
  replyTo?: ReplyTarget;
  draft: string;
  onDraftChange: (value: string) => void;
  onClose: () => void;
  onPosted: () => void;
}) {
  const router = useRouter();
  const { showToast } = useToast();
  const [audience, setAudience] = useState<ReplyControl>("everyone");
  const [audienceOpen, setAudienceOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const fieldRef = useRef<HTMLTextAreaElement>(null);

  const remaining = LIMIT - draft.length;
  const empty = draft.trim().length === 0;

  const post = async () => {
    setBusy(true);
    setError(null);
    const supabase = createSupabaseBrowserClient();
    const { error: rpcError } = await supabase.rpc("create_post", {
      p_body: draft,
      p_parent: replyTo?.id ?? null,
      p_reply_control: replyTo ? "everyone" : audience,
    });
    setBusy(false);
    if (rpcError) {
      setError(rpcError.message);
      return;
    }
    onPosted();
    showToast(replyTo ? "Reply posted" : "Posted");
    router.refresh();
  };

  return (
    <div className="flex flex-col gap-3 p-4">
      <div className="flex items-center justify-between">
        <button
          type="button"
          aria-label="Close composer"
          onClick={onClose}
          className="flex min-h-11 min-w-11 items-center justify-center rounded-md text-text-secondary hover:bg-surface hover:text-text-primary"
        >
          ✕
        </button>
        <h2 className="text-heading">{replyTo ? "Reply" : "New post"}</h2>
        <Button onClick={() => void post()} disabled={empty || remaining < 0 || busy}>
          {busy ? "Posting…" : "Post"}
        </Button>
      </div>

      {replyTo ? (
        <p className="text-caption text-text-tertiary">
          Replying to @{replyTo.handle}: {replyTo.excerpt}
        </p>
      ) : null}

      <div className="flex gap-3">
        <span
          aria-hidden
          className="inline-flex size-10 shrink-0 items-center justify-center rounded-full bg-accent-subtle text-body font-semibold text-accent"
        >
          {viewerHandle.charAt(0).toUpperCase()}
        </span>
        <textarea
          ref={fieldRef}
          data-autofocus
          value={draft}
          maxLength={LIMIT}
          onChange={(event) => onDraftChange(event.target.value)}
          placeholder={replyTo ? `Reply to @${replyTo.handle}` : "Share something with the community"}
          aria-label={replyTo ? `Reply to @${replyTo.handle}` : "New post"}
          rows={4}
          className="min-h-28 w-full resize-none bg-transparent text-body-lg text-text-primary outline-none placeholder:text-text-tertiary"
        />
      </div>

      {error ? (
        <p role="alert" className="text-caption text-danger">
          {error}
        </p>
      ) : null}
      {remaining === 0 ? (
        <p className="text-caption text-danger">You have reached the 500-character limit.</p>
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
                      fieldRef.current?.focus();
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
        {remaining <= SOFT_BAND ? (
          <span
            aria-live="polite"
            className={`text-caption ${remaining === 0 ? "text-danger" : "text-warning"}`}
          >
            {remaining}
          </span>
        ) : null}
      </div>
    </div>
  );
}
