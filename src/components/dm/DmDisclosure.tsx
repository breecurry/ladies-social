import { Eye } from "@phosphor-icons/react/dist/ssr";

/**
 * The honest DM disclosure (owner decision, 2026-10-09). Rendered on
 * every surface where a member starts or reads a direct message — the
 * inbox and every thread. Deliberately unmissable: a persistent
 * banner, never a tooltip, never dismissible, and the copy is not
 * softened. Members deserve to know exactly who can read what before
 * they type.
 */
export function DmDisclosure() {
  return (
    <div
      role="note"
      aria-label="How private your messages are"
      className="flex items-start gap-2.5 border-b border-border bg-surface-raised px-4 py-3"
    >
      <Eye size={18} aria-hidden className="mt-0.5 shrink-0 text-warning" />
      <p className="text-caption text-text-secondary">
        <strong className="text-text-primary">Your messages are not private from Hersciety.</strong>{" "}
        Direct messages are not end-to-end encrypted. The platform owner and moderators can read
        them, and every one of those reads is logged. Messages may be disclosed to authorities in
        matters involving trafficking or sexual exploitation, including of minors.
      </p>
    </div>
  );
}
