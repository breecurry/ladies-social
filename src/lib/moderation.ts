import type { ReportReason, SystemRole } from "@/lib/database.types";

/**
 * Shared vocabulary for the moderation console.
 *
 * 🚨 IDENTITY RULE: nothing in this module, and nothing in any console
 * surface, ever handles display_name. Every person — reporter and
 * accused alike — is an @handle.
 */

/** The console tier a set of roles grants. Mirrors mod_actor_tier(). */
export type ModTier = "none" | "reviewer" | "moderator" | "admin" | "owner";

export function modTier(roles: SystemRole[]): ModTier {
  if (roles.includes("owner")) return "owner";
  if (roles.includes("admin")) return "admin";
  if (roles.includes("moderator")) return "moderator";
  if (roles.includes("ts_reviewer")) return "reviewer";
  return "none";
}

/** Can this tier take any enforcement action at all? */
export function canAct(tier: ModTier): boolean {
  return tier === "moderator" || tier === "admin" || tier === "owner";
}

/** Can this tier apply restrictions/suspensions longer than 7 days? */
export function canExceedSevenDays(tier: ModTier): boolean {
  return tier === "admin" || tier === "owner";
}

/** Ban is Admin and Owner only — a locked owner decision. */
export function canBan(tier: ModTier): boolean {
  return tier === "admin" || tier === "owner";
}

export const TIER_LABEL: Record<ModTier, string> = {
  none: "",
  reviewer: "Reviewer",
  moderator: "Moderator",
  admin: "Admin",
  owner: "Owner",
};

/** Plain-language rule labels — the same vocabulary members report with. */
export const REASON_LABEL: Record<ReportReason, string> = {
  harassment: "Harassment or bullying",
  hate: "Hate speech",
  violence_threat: "Threat of violence",
  doxxing: "Sharing private information",
  csam: "Content involving a minor",
  ncii: "Sexual content or harassment",
  spam: "Spam or scam",
  impersonation: "Impersonation",
  self_harm: "Self-harm",
  other: "Other",
};

/** csam cases resolve only at the Owner; everyone else escalates. */
export function isOwnerOnlyReason(reason: ReportReason): boolean {
  return reason === "csam";
}

/**
 * A case key for URLs: the accused user id, plus the subject post id
 * for post-level cases. "uuid" or "uuid~postId".
 */
export function caseKey(accusedId: string, postId: number | null): string {
  return postId === null ? accusedId : `${accusedId}~${postId}`;
}

export function parseCaseKey(key: string): { accusedId: string; postId: number | null } | null {
  const [accusedId, postPart] = key.split("~", 2);
  if (!accusedId || !/^[0-9a-f-]{36}$/i.test(accusedId)) return null;
  if (postPart === undefined) return { accusedId, postId: null };
  const postId = Number(postPart);
  if (!Number.isInteger(postId) || postId <= 0) return null;
  return { accusedId, postId };
}
