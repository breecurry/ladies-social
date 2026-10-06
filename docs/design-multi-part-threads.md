# Design: Multi-Part Threads

This document designs two things: the composer that lets a member write past the 500-character limit by publishing a connected run of her own posts, and the way those connected runs ("chains") are shown everywhere they appear. It is a design specification, not application code and not a migration. It extends the token system and patterns already implemented in `src/app/globals.css` and set out in `docs/design-phase2-social-core.md` (hereafter P2), `docs/design-phase2b-moderation-and-discover.md` (hereafter P2B), and `docs/design-phase2f-hashtags-mentions-reposts.md` (hereafter P2F). It does not redesign the shell, and it introduces no new design token. Where it adds a new component composition it says so plainly, in section 20.

The owner asked for one specific thing, in her words: "I want them to be able to write a long post even if it means replies to their own thread. like threads, you can only type so many characters per initial message, but then they can choose to add more if they want to by adding to thread." This is the Threads / X / Bluesky multi-part composer. Each part is its own post of up to 500 characters, each published as a reply to the one before it, and the whole run reads as a single train of thought. This document designs that chain pattern and nothing else. A larger single-field long-post ("text attachment") is named once, as a possible future direction, at the very end, and is not designed here.

---

## 0. How to read this document

- **Tokens** are the CSS custom properties already in `src/app/globals.css` and enumerated in P2 section 2: the color roles (`background`, `surface`, `surface-raised`, `border`, `border-strong`, `text-primary`, `text-secondary`, `text-tertiary`, `accent`, `accent-fill`, `accent-subtle`, `on-accent`, `success`, `warning`, `warning-fill`, `danger`, `danger-fill`, `danger-subtle`, `focus-ring`, `scrim`, and the decorative `thread-rail` which is accent at 16 percent), the eight type roles, the base-4 spacing scale, the radius scale (sm 6, md 10, lg 14, xl 20, 2xl 28, full), the elevation scale (e1 cards, e2 popovers and toasts, e3 modals and sheets, plus sticky), and the motion durations and easings. The icon set is Phosphor, Regular weight inactive and Fill or Bold weight active.
- **This document adds no new color, type, spacing, radius, elevation, or motion token.** Section 20 states this explicitly and names every composition it builds from existing tokens, with the measured contrast each pairing reuses.
- **References** use the form "P2 section 4.2" and "P2F section 15" to match the house style of the specs this extends.
- The three statements in 0.1, 0.2, and 0.3 govern every decision below. Read them first.

### 0.1 What already exists, verified in the repo

Nothing here invents a new data relationship. The pieces this design sits on are already built and working:

