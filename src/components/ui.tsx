import type {
  ButtonHTMLAttributes,
  InputHTMLAttributes,
  ReactNode,
  TextareaHTMLAttributes,
} from "react";

/**
 * Minimal Phase 1 UI kit, styled exclusively with the design tokens in
 * globals.css ("Calm paper, sharp tools"). No new visual decisions.
 */

type ButtonVariant = "primary" | "secondary" | "danger" | "ghost";

const buttonBase =
  "inline-flex min-h-11 items-center justify-center gap-2 rounded-md px-4 text-label " +
  "transition-colors duration-(--duration-fast) ease-(--ease-standard) " +
  "disabled:cursor-not-allowed disabled:opacity-50";

const buttonVariants: Record<ButtonVariant, string> = {
  primary: "bg-accent-fill text-on-accent hover:bg-accent-hover",
  secondary: "border border-border-strong bg-surface text-text-primary hover:bg-surface-raised",
  danger: "bg-danger-fill text-white hover:bg-danger-hover",
  ghost: "text-accent hover:bg-accent-subtle",
};

export function Button({
  variant = "primary",
  className = "",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: ButtonVariant }) {
  return <button {...props} className={`${buttonBase} ${buttonVariants[variant]} ${className}`} />;
}

export function Input({ className = "", ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className={
        "min-h-11 w-full rounded-md border border-border-strong bg-surface-raised px-3 " +
        "text-body text-text-primary placeholder:text-text-tertiary " +
        `focus-visible:outline-2 focus-visible:outline-focus-ring ${className}`
      }
    />
  );
}

export function Textarea({
  className = "",
  ...props
}: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea
      {...props}
      className={
        "w-full rounded-md border border-border-strong bg-surface-raised px-3 py-2 " +
        "text-body text-text-primary placeholder:text-text-tertiary " +
        `focus-visible:outline-2 focus-visible:outline-focus-ring ${className}`
      }
    />
  );
}

export function Field({
  label,
  htmlFor,
  hint,
  error,
  children,
}: {
  label: string;
  htmlFor: string;
  hint?: string;
  error?: string | null;
  children: ReactNode;
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={htmlFor} className="text-label text-text-primary">
        {label}
      </label>
      {children}
      {hint && !error ? <p className="text-caption text-text-tertiary">{hint}</p> : null}
      {error ? (
        <p role="alert" className="text-caption text-danger">
          {error}
        </p>
      ) : null}
    </div>
  );
}

export function Card({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <section className={`rounded-lg border border-border bg-surface p-6 shadow-e1 ${className}`}>
      {children}
    </section>
  );
}

type BadgeTone = "neutral" | "accent" | "success" | "warning" | "danger";

const badgeTones: Record<BadgeTone, string> = {
  neutral: "bg-background text-text-secondary border border-border",
  accent: "bg-accent-subtle text-accent",
  success: "bg-success-subtle text-success",
  warning: "bg-warning-fill text-on-warning-fill",
  danger: "bg-danger-subtle text-danger",
};

export function Badge({ tone = "neutral", children }: { tone?: BadgeTone; children: ReactNode }) {
  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-micro uppercase ${badgeTones[tone]}`}
    >
      {children}
    </span>
  );
}

export function Alert({
  tone,
  children,
}: {
  tone: "success" | "danger" | "warning" | "info";
  children: ReactNode;
}) {
  const tones = {
    success: "bg-success-subtle text-success",
    danger: "bg-danger-subtle text-danger",
    warning: "bg-warning-fill text-on-warning-fill",
    info: "bg-accent-subtle text-accent",
  } as const;
  return (
    <div role="status" className={`rounded-md px-4 py-3 text-body ${tones[tone]}`}>
      {children}
    </div>
  );
}
