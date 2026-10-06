/**
 * The DM disclosure's dismissal cycle — both constants are defined
 * HERE and nowhere else. This module is plain shared TypeScript so
 * the server (should-show check, dismiss endpoint) and the client
 * (the dismiss button's accessible name) import the same values.
 */

/**
 * Version of the disclosure copy in src/components/dm/DmDisclosure.tsx.
 * BUMP THIS whenever that copy materially changes. A bump overrides
 * every member's quiet period, so the changed text is seen immediately
 * — that is the point: if staff access behaviour ever changes, the
 * copy changes with it, and nobody waits out a timer to learn it.
 *
 * 🔑 WHEN YOU BUMP IT, DO NOT USE THE NEXT SEQUENTIAL INTEGER.
 * Jump to an unguessable value — a date-derived one is ideal, e.g.
 * 20261106 for a change made on 6 Nov 2026.
 *
 * Why: 20261027000001 clamps direct writes to the dismissal columns and
 * makes any recorded version that is not EXACTLY this one read as
 * "show", which defuses a forged dm_dismiss_disclosure(9999). The one
 * residual it leaves is a member who guesses the NEXT version and
 * pre-dismisses it, suppressing that single bump for up to one quiet
 * period. A sequential bump is trivially guessable; a date-derived one
 * is not. Closing it any other way would mean teaching the database
 * this constant, which would then live in two places and could drift —
 * and a drifted version silently stops re-showing the disclosure for
 * EVERYONE, which is far worse than the attack it would prevent.
 */
export const DM_DISCLOSURE_VERSION = 1;

/**
 * The owner promised "a minimum of 45 days" of quiet after a
 * dismissal. One line to change it. Used by the server-side show/hide
 * check and by the dismiss button's accessible name.
 */
export const DM_DISCLOSURE_QUIET_DAYS = 45;
