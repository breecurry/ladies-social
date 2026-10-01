import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { SignupForm } from "@/components/SignupForm";

export const metadata: Metadata = { title: "Join" };

export default async function SignupPage() {
  const viewer = await getViewer();
  if (viewer) {
    redirect(viewer.isAdmitted ? "/home" : "/pending");
  }

  return (
    <div className="mx-auto flex max-w-md flex-col gap-6">
      <div className="flex flex-col gap-2">
        <h1 className="text-title">Request to join</h1>
        <p className="text-body text-text-secondary">
          If a member invited you, name her below and she&apos;ll be asked to vouch for you.
          Otherwise your application waits for review.
        </p>
      </div>
      <SignupForm />
    </div>
  );
}
