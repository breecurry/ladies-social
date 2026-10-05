"use client";

import type { ReactNode } from "react";
import { ToastProvider } from "@/components/shell/ToastProvider";
import { ComposeProvider } from "@/components/shell/ComposeProvider";

export function Providers({
  viewerHandle,
  children,
}: {
  viewerHandle: string;
  children: ReactNode;
}) {
  return (
    <ToastProvider>
      <ComposeProvider viewerHandle={viewerHandle}>{children}</ComposeProvider>
    </ToastProvider>
  );
}
