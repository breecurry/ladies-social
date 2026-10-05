/**
 * The DM feature flag, environment side. Two layers, both named
 * dm_e2e_enabled, both OFF by default:
 *
 *   1. env DM_E2E_ENABLED="true" — read here, server-side only. Gates
 *      every DM page, nav entry, and /api/dm/* route per deployment
 *      environment (preview on, production off).
 *   2. app_config key 'dm_e2e_enabled' = true — enforced inside every
 *      DM database function, so a hand-crafted RPC call cannot reach
 *      DMs either while the feature is off.
 *
 * Both are flipped deliberately after the external crypto audit; see
 * KNOWLEDGE/app.md. There is no readable-by-anyone fallback: off means
 * the surfaces are not reachable.
 */
export function dmEnvEnabled(): boolean {
  return process.env.DM_E2E_ENABLED === "true";
}
