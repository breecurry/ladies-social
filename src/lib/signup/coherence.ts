/**
 * Profile-coherence heuristics: does the name/handle/email pattern look
 * machine-generated? Pure signals about BOT-NESS — never about
 * appearance, gender, or identity (locked product rule). Output is a
 * 0–1 suspicion score plus human-readable reasons for the review queue.
 */

export interface CoherenceResult {
  score: number;
  reasons: string[];
}

const VOWELS = new Set("aeiouy");

function longestConsonantRun(s: string): number {
  let run = 0;
  let max = 0;
  for (const ch of s.toLowerCase()) {
    if (/[a-z]/.test(ch) && !VOWELS.has(ch)) {
      run += 1;
      if (run > max) max = run;
    } else {
      run = 0;
    }
  }
  return max;
}

function vowelRatio(s: string): number {
  const letters = s.toLowerCase().replace(/[^a-z]/g, "");
  if (letters.length === 0) return 0;
  let v = 0;
  for (const ch of letters) if (VOWELS.has(ch)) v += 1;
  return v / letters.length;
}

function digitRatio(s: string): number {
  if (s.length === 0) return 0;
  return (s.match(/[0-9]/g)?.length ?? 0) / s.length;
}

/** Shannon entropy per character — high values suggest random strings. */
function entropyPerChar(s: string): number {
  if (s.length === 0) return 0;
  const counts = new Map<string, number>();
  for (const ch of s) counts.set(ch, (counts.get(ch) ?? 0) + 1);
  let h = 0;
  for (const count of counts.values()) {
    const p = count / s.length;
    h -= p * Math.log2(p);
  }
  return h;
}

const KEYBOARD_PATTERNS = ["qwert", "asdf", "zxcv", "yuiop", "hjkl", "12345", "09876"];

export function assessProfileCoherence(input: {
  legalName: string;
  handle: string;
  email: string;
}): CoherenceResult {
  const reasons: string[] = [];
  let score = 0;

  const name = input.legalName.trim();
  const handle = input.handle.toLowerCase();
  const emailLocal = (input.email.split("@")[0] ?? "").toLowerCase();

  // --- Name shape ---
  if (!/\s/.test(name)) {
    score += 0.1;
    reasons.push("single-word legal name");
  }
  if (longestConsonantRun(name) >= 5) {
    score += 0.25;
    reasons.push("name contains an unpronounceable consonant run");
  }
  const nameVowels = vowelRatio(name);
  if (name.length >= 5 && (nameVowels < 0.15 || nameVowels > 0.85)) {
    score += 0.2;
    reasons.push("name letter distribution looks non-linguistic");
  }
  if (/[0-9]/.test(name)) {
    score += 0.3;
    reasons.push("legal name contains digits");
  }
  if (/(.)\1{3,}/.test(name.toLowerCase())) {
    score += 0.2;
    reasons.push("name contains long repeated characters");
  }

  // --- Handle shape ---
  if (digitRatio(handle) > 0.5) {
    score += 0.25;
    reasons.push("handle is mostly digits");
  }
  if (/[a-z]+\d{6,}$/.test(handle)) {
    score += 0.2;
    reasons.push("handle ends in a long random-looking number");
  }
  if (handle.length >= 12 && entropyPerChar(handle) > 3.6) {
    score += 0.2;
    reasons.push("handle looks randomly generated");
  }
  for (const pattern of KEYBOARD_PATTERNS) {
    if (handle.includes(pattern) || emailLocal.includes(pattern)) {
      score += 0.15;
      reasons.push("keyboard-walk pattern in handle or email");
      break;
    }
  }

  // --- Email local part ---
  if (emailLocal.length >= 12 && entropyPerChar(emailLocal) > 3.8) {
    score += 0.2;
    reasons.push("email local part looks randomly generated");
  }
  if (digitRatio(emailLocal) > 0.6) {
    score += 0.15;
    reasons.push("email local part is mostly digits");
  }

  // --- Cross-field coherence (weak positive signal when present) ---
  const nameTokens = name
    .toLowerCase()
    .split(/\s+/)
    .filter((t) => t.length >= 3);
  const related = nameTokens.some((t) => handle.includes(t) || emailLocal.includes(t));
  if (!related && nameTokens.length > 0 && handle.length >= 6 && emailLocal.length >= 6) {
    score += 0.1;
    reasons.push("no relationship between name, handle and email");
  }

  return { score: Math.min(1, Number(score.toFixed(3))), reasons };
}
