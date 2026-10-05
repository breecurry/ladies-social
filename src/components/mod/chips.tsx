import {
  ArrowUpRight,
  CheckCircle,
  Circle,
  CircleDashed,
  MinusCircle,
  Warning,
} from "@phosphor-icons/react/dist/ssr";
import type { AccountStatus } from "@/lib/database.types";

/**
 * The console's two chip compositions (design doc §2.2, §16): built
 * entirely from existing tokens. Every chip carries its meaning in the
 * WORD and the GLYPH — the semantic colour is reinforcement only,
 * never the sole carrier (§12.6 colour independence).
 */

const chipBase =
  "inline-flex shrink-0 items-center gap-1 rounded-full border border-border bg-surface px-2 py-0.5 text-caption";

export function StateChip({ state }: { state: string }) {
  switch (state) {
    case "open":
      return (
        <span className={`${chipBase} text-text-secondary`}>
          <Circle size={12} weight="fill" aria-hidden className="text-accent" /> New
        </span>
      );
    case "in_review":
      return (
        <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-accent-subtle px-2 py-0.5 text-caption text-accent">
          <CircleDashed size={12} aria-hidden /> In review
        </span>
      );
    case "escalated":
      return (
        <span className={`${chipBase} text-text-secondary`}>
          <ArrowUpRight size={12} weight="bold" aria-hidden className="text-warning" /> Escalated
        </span>
      );
    case "actioned":
      return (
        <span className={`${chipBase} text-text-secondary`}>
          <CheckCircle size={12} weight="fill" aria-hidden className="text-success" /> Actioned
        </span>
      );
    default:
      return (
        <span className={`${chipBase} text-text-tertiary`}>
          <MinusCircle size={12} weight="fill" aria-hidden /> No action
        </span>
      );
  }
}

export function PriorityChip({ priority }: { priority: string }) {
  if (priority === "critical") {
    return (
      <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-danger-fill px-2 py-0.5 text-caption text-white">
        <Warning size={12} weight="fill" aria-hidden /> Critical
      </span>
    );
  }
  if (priority === "high") {
    return (
      <span className={`${chipBase} text-text-secondary`}>
        <Warning size={12} weight="fill" aria-hidden className="text-warning" /> High
      </span>
    );
  }
  return null;
}

/** The accused account's current standing, so a moderator instantly
 * knows whether an action is already in force. */
export function AccountStatusChip({
  status,
  expiresAt,
}: {
  status: AccountStatus;
  expiresAt?: string | null;
}) {
  const until = expiresAt
    ? ` until ${new Date(expiresAt).toLocaleDateString("en-GB", { day: "numeric", month: "short" })}`
    : "";
  switch (status) {
    case "active":
      return <span className={`${chipBase} text-text-secondary`}>Active</span>;
    case "restricted":
      return <span className={`${chipBase} text-text-secondary`}>Restricted{until}</span>;
    case "suspended":
      return <span className={`${chipBase} text-text-secondary`}>Suspended{until}</span>;
    case "banned":
      return (
        <span className="inline-flex shrink-0 items-center rounded-full bg-danger-subtle px-2 py-0.5 text-caption text-danger">
          Banned
        </span>
      );
    default:
      return <span className={`${chipBase} text-text-tertiary`}>{status}</span>;
  }
}