- **A post is capped at 500 characters**, enforced in two places: the database column check `char_length(body) <= 500` in `supabase/migrations/20261005000001_social_core.sql`, and a guard in `create_post` that raises "Posts are limited to 500 characters." Both count in Postgres `char_length`, which is code points, not bytes and not UTF-16 units. Every character count in this document is code points, to agree with the server exactly.
- **Threaded replies exist.** Every post carries `parent_post_id`, and a trigger sets `root_post_id` (the post's own id for a top-level post, inherited for a reply) and `depth` (0 for a top-level post, parent depth plus one for a reply). `get_thread` walks a thread, and `ThreadView.tsx` renders it with indent guide rails.
- **A multi-part chain is therefore already expressible with the existing schema.** Part 1 is a top-level post (parent null, depth 0, `root_post_id` equal to its own id). Part 2 is a reply to part 1 (depth 1). Part 3 replies to part 2 (depth 2), and so on. Every part shares the same `root_post_id`. This is exactly the reply chain the reference platforms publish, and it is what this design treats as a chain.
- **`create_post` caps thread depth at 30.** A reply to a post already at depth 30 or deeper is refused with a human message. A chain consumes one depth step per part, so the number of parts in a chain is bounded by that ceiling, and the composer must stay well under it to leave room for other people to reply at the end. This is the single hardest number in the design and section 9.1 and section 22 return to it.
- **The Following feed shows top-level posts only.** `feed_following` filters `parent_post_id is null`. Parts 2 through N of a chain are replies, so they never appear in the timeline as their own rows. Only the head of a chain can reach the feed. The feed-flooding problem the owner would otherwise have is already solved by the existing query; section 12 only has to label the head, not suppress the tail.
- **The profile Posts tab shows top-level posts only**, and the Replies tab shows replies. `profile_posts` filters on `parent_post_id is null` for Posts and `parent_post_id is not null` for Replies. So a chain head appears on the Posts tab and its continuation parts would, untouched, appear on the Replies tab as "replying to yourself" rows. Section 13 fixes that.
- **Author status gates every read path.** `feed_following`, `get_thread`, and `profile_posts` all require the author's status to be in (`active`, `restricted`). When an author is suspended or banned, every one of her posts blanks at once on every surface. Because all parts of a chain share one author, the whole chain vanishes together. Section 17 relies on this and designs so nothing can leave a fragment behind.
- **The composer is a single textarea** in `src/components/compose/Composer.tsx`, opened as a bottom sheet below the lg breakpoint and a centered modal at lg and up (`src/components/Dialog.tsx`), with a late-revealing character counter, mention and hashtag autocomplete (`ComposerAutocomplete.tsx`), an inline reply-audience control, and a session-preserved draft held in `ComposeProvider.tsx`. Everything in Part 1 extends this component; it does not replace it.
- **The body tokenizer is shared and code-point exact.** `src/lib/text.ts` decides what is a mention (an `@` at a word boundary followed by 3 to 30 of `[A-Za-z0-9_]`), what is a hashtag (a `#` at a word boundary with at least one letter, folded to NFC lowercase, capped at 40 characters), and what is inert (a well-shaped token the product deliberately does not activate, rendered in the muted tertiary tone). The split rule in section 6 reuses this exact tokenizer so that "never split a token" means never split what the renderer would draw as a token.

### 0.2 The one promise a chain makes

A chain is one thought in several posts. Everything follows from two consequences of that:

1. **Each part is its own full post of up to 500 characters.** The 500 is per part, not shared across the chain, because each part is a separate `posts` row with its own `char_length(body) <= 500` check. A member who adds a second part gets a fresh 500, exactly as on Threads.
2. **A chain publishes completely or not at all.** A member who taps "Post all 4" must end up with four parts or with zero and her draft intact. She must never end up with a broken half-thread (parts 1 through 3 live, parts 4 and 5 lost). Section 14 states this as a hard requirement and designs the member-facing behavior when the publish fails. The implementing agent makes the write atomic in the database; this document specifies the requirement and what the member sees.

### 0.3 The constraints that outrank layout

- **Identity is the `@handle` only.** No surface in this document renders `display_name` (the legal name). The composer, the chain indicator, the "part k of N" label, the feed head, the thread view, and every tombstone identify a person by handle. This is the standing rule from P2 section 3.2 and it is not relaxed for chains.
- **The irreversibility rule (P2B section 0.2).** Destructive actions differ from their neighbors by more than casing or color: a distinct verb, a distinct placement, a distinct weight. Deleting a part of a draft and deleting a published part both touch this; sections 5.3 and 16 honor it.
- **No meaning is carried by color alone.** The chain connector is a visual aid, never the only signal. Position is always available as words ("Part 2 of 4") for a screen reader and for anyone who does not perceive the rail. Section 19 is the accessibility section and it is not optional.
- **The owner dislikes friction and paternalism.** Prior decisions (the 40-character hashtag cap renders grayed rather than blocking; refused mentions go quietly inert; the post always succeeds) establish a house posture: do not nag, do not shame a character count, do not throw an interstitial where an inline, reversible action will do. The over-limit paste in section 6 is designed to that posture: it never blocks and never loses text.

---

# PART 1. THE COMPOSER

## 1. The shape of a multi-part draft

The composer opens exactly as it does today: a bottom sheet below lg, a centered modal at lg and up, with the member's avatar, one text field, the audience control, and the Post button. A fresh composer is a one-part draft, and a member who never taps "Add to thread" sees no change at all. The multi-part machinery is invisible until she asks for it. This matters: the common case is still a single post, and it must not grow a single pixel of chrome it did not have before.

Internally the draft is no longer a single string. It becomes an ordered list of parts, each with its own text, and the chain-level settings (the reply audience, and the quoted post if the composer was opened in quote mode) sit beside the list rather than inside any one part. `ComposeProvider` holds this structured draft for the session, so an accidental dismissal does not lose a half-written five-part thread; the discard confirmation in section 8.4 guards the deliberate dismissal. This is a real change to `ComposeProvider` and section 21 lists it as a build note.

Each part is drawn as a block in a single vertical stack. The first part shows the member's avatar at its top-left, as the composer does today. Every part shows, in a quiet caption row, its position in the draft ("Part 1 of 3"), a small set of controls (reorder and remove, described in section 5), and, when it is near its limit, its own character counter (section 3). The parts are joined by a continuous vertical connector in the `thread-rail` tone running down the avatar column, so the stack reads as one thing that will post together, not as a list of separate drafts. Section 4 details the connector.

## 2. Adding a part: "Add to thread"

Beneath the current last part sits the affordance that is the whole feature. It is a full-width, left-aligned button with a Plus glyph (Phosphor `Plus`) and the label **Add to thread**. The label is deliberate: it is the owner's own phrase and the reference platforms' phrase, so it carries no learning cost, and it reads as "continue what I am writing," not "write a separate post." It uses the `label` type role in `accent`, sits at a 44 by 44 minimum touch target, and is the resting-state, quiet accent treatment used elsewhere for secondary actions (text accent on surface, measured 6.26 light and 6.80 dark, with `accent-subtle` on hover).

Activating it appends a new empty part to the end of the list, extends the connector down to it, moves keyboard focus into the new part's field, and scrolls it into view above the keyboard on mobile (section 9). The new part's caption updates every existing part's "of N" count in one pass, so adding the fourth part relabels parts 1 through 3 from "of 3" to "of 4" immediately. A screen reader hears a polite announcement, "Part added, 4 parts total" (section 19).

"Add to thread" has two homes so a member never has to hunt for it. It sits beneath the last part, where the eye naturally ends, and it is mirrored in the sticky action bar (section 9.2) so it is reachable with the thumb on a phone without scrolling to the bottom of a long last part. Both invoke the same action.

There is one guard. When the draft has reached the part cap (section 9.1), "Add to thread" is disabled, not hidden, and carries a short explanation on focus and in its accessible name: "This thread is at its limit of 25 parts." Hiding the control would make the limit feel like a bug; disabling it with a reason makes it legible.

## 3. Per-part character counting

Each part counts its own characters against 500, independently, because each part is a separate post with its own server-side 500 check. The counter is a per-part object, not a single counter for the draft.

The counter is late-revealing, matching the existing composer, which only shows the count as the member approaches the limit rather than hovering a number over every keystroke. The rule, stated precisely:

- From 0 up to 440 characters in a part, that part shows no counter. The field is clean.
- At 441 characters (60 or fewer remaining), the part's counter appears in the caption row, showing the number remaining, in the `warning` tone (measured 4.74 on surface, light). The appearance is the signal; the number is the detail.
- At exactly 500 characters (0 remaining), the counter reads 0 in the `danger` tone, the field stops accepting further typed input (the field carries `maxLength` of 500, so the 501st typed character is simply not inserted), and a short line appears beneath that part: "This part is full. Add another part to keep writing," with "Add another part" being the live "Add to thread" affordance. This is the one place the limit turns into an invitation rather than a wall: hitting 500 by typing is the natural moment to start the next part, so the design offers the next part right there. Typing is blocked at 500, as on Threads; it is paste, not typing, that gets the richer treatment in section 6.

Only the focused part's counter needs to be loud. On mobile, a collapsed (unfocused) part that happens to be full shows a compact full marker in its summary (section 9.3) rather than a live number, since you cannot be typing into it. The counter is announced politely to a screen reader as it changes (`aria-live="polite"`), never assertively, so it does not interrupt composition.

Counting is in code points, using the same measurement the server uses and that `src/lib/text.ts` already uses for the 40-character tag cap (`[...text].length`). An emoji that is one grapheme but several UTF-16 units counts the way Postgres counts it, so the client and the server never disagree about whether a part is at 500.

## 4. How the parts look connected

The composer must make it obvious, before the member posts, that these parts will go out as one connected chain and not as separate unrelated posts. Three things carry that:

1. **A continuous connector.** A 2px vertical line in the `thread-rail` tone runs down the avatar column from the first part through the last. It is the same visual language as the thread view's reply rail (P2 section 6, and `border-thread-rail` in the code), used here to mean "these belong together." It is decorative and `aria-hidden`; it is reinforcement, never the sole signal.
2. **The position caption on every part.** "Part 2 of 4," in the `caption` role, `text-tertiary`. This is the signal that survives when the rail is not perceived, and it is what a screen reader reads. It is plain words, not a bare "2/4," because in the composer the member is building the thing and the words remove all doubt about what the number means.
3. **One shared frame.** The parts sit inside a single sheet with one Post button at the bottom that names the count ("Post all 4," section 8). A member cannot miss that one action posts all of them.

The connector and caption appear only once a draft has two or more parts. A one-part draft shows neither, because there is nothing yet to connect, and a lone "Part 1 of 1" would be noise.

## 5. Reordering, editing, and removing a part

### 5.1 Editing

Each part is an ordinary text field with its own autocomplete, its own mention and hashtag handling, and its own 500 limit. Everything that works in the single composer works in each part unchanged: `@`-mention autocomplete and its follow-ranked, handle-only, block-excluded results (P2F section 9); hashtag autocomplete and the 40-character cap that renders an over-length tag inert and grayed (the hashtag-cap decision, migration 20261018000001); the inert rendering of a refused or unresolvable mention. Because each part is a separate post, the per-post limits apply per part: up to 30 indexed hashtags and up to 10 mention notifications per part, not per chain. Tapping a part puts the caret in it; it is just a field.

### 5.2 Reordering

Each part (when there is more than one) carries two controls in its caption row: Move up (Phosphor `CaretUp`) and Move down (`CaretDown`), each a 44 by 44 target with an explicit accessible name ("Move part 2 up"). Move up is disabled on the first part and Move down on the last. Pressing one swaps the part with its neighbor, renumbers every caption in one pass, keeps focus on the moved part so a member can move it several places with repeated presses, and announces the result politely ("Part 2 moved up, now part 1").

Up and down buttons are the canonical reorder mechanism, not drag, for two reasons: they are fully keyboard operable and screen-reader legible, and drag-to-reorder is unreliable and fiddly on a phone with the keyboard up, which is the case this design is built for (section 9). Drag may be added as a pointer-only enhancement on top of the buttons, but it is never the only way to reorder and it never replaces them.

### 5.3 Removing a part

Removing a part must be obvious and must not feel destructive, especially for the middle part of a long draft. The behavior depends on whether the part has content, and it honors the irreversibility rule by making an undo always available for anything that could be a mistake.

- Each part (when there is more than one) carries a Remove control (Phosphor `X` or `Trash`) in its caption row, 44 by 44, accessible name "Remove part 3."
- **Removing an empty part** (its trimmed text is empty) happens immediately with no confirmation and no undo. There is nothing to lose, and asking would be friction. The connector re-stitches and the remaining parts renumber.
- **Removing a part that has content** happens immediately and optimistically, the way a repost is undone (P2F section 15): the part collapses out, the connector closes over the gap, the remaining parts renumber, and a single calm inline notice appears for a few seconds with an Undo control: "Part removed. Undo." This is the reshare-undo pattern reused, and it is why removing the middle of a five-part draft does not feel like breaking the chain: the connector simply mends, and one tap brings the part back exactly where it was. There is no modal, no red confirmation dialog, no "are you sure"; the undo is the safety net, which fits the house posture of not nagging.
- **The last remaining part has no Remove control.** A draft always has at least one part. Clearing that part's text empties the composer and disables Post; it does not delete a part that is not there.

Collapsing and re-stitching use the `base` motion duration and the standard easing, and they respect `prefers-reduced-motion` by dropping the translate and simply updating the layout.

## 6. The over-limit paste and the split rule

This is where multi-part composers go wrong, so it is specified exactly.

A member drafts 1,400 characters in her Notes app and pastes it into a part. The naive outcomes are both wrong: silently truncating at 500 loses her words, and refusing the paste makes her do the splitting by hand. The design does neither. It flows the overflow into new connected parts automatically, loses nothing, blocks nothing, and makes the whole thing reversible with one tap.

### 6.1 The behavior

When a paste (or any single edit) would push a part past 500 characters, the composer splits the pasted content across the current part and as many new parts as needed, appends those parts to the draft, renumbers, and shows a single calm inline notice with an Undo: "Added as 3 parts. Undo." Undo restores the pre-paste state (the long text back in one field, over the limit, so she can choose to trim instead). This is the same optimistic-plus-undo pattern as a repost and a part removal; it is consistent, it respects the member's text, and it never throws a dialog in front of her. If the overflow would push the draft past the part cap (section 9.1), the composer splits up to the cap, leaves the remainder in the last part over the limit with its counter in `danger`, and the notice reads "Added as 25 parts. The rest is too long for this thread. Undo," so nothing is lost and the member decides what to cut. It is the one case where a part is left over the limit, and Post stays disabled until she resolves it (section 7).

### 6.2 Where a split is allowed

The split points are chosen by this rule, in order, always keeping each resulting part at 500 code points or fewer, and the splitter uses the shared tokenizer from `src/lib/text.ts` so that a token means exactly what the renderer will draw as a token:

1. **Prefer a sentence boundary.** Within the window that fits in the current part, split after the last sentence-ending punctuation (`.`, `!`, `?`, including runs like `?!` and a trailing closing quote or bracket) that is followed by whitespace. Sentences are the natural seam of a thought, so a chain split at a sentence boundary reads as if it were written in parts.
2. **Fall back to whitespace.** If no sentence boundary fits (the first sentence is longer than 500, or there is none), split at the last whitespace that fits: prefer a paragraph break (a blank line) over a single newline, and a newline over a space. This never splits a word.
3. **Never split inside a token.** A split must never land inside an `@mention`, a `#hashtag`, or a URL, because a half-token is both ugly and wrong (it would change what the server parses and what the renderer links). If the only fitting whitespace would leave a token straddling the boundary, move the split to the whitespace before the token starts, pushing the whole token to the next part. The same holds for a mention or hashtag the member is mid-typing.
4. **Last resort, and only here, a hard break.** A single run with no internal whitespace that is itself longer than 500 code points (a 600-character URL, a wall of unbroken characters) cannot be kept whole, because the server will not accept a 500-plus part. In this one case the splitter breaks at the 500 code-point boundary and the notice names it honestly: "One long stretch did not fit in a single post and was split." This is the only situation in the entire design where a break lands inside a run of non-whitespace, and it exists only because no boundary is available. Everywhere else, tokens and words stay whole.

All of this counts in code points, so a split never lands in the middle of a multi-byte character or a multi-unit emoji.

### 6.3 Why automatic rather than a prompt

The brief notes that Threads "can automatically offer to create another connected post." Hersciety does the automatic flow with an undo rather than a blocking prompt, because a prompt is friction in the one moment the member is clearly trying to move a lot of text in, and the house posture (the grayed hashtag, the quietly inert mention, the always-succeeding post) is to act and offer a reversal rather than to interrogate. The undo preserves the member's control completely: if she wanted one trimmed post and not three parts, Undo gives her the long field back to cut down. Nothing is decided irreversibly on her behalf.

## 7. Empty and whitespace-only parts

An empty or whitespace-only part must be impossible to publish. The server already refuses an empty body (`btrim(p_body) = ''` raises "Post cannot be empty"), and that is the backstop. The composer makes sure the member never reaches it, and makes fixing it obvious rather than just blocking.

- **A part is empty** when its trimmed text is empty. Whitespace-only counts as empty.
- **Trailing empty parts are dropped at publish.** The common accident is tapping "Add to thread," reconsidering, and leaving the new part blank at the end. Those trailing empties are discarded silently when the member posts, so a three-part thought with one abandoned empty part at the bottom posts as three parts, not four, and nobody has to clean up after herself.
- **An interior empty part blocks publishing and is marked.** If a part with content sits above and below an empty part, that empty part is flagged in place with a quiet note in the `warning` tone ("This part is empty. Add something, or remove it") and its Remove control is emphasized. Post stays disabled, and the Post button names the reason (section 8.3). This is the honest state: the member built a gap on purpose or by accident, and the fix (fill it or remove it) is one tap, shown right where the gap is.
- **Post is disabled while any non-trailing part is empty.** The button mirrors the existing `empty` guard, extended across the parts: it is enabled only when every part that will actually be posted has non-whitespace content.

## 8. The publish button and what it promises

### 8.1 The label

Nobody should be surprised by how many posts they are about to make. The button says so:

- A one-part draft: **Post** (unchanged).
- A multi-part draft: **Post all N**, for example "Post all 4." The count is in the label because the count is the thing that could surprise. "Post all 4" is unambiguous: four posts are about to go out as one thread.

While posting, the label reads "Posting..." and the button is disabled.

### 8.2 The audience applies to the whole chain

The reply-audience control (Everyone, People you follow, Only mentioned people) stays exactly where it is in the existing composer and appears once, as a chain-level setting, not once per part. The chosen audience is applied to every part when the chain is published, so whichever part someone replies to, the same rule governs. A member sets who can reply once, for the thread, which is what she means.

### 8.3 When Post is disabled, it says why

A disabled Post button is paired with a short reason so the member is never stuck guessing. The reasons, in priority order: "Add something to post" (the whole draft is empty), "Fill or remove the empty part" (an interior empty part, section 7), "One part is over the limit" (section 6.1's over-cap remainder). The reason uses the `caption` role in `text-tertiary`, sits beside or beneath the button, and is tied to the button with `aria-describedby` so a screen reader hears it.

### 8.4 Discarding a multi-part draft

Closing the composer with unsent content asks before discarding, as it does today, but the copy scales with the draft. A one-part draft asks "Discard this post?" A multi-part draft asks "Discard this thread?" with the body line "All N parts will be discarded," so the member knows the confirmation covers the whole chain, not one part. The two choices keep the irreversibility shape from P2B: the safe choice is the left ghost "Keep editing," the discard is the right `danger-fill` "Discard."

## 9. Mobile first: the composer with the keyboard up

This platform has been through a serious mobile usability failure and a real responsive pass (the no-logout-on-mobile blocker, and the responsive and safe-area work). A multi-part composer on a phone with the keyboard up is the hard case and it is designed as the primary case, not an afterthought.

The problem is vertical space. With the keyboard open, a phone has perhaps 40 percent of its height left, and a five-part draft of full fields does not fit. The design keeps the member's focus and her two most important actions always in reach, and collapses everything she is not editing.

### 9.1 The part cap

The composer caps a single published chain at **25 parts**. The number is bounded from above by the database: `create_post` refuses a reply at depth 30 or deeper, a chain spends one depth step per part, and a chain should leave headroom for other people to reply at its end. Twenty-five parts puts the last part at depth 24 and leaves five depth steps for replies before the ceiling, which is comfortable, and 25 parts of up to 500 characters is 12,500 characters, far more than any single thought needs. The cap is a soft product limit the composer enforces by disabling "Add to thread" (section 2) with a stated reason; it is not a new database constraint.

### 9.2 The sticky action bar

Pinned to the bottom of the sheet, above the keyboard, is a compact action bar that rides with the keyboard and respects `env(safe-area-inset-bottom)` (the sheet already applies this). It carries three things and only three: the **Add to thread** control, the **focused part's character counter** (when it is in the reveal band), and the **Post all N** button. These are the actions a member reaches for repeatedly while building a chain, and keeping them docked means she never dismisses the keyboard to find them. The bar uses the sticky elevation token. On desktop at lg and up, where the keyboard is not an issue, the same controls sit in their natural places and the bar is not sticky.

### 9.3 Collapse everything but the focused part

Only the focused part is drawn full height. Every other part collapses to a compact summary chip: its position caption ("Part 2 of 4"), the first line or so of its text truncated, a full marker if it is at 500, and its reorder and remove controls. Tapping a summary expands it, focuses its field, and collapses whichever part was focused before. This is the move that makes a long chain usable on a small screen: the member edits one part at a time in full, sees the whole structure as a short stack of chips, and can reorder or remove any of them from the chip without expanding it. The connector runs down the whole stack, chips and expanded part alike, so the chain still reads as one thing.

On desktop the collapse is unnecessary and parts render expanded; the summary-chip treatment is a sub-lg affordance.

### 9.4 Scrolling and the autocomplete

When focus moves to a part (by adding one, or by tapping a chip), the composer scrolls that part's field to sit just above the sticky bar and the keyboard, so the caret is always visible. The mention and hashtag autocomplete listbox docks between the focused field and the sticky bar (the pattern P2F section 9 set for mobile), above the keyboard, and never covers the field being typed into.

---

# PART 2. WHAT A CHAIN IS

## 10. The structural definition

A chain is not a new record and not a new table. It is a shape in the existing reply tree, recognized at read time:

**A chain is the maximal run of consecutive posts by one author down a single reply spine, starting at a top-level post.** Concretely, let A be the author of a top-level post P1 (parent null). P2 is the continuation of P1 if P2 is a reply to P1 and P2's author is also A. P3 is the continuation of P2 under the same rule, and so on. The chain is P1, P2, ... Pk, stopping at the first part that has no same-author reply continuing it.

Two consequences, both deliberate:

- **No new column is required to identify a chain.** The run is computed by walking the spine. The implementing agent may, as an optimization, store a part index or a chain marker when it writes the parts atomically (section 14), but the member-facing result must be identical to the structural reading, and nothing in this design depends on such a column existing. This keeps the promise that the design sits on the existing data relationship rather than inventing one.
- **Replying to your own post later extends your thread.** A member who posts something today and replies to it next week with a second thought produces, structurally, a two-part chain, and the design shows it as one. This is deliberate and it matches the reference platforms: it unifies "add to thread now" (the composer) and "add to thread later" (a self-reply) into one concept, so a member who forgot to add a part can simply reply to her own last part and the thread grows. The composer is the common way to make a chain; it is not the only way, and the display does not care which way a chain was made.

### 10.1 The tie-break, stated so the implementer is not guessing

A part can have more than one same-author reply (a member replied to her own P1 twice, in two separate self-reply lines). The spine must be deterministic, so: **the continuation of a part is its earliest-created same-author direct reply.** Any other same-author reply to that part is not on the spine; it renders as an ordinary nested reply under its parent (and carries no "Part k of N" label, because it is not a chain part). In practice the composer always produces a strict line (each part's only same-author child is the next part), so the tie-break only ever bites on hand-made self-reply branches, and it resolves them predictably.

### 10.2 How position and length are computed

The "N" in "Part k of N" is the count of currently visible parts in the chain, computed at read time. "Visible" means the part is not deleted and its author is reachable. Because N is computed live, deleting a part renumbers the chain automatically (section 16); there is no stored count to go stale.

---

# PART 3. DISPLAY

## 11. In the thread view

Opening a chain shows the whole thing, from part 1, read top to bottom, with other people's replies in their places.

### 11.1 Always open from the head

`get_thread(p_post)` returns the subtree below `p_post`, so calling it on a mid-chain part would start the reader in the middle. A chain must always be read from part 1. When the opened post is part of a chain, the thread view loads from the chain head (the post whose id equals the shared `root_post_id`, which for a chain is always part 1) and renders the whole chain, scrolling to and briefly highlighting the part that was actually tapped (for example, when a member opens a reposted or quoted mid-chain part). So "Show this thread" from anywhere lands the reader at the top of the thought, with their entry point marked.

### 11.2 The spine renders flat, replies nest

This is the central display rule, and it is a real change to `ThreadView.tsx`. Today the thread view renders the root plus two nested reply levels (`MAX_REL_DEPTH` is 2), then collapses deeper replies into a "View N more replies" re-root. A chain is a run of replies, so under the unchanged renderer part 3 would already be at the nesting budget and parts 4 and 5 would be hidden behind "view more replies." That is exactly wrong for a thread meant to be read whole.

The fix: **the author's own continuation spine renders as a flat, connected sequence at a single level, and does not count against the nested-reply budget.** The parts stack vertically, joined by the continuous `thread-rail` connector, each a full post card, each with its "Part k of N" caption. The nesting budget (root plus two levels, then re-root) applies only to replies by other people (and to the author's own non-spine branches, section 10.1) hanging off any part. So a five-part chain reads as five connected cards top to bottom, and under, say, part 2, someone else's reply and its two levels of sub-replies nest with the indent rail exactly as they do today, re-rooting beyond that.

The depth cap (30) still protects the recursive walk; the flat rendering is purely presentational and does not change the stored depths.

### 11.3 The position indicator

Hersciety uses **both** a visual connector and a text label, and it uses words rather than a bare fraction in the thread view. Each part card carries a quiet caption, "Part 2 of 4," in `text-tertiary`, and the continuous connector ties the cards together. The justification for both, and for words:

- A connector alone carries meaning by appearance only, which fails the color-and-form-alone rule and tells a screen-reader user nothing. The text label is the signal that always works.
- The text label alone would be a weaker grouping cue than a line that visibly joins the cards, and the product already owns the rail as its threading metaphor. Using it here is consistent, not novel.
- "Part 2 of 4" rather than "2/4" because the words are unambiguous and read correctly aloud. A bare "2/4" can be misread as a date, a score, or a rating, and it reads as "two slash four" to a screen reader unless given an explicit label anyway. The compact "k/N" form is kept only for dense spots (the feed pill in section 12, a corner of a quoted card in section 18), and even there it carries an `aria-label` that spells it out.

### 11.4 Replying from the thread

The thread view's primary reply affordance sits after the last part of the chain, and a reply made from there attaches to the last part, so "replying to the thread" lands the reply at the end, which is the conventional and legible outcome. Replying to a specific earlier part is still possible from that part's own Reply action (section 15). The existing per-post Reply action on each card is unchanged; the chain just adds a clear "reply to the thread" entry at the bottom.

## 12. In feeds

The feed work is small, because `feed_following` already returns only top-level posts, so only a chain's head can appear in the timeline and parts 2 through N never flood it. The head is labeled so a reader knows there is more and can get to it.

- A chain head in the feed renders as a normal post card showing the full first part, with a footer affordance beneath the body: **Show this thread**, accompanied by a compact count. The affordance's accessible name spells out the count ("Show this thread, 5 parts"). Tapping it opens the thread view from part 1 (section 11.1).
- The head card never inlines parts 2 through N. The timeline shows one card per chain, which is the whole anti-dominance design: a member's six-part chain occupies exactly one feed slot, the same as a single post, and the reader chooses to expand it. One person cannot out-shout the timeline by writing a long thread, because the thread is one card until opened.
- A compact "1/5" badge may sit near the head's timestamp as a secondary cue for readers who recognize it, always with a spelled-out `aria-label`; the primary, legible affordance is the worded "Show this thread" footer.

The same treatment applies in the Discover feed (P2B section 9), which is also a top-level-post surface: a chain is one head card with a "Show this thread" affordance, and the chain's length is not an amplification signal (P2B section 11 already refuses engagement-volume signals; a long chain earns no ranking boost for being long).

## 13. On profiles

A profile must represent a prolific chain-writer honestly: her threads should be visible and openable, but a single five-part chain should not read as five posts, and the profile must not fight the existing tabs (Posts, Replies, Reposts).

The rule: **a chain appears on the profile's Posts tab as its head only, one card, carrying the same "Show this thread, N parts" affordance as the feed.** Parts 2 through N do not appear as separate entries. This is mostly already true, because `profile_posts` returns only top-level posts for the Posts tab, so the head is naturally the only part there; the design adds the chain indicator to it.

Two points of judgment:

- **Head only, not head-plus-second.** The reference platforms show the first and second posts of a chain on a profile because their rows are short, so two rows give a useful preview. Hersciety post cards show the full body (up to 500 characters), so the head card is already a substantial preview on its own; a second full card would be redundant bulk and would start to let a chain-writer dominate her own grid. One head card plus the part-count indicator is the right amount of information here, and it keeps one simple rule that matches the feed exactly. The reader who wants more taps "Show this thread."
- **The Replies tab must not show chain parts as self-replies.** `profile_posts` on the Replies tab returns replies, which structurally includes a chain's continuation parts, and left alone they would render as "Replying to yourself" rows, which is noise and misrepresents what the Replies tab is for. Chain continuation parts are suppressed from the Replies tab: they belong to the thread, which is already represented by the head on the Posts tab. The Replies tab keeps its meaning, "her replies to other people's posts." This is a filter change in `profile_posts` and section 21 lists it as a build note; it must not touch genuine replies to other members. The Reposts tab is unaffected, since a repost of a chain part is handled in section 18.

---

# PART 4. THE EDGES

## 14. When publishing fails partway

**The requirement, plainly: a chain publishes completely or not at all.** A member who posts a five-part chain ends with five parts live or with zero parts and her draft intact. She is never left with a broken half-thread, and no reader ever sees a thread that stops at part 3 because parts 4 and 5 failed to write.

The implementing agent makes this atomic in the database: the parts are written in one transaction (for example, a single `create_thread` RPC that inserts every part and rolls the whole thing back on any error, reusing all of `create_post`'s existing checks per part, the author-active check, the per-part 500 cap, the empty-body refusal, the mention parsing, the reply-control, and the depth cap). This document specifies the member-facing contract:

- **The multi-part publish is not optimistically closed.** The single-post composer may close optimistically because one write is one atomic act. A chain must not close and clear until the server confirms all parts committed, because closing early and then failing would strand the draft. So "Post all N" shows a brief in-progress state, the button reads "Posting...," and the composer stays open until success.
- **On success**, the composer closes, the draft clears, and a confirmation toast reads "Thread posted."
- **On failure**, nothing is posted, the composer stays open with every part, its order, and the chosen audience exactly as they were, and one calm message appears: "Could not post your thread. Nothing was posted, so your draft is safe. Try again." The button returns to "Post all N." The member loses nothing and retries when ready.
- **Retry must be safe against a lost response.** If the network drops after the server committed but before the client heard back, a blind retry could double-post the whole chain. The publish carries a client-generated idempotency key so a retry of the same attempt is recognized and does not produce a second copy. This is a build note (section 21); the member-facing promise is simply that tapping "Try again" never duplicates a thread.

## 15. When someone replies to the middle of a chain

A reader can reply to any part, not only the last, and that is allowed and useful: a reply to part 2 of a five-part chain is a response to what part 2 said, in context.

- The reply attaches to the part it answers (its parent is that part), exactly as any reply does today. It is not redirected to the end of the chain.
- In the thread view, that reply renders as a nested reply under the part it answered, with the normal indent rail and the normal two-level budget and re-root (section 11.2). The chain's own spine stays flat and continues past part 2 to part 3; the reply is a separate branch off part 2. The tie-break in section 10.1 is what keeps these straight: part 3 (the earliest same-author child) is the spine, the reader's reply is a nested branch.
- The part's author (the chain author) is notified of the reply through the existing reply-notification path, honoring mutes, blocks, and preferences, unchanged.
- The chain author can keep adding parts to the end of her thread regardless of where readers have replied; a reply in the middle does not close the chain or block its continuation.

## 16. When the author deletes a published part

A member deletes part 3 of her live five-part chain. The existing `delete_post` soft-deletes it: the row stays (so the tree does not break and parts 4 and 5 are not orphaned), with `deleted_at` set and `visibility` set to `removed_author`.

What readers see:

- **The chain renumbers to the parts that remain readable.** N is computed live (section 10.2), so after the deletion the chain has four readable parts and they are labeled Part 1 through Part 4 in order. There is no stored "of 5" to contradict.
- **A slim, honest marker shows where the part was**, in the muted tombstone language the thread view already uses ("The author removed this part"), rather than silently stitching the gap closed. Two reasons for the marker. First, honesty: anyone who read the original thread should see that something was removed, not a seamless shorter thread that pretends the removed part never existed. Second, structure: any replies other people attached to part 3 still hang off it, and the marker is what keeps those replies anchored rather than orphaned. This is the same rationale as the existing reply tombstone, applied to a chain part.
- **The number on a link or a quote may shift**, and that is acceptable. A part someone quoted as "Part 4 of 5" becomes "Part 3 of 4" after an earlier part is deleted, because the label always reflects the live thread. The quoted card links to the live thread, so a reader who follows it sees the current, correct position. We do not freeze a stale number to avoid a shift; the live number is the honest one.

The special case of deleting the **head** (part 1): the head is a top-level post, and the feed shows only top-level posts, so deleting the head removes the chain from the timeline (a deleted post is filtered out of `feed_following`). The remaining parts are not deleted; the member removed one part, not the thread. They stay reachable by direct link and render as a chain beginning at part 2, with the removed-part marker above it. This is the honest outcome: removing your opening post reasonably removes the thread from feeds, while the rest of your words remain accessible to anyone who had the link, clearly marked that the opening was removed. A member who wants the whole thread gone deletes each part, or uses the convenience in section 21.1 if the implementer adopts it.

## 17. When the author is suspended or banned

Verified behavior: a suspended or banned member's posts are removed from every public surface, because `feed_following`, `get_thread`, and `profile_posts` all require the author's status to be in (`active`, `restricted`). Every part of a chain has the same author, so **the entire chain vanishes together, atomically, at read time.** There is no path that can leave a fragment visible, and the design must not create one.

- The chain never appears in any feed (the head's author is filtered out).
- In a thread view that would otherwise show the chain, `get_thread` blanks every part (its `unavailable` flag is set for every row because the author is unreachable). The chain treatment must collapse to a single "This thread is unavailable" tombstone for the whole chain, not a stack of five "Part k of N" cards with blank bodies. A reader must never see the shape of a banned member's thread, only that it is gone.
- A quoted or reposted part of the chain falls to the existing unavailable stub (section 18), with no author, no text, and no part number.
- Nothing may render a part from a stale client cache after the author's status changes. Every part flows through the same author-status gate on every read, so a suspension or a ban blanks the chain uniformly the next time any surface loads it. The design adds no client-side chain cache that could survive the gate.

When a suspension lifts and the author returns to active, the chain returns whole, because the gate simply passes again; nothing was destroyed.

## 18. Reposting or quoting one part of a chain

A member can repost or quote a single part, and a single part out of context ("...and that is the third reason") can mislead. The design does not silently retarget the action to the whole thread (that would violate least-surprise), but it gives the reader a clear signal that there is more.

- **Reposting a chain part** surfaces that part in followers' feeds with the usual "@handle reposted" attribution (P2F section 16). When the reposted post is part of a chain, the card carries the same **Show this thread** affordance and a "Part k of N" cue as any chain part, so a reader who lands on part 3 through a repost can see it is part 3 of a thread and open the whole thing from the top (section 11.1 scrolls them to the part that was reposted). The repost targets the exact post the member chose; the signal, not a retarget, does the work.
- **Quoting a chain part** renders the nested compact card (P2F section 16) with a "Part k of N" marker in a corner of the nested card and the card linking, as it already does, to the quoted post, which opens the full thread from the head. So the quote shows the reader both the part being quoted and that it belongs to a larger thread.
- When the quoted or reposted part becomes unavailable (deleted, its author suspended or banned, or a block stands between any of the people involved), the card falls to the existing unavailable stub, exactly as P2F section 16 and section 17 of this document require, with no part number and no leak.

Quote-posting remains the deferred, carefully gated action P2F recommended; this section specifies the chain signal for whenever quote ships, and the repost signal now.

## 19. Accessibility

Accessibility is a first-class requirement here, as in the specs this extends.

- **Position is announced, never implied.** Every chain part carries its position as text, "Part 2 of 4," in the visible caption and in the part card's accessible name (for example, the card's `aria-label` reads "Post by @handle, part 2 of 4, 3 hours ago"). A screen-reader user always knows where she is in a chain, with no reliance on the connector. The connector is `aria-hidden`.
- **The connector carries no sole meaning.** It is decorative reinforcement of the text label and the grouping; removing it loses no information. This satisfies the color-and-form-alone rule.
- **Keyboard navigation in the composer.** Tab order runs field, then that part's controls (move up, move down, remove), then the next part's field, in visual order. Adding a part moves focus into the new field. Removing a part moves focus to the next part, or the previous if the removed part was last. Reordering keeps focus on the moved part. Every control is a real button with an explicit accessible name ("Move part 2 up," "Remove part 3," "Add to thread," "Post all 4"). The counter is `aria-live="polite"`. Part-count changes are announced politely ("Part added, 4 parts total"; "Part removed, 3 parts total").
- **Keyboard navigation in the thread view.** The chain reads as a sequence of articles in document order, so a screen reader moves through parts 1 to N naturally, then into the nested replies. "Show this thread" and "reply to the thread" are real links and buttons with spelled-out names.
- **Focus and the sheet.** The composer sheet keeps the focus trap, Escape-to-close, and focus-return the Dialog already provides. On mobile, the scroll-into-view on focus change (section 9.4) keeps the focused field visible above the keyboard, which is also a low-vision and motor-access benefit, not only a convenience.
- **Reduced motion.** The connector re-stitch, the part collapse and expand, and any scroll animation respect `prefers-reduced-motion` by dropping translate and scale and simply updating layout; nothing essential is conveyed by motion.
- **Contrast.** Every pairing this design uses is already measured (section 20). The counter's `warning` and `danger` tones, the `text-tertiary` captions and tombstones, and the `accent` affordances all meet AA at the sizes used.

---

# PART 5. CRAFT AND HANDOFF

## 20. Tokens and components

**This design adds no new design token.** Every color, type, spacing, radius, elevation, and motion value it uses already exists. The pairings it relies on, with the measured ratios reused from P2 section 2.3, P2B, and P2F:

- The chain connector reuses `thread-rail` (accent at 16 percent, light and dark), the same decorative rail the thread view already uses, exempt from the 1.4.11 non-text-contrast minimum because it is reinforcement and the text label is the real signal.
- The per-part counter reuses `warning` on surface (measured 4.74 light) in the reveal band and `danger` on surface (measured 5.31 light) at the limit.
- Position captions, the "part full" note, the removed-part marker, and the unavailable tombstone reuse `text-tertiary` on surface (measured 4.88 light, 5.11 dark) and the existing tombstone composition.
- The "Add to thread" control, the "Show this thread" affordance, and the "Part k of N" accent cues reuse `accent` on surface (6.26 light, 6.80 dark) and `accent-subtle` on hover (text-primary on accent-subtle 14.35 light, 13.20 dark).
- The discard confirmation and any destructive pairing reuse the `danger-fill` plus ghost composition from P2B, unchanged.

**New component compositions (not new tokens):**

1. The composer part block (field, position caption, counter, reorder and remove controls) and its mobile summary-chip collapsed form, plus the sticky action bar. All are compositions of the existing field, Button, caption type, Phosphor icons, and the sticky elevation.
2. The chain treatment in the thread view (flat spine plus continuous connector plus "Part k of N" caption), the feed and profile "Show this thread, N parts" affordance, and the removed-part marker. All are compositions of the existing post card, `thread-rail`, caption type, and tombstone.

## 21. Build handoff notes

These are the changes the implementing agent will make; this document does not make them.

- **Atomic multi-part publish.** A single transaction (for example a `create_thread` RPC) that inserts every part in order, each part a reply to the previous, applying all of `create_post`'s existing per-part checks, and rolling back entirely on any error. It carries a client-supplied idempotency key so a retry after a lost response does not double-post (section 14).
- **`ComposeProvider` draft shape.** The session draft changes from a single string to an ordered list of parts plus chain-level settings (audience, quoted post). The session-preservation and discard-confirmation behavior extends to the whole list (sections 1, 8.4).
- **`ThreadView` chain rendering.** Detect the same-author continuation spine (section 10) and render it flat at the root level with the continuous connector, so chain parts do not consume the nested-reply budget; nest only non-spine replies (section 11.2). Resolve a mid-chain entry point to the chain head and highlight the entry part (section 11.1).
- **`profile_posts` Replies tab filter.** Exclude a member's own chain-continuation parts from her Replies tab, without affecting genuine replies to other members (section 13).
- **Chain detection helper.** A read-time function that, given a post, returns its chain head, its parts in order, each part's live "k of N," and whether a part is a chain continuation. It is the single source the feed, profile, thread view, and repost and quote cards all call, so the four surfaces agree. Whether it is computed by walking the spine or backed by a stored part index is the implementer's choice, provided the result matches the structural definition in section 10.
- **The split helper reuses `src/lib/text.ts`.** The over-limit paste splitter (section 6) uses the shared tokenizer so "never split a token" agrees exactly with what the renderer draws as a token, and counts in code points.
- **Feed and quote cards** gain the "Show this thread, N parts" affordance and the "Part k of N" cue (sections 12, 18), fed by the chain detection helper.

### 21.1 Optional convenience, not required

A "Delete entire thread" action on the head's overflow menu, which deletes every part of the author's own chain in one confirmed step, would spare a member from deleting five parts by hand and would avoid the head-deleted-but-tail-remains state in section 16. It is a reasonable convenience and it honors the irreversibility rule if it carries a distinct verb and a confirmation. It is noted, not required, and it is out of the critical path for shipping the composer.

## 22. The judgment calls, and the reasoning

- **Add-part affordance and label: "Add to thread" with a Plus glyph.** The owner's own phrase and the reference platforms' phrase, zero learning cost, reads as continuation rather than a separate post.
- **Position indicator: continuous connector plus the worded label "Part k of N."** Both, because a connector alone fails the color-and-form-alone rule and tells a screen reader nothing, and words are unambiguous where a bare "2/4" is not. The compact "k/N" is kept only for dense spots, always with a spelled-out label.
- **Profile truncation: the head only, one card, plus a part-count indicator.** Because Hersciety cards show the full body, so the head is already a strong preview, and one rule that matches the feed is cleaner than head-plus-second. Chain parts are suppressed from the Replies tab so they do not read as self-replies.
- **Over-limit paste: auto-flow the overflow into connected parts with a single Undo, never block, never lose text.** Split preference: sentence boundary, then whitespace (paragraph over newline over space), never inside an `@mention`, `#hashtag`, or URL (push the whole token forward), with a hard break only as a last resort for a single tokenless run longer than 500, named honestly. All in code points, using the shared tokenizer. Matches the house posture of acting with a reversal rather than interrogating.
- **Part cap: 25 parts per chain.** Bounded by the database depth cap of 30, leaving reply headroom, and generous for any real thought (12,500 characters).
- **Publish is atomic and non-optimistic for multi-part.** All or nothing; on failure the draft is preserved and the member is told nothing was posted; a retry cannot duplicate.
- **Deleting a published part renumbers to the live count and shows a slim honest removed-part marker**, to stay truthful and to keep any attached replies anchored.
- **Chain is a structural shape, not a new record**, and a later self-reply extends a thread, unifying "add now" and "add later."

None of these needs the owner's values or her money, so none is returned to her as a question. They are decisions, recorded with their reasons.

## 23. Out of scope, and one possible future direction

Out of scope for this design: quote-post (remains the deferred, gated action from P2F; section 18 only specifies the chain signal for it), direct-message threading (P2C), and any ranking treatment of chains in Discover (P2B section 11 already refuses length as an amplification signal).

Possible future direction, noted once and not designed here: Threads also ships a single long-text attachment of up to 10,000 characters as an alternative to a multi-part chain, for members who find long chains hard to follow. The owner asked for the chain pattern, which this document designs; the single-field long post is recorded here only as a direction that exists.

## 24. Summary

A member writes her first post as she always has. When she runs out of room, or simply wants to keep going, she taps **Add to thread** and gets a second part with its own fresh 500 characters, joined to the first by a connector so it is obvious they post together. She can add up to 25 parts, reorder them with up and down controls, and remove any one with a single tap and an Undo that mends the chain behind it. If she pastes something too long, the composer flows the overflow into new connected parts automatically and offers one Undo, splitting only at sentence and word boundaries and never through a mention, a hashtag, or a link. Empty parts cannot be posted: trailing ones are dropped, an interior gap is flagged until she fills or removes it. The button says **Post all N** so she knows exactly what she is about to send, and the whole thread posts completely or not at all, with her draft kept safe if it fails. On a phone with the keyboard up, only the part she is editing is full height, the rest collapse to chips, and Add-to-thread, the counter, and Post ride in a bar above the keyboard.

A reader sees a chain as one card in the feed, labeled **Show this thread, 5 parts**, so no one person's long thread can dominate the timeline. Opening it reads the whole thing from the top, the author's parts flat and connected, other people's replies nested in their places, each part captioned **Part 2 of 4** for everyone including a screen reader. A profile shows the head of each thread, not every part. If the author removes a part, the thread renumbers and a quiet marker shows where it was. If the author is suspended or banned, the entire thread disappears as one, never in pieces. Reposting or quoting a single part tells the reader there is more and takes them to the top of the thread. The whole design adds no new token and sits on the reply tree the product already has.
