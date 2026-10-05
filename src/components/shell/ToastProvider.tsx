"use client";

import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";

export interface ToastOptions {
  /** Inline action, e.g. Undo. Keyboard reachable for the full duration. */
  actionLabel?: string;
  onAction?: () => void | Promise<void>;
  /** Defaults to 5000ms; follow-undo toasts use ~6000ms (spec §4.9). */
  durationMs?: number;
}

interface ToastState extends ToastOptions {
  id: number;
  message: string;
}

interface ToastContextValue {
  showToast: (message: string, options?: ToastOptions) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

export function useToast(): ToastContextValue {
  const ctx = useContext(ToastContext);
  if (!ctx) throw new Error("useToast must be used inside ToastProvider");
  return ctx;
}

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastState[]>([]);
  const nextId = useRef(1);

  const dismiss = useCallback((id: number) => {
    setToasts((current) => current.filter((t) => t.id !== id));
  }, []);

  const showToast = useCallback(
    (message: string, options?: ToastOptions) => {
      const id = nextId.current++;
      setToasts((current) => [...current.slice(-2), { id, message, ...options }]);
      window.setTimeout(() => dismiss(id), options?.durationMs ?? 5000);
    },
    [dismiss],
  );

  const value = useMemo(() => ({ showToast }), [showToast]);

  return (
    <ToastContext.Provider value={value}>
      {children}
      <div
        aria-live="polite"
        className="pointer-events-none fixed inset-x-0 bottom-[calc(72px+env(safe-area-inset-bottom))] z-50 flex flex-col items-center gap-2 px-4 lg:inset-x-auto lg:bottom-6 lg:left-6 lg:items-start"
      >
        {toasts.map((toast) => (
          <div
            key={toast.id}
            className="pointer-events-auto flex min-h-11 items-center gap-3 rounded-md bg-surface-raised px-4 py-2 text-body text-text-primary shadow-e2"
          >
            <span>{toast.message}</span>
            {toast.actionLabel ? (
              <button
                type="button"
                className="min-h-11 rounded-md px-2 text-label text-accent hover:bg-accent-subtle"
                onClick={() => {
                  void toast.onAction?.();
                  dismiss(toast.id);
                }}
              >
                {toast.actionLabel}
              </button>
            ) : null}
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}
