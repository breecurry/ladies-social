"use client";

import { useState } from "react";
import { Clock, Copy } from "@phosphor-icons/react";

const DIGIT_WORDS: Record<string, string> = {
  "0": "zero",
  "1": "one",
  "2": "two",
  "3": "three",
  "4": "four",
  "5": "five",
  "6": "six",
  "7": "seven",
  "8": "eight",
  "9": "nine",
};

/** "4F2A" → "four, F, two, A" so screen readers never read it as a word. */
function spellOut(code: string): string {
  return Array.from(code)
    .map((ch) => DIGIT_WORDS[ch] ?? ch)
    .join(", ");
}

/**
 * The blocked screen (spec §17.3): a device that failed the age check
 * is trying again within 14 days. The reference code is the ONLY thing
 * the visitor interacts with, and it is read-only — displayed and
 * copyable, never typed into. No email box, no name box, no message
 * form, no "notify me" (§17.4). Support identifies the device by this
 * code alone, because nobody can read her own fingerprint hash.
 */
export function AgeGateBlocked({ code }: { code: string }) {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // The code text itself is selectable; copy still works by hand.
    }
  };

  return (
    <div className="mx-auto flex w-full max-w-md flex-col items-center gap-6 py-12 text-center">
      <Clock size={64} aria-hidden className="text-text-tertiary" />
      <h1 className="text-title text-text-primary">You cannot create an account right now.</h1>
      <p className="max-w-prose text-body text-text-secondary">
        This device recently did not meet our age requirement. You can try again later.
      </p>

      <div className="flex items-center gap-3">
        <span
          aria-label={`Reference code: ${spellOut(code)}`}
          className="select-all rounded-md border border-border-strong bg-surface-raised px-5 py-3 text-display tracking-[0.2em] text-text-primary"
        >
          {code}
        </span>
        <button
          type="button"
          onClick={() => void copy()}
          className="inline-flex min-h-11 min-w-11 items-center justify-center gap-2 rounded-md border border-border-strong bg-surface px-4 text-label text-text-primary transition-colors duration-(--duration-fast) ease-(--ease-standard) hover:bg-surface-raised focus-visible:outline-2 focus-visible:outline-focus-ring"
        >
          <Copy size={20} aria-hidden />
          {copied ? "Copied" : "Copy"}
        </button>
        <span aria-live="polite" className="sr-only">
          {copied ? "Copied" : ""}
        </span>
      </div>

      <p className="max-w-prose text-body text-text-secondary">
        If you entered the wrong date, email{" "}
        <a
          href={`mailto:support@unitedfeminist.com?subject=Age%20gate%20reference%20code%20${code}`}
          className="text-accent underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-focus-ring"
        >
          support@unitedfeminist.com
        </a>{" "}
        and quote this code. We will sort it out.
      </p>
    </div>
  );
}
