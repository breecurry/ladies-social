import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { ProfileRow, SystemRole } from "@/lib/database.types";
import type { User } from "@supabase/supabase-js";

export interface Viewer {
  user: User;
  profile: ProfileRow | null;
  roles: SystemRole[];
  isOwner: boolean;
  isAdminOrOwner: boolean;
  isReviewer: boolean;
  isAdmitted: boolean;
}

/** Load the signed-in user with her profile and active roles (RLS-scoped). */
export async function getViewer(): Promise<Viewer | null> {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const [{ data: profile }, { data: roleRows }] = await Promise.all([
    supabase.from("profiles").select("*").eq("user_id", user.id).maybeSingle(),
    supabase
      .from("role_assignments")
      .select("role, revoked_at")
      .eq("user_id", user.id)
      .is("revoked_at", null),
  ]);

  const roles = (roleRows ?? []).map((row) => row.role as SystemRole);
  const isOwner = roles.includes("owner");
  const isAdminOrOwner = isOwner || roles.includes("admin");
  return {
    user,
    profile: profile ?? null,
    roles,
    isOwner,
    isAdminOrOwner,
    isReviewer: isAdminOrOwner || roles.includes("moderator") || roles.includes("ts_reviewer"),
    isAdmitted:
      profile !== null &&
      profile.trust_level !== "pending_vouch" &&
      (profile.status === "active" || profile.status === "restricted"),
  };
}
