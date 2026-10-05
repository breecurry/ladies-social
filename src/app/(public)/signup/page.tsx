import type { Metadata } from "next";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { AGE_GATE_COOKIE, getActiveAgeGateBlock, parseAgeGateCookie } from "@/lib/age-gate";
import { AgeGateBlocked } from "@/components/age-gate/AgeGateBlocked";
import { SignupForm } from "@/components/SignupForm";

export const metadata: Metadata = { title: "Join" };

export default async function SignupPage() {
  const viewer = await getViewer();
  if (viewer) redirect("/home");

  // A device that failed the age check within the last 14 days meets
  // the blocked screen instead of the signup form (spec §17.3). The
  // cookie carries only the block's reference code; the client-side
  // fingerprint check in SignupForm covers devices that cleared it.
  const cookieCode = parseAgeGateCookie((await cookies()).get(AGE_GATE_COOKIE)?.value);
  if (cookieCode) {
    const block = await getActiveAgeGateBlock(createSupabaseAdminClient(), null, cookieCode);
    if (block) {
      return (
        <div className="mx-auto w-full max-w-md">
          <AgeGateBlocked code={block.referenceCode} />
        </div>
      );
    }
  }

  return (
    <div className="mx-auto w-full max-w-md">
      <SignupForm />
    </div>
  );
}
