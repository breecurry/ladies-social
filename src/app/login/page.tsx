import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";
import { LoginForm } from "@/components/LoginForm";

export const metadata: Metadata = { title: "Log in" };

export default async function LoginPage() {
  const viewer = await getViewer();
  if (viewer) {
    redirect(viewer.isAdmitted ? "/home" : "/pending");
  }

  return (
    <div className="mx-auto flex max-w-md flex-col gap-6">
      <h1 className="text-title">Log in</h1>
      <LoginForm />
    </div>
  );
}
