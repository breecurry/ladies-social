"use client";

import { useState, type ReactNode } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import {
  House,
  MagnifyingGlass,
  Bell,
  ChatCircle,
  PencilSimple,
  CaretLeft,
} from "@phosphor-icons/react";
import { useCompose } from "@/components/shell/ComposeProvider";
import { useViewer } from "@/components/shell/Providers";
import { AccountMenu } from "@/components/shell/AccountMenu";
import { useAvatarMedia } from "@/components/avatar/useAvatarMedia";
import { avatarUrl, blurhashAverageColor } from "@/lib/media/avatar";
import { BrandWordmark } from "@/components/BrandWordmark";

/**
 * The application shell (spec §1): desktop left rail (>=lg) with a
 * centred 600px reading column; mobile 5-slot bottom tab bar with a
 * thin sticky top bar. Compose is an action, not a destination.
 */
export function AppShell({
  handle,
  initialUnread,
  dmEnabled = false,
  dmUnread = 0,
  children,
}: {
  handle: string;
  initialUnread: number;
  /** The DM feature flag (design 2C §8); when false, no Messages entry exists anywhere. */
  dmEnabled?: boolean;
  /** Unread accepted conversations — a count, never a name or content. */
  dmUnread?: number;
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
        <Link href="/home" className="mb-4 flex px-3">
          <BrandWordmark height={22} />
        </Link>
        {navItems.map((item) => (
          <RailLink key={item.href} {...item} />
        ))}
        {dmEnabled ? (
          <RailLink
            href="/messages"
            label="Messages"
            icon={ChatCircle}
            active={pathname.startsWith("/messages")}
            badge={dmUnread}
          />
        ) : null}
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
          <AccountMenu />
        </div>
      </nav>

      {/* Centre column */}
      <div className="flex w-full max-w-[600px] flex-col">
        {/* Mobile top bar */}
        <header className="sticky top-0 z-20 flex h-12 items-center gap-1 bg-surface px-2 shadow-sticky lg:hidden">
          {isHome ? (
            <span className="flex px-2">
              <BrandWordmark height={20} />
            </span>
          ) : (
            <BackButton />
          )}
          {dmEnabled ? (
            <Link
              href="/messages"
              aria-label={dmUnread > 0 ? `Messages, ${dmUnread} unread` : "Messages"}
              className="ml-auto flex size-11 items-center justify-center rounded-md text-text-primary"
            >
              <span className="relative">
                <ChatCircle
                  size={24}
                  weight={pathname.startsWith("/messages") ? "fill" : "regular"}
                  aria-hidden
                />
                <UnreadBadge count={dmUnread} />
              </span>
            </Link>
          ) : null}
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
          <NavFace
            letter={handle.charAt(0).toUpperCase()}
            active={profileActive}
            sizeClass="size-7"
            textClass="text-caption"
          />
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
        <NavFace
          letter={avatarLetter ?? ""}
          active={active}
          sizeClass="size-6"
          textClass="text-micro"
        />
      )}
      {label}
    </Link>
  );
}

/**
 * The nav identity circle (P2E section 4): the member's own avatar IS
 * the Profile destination. Photo when one is set (resolved through the
 * block-aware resolver like everywhere else), letter otherwise; the
 * 2px accent ring stays the active indicator over both.
 */
function NavFace({ letter, active, sizeClass, textClass }: {
  letter: string;
  active: boolean;
  sizeClass: string;
  textClass: string;
}) {
  const viewer = useViewer();
  const media = useAvatarMedia(viewer.id);
  const [brokenSrc, setBrokenSrc] = useState<string | null>(null);
  const src = media ? avatarUrl(media.key, 96) : null;
  if (src && src !== brokenSrc) {
    return (
      // Immutable unguessable key on the Cloudflare media zone;
      // next/image would proxy it through Vercel and defeat the edge cache.
      // eslint-disable-next-line @next/next/no-img-element
      <img
        src={src}
        alt=""
        aria-hidden
        width={28}
        height={28}
        onError={() => setBrokenSrc(src)}
        className={`rounded-full object-cover ${sizeClass} ${active ? "ring-2 ring-accent" : ""}`}
        style={{ backgroundColor: blurhashAverageColor(media?.blurhash ?? null) ?? undefined }}
      />
    );
  }
  return (
    <span
      aria-hidden
      className={`flex items-center justify-center rounded-full bg-accent-subtle font-semibold text-accent ${sizeClass} ${textClass} ${
        active ? "ring-2 ring-accent" : ""
      }`}
    >
      {letter}
    </span>
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
