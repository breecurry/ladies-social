import type { Json } from "@/lib/database.types";
import { assessProfileCoherence } from "@/lib/signup/coherence";
import { isDisposableEmailDomain } from "@/lib/signup/disposable-domains";

/**
 * Automated signup triage: the bot pre-filter. Under open registration
 * there is no review queue; these signals AUTO-FLAG an account (the
 * flags are stored on the private record and in the audit log for the
 * Owner to act on) but never block it. The only thing that blocks a
 * signup outright is a banned-identifier match, which the API route and
 * create_member() check separately — that is ban-evasion enforcement,
 * not triage.
 *
 * HARD RULE (locked): every signal here is a BOT/ABUSE signal —
 * disposable email, velocity, generated-text patterns. Nothing is, or
 * may ever be, based on appearance, photographs, or gender.
 */

export interface SignupTriageInput {
  email: string;
  legalName: string;
  handle: string;
  subnetSignups24h: number;
}

export interface SignupTriageResult {
  flagged: boolean;
  score: number;
  signals: Json;
}

const SUBNET_CLUSTER_THRESHOLD = 3; // signups from one /24 in 24h, besides this one
const FLAG_COHERENCE = 0.6;

export function runSignupTriage(input: SignupTriageInput): SignupTriageResult {
  const coherence = assessProfileCoherence(input);
  const disposable = isDisposableEmailDomain(input.email);
  const clustered = input.subnetSignups24h >= SUBNET_CLUSTER_THRESHOLD;

  const reasons: string[] = [...coherence.reasons];
  if (disposable) reasons.push("disposable email domain");
  if (clustered) reasons.push(`signup cluster: ${input.subnetSignups24h} from one subnet in 24h`);

  const flagged = disposable || clustered || coherence.score >= FLAG_COHERENCE;

  const score = Math.min(
    1,
    coherence.score + (disposable ? 0.3 : 0) + (clustered ? 0.3 : 0),
  );

  return {
    flagged,
    score: Number(score.toFixed(3)),
    signals: {
      score: Number(score.toFixed(3)),
      coherence_score: coherence.score,
      disposable_email: disposable,
      subnet_signups_24h: input.subnetSignups24h,
      reasons,
    },
  };
}
