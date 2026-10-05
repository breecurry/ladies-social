"use client";

import { useState, type ReactNode } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import {
  House,
  MagnifyingGlass,
  Bell,
  PencilSimple,
  CaretLeft,
  CaretUp,
  GearSix,
  SignOut,
  ShieldStar,
} from "@phosphor-icons/react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { useCompose } from "@/components/shell/ComposeProvider";

/**
 * The application shell (spec §1): desktop left rail (>=lg) with a
 * centred 600px reading column; mobile 5-slot bottom tab bar with a
 * thin sticky top bar. Compose is an action, not a destination.
 */
export function AppShell({
  handle,
  isOwner,
  initialUnread,
  children,
}: {
  handle: string;
  isOwner: boolean;
  initialUnread: number;
  children: ReactNode;
}) {
  const pathname = usePathname();
  const { openCompose } = useCompose();
  const isHome = pathname === "/home";

  const navItems = [
    { href: "/home", label: "Home", icon: House, active: pathname === "/home" },
    {
      href: "/search",
      label: "Search",
      icon: MagnifyingGlass,
      active: pathname.startsWith("/search"),
    },
    {
      href: "/notifications",
      label: "Notifications",
      icon: Bell,
      active: pathname.startsWith("/notifications"),
      badge: initialUnread,
    },
  ] as const;

  const profileActive = pathname === `/u/${handle}`;

  return (
    <div className="mx-auto flex min-h-dvh w-full max-w-[920px] justify-center lg:gap-6">
      {/* Desktop left rail */}
      <nav
        aria-label="Primary"
        className="sticky top-0 hidden h-dvh w-60 shrink-0 flex-col gap-1 py-6 lg:flex"
      >
        <Link href="/home" className="mb-4 px-3 text-heading text-text-primary">
          Hersciety
        </Link>
        {navItems.map((item) => (
          <RailLink key={item.href} {...item} />
        ))}
        <RailLink
          href={`/u/${handle}`}
          label="Profile"
          active={profileActive}
          avatarLetter={handle.charAt(0).toUpperCase()}
        />
        <button
          type="button"
          onClick={() => openCompose()}
          className="mx-4 mt-4 flex min-h-12 items-center justify-center gap-2 rounded-full bg-accent-fill text-label text-on-accent shadow-e1 transition-colors duration-(--duration-fast) hover:bg-accent-hover"
        >
          <PencilSimple size={20} weight="bold" aria-hidden />
          Compose
        </button>
        <div className="mt-auto">
          <AccountMenu handle={handle} isOwner={isOwner} />
        </div>
      </nav>

      {/* Centre column */}
      <div className="flex w-full max-w-[600px] flex-col">
        {/* Mobile top bar */}
        <header className="sticky top-0 z-20 flex h-12 items-center gap-1 bg-surface px-2 shadow-sticky lg:hidden">
          {isHome ? (
            <span className="px-2 text-heading text-text-primary">Hersciety</span>
          ) : (
            <BackButton />
          )}
        </header>
        <main className="flex-1 pb-[calc(72px+env(safe-area-inset-bottom))] lg:pb-8">
          {children}
        </main>
      </div>

      {/* Mobile bottom tab bar */}
      <nav
        aria-label="Primary"
        className="fixed inset-x-0 bottom-0 z-20 flex h-[calc(56px+env(safe-area-inset-bottom))] items-start justify-around border-t border-border bg-surface pb-[env(safe-area-inset-bottom)] shadow-sticky lg:hidden"
      >
        <TabLink href="/home" label="Home" icon={House} active={pathname === "/home"} />
        <TabLink
          href="/search"
          label="Search"
          icon={MagnifyingGlass}
          active={pathname.startsWith("/search")}
        />
        <button
          type="button"
          aria-label="Compose"
          onClick={() => openCompose()}
          className="flex h-14 min-w-11 items-center justify-center"
        >
          <span className="flex size-11 items-center justify-center rounded-md bg-accent-fill text-on-accent">
            <PencilSimple size={22} weight="bold" aria-hidden />
          </span>
        </button>
        <TabLink
          href="/notifications"
          label="Notifications"
          icon={Bell}
          active={pathname.startsWith("/notifications")}
          badge={initialUnread}
        />
        <Link
          href={`/u/${handle}`}
          aria-label="Profile"
          aria-current={profileActive ? "page" : undefined}
          className="flex h-14 min-w-11 items-center justify-center"
        >
          <span
            className={`flex size-7 items-center justify-center rounded-full bg-accent-subtle text-caption font-semibold text-accent ${
              profileActive ? "ring-2 ring-accent" : ""
            }`}
            aria-hidden
          >
            {handle.charAt(0).toUpperCase()}
          </span>
        </Link>
      </nav>
    </div>
  );
}

