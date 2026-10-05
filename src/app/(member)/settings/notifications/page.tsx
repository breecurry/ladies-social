import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { Card } from "@/components/ui";
import { NotificationPrefsForm } from "@/components/settings/NotificationPrefsForm";

export const metadata: Metadata = { title: "Notifications" };

export default async function NotificationSettingsPage() {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");

  const supabase = await createSupabaseServerClient();
  const { data } = await supabase
    .from("notification_prefs")
    .select("prefs")
    .eq("user_id", viewer.user.id)
    .maybeSingle();

  const prefs =
    data && typeof data.prefs === "object" && data.prefs !== null && !Array.isArray(data.prefs)
      ? Object.fromEntries(
          Object.entries(data.prefs).filter(([, v]) => typeof v === "boolean"),
        )
      : {};

  return (
    <div className="flex flex-col gap-4">
      <h2 className="text-title">Notifications</h2>
      <Card>
        <NotificationPrefsForm initial={prefs as Record<string, boolean>} />
      </Card>
    </div>
  );
}
