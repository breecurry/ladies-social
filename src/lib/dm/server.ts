import { createSupabaseServerClient } from "@/lib/supabase/server";
import { dmEnvEnabled } from "@/lib/dm/flag";
import { DM_DISCLOSURE_QUIET_DAYS, DM_DISCLOSURE_VERSION } from "@/lib/dm/disclosure";

/**
 * Is the DM feature on for this request? Both layers must agree: the
 * environment flag (per deployment) AND the database flag (enforced
 * inside every DM function). Any error — including the migration not
 * being applied yet — reads as OFF, so the app degrades to "the
 * feature does not exist" rather than erroring.
 */
export async function dmFeatureOn(): Promise<boolean> {
  if (!dmEnvEnabled()) return false;
  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.rpc("dm_feature_enabled");
    if (error) return false;
    return data === true;
  } catch {
    return false;
  }
}

/**
 * Should the signed-in member see the DM disclosure banner? Resolved
 * on the server (and passed to the clients as a prop) so the banner
 * never flashes in or out after mount. The rule lives in
 * dm_disclosure_should_show(): show when never dismissed (including
 * no dm_settings row), when the dismissed version is older than
 * DM_DISCLOSURE_VERSION, or when the dismissal is older than
 * DM_DISCLOSURE_QUIET_DAYS days.
 *
 * FAILS TOWARD SHOWING: if the migration is not applied yet, the RPC
 * errors, or the result is anything but an explicit `false`, the
 * banner shows. The safe failure direction for a disclosure is
 * visible.
 */
export async function shouldShowDmDisclosure(): Promise<boolean> {
  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.rpc("dm_disclosure_should_show", {
      p_current_version: DM_DISCLOSURE_VERSION,
      p_quiet_days: DM_DISCLOSURE_QUIET_DAYS,
    });
    if (error) return true;
    return data !== false;
  } catch {
    return true;
  }
}
