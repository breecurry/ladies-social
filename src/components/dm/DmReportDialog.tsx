"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { DmMessageRow, ReportReason } from "@/lib/database.types";
import { Dialog } from "@/components/Dialog";
import { useToast } from "@/components/shell/ToastProvider";

const REASONS: Array<{ value: ReportReason; label: string; description: string }> = [
  {
    value: "harassment",
    label: "Harassment or bullying",
    description: "Targeting, intimidating, or demeaning someone.",
  },
  { value: "hate", label: "Hate speech", description: "Attacking people for who they are." },
  {
    value: "violence_threat",
    label: "Threat of violence",
    description: "Threatening or wishing harm on someone.",
  },
  {
    value: "doxxing",
    label: "Sharing private information",
    description: "Sharing someone's address, contacts, or identity without consent.",
  },
  {
    value: "ncii",
    label: "Sexual content or harassment",
    description: "Unwanted sexual content or intimate images shared without consent.",
  },
  {
    value: "csam",
    label: "Content involving a minor",
    description: "Sexual content involving anyone under 18. Taken extremely seriously.",
  },
  {
    value: "impersonation",
    label: "Impersonation",
    description: "Pretending to be someone they are not.",
  },
  {
    value: "spam",
    label: "Spam or scam",
    description: "Deceptive, repetitive, or commercial abuse.",
  },
  {
    value: "self_harm",
    label: "Self-harm",
    description: "Content indicating someone may hurt themselves.",
  },
  {
    value: "other",
    label: "Something else",
    description: "Anything that does not fit the reasons above.",
  },
];

type Step = "select" | "reason" | "details" | "done";

/**
 * Reporting a DM: the member selects exactly which messages the report
 * is about (1-10), picks a reason, and leaves protected (block offered
 * on the way out). The server copies the selected messages into the
 * report itself — the moderator sees them exactly as they were sent.
 */
export function DmReportDialog({
  open,
  onClose,
  conversationId,
  peerId,
  peerHandle,
  viewerId,
  messages,
}: {
  open: boolean;
  onClose: () => void;
  conversationId: string;
  peerId: string;
  peerHandle: string;
  viewerId: string;
  messages: DmMessageRow[];
}) {
  return (
    <Dialog open={open} onClose={onClose} label={`Report @${peerHandle}`}>
      {open ? (
        <ReportBody
          onClose={onClose}
          conversationId={conversationId}
          peerId={peerId}
          peerHandle={peerHandle}
          viewerId={viewerId}
          messages={messages}
        />
      ) : null}
    </Dialog>
  );
}

