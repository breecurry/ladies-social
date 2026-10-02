/**
 * Uniform-timing helper for responses that must not leak, through
 * latency, which internal branch was taken.
 *
 * Under open registration the branch this hides is the ban-evasion
 * refusal: a signup whose email or device hash matches a banned
 * account is answered with the exact same body as a successful signup,
 * but creates nothing — a much shorter code path. Padding every
 * post-validation response to a fixed floor with random jitter makes
 * the difference unmeasurable, so a banned person cannot confirm from
 * timing that she was detected.
 */
const FLOOR_MS = 1400;
const JITTER_MS = 150;

export async function padToUniformTime(startedAt: number): Promise<void> {
  const elapsed = Date.now() - startedAt;
  const target = FLOOR_MS + Math.random() * JITTER_MS;
  const remaining = target - elapsed;
  if (remaining > 0) {
    await new Promise((resolve) => setTimeout(resolve, remaining));
  }
}
