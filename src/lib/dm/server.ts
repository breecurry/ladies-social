import { createSupabaseServerClient } from "@/lib/supabase/server";
import { dmEnvEnabled } from "@/lib/dm/flag";

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
