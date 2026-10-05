import type { Metadata } from "next";
import { Card } from "@/components/ui";
import { ThemePicker } from "@/components/settings/ThemePicker";

export const metadata: Metadata = { title: "Appearance" };

export default function AppearanceSettingsPage() {
  return (
    <div className="flex flex-col gap-4">
      <h2 className="text-title">Appearance</h2>
      <Card className="flex flex-col gap-3">
        <h3 className="text-heading">Theme</h3>
        <ThemePicker />
        <p className="text-caption text-text-tertiary">
          Reduced motion follows your system setting automatically.
        </p>
      </Card>
    </div>
  );
}
