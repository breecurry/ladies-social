# Hersciety, Phase 2D: Visual and UX Design Direction for the Owner's Admin Dashboard, the Member Directory, and the Metrics Foundation

**Status:** Design specification for the Phase 2D build. It defines look, feel, information architecture, component anatomy, states, confirmation patterns, role gating, and privacy rules for two things the owner asked for: a way to see every member and the total member count, and a metrics surface built so that the twentieth metric is a configuration change, not a redesign. It is not code and does not define components in a framework. An engineer should be able to build Phase 2D from this plus the Phase 2 spec, the Phase 2B spec, and the existing token system without guessing.

**Date:** 2026-10-05

**The owner's brief, verbatim:** "i want to be able to see not only every member from my admin dashboard but also the total member count as well. I like to keep track of numbers, so i want you to build this with intent to create something much much bigger eventually."

That last clause is the load-bearing instruction. A single "total members" counter bolted to a page would satisfy the words and fail the intent. This document designs the first room of a building that is meant to grow: a member directory that stays usable from two members to two hundred thousand, and a metrics system whose unit is a declared tile, so that adding the twentieth metric is a line in a registry rather than a new screen.

**Design thesis (inherited, not reopened):** "Calm paper, sharp tools." The same warm sand canvas and single Iris-violet accent carry this surface. The admin dashboard is a management tool, so it is calm and legible, never a cockpit of alarms. It is also the surface most able to turn a safety product into a surveillance product by accident, so its restraint is a safety feature, not a style choice: what it makes easy to see shapes what its one privileged user does.

**Relationship to the earlier specs.** This document extends `docs/design-phase2-social-core.md` (the Phase 2 spec) and `docs/design-phase2b-moderation-and-discover.md` (the Phase 2B spec). It does not restate them and does not change them. References written as "P2 section X" point into the Phase 2 spec; references written as "P2B section X" point into the Phase 2B spec. The application shell (P2 section 1), the token foundation (P2 section 2), the shared primitives (P2 section 3), the empty and loading and error states (P2 sections 9 and 11), the accessibility specification (P2 section 12), the motion specification (P2 section 13), the irreversibility rule (P2B section 0.2), the legal-name constraint (P2B section 0.1), and the AAL2-gated owner surfaces already built (the roles manager and the audit-log viewer) are inherited. Where this document needs something those specs already define (a card, a chip, an input, a confirmation modal, the AAL2 step-up pattern), it reuses it rather than inventing a parallel one.

---

## 0. How to read this document

- **Tokens** are the ones already implemented in `src/app/globals.css` and enumerated in P2 section 2. This document adds no new color, type, spacing, radius, elevation, or motion token. Section 21 states that explicitly and lists the compositions of existing tokens it relies on, with their already-measured contrast ratios.
- **Icons** are Phosphor (MIT), Regular weight inactive and Fill weight active, exactly as the earlier specs set out.
- **The three hard constraints in sections 0.2, 0.3, and 0.4 govern every surface in this document.** They are the reason the product exists and the reason this particular surface has to be built with more care than any other. Read them first.

### 0.1 What this surface is, and the one thing it must never become

The owner wants to see her members and her numbers. That is a reasonable and ordinary thing for a founder to want, and this document gives it to her fully. But a member directory and a metrics dashboard are, between them, the exact shape of a surveillance system: a browsable list of every person, and a set of dials that measure them. On a platform whose members are hiding from specific people, the dashboard is the surface where a careless build would quietly turn a safe space into a panopticon with one authorized viewer.

So the whole design is organized around a single discipline: **the dashboard shows the owner the health of her community and the standing of any account she has a reason to look at, and it is deliberately bad at letting her, or anyone, idly browse the identities of the women who trust the platform.** Those two goals are not in tension once you accept that "see every member" means "be able to account for every member," not "be able to scroll every member's real name." This document draws that line explicitly and repeatedly, because the line is the product.

### 0.2 Hard constraint one: identity is a deliberate, logged, reasoned act, never a column

This inherits P2B section 0.1 and sharpens it for a surface that did not exist when that constraint was written: a browsable roster.

`display_name` is the member's real legal name. It is nullable, trigger-locked to be either NULL or the member's own verified legal name, and its public display is opt-in and off by default (P2 section 3.2 and the identity migration). The rest of a member's identifying data, her legal name as verified, her email, her phone if ever verified, her signup and last-login IP, and her device-signal hashes, lives in `user_private`, readable only by the member herself and the Owner, by row-level security. **Members of this platform are hiding from specific people.** The single most dangerous thing the product can do is make it easy to see who a member really is.

A moderator does the entire enforcement job by `@handle` and never sees a legal name (P2B section 0.1, enforced in the built console). This document extends the same rule to the admin dashboard, and it has to go one step further, because a directory is precisely the surface that tempts a build to "just show the real name so the list is useful." **It does not need to.** Concretely, as law for every surface below:

- **No browsable, sortable, searchable list in this document ever renders a legal name, an email, a phone number, or any contact or location detail.** The directory list columns are `@handle`, join date, account status, role, and a coarse activity bucket. Nothing in a row identifies the human behind the handle. This is not a default that can be toggled on; there is no code path that puts identity into the list.
- **Legal name and contact details are Owner-only and live behind the AAL2 step-up**, on the member-detail identity panel (section 7), reached by a deliberate action that states a reason and is written to the hash-chained `audit_log`. Admins and Moderators never see this panel and are never told it exists. The Owner reaches it only by choosing to, one named account at a time, with the access recorded.
- **Accessing an identity is an event, not a view.** The difference between "I am looking at the directory" and "I am looking at who @maya really is" must be a different screen, a different action, and a logged one, exactly as P2B keeps "I am reading the audit log" and "I am preparing a lawful disclosure" on different screens. A directory that let the Owner read every member's legal name by scrolling would be a catastrophic failure of this product even though the Owner is technically authorized to see those names. Authorization is not the same as ambient access. The product's stance is that every privileged read of identity is a discrete, reasoned, recorded act.

If a future revision feels the urge to add a "Name" column "just for the owner, just to make the list more useful," that urge is the violation. Write it down and stop.

### 0.3 Hard constraint two: the irreversibility rule, and why the directory has no destructive bulk actions

This inherits P2B section 0.2 in full and applies it to the one place it bites hardest on this surface: a list with checkboxes.

On 2026-10-06 the owner destroyed a live production database because an irreversible one-click action offered two choices that differed only by letter case. The rule that follows is a hard constraint: **every destructive or irreversible action in this product must differ from its neighbour by more than casing or colour. It must differ by a distinct verb, a distinct placement, and a distinct visual weight, and anything unrecoverable must additionally require a typed confirmation.**

A member directory is a grid of every account with a natural affordance to select many of them at once. That is the exact ergonomics of the incident: a multi-select, a single button, a reflex. **This document's answer is that the directory carries no destructive bulk actions at all, and in fact no account-changing actions at all** (section 9). The directory is a surface for seeing and accounting, not for acting. Every action that changes an account, warn, remove, restrict, suspend, ban, happens one named account at a time in the moderation console (P2B sections 4 and 5), with that account's full context in front of the acting person and, for the severe actions, the per-action confirmation and typed `@handle` gate the irreversibility rule requires. There is no "select 40 members and..." anything, because a batch is exactly where a reflexive mistake becomes a mass mistake. The single bulk operation the directory supports is a read, an export, and it is treated as a deliberate, logged act, not a destructive one (section 9.2).

### 0.4 Hard constraint three: default to showing staff less

The brief is explicit: "Owner sees everything here. Define precisely what, if anything, Admins and Moderators see. Default to showing them less." This document does, and states the whole gating in one table so a builder has a single source of truth. The roles are the four system roles already in the schema (`owner`, `admin`, `moderator`, `ts_reviewer`).

| Surface | Owner | Admin | Moderator | T&S Reviewer |
|---|---|---|---|---|
| Metrics dashboard (section 10 onward) | full | no (see note) | no | no |
| Member directory, browsable roster (sections 1 to 5) | full | no | no | no |
| Member lookup by exact `@handle` to a standing card (section 6) | yes | yes | no | no |
| Member-detail glance view: handle, status, role, standing, enforcement history (section 6) | yes | yes, only for an account reached by lookup | no | no |
| Identity panel: legal name, email, phone, IPs, device signals (section 7) | yes, AAL2 + reason + logged | no | no | no |
| Link into a member's moderation cases (section 8) | yes | yes | via the case queue only (P2B) | read-only via queue (P2B) |

