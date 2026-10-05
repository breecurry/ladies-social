import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { optionalEnv } from "@/lib/env";

/**
 * Dispatch the safety@ email copies queued in safety_email_outbox.
 *
 * OWNER DECISION (2026-10-05): every report emails
 * safety@unitedfeminist.com so two independently traceable copies
 * exist. The DURABLE record is the outbox row, written inside
 * file_report() in the same transaction as the report itself — a
 * report can never exist without its copy being queued. This module
 * only delivers what is queued.
 *
 * ── THE SINGLE EMAIL INTEGRATION POINT ──────────────────────────────
 * Delivery uses the Resend HTTP API and requires RESEND_API_KEY in the
 * server environment (the same Resend account that already powers the
 * Supabase auth SMTP sender; create a key at resend.com and add it to
 * the deployment env). Until that variable exists, rows stay queued
 * with sent_at NULL — nothing is lost and nothing pretends to be sent.
 * Dispatch is retried on every new report and on every console load.
 * ────────────────────────────────────────────────────────────────────
 *
 * The queued bodies carry a case reference and minimal metadata only —
 * never the reporter, the report text, or any legal name (email is the
 * least secure channel, so it gets the notification, not the contents).
 */

const MAX_ATTEMPTS = 8;
const BATCH = 10;

export async function dispatchSafetyEmails(): Promise<void> {
  const apiKey = optionalEnv("RESEND_API_KEY");
  if (!apiKey) return; // queued durably; delivered once the key exists

  const from = optionalEnv("SAFETY_EMAIL_FROM") ?? "Hersciety <noreply@hersciety.com>";
  const admin = createSupabaseAdminClient();

  const { data: pending } = await admin
    .from("safety_email_outbox")
    .select("id, recipient, subject, body, attempts")
    .is("sent_at", null)
    .lt("attempts", MAX_ATTEMPTS)
    .order("created_at", { ascending: true })
    .limit(BATCH);
  if (!pending || pending.length === 0) return;

  for (const row of pending) {
    let errorText: string | null = null;
    try {
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from,
          to: [row.recipient],
          subject: row.subject,
          text: row.body,
        }),
      });
      if (!response.ok) {
        errorText = `Resend responded ${response.status}`;
      }
    } catch {
      errorText = "Network error reaching Resend";
    }

    await admin
      .from("safety_email_outbox")
      .update(
        errorText === null
          ? { sent_at: new Date().toISOString(), attempts: row.attempts + 1, last_error: null }
          : { attempts: row.attempts + 1, last_error: errorText },
      )
      .eq("id", row.id);
  }
}

/** Fire-and-forget wrapper: delivery must never break the caller. */
export function dispatchSafetyEmailsInBackground(): void {
  void dispatchSafetyEmails().catch(() => {
    // The outbox rows remain queued; the next dispatch retries.
  });
}
