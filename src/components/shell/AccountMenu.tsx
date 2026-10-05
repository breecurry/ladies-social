"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  CaretUp,
  GearSix,
  List,
  ShieldCheck,
  ShieldStar,
  SignOut,
} from "@phosphor-icons/react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { useViewer } from "@/components/shell/Providers";

/**
 * The account menu (design doc §1, §2.4): Moderation (staff only),
 * Settings, Owner tools (owner only), Log out. One shared definition
 * with two mount points — the desktop left rail (>=lg, variant "rail",
 * popup opens upward) and the member's own profile header (<lg,
 * variant "profile", popup opens downward and inward so it can never
 * leave the screen at 320px). Role data comes from the viewer context,
 * so mounting it anywhere inside Providers is a one-line change.
 */
export function AccountMenu({ variant = "rail" }: { variant?: "rail" | "profile" }) {
  const { handle, isOwner, mod } = useViewer();
  const [open, setOpen] = useState(false);
  const router = useRouter();

  const logOut = async () => {
    const supabase = createSupabaseBrowserClient();
    await supabase.auth.signOut();
    router.push("/login");
    router.refresh();
  };

  return (
    <div className={variant === "rail" ? "relative px-1" : "relative"}>
      {open ? (
        <div
          role="menu"
          aria-label="Account"
          className={`absolute z-10 w-56 rounded-md bg-surface-raised py-2 shadow-e2 ${
            variant === "rail" ? "bottom-full left-1 mb-1" : "right-0 top-full mt-1"
          }`}
        >
          {mod ? (
            // The queue count is information, not alarm (§2.4): plain
            // secondary text, "Clear" in success when empty, and the
            // one red dot reserved for open CRITICAL cases, where a
            // delay is itself a harm.
            <Link
              role="menuitem"
              href="/mod"
              onClick={() => setOpen(false)}
              className="flex min-h-11 items-center gap-3 px-4 text-body text-text-primary hover:bg-accent-subtle"
            >
              <span className="relative">
                <ShieldCheck size={20} aria-hidden />
                {mod.criticalCount > 0 ? (
                  <span
                    aria-label={`${mod.criticalCount} critical case${mod.criticalCount === 1 ? "" : "s"}`}
                    className="absolute -right-1 -top-0.5 size-2 rounded-full bg-danger-fill"
                  />
                ) : null}
              </span>
              Moderation
              {mod.openCount > 0 ? (
                <span className="ml-auto text-caption text-text-secondary">
                  {mod.openCount} open
                </span>
              ) : (
                <span className="ml-auto text-caption text-success">Clear</span>
              )}
            </Link>
          ) : null}
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
              href="/owner"
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
      {variant === "rail" ? (
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
      ) : (
        <button
          type="button"
          aria-label="Account menu"
          aria-haspopup="menu"
          aria-expanded={open}
          onClick={() => setOpen((v) => !v)}
          className="flex min-h-11 min-w-11 items-center justify-center rounded-md text-text-primary hover:bg-surface-raised"
        >
          <List size={24} aria-hidden />
        </button>
      )}
    </div>
  );
}
