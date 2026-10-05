"use client";

import { useEffect, useId, useState } from "react";
import { useRouter } from "next/navigation";
import { Lock } from "@phosphor-icons/react";
import type { AccountStatus, PostVisibility, ReportReason } from "@/lib/database.types";
import { canBan, canExceedSevenDays, REASON_LABEL, type ModTier } from "@/lib/moderation";
import { Dialog } from "@/components/Dialog";
import { Field, Input, Textarea } from "@/components/ui";
import { useToast } from "@/components/shell/ToastProvider";

const RULES = Object.entries(REASON_LABEL) as Array<[ReportReason, string]>;

type DialogKind = "warn" | "remove" | "restrict" | "suspend" | "ban" | "escalate" | "lift" | null;

/**
 * The enforcement action rail (design doc §4), lightest at the top,
 * heaviest fenced off at the bottom. THE IRREVERSIBILITY RULE (§0.2)
 * governs every confirmation here: the safe choice is always a
 * left-aligned ghost control with an active verb and default focus;
 * the destructive choice is always right-aligned, filled, and carries
 * a specific verb with its object. No two actions differ by casing or
 * colour alone, and the one unrecoverable action — permanent ban —
 * stays disabled until the exact @handle is typed.
 *
 * Role shapes the rail, never an error after the fact: a reviewer sees
 * no actions at all; a moderator never sees Ban; duration chips over
 * 7 days are visibly locked for moderators with the escalation path
 * beside them.
 */