Note on Admins and metrics: an Admin already sees the one operational number that bears on her job, the open-case count, through the moderation console's calm queue volume (P2B section 2.4). She does not get the analytics dashboard, because growth and community-health numbers are a governance concern, not an enforcement one, and widening who sees them widens the surveillance surface for no operational gain. If the owner later brings on a co-founder or operations partner who genuinely needs the numbers, that is a deliberate widening she authorizes, and it is one of the two real questions in section 22; it is not the default.

The reason staff default to less is the same reason the directory is search-first: the fewer people who can idly survey the membership, the smaller the blast radius if any one staff account is compromised, coerced, or simply curious. A moderator judges conduct from the case queue and never needs a roster. An admin acts on a specific account she has a reason to act on, reached by its handle, and never needs to browse the rest. Only the Owner, who carries the whole company's accountability, gets the whole picture, and even she gets identities only by asking for them on the record.

---

# PART 1. THE MEMBER DIRECTORY

## 1. Where the directory lives, and who reaches it

The member shell is fixed at five primary surfaces (P2 section 1.1) and is not touched. The admin dashboard is a privileged management surface, like Settings and like the moderation console, and is reached the same way: from the account control, not from the primary nav. The Owner-tools cluster already exists in the account menu as **Owner tools** (a `ShieldStar` glyph), landing today on `/owner/roles` and cross-linking to `/owner/audit` and `/owner/age-gate`. Phase 2D adds two siblings to that cluster, **Members** and **Insights**, and makes the Owner-tools landing a small hub that lists all of them. **This is one owner surface gaining rooms, not a second admin area.** It shares the account-menu entry, the role gating, and the visual grammar of the pages already there (a `text-title` page heading, a `max-w-prose` lead paragraph in `text-secondary`, content on `surface` cards, the `Alert tone="warning"` AAL2 step-up prompt).

- **Desktop and large tablet.** The Owner-tools hub is a short list of cards: Roles, Audit log, Age gate (the existing three), plus Members and Insights (the two this document adds). Each card is a labelled row with a one-line description and a `CaretRight`, exactly the Settings-row pattern (P2 section 8.1). Members and Insights open as their own full surfaces inside the same centered frame the rest of the app uses, allowed to widen past the 600px reading measure because a roster and a dashboard are working surfaces, not reading surfaces (the same allowance P2B makes for the moderation console in P2B section 1).
- **Mobile and small tablet.** Same entry, from Profile then the account menu then Owner tools. Members is a single scrolling list that pushes to a full-screen member detail on tap; Insights is a single column of metric cards. Both use the standard push pattern (P2 section 1.4) with a back affordance to the exact scroll position.
- **The dashboard wears the same quiet identity as the rest of the Owner tools.** It does not need the moderation console's persistent accent-subtle strip, because it is not a surface where a reflex closes an account; but every page in the cluster carries the `text-title` heading that names it ("Members", "Insights") so the Owner always knows which room she is in. The identity panel (section 7), the one genuinely sensitive surface, gets its own unmistakable treatment described there.

Role gating is enforced the way the existing owner pages enforce it: the page redirects a non-owner to `/home` and never renders, so a member or a moderator cannot reach it and never learns it exists, exactly as `/owner/roles` and `/owner/audit` already do, and exactly as `/mod` does for non-staff. The Admin lookup affordance (section 6) is the one part of this part that an Admin can reach, and it is reached from the moderation console, not from the Owner-tools cluster, so an Admin never sees the Owner's dashboard chrome at all.

## 2. The directory is search-first, not browse-first (stated as a principle)

Before the columns and the controls, the governing decision, because it shapes all of them: **the directory is built to answer "show me this member" and "account for the shape of the membership," and it is deliberately not built to answer "let me read down the whole list of who is here."**

This is the practical form of constraint 0.2 applied to the roster. A directory that opens on row one and scrolls to row two hundred thousand is a tool for casual browsing of identities, and even with the legal name removed from every row, a browsable list of every handle, join date, and status is a map of the whole membership that should not be idly surveyable, and does not need to be for any legitimate purpose. So:

- The directory **opens on a search and filter surface, with a bounded recent window beneath it**, not on page one of an infinite list. The first thing the Owner sees is the total member count (her explicit ask, section 12), a search field, the filters, and the most recent arrivals; not the start of an endless scroll.
- Reaching a **specific** member is done by **searching her exact or prefix `@handle`**, the same locked people-search rule the public product uses (P2B section 11: "People search stays exact-and-prefix `@handle` only"). You find a member you already have a reason to find; you do not stumble onto her.
- Reaching a **set** of members is done by **filtering** (status, role, joined-in-range, activity bucket), which answers real operational questions ("who is currently suspended", "who joined this week", "who holds a staff role") without ever being an open-ended scroll of everyone.
- The **unfiltered, unsearched** list is capped at a recent window and ends in a calm card that says, in effect, "this is the newest arrivals; search or filter to find anyone else," rather than loading the entire membership on demand (section 4.3). This both performs at 200,000 rows and removes the affordance to browse the whole set.

This principle is not a limitation the Owner will resent; it is the difference between a tool she can trust herself with and one she cannot. It is stated here once and the controls below implement it.

## 3. List view: columns, default sort, and why

### 3.1 The row

Each member is a row, min height 64px, 12px vertical padding, sitting on `surface` with `border` hairline separators, the same calm paper as the feed and the moderation queue (P2 section 4.3, P2B section 2.2). The row is a link into that member's detail (section 6). Left to right:

1. **Avatar** at 40px (the compact-list size, P2 section 3.1), its no-photo state the standard `accent-subtle` fill with the handle's first letter in `accent`, so a photoless new member reads as intentional, not broken.
2. **`@handle`** at `text-label` `text-primary`, the forward identity, clickable. This is the only name in the row.
3. **Joined**, the join date, at `text-caption` `text-tertiary`, shown as an absolute date ("3 Oct 2026") rather than a relative time, because in a directory an exact arrival date is the useful fact and relative times ("4 months ago") get stale and imprecise in a list.
4. **Status**, an account-status chip (section 3.3).
5. **Role**, shown only when the member holds a staff role, as a neutral chip reading "Owner", "Admin", "Moderator", or "Reviewer"; ordinary members show nothing here, so the column is quiet for the overwhelming majority and a staff account stands out at a glance.
6. **Last active**, a coarse activity bucket (section 3.4), at `text-caption` `text-tertiary`.

On mobile the row collapses to avatar, `@handle`, and the status chip, with joined and last-active moving under the handle at `text-caption`; role stays as a chip when present. The columns never become a dense spreadsheet; this is the same calm-list density as the rest of the product.

### 3.2 Default sort, and why

**The default sort is newest join first (most recent arrivals at the top), descending by `created_at`.** The reasoning, because the brief asks for the reasoning on sort:

- It serves the owner's stated intent directly. She "likes to keep track of numbers" and is building for growth; the growing edge of the membership, who just arrived, is the most meaningful default view for someone watching a community form.
- It is the **lowest-surveillance** default. Sorting by join date is purely chronological arrival; it does not rank people by activity, by follower count, by how much they post, or by anything that profiles or compares individuals. An alphabetical-by-handle default, by contrast, is a "scroll to find a specific person" affordance, which is exactly the casual-browsing pattern section 2 designs against; and any activity-based default would be an engagement ranking of people, which section 15 refuses on principle.
- It degrades honestly at both ends of the scale. At two members it shows both, newest first, which reads correctly. At two hundred thousand it shows the most recent arrivals and sends everything else to search and filter, which is the right behaviour at scale (section 4).

The Owner can re-sort within the current filtered view by Joined (oldest first) or by Handle (A to Z) when she has a reason to, but these are chosen sorts, not the default, and sorting A to Z does not lift the recent-window cap (section 4.3): it reorders what is loaded, it does not turn the directory into a full alphabetical scroll of everyone. There is deliberately no "sort by most active" or "sort by most posts", because the directory does not rank people.

### 3.3 The status chip

The status chip maps exactly to the `account_status` enum (`active`, `restricted`, `suspended`, `banned`, `deactivated`, `deleted`) so the UI and the data never drift, and it carries its meaning in the word and a glyph, never in colour alone (P2 section 12.6), reusing the chip composition from P2B section 2.2 and section 16:

| Status | Chip label | Treatment |
|---|---|---|
| active | Active | neutral chip, `Circle` glyph in `success`; the calm default |
| restricted | Restricted until [date] | neutral chip, `Clock` glyph in `warning`, with the end date |
| suspended | Suspended until [date] | neutral chip, `PauseCircle` glyph in `warning`, with the end date |
| banned | Banned | neutral chip, `Prohibit` glyph in `danger` |
| deactivated | Deactivated | neutral chip, `MoonStars` glyph in `text-tertiary`; the member chose to step away |
| deleted | (not shown; see below) | n/a |

