import { optionalEnv } from "@/lib/env";

/**
 * Phone validity + line-type signal via Twilio Lookup v2.
 * VOIP and prepaid numbers are flagged (ban-evasion / burner signal);
 * they are never an automatic rejection on their own.
 * Without Twilio credentials the signal is "unavailable" and neutral.
 */
export interface PhoneSignal {
  checked: boolean;
  valid: boolean | null;
  lineType: string | null;
  flagged: boolean;
}

const FLAGGED_LINE_TYPES = new Set(["nonFixedVoip", "fixedVoip", "voip", "prepaid", "pager"]);

interface TwilioLookupResponse {
  valid?: boolean;
  line_type_intelligence?: { type?: string | null } | null;
}

export async function lookupPhone(phoneE164: string): Promise<PhoneSignal> {
  const sid = optionalEnv("TWILIO_ACCOUNT_SID");
  const token = optionalEnv("TWILIO_AUTH_TOKEN");
  if (!sid || !token || !phoneE164) {
    return { checked: false, valid: null, lineType: null, flagged: false };
  }
  try {
    const response = await fetch(
      `https://lookups.twilio.com/v2/PhoneNumbers/${encodeURIComponent(phoneE164)}?Fields=line_type_intelligence`,
      {
        headers: {
          Authorization: `Basic ${Buffer.from(`${sid}:${token}`).toString("base64")}`,
        },
        signal: AbortSignal.timeout(5000),
      },
    );
    if (!response.ok) {
      // 404 = number does not exist / is invalid.
      if (response.status === 404) {
        return { checked: true, valid: false, lineType: null, flagged: true };
      }
      return { checked: false, valid: null, lineType: null, flagged: false };
    }
    const body = (await response.json()) as TwilioLookupResponse;
    const lineType = body.line_type_intelligence?.type ?? null;
    const valid = body.valid ?? null;
    const flagged = valid === false || (lineType !== null && FLAGGED_LINE_TYPES.has(lineType));
    return { checked: true, valid, lineType, flagged };
  } catch {
    return { checked: false, valid: null, lineType: null, flagged: false };
  }
}
