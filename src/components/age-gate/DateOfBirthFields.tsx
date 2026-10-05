"use client";

import { useId } from "react";

export interface DobParts {
  month: string;
  day: string;
  year: string;
}

/**
 * The §17.1 date-of-birth group: three separately labelled fields in a
 * row (stacking under sm), every one starting BLANK with a visible
 * placeholder. Never a wheel, never a default that would pass the
 * gate — the member must actively enter each part. The 18+ check runs
 * on submit; this component only gathers the parts and announces the
 * group's error politely.
 */
export function DateOfBirthFields({
  value,
  onChange,
  error,
  disabled,
}: {
  value: DobParts;
  onChange: (next: DobParts) => void;
  error: string | null;
  disabled?: boolean;
}) {
  const labelId = useId();
  const hintId = useId();
  const errorId = useId();

  const inputClass =
    "min-h-11 w-full rounded-md border border-border-strong bg-surface-raised px-3 " +
    "text-body text-text-primary placeholder:text-text-tertiary " +
    "focus-visible:outline-2 focus-visible:outline-focus-ring";

  const set = (part: keyof DobParts) => (raw: string) => {
    const digits = raw.replace(/\D/g, "").slice(0, part === "year" ? 4 : 2);
    onChange({ ...value, [part]: digits });
  };

  return (
    <div
      role="group"
      aria-labelledby={labelId}
      aria-describedby={error ? errorId : hintId}
      className="flex flex-col gap-1.5"
    >
      <span id={labelId} className="text-label text-text-primary">
        Date of birth
      </span>
      <div className="flex flex-col gap-3 sm:flex-row">
        <div className="flex-1">
          <label htmlFor={`${labelId}-month`} className="sr-only">
            Month
          </label>
          <input
            id={`${labelId}-month`}
            className={inputClass}
            inputMode="numeric"
            autoComplete="bday-month"
            placeholder="Month"
            value={value.month}
            onChange={(e) => set("month")(e.target.value)}
            disabled={disabled}
          />
        </div>
        <div className="flex-1">
          <label htmlFor={`${labelId}-day`} className="sr-only">
            Day
          </label>
          <input
            id={`${labelId}-day`}
            className={inputClass}
            inputMode="numeric"
            autoComplete="bday-day"
            placeholder="Day"
            value={value.day}
            onChange={(e) => set("day")(e.target.value)}
            disabled={disabled}
          />
        </div>
        <div className="flex-[1.4]">
          <label htmlFor={`${labelId}-year`} className="sr-only">
            Year
          </label>
          <input
            id={`${labelId}-year`}
            className={inputClass}
            inputMode="numeric"
            autoComplete="bday-year"
            placeholder="Year"
            value={value.year}
            onChange={(e) => set("year")(e.target.value)}
            disabled={disabled}
          />
        </div>
      </div>
      <p id={hintId} hidden={Boolean(error)} className="text-caption text-text-tertiary">
        You must be 18 or older to join Hersciety.
      </p>
      <p id={errorId} aria-live="polite" className="text-caption text-danger">
        {error}
      </p>
    </div>
  );
}
