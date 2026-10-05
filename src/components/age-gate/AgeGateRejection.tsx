import Link from "next/link";
import { Hourglass } from "@phosphor-icons/react/dist/ssr";

/**
 * The under-18 rejection screen (spec §17.2). Someone has just been
 * told no. She may be sixteen; she is a member in two years. Clear,
 * warm, brief — and it collects and displays NOTHING identifying. No
 * email field, no name, no "notify me", no contact form (§17.4). The
 * only control is the link back out. If a future revision feels the
 * urge to add a "we will remind you" email box here, do not: that
 * urge is the violation.
 */
export function AgeGateRejection() {
  return (
    <div className="mx-auto flex w-full max-w-md flex-col items-center gap-6 py-12 text-center">
      <Hourglass size={64} aria-hidden className="text-text-tertiary" />
      <h1 className="text-title text-text-primary">You need to be 18 to join.</h1>
      <p className="max-w-prose text-body-lg text-text-secondary">
        Hersciety is for adults 18 and over. You cannot create an account right now. We are not
        going anywhere — we hope to see you in a few years.
      </p>
      <Link
        href="/"
        className="min-h-11 content-center text-body text-accent underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-focus-ring"
      >
        Back to Hersciety
      </Link>
    </div>
  );
}
