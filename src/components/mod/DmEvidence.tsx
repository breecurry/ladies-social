import { SealCheck, Warning } from "@phosphor-icons/react/dist/ssr";
import type { ModDmEvidenceRow } from "@/lib/database.types";
import { REASON_LABEL } from "@/lib/moderation";
import { relativeTime } from "@/lib/format";

/**
 * The DM evidence transcript in a case (design 2C §15): exactly the
 * messages the reporter's device attached, rendered read-only as
 * bubbles, @handle only, with the franking verdict per message and the
 * honest limit the console must carry — the platform cannot see the
 * rest of the conversation.
 */
export function DmEvidence({
  rows,
  accusedHandle,
}: {
  rows: ModDmEvidenceRow[];
  accusedHandle: string;
}) {
  if (rows.length === 0) return null;

  const byReport = new Map<string, ModDmEvidenceRow[]>();
  for (const row of rows) {
    const list = byReport.get(row.report_id) ?? [];
    list.push(row);
    byReport.set(row.report_id, list);
  }

  return (
    <section
      aria-label="Reported direct messages"
      className="rounded-lg border border-border bg-surface"
    >
      <h2 className="border-b border-border px-4 py-2 text-label text-text-secondary">
        Reported direct messages
      </h2>
      {[...byReport.entries()].map(([reportId, messages]) => {
        const first = messages[0];
        if (!first) return null;
        const allVerified = messages.every((m) => m.verified);
        return (
          <div key={reportId} className="border-b border-border px-4 py-3 last:border-b-0">
            <p className="mb-2 flex flex-wrap items-center gap-2 text-caption text-text-tertiary">
              {REASON_LABEL[first.reason]} · reported {relativeTime(first.reported_at)}
              {allVerified ? (
                <span className="inline-flex items-center gap-1 text-success">
                  <SealCheck size={14} weight="fill" aria-hidden />
                  Cryptographically verified
                </span>
              ) : (
                <span className="inline-flex items-center gap-1 text-warning">
                  <Warning size={14} weight="fill" aria-hidden />
                  Contains unverified content
                </span>
              )}
            </p>
            <ul className="flex flex-col gap-1.5">
              {messages.map((message) => {
                const fromAccused = message.sender_handle === accusedHandle;
                return (
                  <li
                    key={`${reportId}:${message.message_id}`}
                    className={`flex flex-col ${fromAccused ? "items-start" : "items-end"}`}
                  >
                    <span className="px-1 text-caption text-text-tertiary">
                      @{message.sender_handle} · {relativeTime(message.sent_at)}
                      {!message.verified ? " · not verified — shown as the reporter's claim" : ""}
                    </span>
                    <div
                      className={`max-w-[85%] whitespace-pre-wrap break-words rounded-[14px] px-4 py-2 text-body text-text-primary ${
                        fromAccused
                          ? "rounded-bl-md border-l-2 border-accent bg-accent-subtle"
                          : "rounded-br-md bg-surface-raised"
                      }`}
                    >
                      {message.plaintext}
                    </div>
                  </li>
                );
              })}
            </ul>
          </div>
        );
      })}
      <p className="px-4 py-3 text-caption text-text-tertiary">
        This is the evidence the reporter shared. Hersciety cannot see the rest of this
        conversation, and no further context can be requested. Messages marked verified were
        cryptographically confirmed to have been sent exactly as shown; unverified messages are
        the reporter&apos;s claim only.
      </p>
    </section>
  );
}
