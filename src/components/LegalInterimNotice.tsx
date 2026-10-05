import Link from "next/link";

/**
 * Interim page for a legal document that is written but not yet
 * published (pending counsel review — see `published` in
 * src/lib/legal.ts). Returns a normal 200 page so the canonical URL the
 * other documents cite never 404s.
 */
export function LegalInterimNotice({ documentName }: { documentName: string }) {
  return (
    <article className="mx-auto flex w-full max-w-prose flex-col gap-4 py-4">
      <h1 className="text-display text-text-primary">{documentName}</h1>
      <p className="text-body-lg text-text-primary">
        The Hersciety {documentName} is being finalised with counsel and will be published on this
        page before launch.
      </p>
      <p className="text-body-lg text-text-primary">
        Until then, conduct on the platform is governed by the{" "}
        <Link href="/community-guidelines" className="text-accent underline underline-offset-2">
          Community Guidelines
        </Link>
        , which are in force today.
      </p>
      <p className="text-body text-text-secondary">
        Questions in the meantime? Contact{" "}
        <a
          href="mailto:support@unitedfeminist.com"
          className="text-accent underline underline-offset-2"
        >
          support@unitedfeminist.com
        </a>
        .
      </p>
    </article>
  );
}
