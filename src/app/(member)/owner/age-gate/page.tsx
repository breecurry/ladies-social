import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { Card } from "@/components/ui";
import { AgeGateSupport } from "@/components/AgeGateSupport";

export const metadata: Metadata = { title: "Age gate" };

/**
 * Owner-only support tool for the age-gate device block (spec §17.3).
 * Pull, not push: nothing notifies anyone of a block. When someone
 * emails support@unitedfeminist.com and quotes the code from her
 * blocked screen, it is looked up here and cleared. Authority is
 * enforced in the database (the lookup/clear functions re-check the
 * Owner), not just by this page's redirect.
 */
export default async function OwnerAgeGatePage() {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  if (!viewer.isOwner) redirect("/home");

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-2">
        <h1 className="text-title">Age gate</h1>
        <p className="max-w-prose text-body text-text-secondary">
          A device that enters an under-18 date of birth is blocked from the signup form for 14
          days. If someone entered the wrong date, she emails support and quotes the reference
          code from her screen; look it up here and clear it. A block stores no name, no email,
          and no date — only a hashed device signal, timestamps and the code — so there is
          nothing to identify anyone by except the code she quotes.
        </p>
      </div>

      <Card className="flex flex-col gap-3">
        <h2 className="text-heading">Look up a reference code</h2>
        <AgeGateSupport />
      </Card>
    </div>
  );
}
