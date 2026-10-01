import type { Json, TriageBucket } from "@/lib/database.types";
import { assessProfileCoherence } from "@/lib/admission/coherence";
import { isDisposableEmailDomain } from "@/lib/admission/disposable-domains";
import type { PhoneSignal } from "@/lib/admission/phone";

/**
 * Automated signup triage. Orders the human review queue (clean on top,
 * flagged at the bottom) and silently discards obvious automated abuse.
 *
 * HARD RULE (locked): every signal here is a BOT/ABUSE signal —
 * disposable email, line type, velocity, fingerprints, generated-text
 * patterns. Nothing is, or may ever be, based on appearance,
 * photographs, or gender. There is no photo anywhere in admission.
 */

export interface TriageInput {
  email: string;
  legalName: string;
  handle: string;
  phone: PhoneSignal;
  subnetSignups24h: number;
  fingerprintBanned: boolean;
  emailBanned: boolean;
  phoneBanned: boolean;
}

export interface TriageResult {
  bucket: TriageBucket;
  score: number;
  signals: Json;
}

const SUBNET_CLUSTER_THRESHOLD = 3; // signups from one /24 in 24h, besides this one
const FLAG_COHERENCE = 0.6;
const REJECT_COHERENCE = 0.85;

export function runTriage(input: TriageInput): TriageResult {
  const coherence = assessProfileCoherence(input);
  const disposable = isDisposableEmailDomain(input.email);
  const clustered = input.subnetSignups24h >= SUBNET_CLUSTER_THRESHOLD;
  const bannedMatch = input.fingerprintBanned || input.emailBanned || input.phoneBanned;

  const reasons: string[] = [...coherence.reasons];
  if (disposable) reasons.push("disposable email domain");
  if (clustered) reasons.push(`signup cluster: ${input.subnetSignups24h} from one subnet in 24h`);
  if (input.phone.flagged) {
    reasons.push(
      input.phone.valid === false
        ? "phone number failed validation"
        : `phone line type: ${input.phone.lineType ?? "unknown"}`,
    );
  }
  if (input.fingerprintBanned) reasons.push("device fingerprint matches a banned account");
  if (input.emailBanned) reasons.push("email matches a banned account");
  if (input.phoneBanned) reasons.push("phone matches a banned account");

  let bucket: TriageBucket = "clean";

  // Auto-reject: only stacked, unambiguous automation/ban-evasion
  // signals. Borderline cases ALWAYS go to a human instead.
  if (
    bannedMatch ||
    (disposable && clustered) ||
    (coherence.score >= REJECT_COHERENCE && (disposable || clustered))
  ) {
    bucket = "auto_rejected";
  } else if (disposable || clustered || input.phone.flagged || coherence.score >= FLAG_COHERENCE) {
    bucket = "flagged";
  }

  const score = Math.min(
    1,
    coherence.score +
      (disposable ? 0.3 : 0) +
      (clustered ? 0.3 : 0) +
      (input.phone.flagged ? 0.2 : 0) +
      (bannedMatch ? 1 : 0),
  );

  return {
    bucket,
    score: Number(score.toFixed(3)),
    signals: {
      score: Number(score.toFixed(3)),
      coherence_score: coherence.score,
      disposable_email: disposable,
      subnet_signups_24h: input.subnetSignups24h,
      phone_checked: input.phone.checked,
      phone_valid: input.phone.valid,
      phone_line_type: input.phone.lineType,
      phone_flagged: input.phone.flagged,
      fingerprint_banned: input.fingerprintBanned,
      email_banned: input.emailBanned,
      phone_banned: input.phoneBanned,
      reasons,
    },
  };
}
