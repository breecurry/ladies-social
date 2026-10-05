import Link from "next/link";
import { redirect } from "next/navigation";
import { getViewer } from "@/lib/auth";

export default async function LandingPage() {
  const viewer = await getViewer();
  if (viewer) redirect("/home");

  return (
    <div className="flex flex-col gap-8 py-12">
      <div className="flex flex-col gap-4">
        <h1 className="text-display text-text-primary">United Feminist</h1>
        <p className="max-w-prose text-body-lg text-text-secondary">
          A social platform built as a safe space for women and their allies. Simple on the surface,
          genuinely sophisticated underneath. Safety is architecture here, not a settings page.
        </p>
        <p className="max-w-prose text-body text-text-tertiary">
          Everyone is welcome to join. What keeps this space safe is conduct, not identity: bullying
          and harassment are not tolerated, and accounts that cross that line are removed. You must
          be 18 or older.
        </p>
      </div>
      <div className="flex flex-wrap gap-3">
        <Link
          href="/signup"
          className="inline-flex min-h-11 items-center rounded-md bg-accent-fill px-6 text-label text-on-accent transition-colors duration-(--duration-fast) hover:bg-accent-hover"
        >
          Join
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
