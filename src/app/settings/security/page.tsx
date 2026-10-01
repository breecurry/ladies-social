import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { SecurityPanel } from "@/components/SecurityPanel";

export const metadata: Metadata = { title: "Security" };

export default async function SecurityPage() {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");

  return (
    <div className="mx-auto flex max-w-xl flex-col gap-6">
      <h1 className="text-title">Two-factor authentication</h1>
      <SecurityPanel />
    </div>
  );
}