/** Mounted fresh on each open, so the selection never goes stale. */
function ReportBody({
  onClose,
  conversationId,
  peerId,
  peerHandle,
  viewerId,
  messages,
}: {
  onClose: () => void;
  conversationId: string;
  peerId: string;
  peerHandle: string;
  viewerId: string;
  messages: DmMessageRow[];
}) {
  const router = useRouter();
  const { showToast } = useToast();
  const selectable = messages.slice(-20);
  const [step, setStep] = useState<Step>("select");
  // Default selection: the most recent messages, so the report carries
  // context, with every line removable.
  const [selected, setSelected] = useState<Set<number>>(
    () => new Set(selectable.slice(-5).map((m) => m.id)),
  );
  const [reason, setReason] = useState<ReportReason | null>(null);
  const [details, setDetails] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const toggle = (id: number) => {
    setSelected((old) => {
      const next = new Set(old);
      if (next.has(id)) next.delete(id);
      else if (next.size < 10) next.add(id);
      return next;
    });
  };

  const submit = async () => {
    if (!reason || selected.size === 0) return;
    setBusy(true);
    setError(null);
    try {
      const response = await fetch("/api/dm/report", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          conversationId,
          reason,
          details: details.trim() === "" ? undefined : details.trim(),
          messageIds: [...selected].sort((a, b) => a - b),
        }),
      });
      const result = (await response.json().catch(() => null)) as {
        ok: boolean;
        error?: string;
      } | null;
      if (!result?.ok) {
        setError(result?.error ?? "Something went wrong. Your selection is kept — try again.");
        return;
      }
      setStep("done");
    } finally {
      setBusy(false);
    }
  };

  const blockNow = async () => {
    const supabase = createSupabaseBrowserClient();
    const { error: blockError } = await supabase
      .from("blocks")
      .insert({ blocker_id: viewerId, blocked_id: peerId });
    if (blockError) {
      showToast(blockError.message);
      return;
    }
    showToast(`Blocked @${peerHandle}`);
    onClose();
    router.refresh();
  };

  return (
    <div className="flex flex-col gap-3 p-4">
      {step === "select" ? (
        <>
          <h2 className="text-heading">Report messages from @{peerHandle}</h2>
          <p className="text-body text-text-secondary">
            Pick the messages this report is about. They go to our safety team with your report,
            exactly as they appear in the conversation.
          </p>
          <ul className="flex max-h-72 flex-col gap-1 overflow-y-auto">
            {selectable.map((message) => (
              <li key={message.id}>
                <label className="flex min-h-11 cursor-pointer items-start gap-3 rounded-md px-2 py-1.5 hover:bg-accent-subtle">
                  <input
                    type="checkbox"
                    checked={selected.has(message.id)}
                    onChange={() => toggle(message.id)}
                    className="mt-1.5 size-4 accent-(--color-accent)"
                  />
                  <span className="min-w-0 flex-1">
                    <span className="block text-caption text-text-tertiary">
                      {message.sender_id === viewerId ? "You" : `@${message.sender_handle}`}
                    </span>
                    <span className="block break-words text-body text-text-primary">
                      {message.body}
                    </span>
                  </span>
                </label>
              </li>
            ))}
          </ul>
          {selectable.length === 0 ? (
            <p className="text-body text-text-secondary">There are no messages to attach yet.</p>
          ) : null}
          <div className="flex justify-end">
            <button
              type="button"
              disabled={selected.size === 0}
              onClick={() => setStep("reason")}
              className="min-h-11 rounded-md bg-accent-fill px-4 text-label text-on-accent hover:bg-accent-hover disabled:opacity-50"
            >
              Continue ({selected.size} selected)
            </button>
          </div>
        </>
      ) : null}

      {step === "reason" ? (
        <>
          <h2 className="text-heading">What is happening?</h2>
          <div
            role="radiogroup"
            aria-label="Reason"
            className="flex max-h-80 flex-col overflow-y-auto"
          >
            {REASONS.map((item) => (
              <button
                key={item.value}
                type="button"
                role="radio"
                aria-checked={reason === item.value}
                onClick={() => setReason(item.value)}
                className={`flex min-h-11 flex-col items-start gap-0.5 rounded-md px-3 py-2 text-left hover:bg-accent-subtle ${
                  reason === item.value ? "bg-accent-subtle" : ""
                }`}
              >
                <span className="text-label text-text-primary">{item.label}</span>
                <span className="text-caption text-text-tertiary">{item.description}</span>
              </button>
            ))}
          </div>
          <div className="flex justify-between">
            <button
              type="button"
              onClick={() => setStep("select")}
              className="min-h-11 rounded-md px-4 text-label text-accent hover:bg-accent-subtle"
            >
              Back
            </button>
            <button
              type="button"
              disabled={reason === null}
              onClick={() => setStep("details")}
              className="min-h-11 rounded-md bg-accent-fill px-4 text-label text-on-accent hover:bg-accent-hover disabled:opacity-50"
            >
              Continue
            </button>
          </div>
        </>
      ) : null}

      {step === "details" ? (
        <>
          <h2 className="text-heading">Anything else we should know?</h2>
          <textarea
            data-autofocus
            value={details}
            maxLength={2000}
            onChange={(event) => setDetails(event.target.value)}
            rows={4}
            placeholder="Optional"
            aria-label="Additional details"
            className="w-full rounded-md border border-border-strong bg-surface px-3 py-2 text-body text-text-primary placeholder:text-text-tertiary"
          />
          {error ? (
            <p role="alert" className="text-caption text-danger">
              {error}
            </p>
          ) : null}
          <div className="flex justify-between">
            <button
              type="button"
              onClick={() => setStep("reason")}
              className="min-h-11 rounded-md px-4 text-label text-accent hover:bg-accent-subtle"
            >
              Back
            </button>
            <button
              type="button"
              disabled={busy}
              onClick={() => void submit()}
              className="min-h-11 rounded-md bg-accent-fill px-4 text-label text-on-accent hover:bg-accent-hover disabled:opacity-50"
            >
              {busy ? "Submitting…" : "Submit report"}
            </button>
          </div>
        </>
      ) : null}

      {step === "done" ? (
        <>
          <h2 className="text-heading">Thanks. Our team will review this.</h2>
          <p className="text-body text-text-secondary">
            You can see the status under Settings, Safety, Report history.
          </p>
          <p className="text-body text-text-secondary">
            Do you also want to block @{peerHandle}? They will not be able to message you, see your
            profile or posts, or follow you. They will not be told.
          </p>
          <div className="flex justify-end gap-2">
            <button
              type="button"
              data-autofocus
              onClick={onClose}
              className="min-h-11 rounded-md px-4 text-label text-accent hover:bg-accent-subtle"
            >
              Done
            </button>
            <button
              type="button"
              onClick={() => void blockNow()}
              className="min-h-11 rounded-md bg-danger-fill px-4 text-label text-white hover:bg-danger-hover"
            >
              Block @{peerHandle}
            </button>
          </div>
        </>
      ) : null}
    </div>
  );
}
