"use client";

import { useCallback, useEffect, useRef, type KeyboardEvent, type ReactNode } from "react";

const FOCUSABLE =
  'a[href], button:not([disabled]), textarea:not([disabled]), input:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])';

/**
 * Accessible modal dialog (spec §3.4, §12.2): scrim, focus trap, Escape
 * closes, focus returns to the trigger on close. Renders as a centred
 * modal on large screens and a bottom sheet below lg when sheet=true.
 */
export function Dialog({
  open,
  onClose,
  label,
  sheet = true,
  children,
  maxWidth = "max-w-[560px]",
}: {
  open: boolean;
  onClose: () => void;
  label: string;
  sheet?: boolean;
  children: ReactNode;
  maxWidth?: string;
}) {
  const panelRef = useRef<HTMLDivElement>(null);
  const restoreRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (!open) return;
    restoreRef.current = document.activeElement as HTMLElement | null;
    const panel = panelRef.current;
    if (panel) {
      const first = panel.querySelector<HTMLElement>("[data-autofocus]") ??
        panel.querySelector<HTMLElement>(FOCUSABLE);
      first?.focus();
    }
    return () => {
      restoreRef.current?.focus?.();
    };
  }, [open]);

  const onKeyDown = useCallback(
    (event: KeyboardEvent<HTMLDivElement>) => {
      if (event.key === "Escape") {
        event.stopPropagation();
        onClose();
        return;
      }
      if (event.key !== "Tab") return;
      const panel = panelRef.current;
      if (!panel) return;
      const focusable = Array.from(panel.querySelectorAll<HTMLElement>(FOCUSABLE));
      if (focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (!first || !last) return;
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    },
    [onClose],
  );

  if (!open) return null;

  return (
    <div
      className={`fixed inset-0 z-50 flex justify-center bg-scrim ${
        sheet ? "items-end lg:items-center" : "items-center"
      }`}
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-label={label}
        onKeyDown={onKeyDown}
        className={`w-full ${maxWidth} bg-surface-raised shadow-e3 ${
          sheet
            ? "max-h-[85dvh] overflow-y-auto rounded-t-2xl pb-[env(safe-area-inset-bottom)] lg:max-h-[80dvh] lg:rounded-xl"
            : "mx-4 rounded-xl"
        }`}
      >
        {sheet ? (
          <div aria-hidden className="flex justify-center pt-2 lg:hidden">
            <span className="h-1 w-8 rounded-full bg-border" />
          </div>
        ) : null}
        {children}
      </div>
    </div>
  );
}
