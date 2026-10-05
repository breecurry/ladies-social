import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { SignupForm } from "@/components/SignupForm";

export const metadata: Metadata = { title: "Join" };

export default async function SignupPage() {
  const viewer = await getViewer();
  if (viewer) redirect("/home");

  return (
    <div className="mx-auto flex max-w-md flex-col gap-6">
      <div className="flex flex-col gap-2">
        <h1 className="text-title">Create your account</h1>
        <p className="text-body text-text-secondary">
          Joining takes an email address, a handle and your legal name. Your legal name stays
          private unless you choose to show it.
        </p>
      </div>
      <SignupForm />
    </div>
  );
}
