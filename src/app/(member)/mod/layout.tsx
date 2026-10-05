import { redirect } from "next/navigation";
import { ShieldCheck } from "@phosphor-icons/react/dist/ssr";
import { getViewer } from "@/lib/auth";
import { modTier, TIER_LABEL } from "@/lib/moderation";

/**
 * The moderation console (design doc Part 1). A privileged management
 * surface reached from the account menu, never from the primary nav.
 * Members without a staff role are redirected and never learn the
 * surface exists.
 *
 * The quiet identity strip below the top bar is orientation, not
 * decoration: a moderator is never in doubt that she is in the
 * privileged tool rather than the public app.
 */
export default async function ModLayout({ children }: { children: React.ReactNode }) {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  const tier = modTier(viewer.roles);
  if (tier === "none") redirect("/home");

  return (
    <div className="flex flex-col">
      <div className="flex h-8 items-center gap-2 bg-accent-subtle px-4">
        <ShieldCheck size={16} weight="fill" aria-hidden className="text-accent" />
        <span className="text-label text-accent">Moderation</span>
        <span className="text-caption text-text-secondary">{TIER_LABEL[tier]}</span>
      </div>
      {children}
    </div>
  );
}
