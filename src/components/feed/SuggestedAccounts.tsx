import type { PersonRow as PersonRowData } from "@/lib/database.types";
import { PersonRow } from "@/components/people/PersonRow";

/**
 * The people-first cold-start module (design doc §12): for a member
 * with few or no follows, Discover leads with people, because the
 * fastest way out of an empty experience on a small network is to
 * follow a few of them. Same identity block and Follow mechanics as
 * everywhere else; @handle-forward, never a legal name.
 */
export function SuggestedAccounts({ people }: { people: PersonRowData[] }) {
  if (people.length === 0) return null;

  return (
    <section aria-label="People to follow" className="border-b border-border bg-surface">
      <h2 className="px-4 pt-4 text-heading text-text-primary">People to follow</h2>
      <div className="flex flex-col pt-1">
        {people.map((person) => (
          <PersonRow key={person.user_id} person={person} />
        ))}
      </div>
    </section>
  );
}
