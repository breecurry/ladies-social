/**
 * Uniform-timing helper for responses that must not leak, through
 * latency, which internal branch was taken.
 *
 * The signup endpoint's handle-resolution branch differs by one indexed
 * lookup and one insert (~1–3 ms). Padding every response to a fixed
 * floor with random jitter makes that difference unmeasurable: the
 * floor dwarfs the branch delta, and the jitter drowns residual noise.
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
