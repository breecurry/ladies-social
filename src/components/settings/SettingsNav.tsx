"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const ITEMS = [
  { href: "/settings", label: "Account" },
  { href: "/settings/privacy", label: "Privacy" },
  { href: "/settings/safety", label: "Safety" },
  { href: "/settings/notifications", label: "Notifications" },
  { href: "/settings/appearance", label: "Appearance" },
  { href: "/settings/about", label: "About and legal" },
] as const;

export function SettingsNav() {
  const pathname = usePathname();
  return (
    <nav
      aria-label="Settings sections"
      className="flex gap-1 overflow-x-auto lg:w-60 lg:shrink-0 lg:flex-col"
    >
      {ITEMS.map((item) => {
        const active =
          item.href === "/settings" ? pathname === "/settings" : pathname.startsWith(item.href);
        return (
          <Link
            key={item.href}
            href={item.href}
            aria-current={active ? "page" : undefined}
            className={`flex min-h-11 shrink-0 items-center rounded-md px-3 text-label transition-colors duration-(--duration-fast) ${
              active
                ? "bg-accent-subtle text-accent"
                : "text-text-secondary hover:bg-surface-raised hover:text-text-primary"
            }`}
          >
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}
