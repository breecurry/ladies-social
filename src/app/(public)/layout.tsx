import Link from "next/link";
import { SiteHeader } from "@/components/SiteHeader";

/**
 * Public, signed-out surfaces: landing, log in, sign up, legal pages.
 * These keep the simple marketing header and narrow reading column; the
 * member app lives in the (member) group inside the full application
 * shell.
 */
export default function PublicLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <SiteHeader />
      <main className="mx-auto w-full max-w-3xl px-4 py-8">{children}</main>
      <footer className="mx-auto w-full max-w-3xl px-4 pb-8">
        <nav
          aria-label="Legal"
          className="flex flex-wrap items-center gap-x-4 gap-y-2 border-t border-border pt-4"
        >
          <Link
            href="/community-guidelines"
            className="text-caption text-text-tertiary underline underline-offset-2 hover:text-accent"
          >
            Community Guidelines
          </Link>
          <span className="text-caption text-text-tertiary">© Curry Co LLC</span>
        </nav>
      </footer>
    </>
  );
}