export function CaseActions({
  tier,
  target,
  accusedHandle,
  accusedStatus,
  postId,
  postVisibility,
  caseState,
  hasCsam,
}: {
  tier: ModTier;
  target: string;
  accusedHandle: string;
  accusedStatus: AccountStatus;
  postId: number | null;
  postVisibility: PostVisibility | null;
  caseState: string;
  hasCsam: boolean;
}) {
  const router = useRouter();
  const { showToast } = useToast();
  const [dialog, setDialog] = useState<DialogKind>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // A reviewer has no action authority at all: controls are absent,
  // not disabled (§1).
  if (tier === "reviewer" || tier === "none") return null;
  const isOwner = tier === "owner";

  const act = async (body: Record<string, unknown>, doneMessage: string): Promise<boolean> => {
    setBusy(true);
    setError(null);
    const response = await fetch("/api/mod/action", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    const result = (await response.json().catch(() => null)) as
      | { ok: boolean; error?: string }
      | null;
    setBusy(false);
    if (!result?.ok) {
      setError(result?.error ?? "Something went wrong.");
      return false;
    }
    showToast(doneMessage);
    setDialog(null);
    router.refresh();
    return true;
  };

  // csam: the single forward action for anyone but the Owner is
  // escalation (§4.8). NCMEC filing and law enforcement are hers.
  if (hasCsam && !isOwner) {
    return (
      <section aria-label="Actions" className="rounded-lg border border-border bg-surface p-4">
        <p className="mb-3 text-body text-text-secondary">
          This is a child-safety case. It can only be escalated to the Owner, who handles NCMEC
          and law-enforcement steps.
        </p>
        {error ? <p className="mb-2 text-caption text-danger">{error}</p> : null}
        <button
          type="button"
          disabled={busy || caseState === "escalated"}
          onClick={() => void act({ action: "escalate", target, postId }, "Escalated to the Owner")}
          className="min-h-11 rounded-md bg-accent-fill px-4 text-label text-on-accent hover:bg-accent-hover disabled:opacity-50"
        >
          {caseState === "escalated" ? "Escalated to the Owner" : "Escalate to the Owner"}
        </button>
      </section>
    );
  }

  const openCase = caseState === "open" || caseState === "in_review" || caseState === "escalated";

  return (
    <section aria-label="Actions" className="rounded-lg border border-border bg-surface">
      <h2 className="border-b border-border px-4 py-2 text-label text-text-secondary">Actions</h2>
      {error ? (
        <p role="alert" className="px-4 pt-2 text-caption text-danger">
          {error}
        </p>
      ) : null}
      <div className="flex flex-col p-2">
        {caseState === "open" ? (
          <RailButton
            label="Mark in review"
            hint="Claim this case so no one else actions it in parallel."
            disabled={busy}
            onClick={() => void act({ action: "claim", target, postId }, "Case claimed")}
          />
        ) : null}
        {caseState === "dismissed" ? (
          <RailButton
            label="Reopen case"
            hint="Dismissal is reversible; this returns the case to Open."
            disabled={busy}
            onClick={() => void act({ action: "reopen", target, postId }, "Case reopened")}
          />
        ) : null}
        {openCase ? (
          <RailButton
            label="Dismiss (no action)"
            hint="A considered outcome: the reports are closed with nothing done."
            disabled={busy}
            onClick={() => void act({ action: "dismiss", target, postId }, "Dismissed, no action")}
          />
        ) : null}
        <RailButton label="Warn" hint="A notice naming the rule. Nothing is restricted." onClick={() => setDialog("warn")} />
        {postId !== null && postVisibility === "visible" ? (
          <RailButton
            label="Remove content"
            hint="The post leaves every public surface. Restorable."
            onClick={() => setDialog("remove")}
          />
        ) : null}
        {postId !== null && postVisibility === "removed_moderation" ? (
          <RailButton
            label="Restore post"
            hint="Puts the removed post back."
            disabled={busy}
            onClick={() => void act({ action: "restore_post", postId }, "Post restored")}
          />
        ) : null}
        {accusedStatus === "active" ? (
          <RailButton
            label="Restrict"
            hint="Can read, cannot post or reply, for a set time."
            onClick={() => setDialog("restrict")}
          />
        ) : null}
        {accusedStatus === "active" || accusedStatus === "restricted" ? (
          <RailButton
            label="Suspend"
            hint="The account is out for a set time."
            onClick={() => setDialog("suspend")}
          />
        ) : null}
        {accusedStatus === "restricted" ||
        (accusedStatus === "suspended" && canExceedSevenDays(tier)) ? (
          <RailButton
            label={accusedStatus === "restricted" ? "Lift restriction" : "Lift suspension"}
            hint="Ends the current limit early."
            onClick={() => setDialog("lift")}
          />
        ) : null}
        <RailButton
          label="Escalate"
          hint="Hand this case to a more senior role, with your note."
          onClick={() => setDialog("escalate")}
        />

        {/* The fence (§4.7): Ban is never an adjacent peer of Suspend. */}
        {canBan(tier) && accusedStatus !== "banned" ? (
          <>
            <div role="separator" className="mx-2 my-2 border-t border-border" />
            <button
              type="button"
              onClick={() => setDialog("ban")}
              className="flex min-h-11 flex-col items-start justify-center rounded-md px-3 text-left hover:bg-danger-subtle"
            >
              <span className="text-label text-danger">Ban permanently</span>
              <span className="text-caption text-text-tertiary">
                Closes the account for good. Requires typing the @handle.
              </span>
            </button>
          </>
        ) : null}
      </div>

      {dialog === "warn" ? (
        <WarnDialog
          busy={busy}
          error={error}
          postId={postId}
          onClose={() => setDialog(null)}
          onSubmit={(rule, message, removeContent) =>
            void act(
              { action: "warn", target, postId, rule, message, removeContent },
              "Warning sent",
            )
          }
        />
      ) : null}
      {dialog === "remove" && postId !== null ? (
        <RemoveDialog
          busy={busy}
          error={error}
          onClose={() => setDialog(null)}
          onSubmit={(rule) => void act({ action: "remove_post", postId, rule }, "Post removed")}
        />
      ) : null}
      {dialog === "restrict" || dialog === "suspend" ? (
        <DurationDialog
          kind={dialog}
          tier={tier}
          busy={busy}
          error={error}
          onClose={() => setDialog(null)}
          onEscalate={(note) =>
            void act({ action: "escalate", target, postId, note }, "Escalated with your note")
          }
          onSubmit={(days, rule) =>
            void act(
              { action: dialog, target, days, rule },
              dialog === "restrict" ? `Restricted ${days} day${days === 1 ? "" : "s"}` : `Suspended ${days} day${days === 1 ? "" : "s"}`,
            )
          }
        />
      ) : null}
      {dialog === "lift" ? (
        <LiftDialog
          status={accusedStatus}
          busy={busy}
          error={error}
          onClose={() => setDialog(null)}
          onSubmit={() => void act({ action: "lift", target }, "Lifted")}
        />
      ) : null}
      {dialog === "escalate" ? (
        <EscalateDialog
          busy={busy}
          error={error}
          onClose={() => setDialog(null)}
          onSubmit={(note) => void act({ action: "escalate", target, postId, note }, "Escalated")}
        />
      ) : null}
      {dialog === "ban" ? (
        <BanDialog
          target={target}
          accusedHandle={accusedHandle}
          busy={busy}
          error={error}
          onClose={() => setDialog(null)}
          onDone={() => {
            setDialog(null);
            showToast(`@${accusedHandle} banned permanently`);
            router.refresh();
          }}
        />
      ) : null}
    </section>
  );
}

function RailButton({
  label,
  hint,
  disabled,
  onClick,
}: {
  label: string;
  hint: string;
  disabled?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className="flex min-h-11 flex-col items-start justify-center rounded-md px-3 text-left hover:bg-accent-subtle disabled:opacity-50"
    >
      <span className="text-label text-text-primary">{label}</span>
      <span className="text-caption text-text-tertiary">{hint}</span>
    </button>
  );
}

function RuleSelect({
  value,
  onChange,
  id,
}: {
  value: ReportReason;
  onChange: (rule: ReportReason) => void;
  id: string;
}) {
  return (
    <select
      id={id}
      value={value}
      onChange={(event) => onChange(event.target.value as ReportReason)}
      className="min-h-11 w-full rounded-md border border-border-strong bg-surface-raised px-3 text-body text-text-primary"
    >
      {RULES.filter(([rule]) => rule !== "csam").map(([rule, label]) => (
        <option key={rule} value={rule}>
          {label}
        </option>
      ))}
    </select>
  );
}

/** Safe choice left + ghost + default focus; destructive right + fill.
 * The pair never reads alike (§0.2, §5). */
function ConfirmRow({
  safeLabel,
  dangerLabel,
  busy,
  disabled = false,
  onSafe,
  onDanger,
}: {
  safeLabel: string;
  dangerLabel: string;
  busy: boolean;
  disabled?: boolean;
  onSafe: () => void;
  onDanger: () => void;
}) {
  return (
    <div className="flex items-center justify-between gap-2 pt-2">
      <button
        type="button"
        data-autofocus
        onClick={onSafe}
        className="min-h-11 rounded-md px-4 text-label text-accent hover:bg-accent-subtle"
      >
        {safeLabel}
      </button>
      <button
        type="button"
        disabled={busy || disabled}
        onClick={onDanger}
        className="min-h-11 rounded-md bg-danger-fill px-4 text-label text-white hover:bg-danger-hover disabled:cursor-not-allowed disabled:opacity-50"
      >
        {dangerLabel}
      </button>
    </div>
  );
}

function WarnDialog({
  busy,
  error,
  postId,
  onClose,
  onSubmit,
}: {
  busy: boolean;
  error: string | null;
  postId: number | null;
  onClose: () => void;
  onSubmit: (rule: ReportReason, message: string, removeContent: boolean) => void;
}) {
  const id = useId();
  const [rule, setRule] = useState<ReportReason>("harassment");
  const [message, setMessage] = useState(
    "A post of yours was found to break our rule on harassment. Please review the Community Guidelines. Nothing has been restricted.",
  );
  const [removeContent, setRemoveContent] = useState(false);
  return (
    <Dialog open onClose={onClose} label="Send a warning" sheet={false}>
      <div className="flex flex-col gap-3 p-5">
        <h2 className="text-heading">Send a warning</h2>
        <Field label="Rule" htmlFor={`${id}-rule`}>
          <RuleSelect
            id={`${id}-rule`}
            value={rule}
            onChange={(next) => {
              setRule(next);
              setMessage(
                `A post of yours was found to break our rule on ${REASON_LABEL[next].toLowerCase()}. Please review the Community Guidelines. Nothing has been restricted.`,
              );
            }}
          />
        </Field>
        <Field label="Message to the member" htmlFor={`${id}-msg`}>
          <Textarea
            id={`${id}-msg`}
            rows={4}
            maxLength={1000}
            value={message}
            onChange={(event) => setMessage(event.target.value)}
          />
        </Field>
        {postId !== null ? (
          <label className="flex min-h-11 items-center gap-2 text-body text-text-primary">
            <input
              type="checkbox"
              checked={removeContent}
              onChange={(event) => setRemoveContent(event.target.checked)}
              className="size-4 accent-(--accent)"
            />
            Also remove the reported post
          </label>
        ) : null}
        {error ? <p className="text-caption text-danger">{error}</p> : null}
        <ConfirmRow
          safeLabel="Cancel"
          dangerLabel="Send warning"
          busy={busy}
          disabled={message.trim() === ""}
          onSafe={onClose}
          onDanger={() => onSubmit(rule, message.trim(), removeContent)}
        />
      </div>
    </Dialog>
  );
}

function RemoveDialog({
  busy,
  error,
  onClose,
  onSubmit,
}: {
  busy: boolean;
  error: string | null;
  onClose: () => void;
  onSubmit: (rule: ReportReason) => void;
}) {
  const id = useId();
  const [rule, setRule] = useState<ReportReason>("harassment");
  return (
    <Dialog open onClose={onClose} label="Remove post" sheet={false} maxWidth="max-w-sm">
      <div className="flex flex-col gap-3 p-5">
        <h2 className="text-heading">Remove post</h2>
        <p className="text-body text-text-secondary">
          This post will be removed from Hersciety. You can restore it later. The author will be
          told their post was removed and why — never who reported it.
        </p>
        <Field label="Rule" htmlFor={`${id}-rule`}>
          <RuleSelect id={`${id}-rule`} value={rule} onChange={setRule} />
        </Field>
        {error ? <p className="text-caption text-danger">{error}</p> : null}
        <ConfirmRow
          safeLabel="Cancel"
          dangerLabel="Remove post"
          busy={busy}
          onSafe={onClose}
          onDanger={() => onSubmit(rule)}
        />
      </div>
    </Dialog>
  );
}

/**
 * The duration control (§4.6): the 7-day moderator boundary is a
 * visible property of the chips, not an error after submission. Locked
 * chips stay present so the shape of authority is legible, and the
 * escalation path sits right beside them.
 */
function DurationDialog({
  kind,
  tier,
  busy,
  error,
  onClose,
  onSubmit,
  onEscalate,
}: {
  kind: "restrict" | "suspend";
  tier: ModTier;
  busy: boolean;
  error: string | null;
  onClose: () => void;
  onSubmit: (days: number, rule: ReportReason) => void;
  onEscalate: (note: string) => void;
}) {
  const id = useId();
  const maxDays = canExceedSevenDays(tier) ? 30 : 7;
  const [days, setDays] = useState(3);
  const [rule, setRule] = useState<ReportReason>("harassment");
  const [clamped, setClamped] = useState(false);
  const presets = [1, 3, 7, 14, 30];
  const title = kind === "restrict" ? "Restrict account" : "Suspend account";
  const verb = kind === "restrict" ? "Restrict" : "Suspend";

  return (
    <Dialog open onClose={onClose} label={title} sheet={false}>
      <div className="flex flex-col gap-3 p-5">
        <h2 className="text-heading">{title}</h2>
        <p className="text-body text-text-secondary">
          {kind === "restrict"
            ? "The member can read, but cannot post or reply, until the restriction ends. Liftable early."
            : "The member cannot use her account until the suspension ends. Liftable early, and she can appeal."}
        </p>
        <fieldset className="flex flex-col gap-2">
          <legend className="text-label text-text-primary">Duration</legend>
          <div className="flex flex-wrap gap-2" role="radiogroup" aria-label="Duration in days">
            {presets.map((preset) => {
              const locked = preset > maxDays;
              return (
                <button
                  key={preset}
                  type="button"
                  role="radio"
                  aria-checked={days === preset}
                  aria-disabled={locked}
                  onClick={() => {
                    if (!locked) {
                      setDays(preset);
                      setClamped(false);
                    }
                  }}
                  className={`inline-flex min-h-11 items-center gap-1 rounded-full border px-4 text-label ${
                    locked
                      ? "cursor-not-allowed border-border text-text-tertiary"
                      : days === preset
                        ? "border-accent bg-accent-subtle text-accent"
                        : "border-border-strong text-text-primary hover:bg-surface-raised"
                  }`}
                >
                  {locked ? <Lock size={14} aria-hidden /> : null}
                  {preset} day{preset === 1 ? "" : "s"}
                </button>
              );
            })}
            <label className="flex items-center gap-2 text-body text-text-secondary">
              Custom
              <input
                type="number"
                min={1}
                max={maxDays}
                value={days}
                aria-label="Custom duration in days"
                onChange={(event) => {
                  const raw = Number(event.target.value);
                  if (!Number.isFinite(raw)) return;
                  const next = Math.max(1, Math.min(Math.round(raw), maxDays));
                  setClamped(raw > maxDays);
                  setDays(next);
                }}
                className="min-h-11 w-20 rounded-md border border-border-strong bg-surface-raised px-3 text-body text-text-primary"
              />
            </label>
          </div>
          {maxDays === 7 ? (
            <p className="text-caption text-text-tertiary">
              {kind === "restrict" ? "Restrictions" : "Suspensions"} over 7 days are set by an
              admin.{clamped ? " Your value was set to 7." : ""}
            </p>
          ) : null}
        </fieldset>
        <Field label="Rule" htmlFor={`${id}-rule`}>
          <RuleSelect id={`${id}-rule`} value={rule} onChange={setRule} />
        </Field>
        {maxDays === 7 ? (
          <button
            type="button"
            disabled={busy}
            onClick={() => onEscalate(`Recommending a ${kind} longer than 7 days.`)}
            className="self-start text-label text-accent hover:underline"
          >
            Escalate for a longer {kind === "restrict" ? "restriction" : "suspension"}
          </button>
        ) : null}
        {error ? <p className="text-caption text-danger">{error}</p> : null}
        <ConfirmRow
          safeLabel="Keep account active"
          dangerLabel={`${verb} ${days} day${days === 1 ? "" : "s"}`}
          busy={busy}
          onSafe={onClose}
          onDanger={() => onSubmit(days, rule)}
        />
      </div>
    </Dialog>
  );
}

function LiftDialog({
  status,
  busy,
  error,
  onClose,
  onSubmit,
}: {
  status: AccountStatus;
  busy: boolean;
  error: string | null;
  onClose: () => void;
  onSubmit: () => void;
}) {
  const noun = status === "restricted" ? "restriction" : "suspension";
  return (
    <Dialog open onClose={onClose} label={`Lift ${noun}`} sheet={false} maxWidth="max-w-sm">
      <div className="flex flex-col gap-3 p-5">
        <h2 className="text-heading">Lift {noun}</h2>
        <p className="text-body text-text-secondary">
          The account returns to full standing immediately. The member is told her account is
          active again.
        </p>
        {error ? <p className="text-caption text-danger">{error}</p> : null}
        <div className="flex items-center justify-between gap-2 pt-2">
          <button
            type="button"
            data-autofocus
            onClick={onClose}
            className="min-h-11 rounded-md px-4 text-label text-accent hover:bg-accent-subtle"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={busy}
            onClick={onSubmit}
            className="min-h-11 rounded-md bg-accent-fill px-4 text-label text-on-accent hover:bg-accent-hover disabled:opacity-50"
          >
            Lift {noun}
          </button>
        </div>
      </div>
    </Dialog>
  );
}

function EscalateDialog({
  busy,
  error,
  onClose,
  onSubmit,
}: {
  busy: boolean;
  error: string | null;
  onClose: () => void;
  onSubmit: (note: string) => void;
}) {
  const id = useId();
  const [note, setNote] = useState("");
  return (
    <Dialog open onClose={onClose} label="Escalate" sheet={false} maxWidth="max-w-sm">
      <div className="flex flex-col gap-3 p-5">
        <h2 className="text-heading">Escalate</h2>
        <p className="text-body text-text-secondary">
          Hands the case to a more senior role with your recommendation attached.
        </p>
        <Field label="Note" htmlFor={`${id}-note`} hint="What should the reviewer know?">
          <Textarea
            id={`${id}-note`}
            rows={3}
            maxLength={2000}
            value={note}
            onChange={(event) => setNote(event.target.value)}
          />
        </Field>
        {error ? <p className="text-caption text-danger">{error}</p> : null}
        <div className="flex items-center justify-between gap-2 pt-2">
          <button
            type="button"
            data-autofocus
            onClick={onClose}
            className="min-h-11 rounded-md px-4 text-label text-accent hover:bg-accent-subtle"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={busy}
            onClick={() => onSubmit(note.trim())}
            className="min-h-11 rounded-md bg-accent-fill px-4 text-label text-on-accent hover:bg-accent-hover disabled:opacity-50"
          >
            Escalate
          </button>
        </div>
      </div>
    </Dialog>
  );
}

/**
 * The ban confirmation (§4.7, §6): unlike every other confirmation on
 * purpose. Mandatory rule and note, de-identified ban-evasion toggles
 * (categories and counts, never values), the honest-limit note on the
 * surface, and the typed-@handle gate — the destructive button stays
 * disabled until the admin has read and reproduced who she is banning.
 */
function BanDialog({
  target,
  accusedHandle,
  busy,
  error,
  onClose,
  onDone,
}: {
  target: string;
  accusedHandle: string;
  busy: boolean;
  error: string | null;
  onClose: () => void;
  onDone: () => void;
}) {
  const id = useId();
  const [rule, setRule] = useState<ReportReason>("harassment");
  const [note, setNote] = useState("");
  const [typed, setTyped] = useState("");
  const [banEmail, setBanEmail] = useState(true);
  const [banDevice, setBanDevice] = useState(true);
  const [banPhone, setBanPhone] = useState(true);
  const [signals, setSignals] = useState<{ email: boolean; phone: boolean; device: boolean } | null>(
    null,
  );
  const [localBusy, setLocalBusy] = useState(false);
  const [localError, setLocalError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const response = await fetch(`/api/mod/ban?target=${encodeURIComponent(target)}`);
      const result = (await response.json().catch(() => null)) as
        | { ok: boolean; signals?: { email: boolean; phone: boolean; device: boolean } }
        | null;
      if (!cancelled && result?.ok && result.signals) setSignals(result.signals);
    })();
    return () => {
      cancelled = true;
    };
  }, [target]);

  const handleMatches =
    typed.trim().replace(/^@/, "").toLowerCase() === accusedHandle.toLowerCase();
  const ready = handleMatches && note.trim() !== "";

  const submit = async () => {
    setLocalBusy(true);
    setLocalError(null);
    const response = await fetch("/api/mod/ban", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        target,
        rule,
        note: note.trim(),
        confirmHandle: typed.trim(),
        banEmail: banEmail && (signals?.email ?? true),
        banPhone: banPhone && (signals?.phone ?? false),
        banDevice: banDevice && (signals?.device ?? true),
      }),
    });
    const result = (await response.json().catch(() => null)) as
      | { ok: boolean; error?: string }
      | null;
    setLocalBusy(false);
    if (!result?.ok) {
      setLocalError(result?.error ?? "Something went wrong.");
      return;
    }
    onDone();
  };

  return (
    <Dialog open onClose={onClose} label={`Ban permanently @${accusedHandle}`} sheet={false}>
      <div className="flex flex-col gap-3 p-5">
        <h2 className="text-heading">Ban permanently @{accusedHandle}</h2>
        <p className="text-body text-text-secondary">
          This permanently closes @{accusedHandle}&apos;s account. It cannot be undone from here.
          The person can appeal within 30 days.
        </p>
        <Field label="Rule" htmlFor={`${id}-rule`}>
          <RuleSelect id={`${id}-rule`} value={rule} onChange={setRule} />
        </Field>
        <Field
          label="Note for the record"
          htmlFor={`${id}-note`}
          hint="Required. A permanent action must be justified on the record."
        >
          <Textarea
            id={`${id}-note`}
            rows={3}
            maxLength={2000}
            value={note}
            onChange={(event) => setNote(event.target.value)}
          />
        </Field>

        <fieldset className="flex flex-col gap-2">
          <legend className="text-label text-text-primary">Prevent new accounts</legend>
          {(signals?.email ?? true) ? (
            <SignalToggle
              label="Email address on record"
              caption="New sign-ups from the same email will be refused."
              checked={banEmail}
              onChange={setBanEmail}
            />
          ) : null}
          {(signals?.device ?? true) ? (
            <SignalToggle
              label="Device signature on record"
              caption="New sign-ups from the same device will be refused."
              checked={banDevice}
              onChange={setBanDevice}
            />
          ) : null}
          {signals?.phone ? (
            <SignalToggle
              label="Phone number on record"
              caption="New sign-ups from the same number will be refused."
              checked={banPhone}
              onChange={setBanPhone}
            />
          ) : null}
          <p className="text-caption text-text-secondary">
            This makes a new account from the same device, email, or number harder and detectable.
            It is not an absolute block; a determined person can still return. Keep watching the
            reports.
          </p>
        </fieldset>

        <Field label={`Type @${accusedHandle} to confirm`} htmlFor={`${id}-confirm`}>
          <Input
            id={`${id}-confirm`}
            value={typed}
            autoComplete="off"
            spellCheck={false}
            onChange={(event) => setTyped(event.target.value)}
          />
        </Field>
        <span aria-live="polite" className="sr-only">
          {ready ? "Confirmation complete. Ban permanently is now available." : ""}
        </span>
        {localError || error ? (
          <p role="alert" className="text-caption text-danger">
            {localError ?? error}
          </p>
        ) : null}
        <ConfirmRow
          safeLabel="Keep account active"
          dangerLabel="Ban permanently"
          busy={busy || localBusy}
          disabled={!ready}
          onSafe={onClose}
          onDanger={() => void submit()}
        />
      </div>
    </Dialog>
  );
}

function SignalToggle({
  label,
  caption,
  checked,
  onChange,
}: {
  label: string;
  caption: string;
  checked: boolean;
  onChange: (next: boolean) => void;
}) {
  return (
    <label className="flex min-h-11 items-start gap-2">
      <input
        type="checkbox"
        checked={checked}
        onChange={(event) => onChange(event.target.checked)}
        className="mt-1 size-4 accent-(--accent)"
      />
      <span className="flex flex-col">
        <span className="text-body text-text-primary">{label}</span>
        <span className="text-caption text-text-tertiary">{caption}</span>
      </span>
    </label>
  );
}