A single filled chip is never used in the directory; unlike the moderation queue, nothing here is urgent enough to earn `danger-fill`, so every chip is the neutral composition. The glyph colour is reinforcement, exempt from 1.4.11 on the same basis as the thread rail (P2 section 2.3), because the word carries the meaning.

**Deleted accounts are not shown in the directory at all, and are excluded from the member count** (section 12.2). A member who deleted her account asked to be gone; a browsable tombstone of her is the opposite of honouring that, and on this platform specifically, keeping a deleted woman visible in an admin list is a quiet betrayal of the reason she left. The schema keeps whatever it must keep for integrity; the directory does not surface it. **Deactivated** accounts (a reversible "I am stepping away") are shown, dimmed, so the Owner's count of who is present is honest, but they are clearly marked as away rather than active. **The system account (`is_system`) is excluded from the directory and from every count** (section 12.2); it is infrastructure, not a member.

### 3.4 Last active, handled with care (the schema reality and the privacy reality)

The brief lists "last active" as a column, and it is a reasonable operational signal (is this a live account or a dormant one), but it is also the single most dangerous column in a directory for this threat model, for two reasons that compound.

First, the schema reality: **there is no `last_active_at` on `profiles`.** The nearest signal, `last_login_at`, lives on `user_private`, the Owner-only private table. So a precise last-active time is not an ordinary account fact; it is private data, Owner-visible only, sitting next to the legal name and the IPs.

Second, the privacy reality: **a precise last-seen time is a surveillance signal.** "@maya was last active 11 minutes ago" is exactly the kind of fact a coerced or compromised account, or an over-curious one, could turn into a pattern of a specific woman's daily rhythm. It is the metadata a stalker would most want.

So the directory's "last active" column is a **coarse bucket, never a timestamp**, and the buckets are deliberately wide:

- **Active recently** (within the last 7 days)
- **This month** (8 to 30 days)
- **Earlier** (31 to 180 days)
- **Dormant** (over 180 days)
- **New, not yet active** (joined but no activity recorded)

A coarse bucket answers the only legitimate directory question, "is this a live account," and answers nothing a watcher could use. The precise `last_login_at` is never rendered in the list; it is part of the Owner-only identity panel (section 7), behind the step-up and the log, where reading it is a reasoned, recorded act like reading any other private fact. The bucket itself is derived server-side; the client receives only the bucket label, never the underlying time, so the precise value does not travel to the browser merely to render a row. This is a build note, not an owner decision, and it is the honest resolution of a column the brief asked for and the threat model complicates.

## 4. Search, filter, and pagination that stay usable at 2 and at 200,000

### 4.1 Search

One search field, at the top of the directory, labelled "Find a member by @handle". It is **exact-and-prefix handle search only**, the locked rule (P2B section 11). Typing `may` matches `@maya` and `@maybelle`; it does not do fuzzy or substring matching, and it never searches legal names, emails, or bios, because searching those would be a deanonymisation path and legal name is not in this surface's reach at all. Results render as the same rows as the list (section 3.1). The field is a standard `Input` from the kit (`border-strong` outline, measured 3.47 light / 3.52 dark), with a leading `MagnifyingGlass` glyph and a clear affordance. Search is debounced and the query is reflected in the URL so a view can be returned to on refresh.

This single decision is most of what makes the directory safe at scale: at 200,000 members the way you reach a person is to know her handle, which means you reach the people you have a reason to reach and cannot trawl the rest.

### 4.2 Filters

Above the list, a filter bar built entirely from the existing segmented-control and pill patterns (P2 section 3.6, P2B section 2.3), nothing novel:

- **Status:** a multi-select pill row (Active, Restricted, Suspended, Banned, Deactivated). Default is all-present statuses selected except Banned and Deactivated, so the default view is "people who are here and in good standing", and seeing banned or departed accounts is a deliberate selection.
- **Role:** a pill row (Staff only, or a specific role). "Staff only" answers "who has powers," which is a real governance question the Owner should be able to ask in one tap, and it pairs with the roles manager at `/owner/roles`.
- **Joined:** a date-range control (This week, This month, Custom range). This is how growth questions get answered at the individual level ("who are the 40 people who joined this week") without a scroll.
- **Activity:** a pill row of the coarse buckets from section 3.4 (Active recently, This month, Earlier, Dormant, New). This answers "how many accounts are dormant" without ever exposing a per-person timestamp.

Filters compose, and the active filter set is reflected in the URL so a scoped view ("all suspended accounts", "staff only") can be shared by link with a future co-admin or simply survive a refresh. The count of the current filtered result is shown above the list in `text-secondary` as plain information ("312 members match"), subject to the small-N suppression rule (section 16) where a filter is narrow enough to single someone out.

### 4.3 Pagination, and the recent-window cap

Pagination is **keyset (cursor) based on `(created_at, user_id)`**, not offset based, so performance is constant whether you are at the first page or deep in the set; offset pagination degrades badly at 200,000 rows and, worse, invites paging arbitrarily deep through everyone, which is the browsing pattern section 2 refuses. Loading more is a "Load more" affordance (or infinite scroll with a sentinel), never a page-number strip.

But cursor pagination alone still permits scrolling the whole set, so the directory adds the **recent-window cap**: in the **unfiltered, unsearched** default view, the directory loads the most recent arrivals up to a bounded window (a few hundred rows) and then, instead of loading more, closes with a calm end-of-list card: "This is the most recent [N] members. To find anyone else, search their @handle or add a filter above." The cap is lifted the moment a filter or a search is applied, because at that point the Owner has expressed a specific, bounded intent ("suspended accounts", "joined this week", "@maya"), and loading that bounded set fully is exactly right. The cap exists only on the open-ended, no-intent view, which is the only view that would otherwise be an invitation to trawl.

This is the pattern that makes the directory honest at both scales at once: at two members, the recent window trivially holds everyone and the end-of-list card reads as "that is everyone, for now"; at two hundred thousand, the recent window holds the growing edge and the card points to search and filter for the rest. One behaviour, correct at both ends.

## 5. The directory's states (empty, loading, error, too many results)

These follow P2 sections 9 and 11, the same empty-and-error grammar as the rest of the product: skeletons for loading, warm and honest copy for emptiness, calm and actionable copy for errors, never a bare spinner where emptiness is the real state.

- **Loading.** The list loads with **skeleton rows** (avatar circle, two text lines) using `--skeleton-base` and the slow sheen, respecting reduced motion (P2 section 11.1). The count at the top shows a skeleton pill, not a flash of zero.
- **Empty (no members yet).** This should essentially never happen once the owner's own account exists, but if a filter view is genuinely empty it is handled below; a truly memberless platform shows the founding-posture copy from P2 section 9.6, framed for the Owner: "No members yet. You are the first." It is an invitation, not an error.
- **Empty filter result.** A filter that matches nobody ("No members are currently suspended") shows a calm one-line statement, never a bare "0 results" and never an error. An empty "suspended" filter is a good state, so it reads as one: "No one is suspended right now."
- **Error.** A directory that could not load uses the full-surface error layout (P2 section 11.3): a calm headline, "Something went wrong loading the directory", and a Retry button. No codes, no stack traces, never blame.
- **Too many results.** When a search or filter would return more rows than a sane working window (the same bounded window as section 4.3), the directory does **not** stream all of them; it shows the first window and a clear `text-secondary` note: "Showing the first [N] of [count] matches. Narrow your search or add a filter to see fewer." This is the explicit "too many results" state the brief asks for, and it is also a safety behaviour: it refuses to render a trawlable wall of the whole membership even under a broad filter, and nudges the Owner toward the specific question she actually has. The suppression rule (section 16) governs the opposite extreme, a result small enough to identify an individual.

## 6. Member detail: the glance view (what the Owner, and a looking-up Admin, see without a step-up)

Selecting a member row (Owner), or looking up a member by exact handle (Admin, section 6.2), opens that member's detail: a right pane on desktop, a pushed full screen on mobile, the same push pattern as the moderation case detail (P2B section 3). This is the account-accounting surface. It shows everything needed to understand an account's standing and conduct, and **nothing that identifies the person behind it.** Identity is a separate panel, behind the step-up (section 7).

### 6.1 Anatomy of the glance view

Top to bottom:

