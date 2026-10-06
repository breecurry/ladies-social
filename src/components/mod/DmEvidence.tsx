import type { ModDmEvidenceRow } from "@/lib/database.types";
import { REASON_LABEL } from "@/lib/moderation";
import { relativeTime } from "@/lib/format";

/**
 * The DM evidence transcript in a case: the messages the reporter
 * selected, copied server-side from the conversation at filing time,
 * rendered read-only as bubbles, @handle only. Every load of this
 * evidence is written to the audit log by mod_dm_evidence() — staff
 * reads of message content are accountable, never invisible.
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
        return (
          <div key={reportId} className="border-b border-border px-4 py-3 last:border-b-0">
            <p className="mb-2 text-caption text-text-tertiary">
              {REASON_LABEL[first.reason]} · reported {relativeTime(first.reported_at)}
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
                    </span>
                    <div
                      className={`max-w-[85%] whitespace-pre-wrap break-words rounded-[14px] px-4 py-2 text-body text-text-primary ${
                        fromAccused
                          ? "rounded-bl-md border-l-2 border-accent bg-accent-subtle"
                          : "rounded-br-md bg-surface-raised"
                      }`}
                    >
                      {message.body}
                    </div>
                  </li>
                );
              })}
            </ul>
          </div>
        );
      })}
      <p className="px-4 py-3 text-caption text-text-tertiary">
        These messages were copied from the conversation by the server when the report was filed —
        they are shown exactly as they were sent. This read of message content has been recorded in
        the audit log.
      </p>
    </section>
  );
}
