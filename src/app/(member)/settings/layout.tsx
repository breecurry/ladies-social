import type { Metadata } from "next";
import { SettingsNav } from "@/components/settings/SettingsNav";

export const metadata: Metadata = { title: "Settings" };

/**
 * Settings IA (spec §8): Account, Privacy, Safety, Notifications,
 * Appearance, About — privacy and safety deliberately high in the
 * order. Two-pane on desktop, stacked nav on mobile.
 */
export default function SettingsLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-4 p-4 lg:mt-6 lg:flex-row lg:items-start lg:gap-6 lg:p-0">
      <h1 className="sr-only">Settings</h1>
      <SettingsNav />
      <div className="min-w-0 flex-1">{children}</div>
    </div>
  );
}
