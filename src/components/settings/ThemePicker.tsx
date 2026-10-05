"use client";

import { useState, useSyncExternalStore } from "react";

type Theme = "system" | "light" | "dark";

const KEY = "uf-theme";
const emptySubscribe = () => () => {};

function readTheme(): Theme {
  try {
    const value = window.localStorage.getItem(KEY);
    return value === "light" || value === "dark" ? value : "system";
  } catch {
    return "system";
  }
}

/**
 * Theme choice (spec §8.2.5): System, Light, Dark via [data-theme],
 * applied before first paint by the root layout's init script.
 * Reduced motion follows the system setting automatically.
 */
export function ThemePicker() {
  const stored = useSyncExternalStore(emptySubscribe, readTheme, () => "system" as Theme);
  const [theme, setTheme] = useState<Theme | null>(null);
  const current = theme ?? stored;

  const apply = (next: Theme) => {
    setTheme(next);
    const root = document.documentElement;
    try {
      if (next === "system") {
        window.localStorage.removeItem(KEY);
        root.removeAttribute("data-theme");
      } else {
        window.localStorage.setItem(KEY, next);
        root.setAttribute("data-theme", next);
      }
    } catch {
      // Storage unavailable; the choice applies for this page view only.
      if (next !== "system") root.setAttribute("data-theme", next);
    }
  };

  const options: Array<{ value: Theme; label: string }> = [
    { value: "system", label: "System" },
    { value: "light", label: "Light" },
    { value: "dark", label: "Dark" },
  ];

  return (
    <div
      role="radiogroup"
      aria-label="Theme"
      className="inline-flex rounded-md border border-border-strong"
    >
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          role="radio"
          aria-checked={current === option.value}
          onClick={() => apply(option.value)}
          className={`min-h-11 px-4 text-label first:rounded-l-md last:rounded-r-md ${
            current === option.value
              ? "bg-accent-subtle text-accent"
              : "text-text-secondary hover:bg-surface-raised"
          }`}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}
