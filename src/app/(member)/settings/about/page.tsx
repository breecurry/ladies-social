import type { Metadata } from "next";
import Link from "next/link";
import { Card } from "@/components/ui";

export const metadata: Metadata = { title: "About and legal" };

export default function AboutSettingsPage() {
  return (
    <div className="flex flex-col gap-4">
      <h2 className="text-title">About and legal</h2>
      <Card className="flex flex-col gap-3">
        <h3 className="text-heading">Hersciety</h3>
        <p className="max-w-prose text-body text-text-secondary">
          A social platform built as a safe space for women and their allies. Operated by Curry Co
          LLC. Open to everyone 18 and over; what keeps this space safe is conduct, not identity.
        </p>
        <p className="text-caption text-text-tertiary">Version: Phase 2A (social core)</p>
      </Card>
      <Card className="flex flex-col gap-3">
        <h3 className="text-heading">Documents</h3>
        <ul className="flex flex-col gap-1 text-body text-text-secondary">
          <li>
            <Link className="text-accent underline" href="/community-guidelines">
              Community Guidelines
            </Link>
          </li>
        </ul>
        <p className="max-w-prose text-body text-text-secondary">
          The Terms of Service and Privacy Policy are being finalised with counsel and will be
          published before launch.
        </p>
      </Card>
      <Card className="flex flex-col gap-3">
        <h3 className="text-heading">Contact</h3>
        <ul className="flex flex-col gap-1 text-body text-text-secondary">
          <li>
            Safety concerns:{" "}
            <a className="text-accent underline" href="mailto:safety@unitedfeminist.com">
              safety@unitedfeminist.com
            </a>
          </li>
          <li>
            Appeals:{" "}
            <a className="text-accent underline" href="mailto:appeals@unitedfeminist.com">
              appeals@unitedfeminist.com
            </a>
          </li>
          <li>
            Support:{" "}
            <a className="text-accent underline" href="mailto:support@unitedfeminist.com">
              support@unitedfeminist.com
            </a>
          </li>
        </ul>
      </Card>
    </div>
  );
}