1. **Header.** Avatar at 96px (mobile) or 128px (desktop), the `@handle` at `text-heading`, the account-status chip (section 3.3) with its end date if time-boxed, the role chip if staff, and the founding-member pill if set. **No legal name anywhere in this header**, the same rule as the moderation case header (P2B section 3.1).
2. **Standing strip.** A compact row of the account's shape: join date (absolute), coarse activity bucket, post count, follower and following counts. These are the same counts a member's own public profile shows (P2 section 7), so nothing here is more than the Owner could see by visiting the profile; it is gathered in one place for accounting. The follower and following counts are counts, not lists: the detail view does not expose who follows whom, because a browsable social graph is a person-finding tool and the threat model forbids it (the same reasoning P2B section 11 uses to refuse "people you may know").
3. **Enforcement standing.** The account's current standing and its de-identified enforcement history, drawn from the moderation layer that already exists (section 8). This is the single most decision-relevant thing about an account and it belongs here, keyed to the handle, actor shown by role.
4. **A link into moderation**, not a duplicate of it (section 8).
5. **The identity panel, collapsed and gated** (section 7). It is the last thing on the surface, visually set apart, and it is closed. Opening it is the deliberate act.

### 6.2 The Admin lookup, narrower than the Owner's view

An Admin does not get the browsable roster (section 0.4). What an Admin gets is a **lookup**: from the moderation console (where she already works), she can resolve an exact `@handle` to that one member's glance view, so that when she is weighing a report or an appeal she can see the account's standing without the Owner having to hand it to her. The Admin's glance view is the same as the Owner's glance view with two subtractions: there is **no identity panel** (section 7 is Owner-only and absent, not locked, for an Admin, exactly as the ban control is absent rather than disabled for a Moderator in P2B section 1), and there is no path from the lookup into a browsable list. An Admin reaches one account she has a reason to reach, by its handle, and sees its conduct and standing; she cannot survey the membership and she cannot see who anyone really is. A Moderator gets neither the roster nor the lookup; she works entirely from the case queue (P2B), which already shows her the accused's de-identified context.

## 7. The identity line, and the AAL2 step-up (where the browsable surface ends and the identity surface begins)

This is the hinge of Part 1, and the brief asks for the line to be drawn explicitly. Here it is, stated as plainly as it can be:

**On one side of the line, at a glance, keyed to the `@handle`, no step-up: everything about the account's conduct and standing.** The handle, the join date, the status and its history, the role, the coarse activity bucket, the post and follower and following counts, the de-identified enforcement history, the link into moderation. This is what the directory and the glance view show, and it is enough to account for any member and to run the platform.

**On the other side of the line, behind the AAL2 step-up, a stated reason, and an audit-log entry, Owner-only: everything that identifies or locates the real person.** The verified legal name, the email, the phone if ever verified, the signup and last-login IP, the precise last-login time, and the device-signal information (as categories and counts, never raw hashes, the same de-identified treatment the ban surface uses in P2B section 6). This is the identity panel, and reaching it is the event.

The test for which side a fact sits on is simple and is stated in the doc as the rule: **does the fact describe what the account did, or who the person is? Conduct is at a glance; identity is behind the step-up.** "This account has been suspended twice" is conduct. "This account belongs to Jane Doe at this email in this city" is identity. The first runs the platform; the second is only ever needed for a lawful disclosure or a safety escalation, and it is treated accordingly.

### 7.1 How the step-up is presented, so it feels like a deliberate act

The identity panel at the foot of the glance view (section 6.1) is **closed by default and visually unlike anything else on the surface**, so the Owner cannot slide into it by reflex. It is a single card with a `Lock` glyph, a `text-heading` label "Identity and contact details", and a one-line explanation in `text-secondary`: "Seeing this member's legal name and contact details is a separate, recorded step. Open it only when you have a reason." Below that, a single control, "Reveal identity details", which is **not** a toggle and **not** styled like the other expanders on the page; it is a bordered, deliberate button.

Activating it runs the step-up, reusing the exact AAL2 pattern the owner pages already use (`/owner/roles` and `/owner/audit` check `supabase.auth.mfa.getAuthenticatorAssuranceLevel()` and show an `Alert tone="warning"` with a link to `/settings/security` when the current level is not `aal2`):

1. **If the Owner is not at AAL2**, the panel shows the warning Alert: "Seeing identity details requires your security key or authenticator." with the step-up link. There is no way to see the details without clearing this; the gate is the database row-level security on `user_private`, not merely this UI, so a skipped UI check cannot leak the data (the same defence-in-depth the roles page relies on).
2. **A stated reason is required before the reveal.** A short, mandatory text field, "Why are you accessing this? (recorded in the audit log)", with examples in the placeholder ("responding to a law-enforcement request", "verifying an NCMEC escalation", "member asked me to confirm her account"). The reveal button stays disabled until a reason is entered. This is the deliberate-act friction: you cannot see who someone is without saying, on the record, why.
3. **The reveal is written to the hash-chained `audit_log`** before the data is shown, with the actor (Owner), the target `@handle`, the stated reason, and the time, as a privileged-read event. This reuses the existing `append_audit` path that every privileged action already uses; identity access is logged exactly as role grants and enforcement actions are. The audit-log viewer (`/owner/audit`, already built) will show these reads as entries, so the Owner's own accesses are as accountable as everything else, and the hash chain makes the record tamper-evident even against the Owner (P2B section 8.2).
4. **Once revealed, the panel shows the identity data plainly and quietly**, on a `surface-raised` card, with a clear "Hide again" control and an automatic re-collapse when the Owner leaves the member detail, so the data is not left sitting open on screen. The device information is shown as categories and counts ("3 device signatures on record"), never raw hashes, matching P2B section 6.

### 7.2 Why the reason and the log are not theatre

It would be easy to treat the reason field and the audit entry as friction for its own sake. They are not. On a solely-owned platform there is no one above the Owner to approve her access, so the only available discipline is the record: a tamper-evident log of every time the Owner looked at a real identity, with the reason she gave. If the Owner is ever compelled, by a court, by an abuser who has gained access, by her own worst day, the log is what makes the access visible after the fact, and the stated-reason field is what makes casual access feel like what it is, a serious act. This is the same honesty P2B applies to the owner-conflict limitation: the product cannot prevent an authorized owner from looking, but it can ensure she never looks invisibly, and that is worth building.

## 8. How this connects to the moderation console, without duplicating the case queue

A member's detail needs to show her standing, her enforcement history, and her reports, and it must do so **by linking into the moderation console, never by rebuilding it.** The console (P2B) is the single source of truth for cases, enforcement, and appeals; the directory is a lens onto an account, not a second queue.

