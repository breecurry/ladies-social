"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { ReportReason } from "@/lib/database.types";
import { Dialog } from "@/components/Dialog";
import { useToast } from "@/components/shell/ToastProvider";
import { useViewer } from "@/components/shell/Providers";

const REASONS: Array<{ value: ReportReason; label: string; description: string }> = [
  { value: "harassment", label: "Harassment or bullying", description: "Targeting, intimidating, or demeaning someone." },
  { value: "hate", label: "Hate speech", description: "Attacking people for who they are." },
  { value: "violence_threat", label: "Threat of violence", description: "Threatening or wishing harm on someone." },
  { value: "doxxing", label: "Sharing private information", description: "Posting someone's address, contacts, or identity without consent." },
  { value: "ncii", label: "Sexual content or harassment", description: "Unwanted sexual content or intimate images shared without consent." },
  { value: "csam", label: "Content involving a minor", description: "Sexual content involving anyone under 18. Taken extremely seriously." },
  { value: "impersonation", label: "Impersonation", description: "Pretending to be someone they are not." },
  { value: "spam", label: "Spam or scam", description: "Deceptive, repetitive, or commercial abuse." },
  { value: "self_harm", label: "Self-harm", description: "Content indicating someone may hurt themselves." },
  { value: "other", label: "Something else", description: "Anything that does not fit the reasons above." },
];

type Step = "reason" | "details" | "done";

/**
 * The reporting flow (spec §10.4): reason, optional detail, calm
 * confirmation, with immediate Block offered on the way out. Routing
 * is computed server-side and never shown; the flow is identical
 * whoever the accused is (spec §10.5).
 */
export function ReportDialog({
  open,
  onClose,
  subjectHandle,
  subjectUserId,
  postId,
  canBlock,
}: {
  open: boolean;
  onClose: () => void;
  subjectHandle: string;
  subjectUserId: string;
  postId?: number;
  canBlock?: boolean;
}) {
  const router = useRouter();
  const viewer = useViewer();
  const { showToast } = useToast();
  const [step, setStep] = useState<Step>("reason");
  const [reason, setReason] = useState<ReportReason | null>(null);
  const [details, setDetails] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reset = () => {
    setStep("reason");
    setReason(null);
    setDetails("");
    setError(null);
  };

  const close = () => {
    reset();
    onClose();
  };

  const submit = async () => {
    if (!reason) return;
    setBusy(true);
    setError(null);
    const supabase = createSupabaseBrowserClient();
    const { error: rpcError } = await supabase.rpc("file_report", {
      p_subject: postId !== undefined ? "post" : "user",
      p_post: postId ?? null,
      p_user: postId !== undefined ? null : subjectUserId,
      p_reason: reason,
      p_details: details.trim() === "" ? null : details.trim(),
    });
    setBusy(false);
    if (rpcError) {
      setError(rpcError.message);
      return;
    }
    setStep("done");
  };

  const blockNow = async () => {
    const supabase = createSupabaseBrowserClient();
    const { error: blockError } = await supabase
      .from("blocks")
      .insert({ blocker_id: viewer.id, blocked_id: subjectUserId });
    if (blockError) {
      showToast(blockError.message);
      return;
    }
    showToast(`Blocked @${subjectHandle}`);
    close();
    router.refresh();
  };

  return (
    <Dialog open={open} onClose={close} label={`Report @${subjectHandle}`}>
      <div className="flex flex-col gap-3 p-4">
        {step === "reason" ? (
          <>
            <h2 className="text-heading">Report {postId !== undefined ? "this post" : `@${subjectHandle}`}</h2>
            <p className="text-body text-text-secondary">What is happening?</p>
            <div role="radiogroup" aria-label="Reason" className="flex flex-col">
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
            <div className="flex justify-end">
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
            {canBlock ? (
              <p className="text-body text-text-secondary">
                Do you also want to block @{subjectHandle}? They will not be able to see your
                profile or posts, follow you, or message you. They will not be told.
              </p>
            ) : null}
            <div className="flex justify-end gap-2">
              <button
                type="button"
                data-autofocus
                onClick={() => {
                  close();
                }}
                className="min-h-11 rounded-md px-4 text-label text-accent hover:bg-accent-subtle"
              >
                Done
              </button>
              {canBlock ? (
                <button
                  type="button"
                  onClick={() => void blockNow()}
                  className="min-h-11 rounded-md bg-danger-fill px-4 text-label text-white hover:bg-danger-hover"
                >
                  Block @{subjectHandle}
                </button>
              ) : null}
            </div>
          </>
        ) : null}
      </div>
    </Dialog>
  );
}