function UnreadBadge({ count }: { count: number }) {
  if (count <= 0) return null;
  return (
    <span
      aria-label={`${count} unread`}
      className="absolute -right-1.5 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-danger-fill px-1 text-micro text-white"
    >
      {count > 9 ? "9+" : count}
    </span>
  );
}

function RailLink({
  href,
  label,
  icon: Icon,
  active,
  badge,
  avatarLetter,
}: {
  href: string;
  label: string;
  icon?: typeof House;
  active: boolean;
  badge?: number;
  avatarLetter?: string;
}) {
  return (
    <Link
      href={href}
      aria-current={active ? "page" : undefined}
      className={`relative flex min-h-11 items-center gap-3 rounded-md px-3 text-label transition-colors duration-(--duration-fast) hover:bg-surface-raised ${
        active ? "text-accent" : "text-text-secondary"
      }`}
    >
      {active ? (
        <span aria-hidden className="absolute inset-y-2 left-0 w-0.5 rounded-full bg-accent" />
      ) : null}
      {Icon ? (
        <span className="relative">
          <Icon size={24} weight={active ? "fill" : "regular"} aria-hidden />
          <UnreadBadge count={badge ?? 0} />
        </span>
      ) : (
        <span
          aria-hidden
          className={`flex size-6 items-center justify-center rounded-full bg-accent-subtle text-micro font-semibold text-accent ${
            active ? "ring-2 ring-accent" : ""
          }`}
        >
          {avatarLetter}
        </span>
      )}
      {label}
    </Link>
  );
}

function TabLink({
  href,
  label,
  icon: Icon,
  active,
  badge,
}: {
  href: string;
  label: string;
  icon: typeof House;
  active: boolean;
  badge?: number;
}) {
  return (
    <Link
      href={href}
      aria-label={label}
      aria-current={active ? "page" : undefined}
      className={`flex h-14 min-w-11 items-center justify-center ${
        active ? "text-accent" : "text-text-secondary"
      }`}
    >
      <span className="relative">
        <Icon size={24} weight={active ? "fill" : "regular"} aria-hidden />
        <UnreadBadge count={badge ?? 0} />
      </span>
    </Link>
  );
}

function BackButton() {
  const router = useRouter();
  return (
    <button
      type="button"
      aria-label="Back"
      onClick={() => router.back()}
      className="flex min-h-11 min-w-11 items-center justify-center rounded-md text-text-primary"
    >
      <CaretLeft size={22} aria-hidden />
    </button>
  );
}

function AccountMenu({ handle, isOwner }: { handle: string; isOwner: boolean }) {
  const [open, setOpen] = useState(false);
  const router = useRouter();

  const logOut = async () => {
    const supabase = createSupabaseBrowserClient();
    await supabase.auth.signOut();
    router.push("/login");
    router.refresh();
  };

  return (
    <div className="relative px-1">
      {open ? (
        <div
          role="menu"
          aria-label="Account"
          className="absolute bottom-full left-1 mb-1 w-56 rounded-md bg-surface-raised py-2 shadow-e2"
        >
          <Link
            role="menuitem"
            href="/settings"
            onClick={() => setOpen(false)}
            className="flex min-h-11 items-center gap-3 px-4 text-body text-text-primary hover:bg-accent-subtle"
          >
            <GearSix size={20} aria-hidden /> Settings
          </Link>
          {isOwner ? (
            <Link
              role="menuitem"
              href="/owner/roles"
              onClick={() => setOpen(false)}
              className="flex min-h-11 items-center gap-3 px-4 text-body text-text-primary hover:bg-accent-subtle"
            >
              <ShieldStar size={20} aria-hidden /> Owner tools
            </Link>
          ) : null}
          <button
            type="button"
            role="menuitem"
            onClick={() => void logOut()}
            className="flex min-h-11 w-full items-center gap-3 px-4 text-left text-body text-text-primary hover:bg-accent-subtle"
          >
            <SignOut size={20} aria-hidden /> Log out
          </button>
        </div>
      ) : null}
      <button
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
        className="flex min-h-11 w-full items-center gap-3 rounded-md px-3 text-label text-text-primary hover:bg-surface-raised"
      >
        <span
          aria-hidden
          className="flex size-8 items-center justify-center rounded-full bg-accent-subtle text-caption font-semibold text-accent"
        >
          {handle.charAt(0).toUpperCase()}
        </span>
        @{handle}
        <CaretUp size={14} aria-hidden className="ml-auto" />
      </button>
    </div>
  );
}