- **Current standing** is read from the same data the member-facing status reads (`my_account_status` and the account's `account_status`), rendered as the status chip and, where a restriction or suspension is in force, its end date. This is a read, shared with the console, not a reimplementation.
- **Enforcement history** is the de-identified action trail the console already produces for an account (the `mod_enforcement_history` / account-context reads in P2B section 8.1): "Warned, 3 Oct, rule harassment. Suspended 7 days, 10 Oct, rule hate." Actor shown by role, keyed to the handle, no legal name. It appears in the glance view's enforcement-standing section (section 6.1) because a pattern is the most decision-relevant fact about an account, and the guidelines say pattern matters.
- **Reports and cases involving the member** are reached by a single link, "View in moderation", which opens the moderation console filtered to that accused, reusing the existing case route (`/mod/case/[key]` keyed by the accused's id, P2B). The directory does **not** render reports, reporter identities, or the case queue itself; it hands off to the surface built to show them, with the reporter-protection and routing rules that surface already enforces (P2B sections 2.5 and 3.3). This keeps reporter confidentiality and routing logic in exactly one place and means the directory can never accidentally leak a reporter or an owner-named report.
- **The direction of the link is one-way by design:** the directory links into moderation, moderation does not link back into a browsable directory, because the console's whole posture is that staff see one accused at a time, not a roster (P2B section 0.1). An Admin in a case who needs the accused's standing uses the lookup (section 6.2), which resolves one handle, not the roster.

## 9. Bulk actions: the argument against, and the one deliberate bulk read

### 9.1 The argument against any destructive bulk action, made explicitly

The brief asks for an argument for or against bulk actions, and the argument is against, decisively, for this surface.

A member directory is the single most dangerous place in the product to put a bulk action, because its ergonomics are the ergonomics of the database-deletion incident: a grid of rows, a select-all, one button, a reflex. Every reason the irreversibility rule exists (P2B section 0.2) points at forbidding batch enforcement here. Enforcement is destructive or semi-destructive by nature (suspend, ban, remove), it is exactly the thing a reflex must never trigger at scale, and it already has a correct home: the moderation console, where each action is taken against one named account, with that account's context in front of the acting person, with the per-action confirmation gradient, and with the typed `@handle` gate on the one unrecoverable action (P2B sections 4 and 5). Moving any of that into a directory multi-select would strip away the context and the per-account friction that make it safe, and would recreate the precise conditions of the incident. P2B already limited bulk action in the console to two non-destructive operations (dismiss and claim) for this reason; the directory goes further and has **no account-changing action at all, bulk or single.** The directory is for seeing and accounting; acting happens in the console, one named person at a time.

So: **no bulk suspend, no bulk ban, no bulk restrict, no bulk remove, no bulk role change, no bulk message, no bulk anything that changes an account.** The directory's rows are links to understanding, not checkboxes for action. There is no select-all. This is a feature.

### 9.2 Export: the one bulk operation, treated as a deliberate logged read

There is one legitimate bulk operation a founder genuinely needs as she grows: exporting the roster or a filtered slice of it (for a backup, for a board update, for a lawful request). Export is a **read**, not a destructive action, but on this surface a bulk read of member data is itself sensitive, so it is treated with deliberate friction and a record, not hidden and not casual:

- Export is **Owner-only**, reached from the directory as a single "Export this view" action that exports exactly the current filtered view (so the Owner exports the slice she is looking at, not silently the whole membership).
- The export contains **only the glance-level, non-identity columns** by default: `@handle`, join date, status, role, activity bucket, counts. **It does not contain legal names, emails, phones, or IPs.** An export that included identity would be a bulk deanonymisation file, the worst possible artifact to have sitting in a downloads folder or an email; identity is never in a bulk export. If a lawful request genuinely requires identity for specific named accounts, that is the per-account, reason-stated, logged identity panel (section 7), one account at a time, not an export.
- The export is **logged to the audit log** as a privileged bulk read, with the filter that produced it and the row count, so a mass read of member data is as accountable as an identity reveal.
- The export action uses the ordinary distinct-verb confirmation (a left-aligned ghost "Cancel", a right-aligned filled "Export [N] members"), because while it is not destructive, it is a bulk read the Owner should confirm she means; it does not need the typed gate, which is reserved for the one unrecoverable action in the product (P2B section 5).

This gives the Owner the "keep track of numbers" capability she will eventually want in a spreadsheet, without ever turning the directory into a leak of who her members are.

---

# PART 2. THE METRICS FOUNDATION

This is the "much much bigger" part, and it is designed as a system, not a page. The owner asked for a total member count; she described a building. The deliverable is the building's structural grammar: a single repeatable unit from which every metric, the first and the fiftieth, is assembled, so that growth is a matter of declaring metrics, not designing screens.

## 10. The repeatable unit: the metric descriptor and the metric card

### 10.1 The idea, stated once

**A metric is declared as data, and rendered by one component.** There is exactly one visual unit, the **metric card**, and exactly one way to add a metric, by adding a **metric descriptor** to a registry. The card knows how to render any descriptor; the descriptor knows what the metric is. Adding the twentieth metric is writing a twentieth descriptor; it is never designing a twentieth card. This is the whole answer to "build with intent to create something much much bigger": the bigness is additive data, not additive design.

### 10.2 The metric descriptor (what a metric is, as a declaration)

A descriptor is a plain declaration with these fields. It is specified here as a shape, not as code; the build expresses it in whatever the codebase uses.

- **id** and **label**: a stable identifier and the human name shown on the card ("Total members").
- **group**: which dashboard section it belongs to (Membership, Content, Safety, Growth; section 18). Grouping is how the dashboard stays legible at 50 metrics.
- **value source**: the aggregate the card displays, described in plain terms (a count, a count over a time window, a ratio). In the build this resolves to a read; this document does not write the read, but every day-one metric resolves to a `COUNT` or a `COUNT ... GROUP BY` over `created_at` on tables that already exist (section 12), so no new data model is needed for the first six.
- **unit and format**: how the value reads (a plain integer, a percentage, a duration, a count with a noun: "members", "posts").
- **time-range support**: whether the metric responds to the global range control (Today / 7d / 30d / All time; section 14), and what "all time" means for it.
- **comparison**: whether and how it shows change versus the previous equal period, and the rule for when a percentage is allowed versus an absolute delta only (section 14).
- **drill-in**: what tapping the card opens, if anything, a time series, a breakdown, or a link into another surface (never a list of individuals below the suppression floor; section 16).
- **min-N / suppression**: the floor below which this metric, when segmented or filtered, is suppressed rather than shown (section 16). Top-line non-segmented totals declare themselves exempt.
- **states**: the descriptor does not define states; the card defines them once, for all metrics (section 11). A new metric inherits every state for free.

Because states, layout, accessibility, and motion live in the card and the dashboard, and only the per-metric facts live in the descriptor, a new metric cannot be visually inconsistent, cannot forget its loading state, cannot forget its suppression rule, and cannot invent a new color. The system makes good metrics the default and makes a one-off impossible. That is the design goal.

## 11. The metric card: anatomy and its complete set of states

The card is a `surface-raised` card, `radius-lg`, `shadow-e1`, the same card chrome as the rest of the product. One card, every state defined here once so every metric has them.

### 11.1 Anatomy (the value state)

Top to bottom, inside the card:

1. **Label** at `text-label` `text-secondary`: what the metric is ("Total members").
2. **Value** at `text-display` (the large, confident number) `text-primary`, with its unit at `text-body` `text-secondary` beside or beneath it ("1,284 members"). The value is the hero of the card.
3. **Comparison line** at `text-caption`, when the descriptor supports it and the data allows it: the change versus the previous period, as a signed value with a direction glyph (`ArrowUp` / `ArrowDown` / `Minus`) and, only above the base threshold, a percentage (section 14). The glyph and the sign carry the direction; colour (`success` for a healthy direction, `text-tertiary` for flat, `warning` only where a rise is genuinely a concern like a spike in reports) is reinforcement, never the sole signal (P2 section 12.6). Direction is never assumed to be good or bad by default: more members is good, more open reports is not, and the descriptor says which, so the card never implies that "up" is universally positive.
4. **Sparkline or micro-context** at the foot, optional per descriptor: a small time series for metrics that have one, drawn in `accent` with its data points marked, never a bare colored line (section 19). At tiny N it shows dots, not a confident curve (section 13).
5. **Drill-in affordance**: the whole card is a link when the descriptor declares a drill-in, with a `CaretRight` at the top-right corner and a clear `aria-label`; cards without a drill-in are not links and do not pretend to be.

### 11.2 The complete state set (defined once, inherited by every metric)

- **Loading.** A skeleton card: a skeleton label line and a skeleton value block, using `--skeleton-base` and the slow sheen, reduced-motion respected (P2 section 11.1). Never a spinner in the value slot; a number is coming, and its shape is known.
- **Value.** The anatomy above.
- **Zero.** A real, honest zero is shown as "0" with its unit, calm, with a one-line `text-tertiary` context when the zero deserves framing ("No reports filed. That is a good sign."). A zero is a correct value, not an error and not an empty state; it is never hidden and never dressed up.
- **Not enough data yet.** Distinct from zero. When a metric needs history it does not have (a trend with fewer than two periods, a comparison with no prior period), the card shows the current value plainly and replaces the comparison line with a quiet `text-tertiary` note, "Not enough history yet to show a trend", rather than drawing a fake trend from one point. This is the honest-at-small-N behaviour (section 13) built into the card so every metric gets it.
- **Suppressed (small N).** When a segmented or filtered value falls below the suppression floor (section 16), the card shows the floor label ("Fewer than 5") or a dash, with a `text-tertiary` note, "Hidden to protect individuals", never the exact small number. This is defined on the card so no metric can forget it.
- **Error.** A card that could not load its value shows a calm inline error in the card's own footprint, "Could not load this metric. Retry.", with a retry affordance, following P2 section 11.3. One card failing never breaks the dashboard; the others render.

Defining all six states on the card, once, is the mechanism that lets a new metric be added by declaration without a redesign: the card already knows how to be empty, zero, insufficient, suppressed, loading, and broken, so the descriptor only supplies the number.

## 12. Day-one metrics

Seven metrics ship on day one: the owner's explicit ask plus the ones that make a social platform's health legible. Each is a descriptor (section 10.2); each resolves to a count or a grouped count over `created_at` on an existing table, so day one needs no new data model.

### 12.1 Total members (the explicit ask)

- **Value:** the current count of real member accounts.
- **Definition, stated precisely because it matters:** total members counts `profiles` rows, **excluding the system account (`is_system`)**, **excluding deleted accounts** (a deleted member asked to be gone; counting her inflates the number and dishonours the request), and **excluding banned accounts from the headline** while keeping them available as a breakdown. Deactivated accounts (a reversible step-away) are counted but shown as a sub-figure, so the headline is "members who are here" and the breakdown is honest about who is restricted, suspended, banned, or away. This precise definition is written on the drill-in so the number never silently changes meaning.
- **Drill-in:** a breakdown by status (active, restricted, suspended, banned, deactivated), each a count, subject to suppression (section 16). This is where "see every member" meets "see the total": the number is the headline, the breakdown is the shape, and the directory (Part 1) is where an individual is reached.
- **Comparison:** net change over the selected range ("+12 this week"), absolute at small N, percentage only above the base threshold (section 14).

### 12.2 Signups over time

- **Value:** new member accounts created in the selected range, with a sparkline of daily or weekly signups.
- **Source:** count of `profiles.created_at` in range, excluding the system account.
- **Drill-in:** the signup time series at the dashboard's current granularity. This is the growth curve the owner is building to watch, and it is honest at small N (section 13): two signups is two dots, not a hockey stick.

### 12.3 Active members

This is the metric that must be designed against becoming a vanity metric, because the brief asks for "active members" and section 15 refuses "daily active users." The distinction is real and is the design:

- **Value:** the count of members who took an authentic action (posted, replied, followed, or logged in) within the selected range, shown as a count and as a share of total members.
- **Definition and the position:** "active members" here is a **coarse liveness check reported over a wide window (30 days by default), not a daily-tracked engagement dial.** The difference between this and DAU is cadence and intent: DAU is a number you check every morning and try to make go up, which is the metric that shapes a founder toward building for compulsion; "active members this month" is a health reading you glance at to know the community is alive. The card deliberately defaults to the 30-day window and does not offer a "today" view of active members, precisely so it cannot quietly become a daily-engagement obsession. It is never shown per-member (who is active is not a list; section 15), only as an aggregate.
- **Source:** distinct authors of posts plus distinct actors of follows in range, unioned with logins in range (the login signal from `user_private.last_login_at`, read in aggregate only, never per-person on this surface).

### 12.4 Posts

- **Value:** posts created in the selected range (a content-liveness signal), with a sparkline.
- **Source:** count of `posts.created_at` in range, counting member-visible posts (`visible`), so the number reflects real content, not moderation-removed or author-deleted items.
- **Drill-in:** the posts time series. Not a list of posts and never a per-author ranking (section 15).

### 12.5 Reports filed, and 12.6 Reports resolved

Two cards, together the safety-operations health of the platform:

- **Reports filed:** count of `reports.created_at` in range. This is a workload and a safety-signal reading. Its comparison direction is **not** assumed good when down or bad when up; a spike is worth noticing (it may be a brigade, section P2B 2.1) and a flat zero at tiny scale is expected, so the card frames it neutrally.
- **Reports resolved:** count of reports that reached `actioned` or `dismissed` in range, plus the **resolution rate** (resolved as a share of filed) and, as the operational-health metric that actually matters on a safety platform, **median time to resolution**. These replace the engagement metrics section 15 refuses: the question a safety-first founder should be asking is not "how long are people on the site" but "how fast do we protect them when they ask," and this card answers that.

### 12.7 Enforcement actions taken

- **Value:** count of `moderation_actions.created_at` in range, with a breakdown by action type (warn, remove, restrict, suspend, ban).
- **Source:** the `moderation_actions` enforcement history that P2B already writes.
- **Drill-in:** the breakdown by action, subject to suppression (at tiny N, "1 ban" can identify a person, so the breakdown suppresses below the floor; section 16). This closes the loop with the audit log and the moderation console: the dashboard shows the shape of enforcement, the console shows the cases, the audit log is the tamper-evident record.

## 13. Behaving honestly at a tiny network, without looking broken

With two members, a naive dashboard is a wall of zeros and flat lines that reads as a dead product, and the owner specifically flagged this as a real problem, not a detail. The design treats small numbers as a first-class state, not a degenerate one.

- **Zeros are framed, not hidden.** A zero is shown as a real number with context (section 11.2): "0 reports filed. That is a good sign," "No one is suspended right now." The dashboard at N=2 is not blank and not alarming; it is a small, honest, calm picture of a small, healthy, new community. Honesty about being new is more trustworthy than inflation, and this is a founder's own dashboard, so there is no one to impress and every reason to be accurate.
- **No fake trends from tiny samples.** A sparkline with two points shows two dots, not a line implying a trajectory; a comparison with no prior period shows "Not enough history yet", not "+0%" or "0%". The card's "not enough data yet" state (section 11.2) is exactly this, and it is why that state exists as a distinct thing from zero.
- **Absolute deltas, not percentages, at small N.** "2 to 3 members, +1 this week" is honest; "members up 50% this week" from a base of two is technically true and deeply misleading, and on a founder's own dashboard it trains bad intuition. The base threshold (section 14) governs this: below it, the card shows the raw change and withholds the percentage.
- **The dashboard says it is early, once, warmly.** A single dismissible line at the top of Insights, in the founding-posture voice the product already uses (P2 section 9.6): "Hersciety is new. These numbers are small because the community is young, and that is exactly where you should be." It is shown while the network is genuinely tiny and removes itself as the numbers grow. This reframes smallness as earliness, the same move the empty states already make, so the first time the owner opens her dashboard she sees a beginning, not a void.
- **No invented liveliness.** The dashboard never pads a number, never shows a placeholder metric, never fabricates a data point to make a chart look populated. A founder can tell the difference between "early and real" and "fake," and the trust the whole platform runs on starts with the owner trusting her own numbers.

## 14. Time ranges and comparison, without false precision

- **The global range control** sits at the top of Insights: a segmented control (P2 section 3.6) with **Today / 7 days / 30 days / All time**. It sets the range for every card that supports a range (its descriptor says so; section 10.2). 30 days is the default, because it is the window that reads honestly at small scale and avoids the daily-obsession cadence section 15 warns against. A card whose descriptor declares a fixed window (like Active members, which is deliberately 30-day, section 12.3) shows its own window and ignores the global control, with a small caption saying so, so the range a number covers is never ambiguous.
- **Comparison is versus the previous equal period:** 7 days compares to the 7 days before; 30 days to the 30 before. The comparison line shows a signed absolute change always, and a percentage **only when the comparison base is at or above a threshold** (recommend a base of 20) below which a percentage is misleading. Below the threshold, the card shows "+1" and withholds the percent. This single rule is what keeps the dashboard from ever telling the owner a dramatic percentage story about three people.
- **"All time" shows no comparison**, because there is no prior all-time to compare to; the card shows the cumulative value and a full-history sparkline where it has one.
- **Granularity follows range**: Today is hourly where it has the data, 7 and 30 days are daily, All time is weekly or monthly, so a sparkline never tries to draw 200,000 daily points or two hourly ones. The card picks a sane granularity for the range and labels it.

## 15. The metrics I will deliberately not build, and why (the position)

The brief asks for a position, and this is the position, stated as a refusal list so a future build cannot quietly add one of these back "for growth." Vanity and engagement-maximising metrics shape a founder's behaviour, and on a safety-first platform the wrong dial is not neutral; it bends the product toward being addictive rather than good.

- **Time on site, session length, time in app.** Refused. This is the definitional engagement-maximising metric: the only way to make it go up is to make the product harder to put down, which is the opposite of what a safe space should want. A woman using Hersciety to feel safe and then close the app is a success, and a metric that reads that as a failure would push every future decision the wrong way.
- **DAU, MAU, and the DAU/MAU "stickiness" ratio.** Refused as primary dials. These are the metrics whose entire purpose is to be maximised, and maximising them means engineering compulsion, notifications-to-pull-people-back, streaks, variable rewards. The honest liveness this product needs is served by "active members this month" (section 12.3) as a wide-window health reading, deliberately not a daily cadence and deliberately not a growth target.
- **Streaks, daily-return mechanics, and any "come back" metric.** Refused. They are the machinery of compulsion loops and have no place on a platform for people under stress.
- **Per-member engagement rankings, "power users", "most active", "top posters", most-followed leaderboards.** Refused on two grounds at once: they are engagement-maximising (they reward and encourage the loudest use), and they are individual-surveilling (they are a ranked list of named people by behaviour, exactly the person-profiling the threat model forbids). The dashboard measures the community in aggregate; it does not rank the women in it.
- **"Who is online now", precise last-seen per member, real-time presence.** Refused. This is the single most dangerous metric for the threat model, a live map of specific women's activity, and it appears nowhere, not on the dashboard, not in the directory (where last-active is a coarse bucket, section 3.4), not anywhere.
- **Virality and growth-loop metrics (K-factor, invites sent, referral coefficients).** Refused for now. The platform is not invite-based (registration is open), and chasing a virality coefficient is chasing growth for its own sake; the owner can watch signups (section 12.2) without a dial designed to be gamed.

**What I build instead, and why it is better for this product:** safety and health operations. Reports filed and resolved, resolution rate, median time to resolution (section 12.5, 12.6), enforcement actions (section 12.7), and later appeals volume and backlog (section 17). These answer the questions a safety-first founder should actually be asking, how quickly do we protect people, is enforcement proportionate, is the backlog under control, rather than how long can we hold attention. The refusal list is not caution for its own sake; it is choosing the dials that make the product better over the dials that make the number bigger. This is a values call and the owner owns it (section 22), but the recommendation is firm.

## 16. Aggregates must not leak individuals: the small-N suppression rule

At a tiny network, and even at a large one under a narrow filter, a count can identify a specific person. "1 member is suspended" plus the knowledge of who recently went quiet is a deanonymisation; "banned members: 1" names a person implicitly. So the metrics system has a suppression rule, stated once and enforced by the card (section 11.2) and the directory (section 5) alike.

- **The rule:** any **segmented, filtered, or broken-down** aggregate whose result is below the floor **k** is suppressed. It is shown as "Fewer than k" or a dash, with the note "Hidden to protect individuals", never as the exact small number. **Recommended k = 5.**
- **Top-line, non-segmented totals are exempt**, because a count of the whole membership (total members = 2) does not single out any individual; it is the breakdowns and cross-tabs that do. "Total members: 2" is fine; "members in [narrow segment]: 1" is suppressed.
- **Drill-ins obey the floor:** a metric card's drill-in may show a breakdown or a time series, but it may **never** drill from an aggregate into a list of the specific individuals who make it up when that list is below the floor, and in fact the metrics surface never drills into a list of individuals at all. The path from "a number" to "a person" is the directory and the identity panel (Part 1), with their own gating and logging; the dashboard is aggregates only, by construction. This keeps the two jobs separate: Insights tells you the shape, the directory lets you reach a person you have a reason to reach, and there is no sneaky path from the first to the second that bypasses the directory's rules.
- **At today's N=2, this means almost every breakdown is suppressed**, and that is correct and honest: with two members, the shape of the community is "two members", and any finer cut would identify them. The dashboard says so plainly ("Breakdowns are hidden while the community is small, to protect individuals") rather than showing cuts of two people. As the network grows past the floor, breakdowns unlock naturally. This is one of the two things worth telling the owner she will see on day one (section 22), so it is not a surprise that her breakdowns are hidden at two members.

k is a single tunable number in one place; raising or lowering it is a configuration change, not a redesign, consistent with the whole system's posture.

## 17. The growth path: what this becomes at 10 metrics and at 50

The brief asks for a sketch that proves the layout survives growth. It does, because growth is adding descriptors and sections, never redesigning the card or the page.

**At 10 metrics.** The dashboard is a responsive grid of metric cards (section 18): one column on mobile, two at md, three at lg. Ten cards are two or three tidy rows. The new metrics beyond the day-one seven are declared, not designed: appeals filed and resolved (closing the P2B appeals loop), follows created (network-formation health), and the median-time-to-resolution card promoted to prominence. Cards that have a time series gain a sparkline; cards with a breakdown gain a drill-in; nothing about the page changes. Charts arrive as drill-ins (a card expands to a full time series on tap), not as a separate charting surface, so the grid stays the home and detail is one level down.

**At 50 metrics.** The dashboard becomes a **sectioned** grid: the `group` field on every descriptor (section 10.2) sorts cards into labelled sections, Membership, Content, Safety and operations, Growth, each a titled band of cards, collapsible, in a deliberate order (safety and operations high, because this is a safety product). Fifty cards across four sections is legible where fifty cards in one undifferentiated grid would not be, and the sectioning is free because the grouping already lives in the data. At this scale the system also gains, all as additions to the existing grammar, not redesigns:

- **A metric catalog / search**, so the owner can jump to a metric by name when there are fifty, the same search-first discipline the directory uses.
- **Saved views**, a named set of range-plus-section selections, so "my Monday safety view" is one click; this is URL state (sections 4.2, 14) promoted to a saved name.
- **Segments**, a filter applied across a section's cards (for example, the founding cohort versus everyone), always subject to the suppression floor (section 16), so a segment can never become a deanonymisation.
- **Exports**, the same deliberate, logged, identity-free bulk read the directory defines (section 9.2), extended to a metric or a section's underlying aggregates (aggregates, never individuals).
- **Scheduled summaries**, a weekly digest of the top-line numbers emailed to the owner, honest at small N (it says "early days" while the network is tiny, section 13) and aggregates-only (it can never contain an individual's data, by the same rule as export). Whether this digest should exist, and to what address, is a real future question but not a day-one one; it is noted, not built.

The proof the layout survives is structural: at every scale the atomic unit is the same card, the page is the same responsive grid, and the only things that change are how many descriptors exist and whether they are grouped into sections. There is no point on the growth path where the owner's dashboard needs to be redesigned, which is exactly what "build with intent to create something much much bigger" asked for.

## 18. The dashboard layout and information architecture

- **Insights** opens with: the founding-posture line while the network is tiny (section 13), the global range control (section 14), and then the grid of metric cards. **Total members is the first card, top-left**, because it is the owner's explicit ask and the number she most wants; the rest follow in a deliberate order (membership, then growth, then content, then safety and operations) that becomes the section order once sectioning arrives (section 17).
- **The grid** is one column on mobile, two at md (768px), three at lg (1024px) and up, with 16px gaps on the base-4 rhythm (P2 section 1.5). Cards are equal-width and flow; the grid never becomes a fixed dashboard of pinned tiles that breaks when a metric is added, it simply reflows, which is why adding a metric never disturbs the layout.
- **The whole surface is read-only.** Insights shows numbers; it changes nothing. There are no actions on this surface except drill-ins (reads) and, later, export and saved-view management (section 17). A metrics surface that could change account state would reintroduce exactly the bulk-action danger section 9 removed; it cannot, because it has no account-changing affordances at all.
- **It is Owner-only**, gated the same way the other owner pages are (redirect a non-owner, never render; section 0.4). Metrics are not behind AAL2 the way the identity panel is, because aggregates with the suppression floor do not expose individuals; the step-up is reserved for the one thing that identifies a person (section 7), so it stays meaningful and the owner is not trained to step up for routine numbers.

---

## 19. Accessibility notes specific to Phase 2D

Everything in the Phase 2 accessibility specification (P2 section 12) is inherited unchanged: 44x44 minimum targets, visible 2px `focus-ring` with 2px offset, full keyboard operation, focus-trapped and Escape-dismissable modals that restore focus to their trigger, reduced-motion fallbacks, and colour independence. The additions specific to the surfaces in this document, several of which the brief calls out directly:

- **The directory and any tabular metric breakdown are real data tables with real semantics.** Where the directory renders as a table (desktop), it uses a true `<table>` with a `<thead>`, `<th scope="col">` on every column header (Handle, Joined, Status, Role, Last active), and row association, exactly as the already-built audit-log viewer does (`/owner/audit` renders a real `<thead>` with headers). A breakdown drill-in that is tabular (status counts, action counts) uses `scope="row"` and `scope="col"` so a screen-reader user can navigate by header. The directory is keyboard-navigable row to row, each row's primary link reachable and labelled ("View @handle"), and the sort controls are real buttons announcing their sort state (`aria-sort`).
- **No meaning is ever conveyed by colour alone** (P2 section 12.6), stated because a dashboard is where this is most often violated. Every status and activity chip carries its meaning in its word and its glyph (section 3.3); every metric comparison carries its direction in a glyph and a sign, not only in `success` or `warning` colour (section 11.1); every sparkline and chart carries its data in marked points and accessible labels, not only in a coloured line (section 11.1). A screen-reader user hears "Total members, 1,284, up 12 this week"; a colour-blind user reads the sign and the glyph. The single-series sparkline uses one accent colour with marked points and a text value, so it never depends on colour to be read; multi-series charts, which would need a categorical palette and the colour-independence work that implies, are deliberately not built yet (section 21), so no chart in Phase 2D conveys a series by colour alone.
- **The AAL2 identity step-up is announced as the serious action it is.** The reveal control exposes its gated state to assistive tech; the required-reason field is a labelled input; the warning Alert is announced; and when the data reveals, the panel is an announced region, not a silent change, with the "Hide again" control reachable. The identity data, when shown, exposes the legal name as text (not as an image) so it is readable by assistive tech for the authorized Owner, and the reference-style data (device counts) is read as counts.
- **Live numbers do not steal focus.** If a metric updates while the owner is on the page, the update is announced via a polite live region at most, never by moving focus, the same rule the product applies to the new-posts pill and toasts (P2 section 12.2). A dashboard that yanked focus on every tick would be unusable with a screen reader.
- **The suppression and not-enough-data states are conveyed in text**, not by a blank or a dash alone: "Hidden to protect individuals", "Not enough history yet", so a non-visual user understands why a value is absent rather than meeting an unexplained gap.

## 20. Motion notes specific to Phase 2D

All motion inherits the existing durations and easings and degrades under reduced motion (P2 section 13). **Phase 2D adds no new motion.** The directory list-to-detail is the standard push on mobile and an instant content swap on desktop (P2 section 1.4); metric cards fade in as their data resolves using the existing optimistic-settle opacity, not a bespoke animation; the identity panel reveal is the existing modal-grade fade, deliberately unflashy, because a flourish on an identity reveal would be exactly the wrong tone; sparklines draw instantly (no "animate the line in" effect, which would be decoration and would misread as the data changing). There are no counting-up number animations, no animated gauges, no dashboard theatrics; a metrics surface that performed for delight would pull the owner toward watching numbers move rather than reading them, which is the opposite of the calm, honest posture this whole part is built on.

## 21. Tokens: what Phase 2D adds, and what it deliberately does not

**Phase 2D introduces no new color, type, spacing, radius, elevation, or motion token.** Both surfaces are built entirely from the inherited system (P2 section 2, P2B section 16). This matches the discipline of the earlier specs: the strongest way to keep a privileged surface feeling like the same calm product is to deny it any private palette.

The compositions this document relies on are reuse, not new tokens, and are listed so a builder has them in one place:

- **The status and activity chips** (sections 3.3, 3.4) are the neutral chip composition already defined in P2B section 16: a chip on `surface` with a `border` hairline, a `text-secondary` or `text-tertiary` label, and a leading Phosphor glyph whose Fill colour is the semantic token (`success`, `warning`, `danger`, `text-tertiary`) as reinforcement. No filled chip is used in the directory.
- **The metric card** is an ordinary `surface-raised` card (`radius-lg`, `shadow-e1`) composing existing type roles: `text-label` for the metric name, `text-display` for the value, `text-caption` for the comparison, `text-body` for the unit.
- **The single-series sparkline** is drawn in `accent` (the existing interactive/brand colour) with marked data points; it is decorative in the same sense the thread rail is, reinforced by the card's numeric value and by marked points, so it is exempt from 1.4.11 on the same basis (P2 section 2.3). It needs no new token.

Every foreground/background pairing this document relies on is already measured. The ones it leans on most:

| Pairing | Used for | Light | Dark | Source |
|---|---|---|---|---|
| text-primary on surface-raised | metric value, identity panel body, member-detail body | 16.91 | 13.27 | P2 2.3 |
| text-secondary on surface-raised | metric unit, labels on cards | (base, passes AA) | (base) | base |
| text-tertiary on surface | joined and last-active in rows, counts, suppressed-value note | 4.88 | 5.11 | P2 2.3 |
| accent on surface | status-chip glyphs where accent, sparkline stroke, drill-in caret | 6.26 (on background), see base on surface | (base) | P2 2.3 / base |
| success on surface | Active status glyph, healthy comparison direction | (base, passes AA) | (base) | base |
| warning on surface | restricted/suspended glyphs, comparison where a rise is a concern | 4.74 | (base) | P2 2.3 |
| danger on surface | banned status glyph | (base, passes AA) | (base) | base |
| border-strong on surface | search field and filter control outlines | 3.47 | 3.52 | P2 2.3 |
| text-primary on accent-subtle | founding-posture line, identity-panel gated-card body | 14.35 | 13.20 | P2 2.3 |
| accent on background | links and active controls on the dashboard background | 6.26 | 6.80 | P2 2.3 |

Nothing here is new to measure. **One token is deliberately deferred, not added:** when the dashboard eventually grows multi-series charts (several lines or segments in one chart, likely around the 50-metric mark, section 17), those will need a small categorical series palette that is colour-independent-safe (distinct hues plus distinct markers and labels). That palette is not designed here because no multi-series chart exists in Phase 2D; single-series sparklines need only `accent`. Flagging it now so that when it is needed it is a deliberate, measured addition with its own accessibility work, not an ad-hoc set of colours chosen under deadline.

## 22. Open questions that genuinely need the owner

Kept short and real. Everything else in this document is a professional design decision already made; the owner is time-poor and these are the only two that genuinely need her.

1. **Should anyone other than you ever see the metrics dashboard or the full member directory?** The design defaults both to Owner-only: Admins get a narrow lookup to one account by handle (for enforcement), Moderators get neither, and no staff role gets the analytics. That is the safest default and it is what is built unless you say otherwise. The reason to revisit it is growth: if you bring on a co-founder, an operations partner, or a trusted second admin who genuinely needs to see the numbers or the roster, that is a deliberate widening you authorize, and it would be built as a new, logged capability rather than by loosening the default. The question is only whether you anticipate wanting that soon enough to shape the gating now, or whether Owner-only is right for the foreseeable present. Recommendation: Owner-only now; widen deliberately when a real second person exists.

2. **Confirm (or veto) the metrics I have refused to build (section 15).** I have deliberately not built time on site, DAU/MAU and stickiness, streaks and daily-return mechanics, per-member engagement rankings and "most active" leaderboards, "who is online now" and precise per-member presence, and virality coefficients, and I have built safety and health operations metrics instead (how fast reports are resolved, enforcement shape, backlog). This is a values call and it is yours to make, because these dials shape how you will instinctively build the product: the refused ones push toward making Hersciety hard to put down, which is the wrong goal for a safe space. I recommend the refusals stand. If you want any of them, say which and why, and I will design it honestly, but I would push back on the engagement dials specifically.

That is the entire list. The repeatable metric unit, the card and descriptor and their states, the small-N suppression floor (k, recommended 5), the directory's search-first behaviour and its columns and default sort, the identity line and the AAL2 step-up, the no-bulk-actions position, the identity-free logged export, the layout's survival to 50 metrics, and the day-one metric set are all decided here and do not need your time.

---

## 23. Summary of deliverables for the Phase 2D build

An engineer implementing Phase 2D from this document builds, as new rooms in the existing Owner-tools cluster (`/owner`, reached from the account menu, Owner-only, redirect-gated like the roles and audit pages):

For the **member directory** (Part 1): a search-first, filter-first roster (section 2) that opens on the total-member count, a handle search, filters, and a bounded recent window rather than an infinite scroll (sections 3, 4); rows that show `@handle`, join date, status chip, role chip, and a coarse activity bucket, defaulting to newest-join-first, and never a legal name, email, or contact (sections 3, 0.2); keyset pagination with a recent-window cap on the no-intent view and a "too many results" state under broad filters (sections 4, 5); the full empty, loading, error, and too-many states (section 5); a member-detail glance view of standing and conduct with the identity panel closed and set apart (section 6); the AAL2 identity step-up that requires a stated reason and writes a privileged-read entry to the hash-chained audit log, reusing the existing owner-page AAL2 pattern (section 7); the one-way link into the moderation console for a member's cases and standing, with no duplication of the case queue (section 8); and no account-changing actions and no destructive bulk actions at all, with the sole bulk operation being an identity-free, logged, Owner-only export (section 9).

For the **metrics foundation** (Part 2): a metrics system whose unit is a declared descriptor rendered by one metric card, so a new metric is added by declaration, not design (section 10); the card with its six states defined once and inherited by every metric, loading, value, zero, not-enough-data, suppressed, error (section 11); the day-one metric set, total members (with its precise definition excluding the system account, deleted, and banned-from-headline), signups over time, active members (as a wide-window liveness check, not DAU), posts, reports filed and resolved with resolution rate and median time to resolution, and enforcement actions (section 12); honest behaviour at a tiny network with framed zeros, no fake trends, absolute-not-percentage deltas at small N, and a warm "it is early" line (section 13); global time ranges and previous-period comparison with percentages withheld below a base threshold (section 14); the explicit refusal of engagement and surveillance metrics in favour of safety-operations metrics (section 15); the small-N suppression rule (recommended k = 5) that suppresses segmented aggregates below the floor while exempting top-line totals, with no path from an aggregate to an individual on this surface (section 16); a layout that survives to 50 metrics by adding descriptors and sections rather than redesigning (sections 17, 18); and a read-only, Owner-only dashboard that changes nothing.

It stays within the existing token system, adding no new token and only reusing documented compositions of existing ones, and deferring a multi-series chart palette until multi-series charts exist (section 21). It leaves the owner exactly two decisions (section 22). And it holds the three constraints that make this the most carefully built surface in the product: identity is a deliberate, logged, reasoned act and never a column (constraint 0.2); no destructive action, and in the directory no account action at all, is ever reachable by reflex (constraint 0.3); and staff default to seeing less than the Owner, with only the Owner seeing the whole picture and even she seeing identities only on the record (constraint 0.4). Those constraints are the reason a member directory and a metrics dashboard, which together have the exact shape of a surveillance system, are built here as the opposite of one.
