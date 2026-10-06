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
 */
export const DM_DISCLOSURE_VERSION = 1;

/**
 * The owner promised "a minimum of 45 days" of quiet after a
 * dismissal. One line to change it. Used by the server-side show/hide
 * check and by the dismiss button's accessible name.
 */
export const DM_DISCLOSURE_QUIET_DAYS = 45;
