import Link from "next/link";
import { getViewer } from "@/lib/auth";
import { LogoutButton } from "@/components/LogoutButton";

export async function SiteHeader() {
  const viewer = await getViewer();

  return (
    <header className="sticky top-0 z-10 border-b border-border bg-surface shadow-sticky">
      <nav
        aria-label="Primary"
        className="mx-auto flex max-w-3xl items-center justify-between gap-4 px-4 py-3"
      >
        <Link href="/" className="text-heading text-text-primary">
          United Feminist
        </Link>
        <div className="flex items-center gap-1">
          {viewer ? (
            <>
              {viewer.isAdmitted ? (
                <>
                  <HeaderLink href="/home" label="Home" />
                  <HeaderLink href="/vouches" label="Vouches" />
                  <HeaderLink href="/settings" label="Settings" />
                </>
              ) : (
                <HeaderLink href="/pending" label="Application" />
              )}
              {viewer.isReviewer ? <HeaderLink href="/review" label="Review" /> : null}
              {viewer.isOwner ? (
                <>
                  <HeaderLink href="/owner/roles" label="Roles" />
                  <HeaderLink href="/owner/audit" label="Audit" />
                </>
              ) : null}
              <LogoutButton />
            </>
          ) : (
            <>
              <HeaderLink href="/login" label="Log in" />
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

function HeaderLink({ href, label }: { href: string; label: string }) {
  return (
    <Link
      href={href}
      className="inline-flex min-h-11 items-center rounded-md px-3 text-label text-text-secondary transition-colors duration-(--duration-fast) hover:bg-accent-subtle hover:text-accent"
    >
      {label}
    </Link>
  );
}
