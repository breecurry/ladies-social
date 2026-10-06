/**
 * The DM feature flag, environment side. Two layers, both OFF by
 * default:
 *
 *   1. env DM_ENABLED="true" — read here, server-side only. Gates
 *      every DM page, nav entry, and /api/dm/* route per deployment
 *      environment.
 *   2. app_config key 'dm_enabled' = true — enforced inside every DM
 *      database function, so a hand-crafted RPC call cannot reach DMs
 *      either while the feature is off.
 *
 * Both are flipped deliberately by the Owner; see KNOWLEDGE/app.md.
 * Off means the surfaces are not reachable at all.
 */
export function dmEnvEnabled(): boolean {
  return process.env.DM_ENABLED === "true";
}
