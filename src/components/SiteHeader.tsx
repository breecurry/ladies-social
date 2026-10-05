import Link from "next/link";
import { getViewer } from "@/lib/auth";

/**
 * Public (signed-out) marketing header. Signed-in members are
 * redirected into the app shell by the public pages themselves; if a
 * session exists the header simply offers the way back in.
 */
export async function SiteHeader() {
  const viewer = await getViewer();

  return (
    <header className="sticky top-0 z-10 border-b border-border bg-surface shadow-sticky">
      <nav
        aria-label="Primary"
        className="mx-auto flex max-w-3xl items-center justify-between gap-4 px-4 py-3"
      >
        <Link href="/" className="text-heading text-text-primary">
          Hersciety
        </Link>
        <div className="flex items-center gap-1">
          {viewer ? (
            <Link
              href="/home"
              className="inline-flex min-h-11 items-center rounded-md bg-accent-fill px-4 text-label text-on-accent transition-colors duration-(--duration-fast) hover:bg-accent-hover"
            >
              Open the app
            </Link>
          ) : (
            <>
              <Link
                href="/login"
                className="inline-flex min-h-11 items-center rounded-md px-3 text-label text-text-secondary transition-colors duration-(--duration-fast) hover:bg-accent-subtle hover:text-accent"
              >
                Log in
              </Link>
              <Link
                href="/signup"
                className="inline-flex min-h-11 items-center rounded-md bg-accent-fill px-4 text-label text-on-accent transition-colors duration-(--duration-fast) hover:bg-accent-hover"
              >
                Join
              </Link>
            </>
          )}
        </div>
      </nav>
    </header>
  );
}
