import Link from "next/link";
import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";

export default async function LandingPage() {
  const viewer = await getViewer();
  if (viewer) {
    redirect(viewer.isAdmitted ? "/home" : "/pending");
  }

  return (
    <div className="flex flex-col gap-8 py-12">
      <div className="flex flex-col gap-4">
        <h1 className="text-display text-text-primary">United Feminist</h1>
        <p className="max-w-prose text-body-lg text-text-secondary">
          A social platform built as a safe space for women and their allies. Simple on the surface,
          genuinely sophisticated underneath — and safety is architecture here, not a settings page.
        </p>
        <p className="max-w-prose text-body text-text-tertiary">
          Admission is by vouching or human review. Nobody is ever judged by appearance,
          photographs, or gender — the standard is behaviour. You must be 18 or older.
        </p>
      </div>
      <div className="flex flex-wrap gap-3">
        <Link
          href="/signup"
          className="inline-flex min-h-11 items-center rounded-md bg-accent-fill px-6 text-label text-on-accent transition-colors duration-(--duration-fast) hover:bg-accent-hover"
        >
          Request to join
        </Link>
        <Link
          href="/login"
          className="inline-flex min-h-11 items-center rounded-md border border-border-strong bg-surface px-6 text-label text-text-primary transition-colors duration-(--duration-fast) hover:bg-surface-raised"
        >
          Log in
        </Link>
      </div>
    </div>
  );
}
