"use client";

import { createContext, useContext, type ReactNode } from "react";
import { ToastProvider } from "@/components/shell/ToastProvider";
import { ComposeProvider } from "@/components/shell/ComposeProvider";

/** Shown in the account menu for staff roles only (design doc §1, §2.4). */
export interface ModMenuInfo {
  label: string;
  openCount: number;
  criticalCount: number;
}

export interface ViewerInfo {
  id: string;
  handle: string;
  /** Whether the viewer holds the owner role (gates the Owner tools entry). */
  isOwner: boolean;
  /** Moderation-queue summary when the viewer is staff; null otherwise. */
  mod: ModMenuInfo | null;
}

const ViewerContext = createContext<ViewerInfo | null>(null);

/** The signed-in member, available to every client component in the shell. */
export function useViewer(): ViewerInfo {
  const ctx = useContext(ViewerContext);
  if (!ctx) throw new Error("useViewer must be used inside Providers");
  return ctx;
}

export function Providers({ viewer, children }: { viewer: ViewerInfo; children: ReactNode }) {
  return (
    <ViewerContext.Provider value={viewer}>
      <ToastProvider>
        <ComposeProvider viewerHandle={viewer.handle}>{children}</ComposeProvider>
      </ToastProvider>
    </ViewerContext.Provider>
  );
}
