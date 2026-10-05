"use client";

import Link from "next/link";

export type HomeTab = "following" | "discover";

/** Remembered for a year so the server can honour the last choice (spec §4.7). */
function rememberTab(tab: HomeTab) {
  document.cookie = `home_tab=${tab}; path=/; max-age=31536000; samesite=lax`;
}

/**
 * The two-tab Home header (spec §4.1, §4.7): Following and Discover as
 * a segmented pair with the accent underline carrying the active
 * state. Tabs are links, so the choice is shareable URL state; a click
 * also remembers itself in a cookie for the next visit's default.
 */
export function HomeTabs({ active }: { active: HomeTab }) {
  return (
    <nav
      aria-label="Home feeds"
      className="flex border-b border-border bg-surface"
    >
      <TabLink
        href="/home?tab=following"
        label="Following"
        active={active === "following"}
        onNavigate={() => rememberTab("following")}
      />
      <TabLink
        href="/home?tab=discover"
        label="Discover"
        active={active === "discover"}
        onNavigate={() => rememberTab("discover")}
      />
    </nav>
  );
}

function TabLink({
  href,
  label,
  active,
  onNavigate,
}: {
  href: string;
  label: string;
  active: boolean;
  onNavigate: () => void;
}) {
  return (
    <Link
      href={href}
      aria-current={active ? "page" : undefined}
      onClick={onNavigate}
      className={`flex min-h-11 flex-1 items-center justify-center border-b-2 text-label transition-colors duration-(--duration-fast) ${
        active
          ? "border-accent text-accent"
          : "border-transparent text-text-secondary hover:text-text-primary"
      }`}
    >
      {label}
    </Link>
  );
}
