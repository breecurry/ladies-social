import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/shell/AppShell";
import { Providers } from "@/components/shell/Providers";
import { Card } from "@/components/ui";

/**
 * Every signed-in surface lives inside the application shell: desktop
 * left rail + centred 600px column, mobile bottom tab bar, compose
 * modal and toasts via providers.
 */
export default async function MemberLayout({ children }: { children: React.ReactNode }) {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");

  if (!viewer.isActiveMember || !viewer.profile) {
    return (
      <main className="mx-auto w-full max-w-md px-4 py-16">
        <h1 className="mb-6 text-title">Account unavailable</h1>
        <Card className="flex flex-col gap-3">
          <p className="text-body text-text-secondary">
            This account is currently suspended or closed. If you believe this is a mistake,
            contact{" "}
            <a className="text-accent underline" href="mailto:appeals@unitedfeminist.com">
              appeals@unitedfeminist.com
            </a>
            .
          </p>
        </Card>
      </main>
    );
  }

  const supabase = await createSupabaseServerClient();
  const { count } = await supabase
    .from("notifications")
    .select("id", { count: "exact", head: true })
    .is("read_at", null);

  return (
    <Providers viewer={{ id: viewer.user.id, handle: viewer.profile.handle }}>
      <AppShell handle={viewer.profile.handle} isOwner={viewer.isOwner} initialUnread={count ?? 0}>
        {children}
      </AppShell>
    </Providers>
  );
}
