# Hersciety, Phase 2B: Visual and UX Design Direction for the Moderation Console and the Discover Feed

**Status:** Design specification for the Phase 2B build. It defines look, feel, information architecture, component anatomy, states, confirmation patterns, and safety rules for two surfaces: the moderation console (the surface that lets a report be acted on) and the Discover feed (finding people and posts beyond the follow graph). It is not code and does not define components in a framework. An engineer should be able to build Phase 2B from this plus the Phase 2 spec and the existing token system without guessing.

**Date:** 2026-10-05

**Design thesis (inherited, not reopened):** "Calm paper, sharp tools." The same warm sand canvas and single Iris-violet accent carry both surfaces. The moderation console is the sharpest tool in the product, so it is also the calmest: a tool that provokes alarm provokes mistakes, and a mistake here closes a real person's account. Discover is the widest surface, so it is the most carefully ranked: on a platform built for people hiding from someone, what gets amplified is a safety decision, not a growth decision.

**Relationship to the Phase 2 spec.** This document extends `docs/design-phase2-social-core.md` (the Phase 2 spec). It does not restate it and does not change it. Every reference written as "P2 section X" points into that document. The application shell (P2 section 1), the token foundation (P2 section 2), the shared primitives (P2 section 3), the member-facing safety controls (P2 section 10), the accessibility specification (P2 section 12), and the motion specification (P2 section 13) are inherited verbatim. Where this document needs a component that the Phase 2 spec already defines (the overflow menu, the toast, the identity block, the three-level thread view), it reuses it rather than inventing a parallel one.

---

## 0. How to read this document

- **Tokens** are the ones already implemented in `src/app/globals.css` and enumerated in P2 section 2. They are named exactly as the CSS custom properties and Tailwind theme names in that file (`surface`, `surface-raised`, `background`, `border`, `border-strong`, `text-primary`, `text-secondary`, `text-tertiary`, `accent`, `accent-fill`, `accent-subtle`, `on-accent`, `success`, `success-subtle`, `warning`, `warning-fill`, `danger`, `danger-fill`, `danger-subtle`, `focus-ring`, `scrim`, the eight type roles, the base-4 spacing scale, the radius and elevation scales, the Phosphor icon set). This document adds no new color, type, spacing, radius, elevation, or motion token. Section 16 states that explicitly and lists the two chip compositions it builds from existing tokens.
- **Contrast.** Every foreground/background pairing this document relies on is already measured, either in the base system or in P2 section 2.3. Section 16 lists each pairing used here and the measured ratio it reuses. Nothing new to measure is introduced.
- **Icons** are Phosphor (MIT), Regular weight inactive and Fill weight active, exactly as P2 section 0 sets out. Named glyphs map to real Phosphor icons.
- **The two hard safety constraints in section 0.1 and 0.2 govern every surface in this document.** They are not style; they are the reason the product exists. Read them first.

### 0.1 Hard constraint one: the legal name never appears in any moderation surface

`display_name` is the member's real legal name. It is nullable, trigger-locked to be either NULL or the member's own verified legal name, and its public display is opt-in and off by default (P2 section 3.2, and the identity migration). **Members of this platform are hiding from specific people.** The single most dangerous thing the product can do is show a legal name to someone who has not been granted it.

A moderation console is exactly the surface where a careless build would leak it, because moderation feels like it needs "the real identity." **It does not.** Every moderation surface in this document identifies every member, reporter and accused alike, by **`@handle` only**. There is no queue row, no case header, no report detail, no enforcement dialog, no audit entry, and no member-facing notice in this document that renders `display_name`. A moderator can do the entire job of reading reports and applying the enforcement ladder without ever seeing a legal name, because conduct, not identity, is what is being judged (this mirrors the guidelines: the only basis for action is what a person does).

The one and only place a legal identity may be needed is a law-enforcement or NCMEC escalation, which is **Owner-only, behind AAL2 step-up**, on a surface that is not part of the moderator console at all (section 4.8 and section 8.2). That surface is drawn deliberately apart from the queue so that "I am looking at a report" and "I am looking at a legal identity for a lawful disclosure" can never be the same screen or the same muscle action.

If a future revision feels the urge to "just show the real name so the moderator has full context," that urge is the violation. Write it down and stop.

### 0.2 Hard constraint two: the irreversibility rule

On 2026-10-06 the owner destroyed a live production database because an irreversible one-click action offered two choices that differed only by letter case. The lesson is now a product rule, and it is a hard constraint, not a preference:

**Every destructive or irreversible action in this product must differ from its neighbour by more than casing or colour. It must differ by a distinct verb, a distinct placement, and a distinct visual weight, and anything unrecoverable must additionally require a typed confirmation.**

The moderation console is where this product does its most destructive work, so this rule is enforced hardest here. Concretely, everywhere in this document:

- A destructive action and its cancel are **never** a matched pair that reads the same. The safe choice is a left-aligned ghost control with an active, reassuring verb ("Keep account active", "Cancel"); the destructive choice is a right-aligned filled `danger-fill` control with a specific destructive verb ("Suspend 7 days", "Remove post", "Ban permanently"). They differ by verb, by colour, by fill, and by position at once, so no single one of those being misread can cause the wrong outcome.
- Two destructive choices are **never** placed side by side differing only by a number or a word's case. Where an action can escalate (suspend versus ban), the two live in different places in the action rail, carry different verbs and weights, and the more severe one is gated behind a typed confirmation that the lighter one does not require.
- **Anything unrecoverable requires typing the target's `@handle`** into a confirmation field before the destructive button enables. A permanent ban (section 4.7) is the clearest case: the "Ban permanently" button stays disabled until the moderator types the exact `@handle` of the account being banned. You cannot ban the wrong person by reflex, because banning requires you to have read and reproduced who you are banning.

This constraint is stated here, once, as law, and every action surface below cites it rather than re-deriving it.

---

# PART 1. THE MODERATION CONSOLE

Nothing in the product can action a report today. The `reports` table has no update path for any role, no suspend, ban, restrict, warn, or remove function exists, and nothing writes the ban-evasion blocklist. That is why the platform stays `noindex`. This part designs the surface that fixes it. It is the priority of this brief and it is specified first and most thoroughly.

The console actions exactly the vocabulary the legal documents already promised members. The community guidelines name a four-rung enforcement ladder (Warning, Content removal, Temporary suspension of 3 to 30 days, Permanent removal), a reporting flow that confirms receipt and reports an outcome, confidentiality (the reported person is never told who reported them), and an appeals path at `appeals@unitedfeminist.com` within 30 days. The console is built to do precisely those things and nothing the documents did not promise.

## 1. Where the console lives, and who reaches it

The member shell is fixed at five primary surfaces (P2 section 1.1) and is not touched. The moderation console is a privileged management surface, like Settings, and is reached the same way Settings is reached: from the account control, not from the primary nav.

- **Desktop and large tablet.** The left-rail account control (P2 section 1.2) opens the small account menu (Settings, Switch appearance, Log out). For an account that holds a staff role, that menu gains one item above Settings: **Moderation**, with a `ShieldCheck` glyph. It appears only for `moderator`, `ts_reviewer`, `admin`, and `owner`; a member never sees it and never learns it exists.
- **Mobile and small tablet.** Same entry, from Profile then the account menu. The console is a full push surface with its own internal nav, exactly as Settings is (P2 section 1.4, section 8). It never occupies one of the five bottom-tab slots, because it is not a destination members use.
- **Internal layout.** On desktop the console is a two-pane surface: a left list of cases (the queue) and a right detail pane for the selected case, inside the same centered frame the rest of the app uses, but allowed to widen past the 600px reading measure because a queue is a working surface, not a reading surface. On mobile it is a single list that pushes to a full-screen detail on tap, with a back affordance to the exact scroll position (the standard push pattern from P2 section 1.4).

**The console wears a quiet identity strip** so a moderator is never in doubt that she is in the privileged tool rather than the public app. A persistent 32px strip sits directly under the top bar, `accent-subtle` fill, a `ShieldCheck` glyph, and the label "Moderation" at `text-label` in `accent`, followed by the moderator's own role in `text-caption` `text-secondary` ("Moderator", "Admin", "Owner", "Reviewer"). The strip is reassurance and orientation, not decoration, and it is the one persistent use of `accent-subtle` as a surface tint in the product. `accent` on `accent-subtle` is measured 6.03 light / 5.55 dark; `text-secondary` on `accent-subtle` is 6.52 / 6.90 (P2 section 2.3).

**Role shapes the whole console, not just individual buttons.** What a person can see and do is set by role and is reflected in the surface, never discovered by hitting an error:

- **T&S Reviewer** sees the queue read-only. Every action control is absent, not disabled-with-a-lock, because a reviewer has no action authority at all and showing locked buttons would imply she might earn them. She can read, filter, and add an internal triage note; she cannot dismiss, warn, remove, restrict, suspend, or ban. Her one forward action is "Flag for a moderator" (a triage note, not an enforcement action).
- **Moderator** sees the full queue and the ladder up to and including Remove content, Restrict, and Suspend for 7 days or fewer. Ban is absent from her console entirely (not disabled): she never bans, so she never sees a ban control to be tempted by or confused by. Suspensions longer than 7 days are present but expressed as an escalation, never as a button she can press (section 4.6).
- **Admin** sees everything the moderator sees plus suspensions longer than 7 days and the permanent Ban action with its typed confirmation and ban-evasion controls (sections 4.7, 6).
- **Owner** sees everything an admin sees, plus the audit-log viewer (section 8.2) and the Owner-only NCMEC and law-enforcement escalation surface (section 4.8), both behind AAL2 step-up. Reports that name the Owner appear in her own panel like any other staff-lane case (section 7, owner decision).

## 2. The report queue, list view

### 2.1 The triage model, and the case

Reports do not arrive one clean item at a time. A single bad actor draws many reports; a brigade can file many reports about one victim to bury her; the same post can be reported by ten people for the same reason. If the queue is a flat list of raw reports, volume alone becomes noise and a coordinated pile-on of reports reads as "this person must be guilty, look how many reports."

So the queue's unit is the **case**, not the raw report. A case groups all open reports that share the same **accused account** and, for post reports, the same **subject post**. A case shows:

- the accused `@handle`;
- a one-line summary of the most severe reason present in the case (reasons are ranked by severity, see 2.2), plus a count of distinct reporters and a count of total reports when either exceeds one ("7 reports from 5 people");
- the newest report time;
- the case's triage state and priority (2.2).

Grouping is a safety feature, not only a convenience. It makes a report-brigade legible as what it is (many reports, one target, often the same copied text) rather than as damning volume, and it means a moderator reviews a person once with all the evidence in front of her, not seven times in a row. It also defuses mass-reporting as a denial-of-service and as a harassment tactic, because fifty reports about one woman collapse into one case with a visible "50 reports from 2 people" signal that invites scrutiny of the reporters, not the target.

### 2.2 List layout, triage state, and priority

Each case is a row, min height 72px, 16px vertical padding, sitting on `surface` with `border` hairline separators exactly as the feed does (P2 section 4.3), so the queue reads as the same calm paper. Left to right:

1. A **priority chip** (see below), or nothing for Normal priority.
2. The accused **`@handle`** at `text-label` `text-primary`, and under it the most-severe reason label at `text-body` `text-secondary`, with the reporter/report counts as `text-caption` `text-tertiary`.
3. A **triage-state chip** (see below).
4. The newest-report **relative time** at `text-caption` `text-tertiary`.
5. On the far right, a **checkbox** for bulk selection (2.4 of this document, and section 4).

**Triage state** maps exactly to the existing `report_status` enum (`open`, `in_review`, `actioned`, `dismissed`, `escalated`) so the UI and the data never drift:

| State | Chip label | Treatment |
|---|---|---|
| open | New | neutral chip, leading `Circle` glyph in `accent` |
| in_review | In review | `accent-subtle` chip, `accent` label, `CircleDashed` glyph (someone has claimed it) |
| escalated | Escalated | neutral chip, `ArrowUpRight` glyph in `warning` |
| actioned | Actioned | neutral chip, `CheckCircle` glyph in `success` |
| dismissed | No action | neutral chip, `MinusCircle` glyph in `text-tertiary` |

**Priority** is a separate axis from state and exists to float genuinely urgent cases to the top without turning the whole queue red:

| Priority | When | Chip |
|---|---|---|
| Critical | reason is `csam`, `ncii`, or `violence_threat`; auto-escalated on arrival | `danger-fill` chip, white label "Critical", `Warning` glyph; the only filled chip in the queue |
| High | reason is `doxxing`, `self_harm`, or `hate`; or a case has crossed a repeat-offender threshold | neutral chip, `warning` glyph, label "High" |
| Normal | everything else | no chip |

The chips carry their meaning in the **word and the glyph**, never in colour alone, so they satisfy colour independence (P2 section 12.6). The semantic colour on a glyph is reinforcement, exactly as the thread rail's colour is reinforcement (P2 section 2.3), and is exempt from 1.4.11 on the same reasoning. The one filled chip, Critical, uses `danger-fill` plus white, measured 5.62 light / 4.83 dark (P2 section 2.3). Every other chip uses a neutral surface with `text-secondary` or `text-tertiary` labels against measured base pairings (section 16).

### 2.3 Filtering and sorting

Above the list sits a filter bar built from the existing segmented-control and pill patterns (P2 section 3.6, section 4.1), nothing novel:

- **State filter:** a segmented control, Open (default) / In review / Resolved (actioned and dismissed together) / Escalated. "Open" is the working view and is where a moderator lives.
- **Reason filter:** a multi-select pill row of the plain-language reasons, so a reviewer can pull all `doxxing` or all `impersonation` cases together when a pattern is suspected.
- **Assignment filter:** Mine / Unassigned / Anyone. Claiming a case (2.4, section 3) sets `assigned_to`, so two moderators are not unknowingly actioning the same person.
- **Sort:** Priority then newest (default), Newest, Oldest, Most reporters. Default is Priority then newest so Critical cases are never below the fold; there is no sort that ranks by raw report count alone, because that would reward brigading.

Filters are state in the URL so a moderator can share a scoped view ("all open doxxing cases") with a colleague by link, and so a refresh does not lose her place.

### 2.4 Queue volume communicated without alarm

How many reports are waiting is information, not an emergency, and it must be shown as information. A large red number on the Moderation entry would do to the moderator exactly what a red confirmation dialog does to anyone under stress: push her toward fast, reflexive, error-prone action. On a surface whose actions close accounts, alarm is a defect.

So the queue count is **calm by default and sharp only where it is truly urgent**:

- The **Moderation** item in the account menu carries no red badge. It shows an open-case count in `text-secondary` as plain text ("12 open"), the same neutral weight as any other count in the product. If there are zero open cases it says "Clear", not "0", in `success` text, so an empty queue reads as a good state rather than an absence.
- The **one exception** is Critical. If one or more Critical cases are open, and only then, a small `danger-fill` dot sits on the `ShieldCheck` glyph, because `csam`, `ncii`, and credible threats are the cases where a delay is itself a harm and where the convention of a red alert is earned. This is the same single, deliberate exception the product already makes for the member notification badge (P2 section 4.6): red means "a human must look now", and it is reserved for when that is literally true.
- At the top of the queue, a one-line summary in `text-secondary` states the shape without drama: "12 open, 2 critical, 4 in review." No trend arrows, no "up 300% today", nothing that turns a workload into a panic. If the owner later wants volume trends, they belong on an Owner analytics surface, not on the working queue.

This deliberately inverts the member-facing red-badge convention, and it does so for a stated reason: the member's red badge exists to pull attention to her own notifications, which is harmless; the moderator's queue count sits one click from irreversible action, where pulled attention becomes rushed destruction. Convention serves the member; calm serves the moderator and, through her, the accused.

### 2.5 The two routing lanes, as the list expresses them

> **OWNER OVERRIDE (2026-10-05).** This section originally described three lanes, with `owner_conflict` sealed from everyone including the Owner. The owner rejected that design (section 7). `file_report()` now computes two lanes; a report naming the Owner routes `admin_only`. The enum value `owner_conflict` still exists in the schema (PostgreSQL cannot drop enum values) but nothing writes it, and any legacy rows were re-routed to `admin_only` by migration `20261010000001`.

`file_report()` computes a routing value server-side (`standard`, `admin_only`) and the reporter never learns which lane her report took (P2 section 10.5). The queue honours routing exactly:

- **`standard`** cases appear in the moderator queue, the default working view.
- **`admin_only`** cases (the accused holds a staff role, **the Owner included**) appear only to admins and the Owner, and are marked with a small staff chip reading "Staff" at `text-caption`, so an admin knows she is weighing a colleague and should expect to document carefully. A moderator never sees these and is never told they exist. A non-Owner staff member never sees a report that names herself; the Owner, by her own explicit decision, **does** see reports that name her (section 7).

## 3. The report detail view

Selecting a case opens its detail in the right pane (desktop) or a pushed full screen (mobile). This is where a moderator reads everything and acts. Its job is to put all the evidence in one place, in context, without ever sending her out of the console to understand what she is looking at, and without ever leaking a legal name.

### 3.1 Anatomy

Top to bottom:

1. **Case header.** The accused `@handle` at `text-heading`, linking to the accused's profile in a side peek (a drawer, not a navigation away, so the moderator keeps her place). Beside the handle, the account's current status as a chip (Active, Restricted, Suspended until a date, Banned) so the moderator instantly knows whether an action is already in force. Then the priority and triage-state chips from 2.2. **No legal name anywhere in this header.**
2. **The reported content**, rendered faithfully (3.2). For a reported post or reply, the actual post as members see it; for a reported account, a compact profile card plus that account's recent public posts.
3. **The reports themselves**, as a list: each report's reason, its free-text detail if any, its time, and the reporter (3.3). When the case groups several reports, they stack newest first, and identical copied-and-pasted detail text across many reports is visually collapsed with a "5 reports with the same text" note, which is itself a brigade tell.
4. **The account context strip**: the account's age on the platform, its post count, its prior enforcement history (section 8.1), and whether it has been actioned before. A repeat pattern is the single most useful thing a moderator can know and it belongs here, de-identified, keyed to the handle.
5. **The action rail** (section 4): the enforcement ladder, laid out by severity, gated by role.

### 3.2 Showing a reported reply in its thread context, without leaving the queue

A reply reported in isolation is often unreadable: "you are disgusting and everyone knows it" might be harassment, or might be the fourth turn of a consensual roast between friends, and the moderator cannot tell which from the reply alone. She needs the surrounding thread. She must get it **inside the detail pane**, because sending her to the public thread view loses the case, loses her claim on it, and invites her to act from the public surface instead of the console.

So the detail view renders the reported item **in place, in context**, using the thread components the product already has (P2 section 6, the three-level nesting, the `--thread-rail` guide, the elbow into each reply, avatars inside each reply header):

- The reported reply is shown with its **parent chain above it** (the post it replies to, and that post's parent, up to the root) and a **small window of sibling and child replies below it**, so the conversation reads the way it did when it happened.
- The reported reply itself is marked unmistakably: a 2px `accent` left edge and a faint `accent-subtle` background band on that one reply, plus a `text-caption` `accent` label "Reported reply", so the moderator's eye lands on exactly the item in question and is never confused about which turn in the thread is under review.
- Context is **collapsed by default to a tight window** (a few turns each side) with a "Show more of this thread" expander, so a 200-reply thread does not flood the pane; expanding loads more turns in place.
- Every author in the context is shown by `@handle` only, including the accused and the reporter if they appear. The thread context is a read rendering: the action row (reply, like, reshare) is **absent** here, because the console is for judging, not participating, and a moderator must not be able to reply to or like content from inside a case.
- Content that was already removed by moderation earlier in the thread shows as a neutral **removed stub** ("Removed by moderation") rather than the original text, so the console never silently re-surfaces content a colleague already took down (this matches the existing `post_visibility` state `removed_moderation`, which the read functions already skip for members).

For a reported **account** rather than a single post, the same principle applies at account scale: the detail shows the account's recent public posts inline, newest first, each expandable to its own thread context on demand, so a pattern of behaviour across posts is visible without leaving the case.

### 3.3 Reporter protection, and reporter-abuse signals

The guidelines promise the accused is never told who reported them. The console honours that absolutely: there is no surface, notice, audit entry, or appeal response in this document that reveals a reporter's identity to the accused. But a moderator needs to see reporters, both to weigh a report and to catch the abuse of reporting itself (a harasser who reports his target repeatedly to bury her, or a ring that mass-reports one woman).

The balance:

- Reporter `@handle`s are visible **to the moderator inside the case**, but **collapsed by default** behind a "Show reporters" control, so merely reading a case does not expose who reported, and casual browsing of the queue does not build a picture of who reports whom. Revealing reporters is an intentional act. It is also audit-logged (section 8.1): the console records that this moderator viewed the reporter identities on this case, because the ability to see who reports is itself a power that can be abused, and the product's stance is that every power a staff member holds is logged (this is the same principle as the Owner-only, audit-logged access to contact info).
- When the same reporter has filed many reports against many different accounts in a short window, the case shows a quiet `text-caption` `warning` note on that reporter's row ("This account has filed 14 reports in 24 hours"), so report-abuse is visible to the person who can act on it. Reporting is a tool, and like every tool here it can be weaponised; the console surfaces that without punishing good-faith reporters who happen to report a lot of genuine abuse.
- The existing per-reporter rate limits (one report per accused per reason per 24 hours, ten per reporter per hour) already blunt flooding at the source; this surface makes the residual pattern legible to a human.

### 3.4 Single action and bulk action

Most moderation is one case at a time, and the detail view is built for that. But two situations genuinely need bulk action, and both are safe to batch:

- **Dismissing many clearly-nothing cases** (a wave of spam-reports that are not violations, a brigade of identical reports that a moderator has judged baseless). Selecting several open cases in the list (via the row checkboxes, 2.2) enables a bulk bar with exactly two actions: **Mark in review** (claim them) and **Dismiss (no action)**. Dismiss is reversible: a dismissed case can be reopened (section 4.2), so a batch dismiss is not a destructive act and does not require the typed gate.
- **Actioning identical content from one account** (the same violating post reshared or reposted many times). This is still one accused, so it is one case by the grouping rule (2.1), and it is handled as a single action, not a bulk one.

**Bulk action is deliberately limited to the two non-destructive operations above.** You cannot bulk-suspend, bulk-ban, or bulk-remove across different accused accounts from the list. Every account-level enforcement action (warn, remove, restrict, suspend, ban) happens in a single case's detail view, against one named account, with that account's context in front of the moderator and, for the severe actions, with the per-action confirmation the irreversibility rule requires. Destructive actions are never batched, because a batch is exactly where a reflexive mistake becomes a mass mistake. This is a direct application of constraint 0.2: the more severe and less reversible an action, the more it is forced to be singular, deliberate, and named.

## 4. The enforcement action surfaces

### 4.1 The action rail and the ladder

The detail view's action rail lays the enforcement ladder out by severity, lightest at the top, heaviest at the bottom, with the heaviest fenced off. This is the same shape as the member overflow menu (P2 section 10.1), for the same reason: a familiar, escalating order is readable under pressure. The rail, top to bottom, with role gating:

1. **Dismiss (no action)** (4.2). All action-capable roles.
2. **Warn** (4.3). Moderator and above.
3. **Remove content** (4.4). Moderator and above.
4. **Restrict** (4.5). Moderator and above.
5. **Suspend** (4.6). Moderator (7 days or fewer) and Admin (any duration).
6. *(fence)*
7. **Ban permanently** (4.7). **Admin only.** Absent from the moderator and reviewer rails entirely.
8. **Escalate** (to a more senior role, or, for the severe child-safety and threat reasons, to the Owner-only path, 4.8). All action-capable roles.

Every action writes the `reports` case to an appropriate `report_status` (`actioned`, `dismissed`, or `escalated`), records the acting role and a required or optional note, sets the account's `account_status` where relevant, moves affected posts to the correct `post_visibility`, and appends to the hash-chained `audit_log`. The member-facing consequence of each is in section 8.3.

The ladder maps one-to-one onto the guidelines' published ladder so the console can do exactly what members were promised and nothing more: Warn is Warning, Remove content is Content removal, Suspend is Temporary suspension (the guidelines' 3-to-30-day band), Ban is Permanent removal. Restrict is a lighter-than-suspension state the `account_status` enum already carries and the guidelines' "your account remains active" cases make room for.

### 4.2 Dismiss, no action

The lightest outcome and the most common one. A single click from the detail view, or a bulk operation from the list (3.4). It sets the case `dismissed`, optionally records a one-line internal reason (not shown to anyone outside staff), and notifies the reporter only that review is complete (section 8.3 and the guidelines' promise to report an outcome). It is **reversible**: a dismissed case keeps its contents and can be reopened to `open` or `in_review` if new reports arrive or a colleague disagrees, so dismissing is low-stakes and needs no confirmation dialog. The verb is "Dismiss (no action)", never a bare "No" or "Reject", so it reads as a considered outcome rather than a brush-off.

### 4.3 Warn

A warning is a message to the member naming the rule and the content, with the content optionally removed (the guidelines allow either). The warn surface is a single step: pick the rule from the plain-language reason list (the same labels as the report reasons), write or accept a short standard message, and choose whether to also remove the specific content. It is reversible in the sense that a warning carries no functional restriction; it is a recorded notice. Confirmation is lightweight (a single confirm, no typed gate), because nothing about it is destructive. The member sees it as a dismissible notice (section 8.3).

### 4.4 Remove content

Removes the specific post or reply. It moves that post to `post_visibility = removed_moderation`, which the member read functions already skip, so the content vanishes from every public surface and can never resurface as a thread parent (the read layer already guards this). It is **reversible**: a moderation removal can be restored, which is why the member-facing stub says "removed", not "deleted". Removing one's own content as a member is a different state (`removed_author`) and the two are never conflated, so a member always knows whether she hid something or the platform did (section 8.3).

Confirmation is a single modal, following the irreversibility rule's shape even though removal is reversible: a left-aligned ghost "Cancel" and a right-aligned `danger-fill` "Remove post" with the specific verb. No typed gate, because it is reversible and scoped to one item. The modal states plainly what will happen ("This post will be removed from Hersciety. You can restore it later. The author will be told their post was removed and why.").

### 4.5 Restrict

A lighter state than suspension, using the existing `restricted` account status. A restricted member can still read and use the parts of the product that pose no risk, but is limited in the way that fits the violation: typically she can read but not post or reply for the restriction window, or is rate-limited. Restrict exists so that not every actionable violation forces the blunt instrument of a full suspension. It is time-boxed, reversible, and carries a required rule and an optional note. Its confirmation is a single modal with the distinct-verb pattern ("Cancel" / "Restrict"), no typed gate. The member sees a clear account-status banner explaining exactly what she can and cannot do and until when (section 8.3).

### 4.6 Suspend, and expressing the 7-day boundary before the fact

Suspension is temporary and reversible, and it is the first action where role genuinely changes what the acting person may do. The locked decision: **Moderators may suspend for 7 days or fewer; suspensions longer than 7 days are Admin-only.** The brief is explicit that this boundary must be expressed in the UI, not delivered as an error after a moderator has already chosen 30 days.

The suspend surface makes the boundary a visible property of the control, so it is impossible to choose a duration you cannot apply:

- The duration control is a row of **preset chips** plus a custom field: 1 day, 3 days, 7 days, 14 days, 30 days, and "Custom". The guidelines' own band is 3 to 30 days, so these presets are the common cases.
- **For a moderator**, the 1, 3, and 7 day chips are live and selectable. The 14 and 30 day chips are **present but visibly out of reach**: rendered in `text-tertiary` with a small `Lock` glyph and a persistent inline caption beneath the row, "Suspensions over 7 days are set by an admin." They are not hidden, because hiding them would make the limit invisible and make "why can I only pick 7" a mystery; they are shown precisely so the moderator understands the shape of her authority. The custom field, for a moderator, accepts 1 to 7 and will not accept a larger number: typing 8 clamps to 7 with the same inline caption, so there is no way to compose an over-limit value and be rejected after the fact.
- Next to the locked chips, a moderator has an **"Escalate for a longer suspension"** action, which hands the case to an admin with her recommendation attached (section 4.1 Escalate). This is the intended path when a moderator judges that more than 7 days is warranted: she does not hit a wall, she hands it up with context.
- **For an admin**, all chips are live and the custom field accepts any duration the guidelines permit. The permanent option is not here; permanent is Ban, a different action in a different place (4.7), never a "99999 days" on the suspend control, because an unrecoverable outcome must never be reachable by typing a big number into a reversible control's field.

Suspension's confirmation is a single modal with the distinct-verb pattern: left-aligned ghost "Keep account active", right-aligned `danger-fill` "Suspend 7 days" (the verb carries the chosen duration, so the button literally says what it will do). A required rule and optional note. No typed gate, because suspension is time-boxed and reversible: an admin or the Owner can lift a suspension early, and the member can appeal. The member sees an account-status banner with the exact end date and what is blocked (section 8.3).

### 4.7 Ban, permanently, Admin only

Permanent removal is the apex of the ladder, it is **Admin-only**, and it is the most irreversible thing a staff member can do to a person. Moderators and reviewers never see a ban control. Members never ban. The owner's own stated rule is that a ban extends to any new accounts the person makes, which makes the ban-evasion controls part of this surface (section 6).

Ban is drawn to be deliberate to the point of friction, because that friction is the feature:

- It is **fenced off** at the bottom of the action rail, below a divider, visually separated from Suspend above it so the two are never adjacent peers. Suspend and Ban differ by verb, by weight, by position, and by the confirmation they demand (constraint 0.2).
- Selecting it opens a confirmation that is unlike every other confirmation in the product, on purpose. It states the consequence in plain words ("This permanently closes @handle's account. It cannot be undone from here. The person can appeal within 30 days."), it requires a **rule selection** and a **note** (both mandatory, because a permanent action must be justified on the record for the audit log and any appeal), and it carries the **ban-evasion options** (section 6).
- The destructive button, **"Ban permanently"**, is `danger-fill`, right-aligned, and **stays disabled until the admin types the exact `@handle` of the account being banned** into a confirmation field above it. The field uses the existing input styling (`border-strong` outline, measured 3.47 / 3.52) with a `text-caption` label "Type @handle to confirm". The left-aligned ghost choice is "Keep account active", an active verb, never a bare "Cancel" that could be misread as the destructive one. You cannot ban the wrong person by reflex: banning requires you to have read who you are banning and reproduced their handle by hand.
- Ban is the one action this document calls unrecoverable from the console. It sets `account_status = banned`, moves the account's public content out of every public surface, and, per the ban-evasion options, writes the chosen de-identified signals to the blocklist. The member meets the terminal banned screen and the 30-day appeal path (section 8.3, 8.4). "Cannot be undone from here" is literal and honest: a reversal of a permanent ban is an Owner-level act via the audit trail and appeal, not a button in the admin's rail, so the admin is never tempted to treat it as casually reversible.

### 4.8 CSAM, NCII, and credible threats: the Owner-only escalation

Three reason categories are not ordinary moderation and the console treats them as such. For `csam`, these cases carry Critical priority (2.2), and the console **does not let a moderator or admin "action" or "dismiss" them in the ordinary way at all.** A `csam` case offers exactly one forward action to a moderator or admin: **Escalate to the Owner**, because filing with NCMEC and contacting law enforcement are Owner-only powers (the roles matrix reserves "file NCMEC reports" and "initiate law enforcement contact" to the Owner). The case is immediately removed from the ordinary queue, the content is withheld, and the Owner is alerted on the Critical channel (2.4). A moderator can never close a child-safety case by judgement; she can only route it to the one person legally positioned to handle it.

The Owner's handling surface for these is **separate from the moderation console and behind AAL2 step-up**, because it is the one place a lawful disclosure may require real identity, and real identity must never live on the same screen as the ordinary queue (constraint 0.1). That surface is drawn and labelled as what it is ("Child-safety and law-enforcement escalations"), it is reached only by the Owner, and it is where the legal-identity view and the NCMEC workflow live. Everything about it is logged. `ncii` and credible `violence_threat` cases are also Critical and also offer immediate protective removal plus escalation, but they are actionable by admins within the ladder as well, because they do not carry the same mandatory-reporting posture that `csam` does. The guidelines already promise members that NCII is removed immediately on verification and the account suspended, and that threats go to law enforcement where appropriate; this surface does exactly that.

## 5. Confirmation patterns, proportional to severity (the irreversibility rule applied)

Section 0.2 states the rule as law. This section is the table that applies it to every action, so a builder has one place to check that no two destructive actions ever read alike, and so the gradient of friction tracks the gradient of harm. Friction is deliberately proportional: an easily-undone action gets none, and an unrecoverable one gets the most.

| Action | Reversible? | Confirmation | Destructive-button verb | Safe-choice verb | Typed gate |
|---|---|---|---|---|---|
| Dismiss (no action) | yes (reopenable) | none (single click) | "Dismiss (no action)" | n/a | no |
| Warn | yes (notice only) | single confirm | "Send warning" | "Cancel" | no |
| Remove content | yes (restorable) | single modal | "Remove post" | "Cancel" | no |
| Restrict | yes (time-boxed, liftable) | single modal | "Restrict" | "Cancel" | no |
| Suspend | yes (time-boxed, liftable) | single modal, duration on the button | "Suspend 7 days" | "Keep account active" | no |
| Ban permanently | no (Owner/appeal only) | distinct modal, mandatory rule + note | "Ban permanently" | "Keep account active" | **yes, type @handle** |
| Escalate | yes | single confirm | "Escalate" | "Cancel" | no |

Rules that hold across the table, enforced in review:

- **No destructive confirmation pair ever differs only by case or colour.** The safe choice is always a left-aligned ghost control with an active, reassuring verb; the destructive choice is always a right-aligned `danger-fill` control with a specific destructive verb. They differ on at least four axes at once (verb, fill, colour, position).
- **The safe choice holds focus by default** in every confirmation modal, so a reflexive Enter never fires the destructive action. Escape always cancels. These match the member-facing block confirmation (P2 section 10.2) so the pattern is one pattern across the whole product.
- **Verbs carry their object.** "Suspend 7 days", "Remove post", "Ban permanently @handle" (in the ban modal's heading) say what will happen to whom, so no button is a bare "Confirm" that depends on the title to mean anything.
- **The only typed gate is the one unrecoverable action.** Adding typed gates to reversible actions would train moderators to type past confirmations as noise and would dull the one place the gate must be felt. The gate is reserved for ban precisely so it stays meaningful.

This is a hard constraint and it is called out here as one: the whole reason it exists is that an irreversible action whose choices differed only by letter case already destroyed a production system once, and the product's answer is that no irreversible action in Hersciety is ever again distinguishable from its neighbour by so little.

## 6. Ban evasion, the moderator-facing side

The owner's rule is "I can ban whoever I want, including any new accounts they make." The schema holds a `banned_identifiers` table of HMAC hashes (`email_hash`, `phone_hash`, `device_hash`) and never raw values, but nothing writes to it yet, so the rule is unenforced. The ban surface (4.7, Admin-only) is where it gets written, and the design has to let an admin extend a ban to future accounts **without ever exposing a raw identifier** and **without letting anyone believe a ban is a permanent wall.**

The ban confirmation (4.7) carries a **"Prevent new accounts" section**, below the ban reason and above the typed-gate field. It lists only the **categories of signal the system holds for this account, de-identified, as plain-language toggles with counts**, never the values:

- "Device signatures on record (3)" with a short caption, "New sign-ups from the same devices will be refused."
- "Email address on record" with "New sign-ups from the same email will be refused."
- "Phone number on record" shown only if a verified phone exists (phone verification is currently off, so this row is usually absent), with "New sign-ups from the same number will be refused."

Each row is a toggle. Device and email default **on**, because the owner's rule is to extend the ban to new accounts by default; phone defaults on when present. **The admin never sees the device hash, the email, or the number.** She sees the category and the count. On confirm, the system hashes the account's known identifiers with the server pepper and writes them to `banned_identifiers` with the source account and the ban reason. The whole operation is a set of toggles over categories; the raw identifiers never reach the client, the console, or the audit entry's visible fields (the audit entry records that identifiers of each chosen kind were added, by count, not their values).

**The honest-limit note is part of the surface, not a footnote.** Directly under the toggles sits one line of `text-caption` `text-secondary`: "This makes a new account from the same device, email, or number harder and detectable. It is not an absolute block; a determined person can still return. Keep watching the reports." This is here on purpose. Memory and the ban-evasion research are consistent and emphatic: web fingerprinting is probabilistic (40 to 60 percent self-hosted), email is nearly free to regenerate, phone is the strongest signal and is currently off, and the honest framing is "harder and detectable, not impossible." A moderator who believes a ban is a wall will reassure a frightened member that she is safe when she may not be. The surface tells the truth so the moderator can.

**Managing the blocklist** is Owner-only and de-identified. The admin's act is to toggle signals at ban time; she cannot browse the blocklist. The Owner has a read surface (behind AAL2) that lists blocklist entries **by source account @handle, kind, reason, and date**, never by raw hash or value, so the Owner can audit and, if needed, retract an entry (for instance, when a shared family device wrongly caught an innocent person) without ever handling a raw identifier. Retracting an entry is reversible and low-stakes and uses the ordinary distinct-verb confirmation, not the typed gate.

## 7. Reports that name the Owner — OWNER DECISION, SUPERSEDING THIS DOCUMENT'S ORIGINAL RECOMMENDATION

> **⚠️ OWNER OVERRIDE (2026-10-05).** This section originally analysed the "owner-conflict black hole" and recommended routing reports about the Owner to a named independent external recipient (an attorney, trusted third party, or ombudsperson) with a sealed in-app lane and a narrow external review view. **The owner has explicitly and repeatedly rejected that recommendation, and it must not be built.** Her decision, verbatim:
>
> *"reports against me should still go to the admin report panel. that panel should email safety@ every time a report is made so there are two copies completely traceable."*
>
> What follows is the decided design, which migration `20261010000001` implements. The original Options A/B/C analysis is removed so this document cannot be mistaken for an open question; the history is in version control.

### 7.1 The decided design

1. **A report naming the Owner routes `admin_only` and appears in the normal admin report panel, visible to the Owner herself.** There is no sealed lane, no external recipient, no independent-review surface, and no setup task demanding one. The previous `owner_conflict` total-invisibility routing is removed: nothing writes it, and legacy rows were re-routed.
2. **Every report — not only reports about the Owner — also emits an email to `safety@unitedfeminist.com`**, so two independently traceable copies of every report exist: the database row and the email. The email copy is queued durably by the same database transaction that creates the report (`safety_email_outbox`), so a report can never exist without its copy. Per the architecture's "email the notification, not the contents" rule, the copy carries the case reference, time, reason category, and the accused `@handle` — never the reporter, the report text, or any legal name.
3. **A non-Owner staff member still never sees a report that names herself.** The accused-is-the-reviewer exclusion remains for admins, moderators, and reviewers; the Owner is the one deliberate exception, by her own decision.
4. The reporter's experience is unchanged and identical whoever the accused is (P2 section 10.5), and because owner-named reports now live in a worked queue, they reach resolution on the same human timescale as any other report — the "frozen forever at New" leak the original analysis worried about no longer exists.

### 7.2 The honest limit, stated once

On a solely-owned platform there is no technical mechanism that can discipline the Owner: she reads and resolves reports about herself. The owner made this decision knowingly; the design's job is to keep the conflict **visible and witnessed**, not to pretend to resolve it. That is what the email copy does: it lands outside the application database, timestamped, for every report, so no report — including one naming the Owner — can be quietly deleted without the external copy surviving. The hash-chained audit log records every resolution. If a second admin ever exists, nothing here prevents her from reviewing owner-named cases too; they are ordinary `admin_only` cases.

## 8. Audit and accountability

### 8.1 The action trail, in the case and on the account

Every enforcement action already appends to the hash-chained, append-only `audit_log` (Owner-readable, AAL2). This document surfaces that history in the two places a moderator and the Owner actually need it:

- **In the case:** a reverse-chronological action trail at the foot of the detail view: who did what, when, with what rule and note. "Moderator removed a post, 3 Oct, rule: harassment." Staff are shown by role plus `@handle`; this is a staff-only surface, so staff handles are visible to staff, but note that staff identities are not shown to each other across cases by default (the architecture's stance that moderators cannot see each other's identities to prevent off-platform coordination), so the trail names the acting role and shows the specific `@handle` only to admins and the Owner reviewing accountability.
- **On the account:** the account-context strip (3.1) shows the account's prior enforcement history, de-identified and keyed to the handle, so a moderator weighing a new report sees at once whether this is a first lapse or a pattern. This is the single most decision-relevant fact in most cases and the guidelines explicitly say pattern matters.

### 8.2 The Owner's audit-log viewer

The Owner, and only the Owner, behind AAL2 step-up, has a read-only audit-log viewer (a surface in the console available to the Owner role). It presents the append-only log as a filterable, reverse-chronological list (by actor, action type, target, date), and it shows the **hash-chain verification status** prominently at the top: a `success` "Chain verified" state when `verify_audit_chain()` passes, and a `danger` "Chain integrity failed at entry N" state if any row was altered or removed, because an owner-tamperable log is worthless and the one thing the Owner must be able to trust is that the log has not been edited, including by her. The viewer is read-only by construction (no update or delete path exists for the log at any layer), and it never renders a legal name; targets are shown by `@handle` and by the de-identified references the log already stores. The NCMEC and law-enforcement escalation surface (4.8), where legal identity may lawfully be needed, is a distinct Owner-only surface, reached separately, so "I am reading the audit log" and "I am preparing a lawful disclosure" are never the same screen.

### 8.3 What the member sees: "what happened to me"

Accountability runs both ways. A member on the receiving end of an action is told what happened, in plain language, naming the rule and never the reporter, consistent with the guidelines' promise to report an outcome and their promise of reporter confidentiality. The surface is **Settings, Safety, Account status**, plus a notification at the moment of action from the unblockable system account:

- **Warned:** a dismissible notice, in Settings and as a notification: "A post was found to break our rule on harassment. [What the content was.] Please review the guidelines. Nothing has been restricted." It names the rule and the content, never who reported it.
- **Content removed:** the specific post shows the member a **removed stub** reading "Removed by moderation" with the rule and a link to appeal, which is visibly different from a post she deleted herself (which reads as her own action). The distinction is carried by the `post_visibility` states `removed_moderation` versus `removed_author`, so a member always knows whether she hid something or the platform did.
- **Restricted:** a persistent, calm **account-status banner** under the top bar on every surface, built from a `surface-raised` card with a `warning` leading glyph and `text-primary` body: "Your account is limited until 9 Oct. You can read, but you cannot post or reply right now. Reason: [rule]." plus an "Appeal this decision" affordance. It states exactly what is and is not possible and until when.
- **Suspended:** on login, a full interstitial, not a silent failure: "Your account is suspended until 12 Oct. During this time you cannot post, reply, like, follow, or message. Your profile stays visible. Reason: [rule]." with the appeal path. The member is never left guessing why an action failed; the state is explained before she tries anything.
- **Banned:** a terminal screen on login, calm and non-taunting, consistent with the voice of the age-gate rejection (P2 section 17.2): "Your account has been permanently closed. Reason: [rule category]." plus the appeal path and the 30-day window the guidelines promise. `text-primary` on `background` is 14.90; a single calm Phosphor glyph, never a stop sign or a crossed-out face. No access to any in-app surface beyond this screen and the appeal path.

In every case the member learns the **rule** and the **action**, never the **reporter**. The appeal address `appeals@unitedfeminist.com` is a real, working alias named in the legal documents.

### 8.4 Appeals

The guidelines promise a human reviews every appeal, within 30 days of the action, and that a member tells us her handle, what action was taken, and why she thinks it was wrong. The console surfaces this on both ends:

- **Member side.** The Account-status surface (8.3) and the banned terminal screen both carry an "Appeal this decision" affordance. For a member who still has account access (warned, restricted, suspended), it opens a short in-app appeal form (she is a known, authenticated member, so there is nothing new to collect): the action in question is pre-filled, and she writes why she believes it was wrong. Submitting records an appeal tied to the action and notifies `appeals@unitedfeminist.com`. For a **banned** member who cannot reach in-app surfaces, the terminal screen carries the appeal path as an outbound `mailto:appeals@unitedfeminist.com` with a short **case reference code** pre-filled (the same read-only, copyable reference-code pattern the age-gate blocked screen uses, P2 section 17.3), so support can find the case without the member having to expose anything, and so no form collects data from someone locked out. The case reference is the key: it lets an appeal be matched to an action without the member needing to describe internal state.
- **Staff side.** Appeals arrive as their own filtered view in the console, visually distinct from new reports (an appeal is about an action already taken, not a fresh complaint), showing the original action, its audit trail (8.1), the member's stated reason, and the reviewing staff member's decision field. The guidelines' stance that persistence alone does not reverse a decision, but new information or a compelling argument is considered, is a copy and policy matter the surface simply makes room for; the design does not editorialise it. Reversing an action (restoring removed content, lifting a suspension) is reversible and uses the ordinary distinct-verb confirmation. Reversing a **permanent ban** is deliberately an Owner-level act, reached from the appeal via the audit trail, not a one-click undo in a reviewer's hands, because an unrecoverable action's reversal should be as considered as the action was.

---

# PART 2. THE DISCOVER FEED

Discover is the second feed, for finding people and posts beyond the follow graph. The owner insisted on it over an earlier recommendation to hold it back, and she is right that a social platform where a newcomer sees an empty feed is dead on arrival. The brief is to design it well, not minimally. The governing fact that shapes every ranking decision here: **this is a safety-first platform for women, some of whom are hiding from a specific person.** What Discover amplifies, and whom it makes findable, are safety decisions first and growth decisions second.

## 9. What Discover is in Phase 2B, and how it relates to Home

Discover already exists as a surface in the Phase 2 spec: it is one of the two tabs on Home (Following and Discover, P2 section 4.1 and 4.7), not a destination in the nav. **That arrangement does not change, and the shell is not touched.** Discover stays a tab on Home; the desktop left-nav and the mobile five-slot bottom tabs are exactly as the Phase 2 spec defines them. A member switches between Following and Discover with the segmented-tab control already specified (P2 section 4.1): `border-strong` track, `accent` text and a 2px `accent` underline for the active tab, switching at `fast`. A brand-new member with zero follows lands on Discover; once she follows anyone, the default becomes Following and the app remembers her last choice (P2 section 4.7). The post card is identical to the Following card (P2 section 4.2); the only visible difference is the on-card Follow pill, which appears for accounts she does not yet follow (P2 section 4.9). None of that is reopened here.

**What Phase 2B adds is the ranking.** The Phase 2 spec deferred Discover's ordering to "plain reverse-chronological for now, ranked For You in Phase 5." The owner's product direction is more specific and earlier than that: she asked for Discover to show "posts similar to ones they've interacted with positively." Phase 2B is where Discover gets that light, positive-signal ranking. This is a deliberate, owner-directed evolution of the P2 section 4.7 note, and it supersedes only the "plain reverse-chronological" ordering line there; everything else in P2 sections 4.7 and 4.8 (the card treatment, the dismissible "Recent posts from across Hersciety" header, the hide signal, the sparse-cohort states, the interim-moderation note) still stands.

Two framings matter and are kept distinct, so expectations do not run ahead of the build:

- **Discover (Phase 2B) is lightly ranked, not a heavy For You feed.** It still reads as "recent posts and people from across Hersciety," freshness-forward, nudged by your positive signals. It is not an engagement-maximising machine and must never become one. The heavier, model-driven For You feed (with per-post "why you are seeing this" explanations and topical similarity via a vector store) remains Phase 5, as the P2 spec says.
- **Discover is for people and posts both.** The owner framed Discover as finding people, not only reading posts, and on a tiny founding network finding people matters more than ranking posts. So Discover interleaves a **suggested-accounts module** with the post stream (section 12), rather than being a pure post feed.

## 10. Ranking: the positive signals

The ranking combines a small set of positive, safety-compatible signals. Every one of them answers "what does this member genuinely, positively like," never "what will provoke a reaction." The signals, grouped:

**Your own positive affinity (personalisation):**
- **Accounts whose posts you have liked, reshared, or followed.** Likes and reshares and follows are explicit positive acts. More of what you have positively engaged with, from the same authors and from authors like them.
- **Threads you opened and read (dwell on the thread view), when that dwell is followed by a neutral or positive act** (you read it, you did not then block or mute or report the author). Reading time is a positive signal only when it is not the prelude to a protective action; see section 11 for why rubbernecking is explicitly excluded.
- **Profiles you chose to visit and then engaged with** (visited and followed, or visited and liked). A profile visit on its own is weak and ambiguous; a visit that leads to a positive act is a real affinity signal.
- **Topics and hashtags you have positively engaged with.** Derived from the hashtags on posts you liked, reshared, or followed authors of. In Phase 2B this is simple hashtag and author affinity; the vector-based topical similarity is the Phase 5 upgrade.

**Positive signals aggregated across members (quality, not personalisation):**
- **Like and reshare counts on a post.** Positive endorsements from other members, used gently and normalised for author reach so that a small account's genuinely-loved post is not buried under a large account's merely-okay one.
- **Follow-graph proximity:** posts and accounts favoured by the people you already follow (authors your follows follow, posts your follows liked). This is the social-proof signal every healthy discovery feed uses, and it is positive by construction: it surfaces people vouched-for by your own chosen graph.

**Freshness and fairness:**
- **Recency.** Discover is freshness-forward; a post decays in rank as it ages, so Discover stays a living "what is happening" surface and never a stale greatest-hits. This is also what keeps the Phase 2B feed honestly describable as "recent posts from across Hersciety."
- **A small, quality-gated cold-start boost for new authors.** A brand-new member's first good posts get a modest, time-limited lift so new voices can be seen at all in a feed that otherwise rewards accumulated likes. The boost is small, it decays fast, and it is gated so it cannot be farmed; its job is fairness to newcomers, not virality.

The weighting leans toward freshness and your own explicit positive affinity, with aggregate counts and graph proximity as gentle nudges rather than dominant forces, precisely so Discover stays calm and does not tip into chasing whatever is most-liked platform-wide. The exact weights are an empirical tuning question for the build and for the owner's eye on a real screen; the design fixes the signal set and their direction, not their coefficients.

## 11. Ranking: the signals we refuse, and why

This list is as important as section 10, and on this platform it is more important. Each refusal is a safety decision with a reason, and the reasons are stated so a future build cannot quietly add one back for engagement.

- **Reply and comment volume.** Refused. Reply count is the signal most directly correlated with fights, pile-ons, and ratioed posts. Ranking on it amplifies exactly the conflict the platform exists to protect people from. A heavily-replied post is as likely to be a harassment magnet as a good conversation, and Discover must not reward the former.
- **Controversy, divisiveness, and ratio signals** (like-to-reply ratios, "this is blowing up", velocity of disagreement). Refused outright. This is the outrage-amplification pattern that every engagement-optimised feed drifts into, and it is categorically incompatible with a safety-first platform. Discover will never surface a post because it is dividing people.
- **Report, block, and mute counts as amplification.** Refused as amplification, hard. Negative attention is still attention, and a naive "engagement" metric would treat a much-reported account as "interesting." It is not. Reports, blocks, mutes, and hides are used **only to suppress and to remove**, never to boost. An account many people have reported or blocked is a candidate for the moderation queue, not for the top of Discover.
- **Negative-reaction velocity** ("trending because people are angry"). Refused, for the same reason as controversy: anger is a reaction, and this feed does not rank on reactions, only on positive endorsement.
- **Dwell time that precedes a protective action** (rubbernecking). Refused. If you lingered on someone's profile or thread and then blocked, muted, or reported them, that dwell is the opposite of affinity and must never be read as interest. Dwell counts as positive only when it is not the prelude to protection (section 10).
- **Quote-dunk and pile-on chains.** Refused. A quote post that drives a crowd onto an original author is a harassment vector, not a discovery signal, and its engagement must not lift either the quote or, through it, the target.
- **Any contacts, phone-book, or "people you may know" signal, and any surfacing based on who viewed whom.** Refused, and this is the one that matters most for the core threat model. Discover must never suggest an account because it is in someone's contacts, because a phone number matched, or because that person viewed her profile. A member hiding from a specific man must not be surfaced to him because he looked her up, imported his contacts, or shares a network edge with her. Discovery here flows only from a member's own positive, outward acts (what she likes and follows and reads), never from someone else's attempt to find her. People search stays exact-and-prefix `@handle` only, as locked (the structural defence against turning discovery into a people-finder), and Discover adds no softer path to the same deanonymisation.

The through-line: **Discover ranks on what members positively choose to embrace, and refuses every signal that measures conflict, negative attention, or someone else's attempt to locate a person.** That is the owner's "interacted with positively" instinct followed all the way to its safety conclusions.

## 12. Empty and cold-start states

The network is tiny right now, and a sparse Discover must never read as a dead product. The Phase 2 spec already ruled out spinners-to-empty and specified a sparse end-of-feed card rather than an endless loader (P2 sections 4.7, 9.1). Phase 2B makes the thin-network experience a designed, warm, founding-cohort experience rather than an absence:

- **Discover is never empty for a logged-in member,** because on a small network Discover is effectively "recent posts and people from across Hersciety" (the whole platform is the discovery pool), ordered by section 10. Even a member with zero interaction history gets a populated feed: with no personal affinity yet, the ranking falls back to freshness plus gentle aggregate positive signals plus the founding cohort and the system announcements, so the first session is a real feed, not a prompt to come back later.
- **A people-first cold start.** For a member with few or no follows, the top of Discover leads with a **suggested-accounts module**, not posts, because the fastest way out of an empty experience on a tiny network is to follow a few people. The module is a small set of account cards (avatar, `@handle`, a one-line self-description, a Follow pill, the P2 section 3.6 pattern), drawn from the founding cohort, the owner's account, and accounts your early positive signals point toward. It uses the same identity block and Follow mechanics as everywhere else, so it needs no new learning, and it never shows a legal name.
- **A warm, honest sparse state at the end of the feed.** When a member reaches the end of a thin Discover, the end-of-feed card says so plainly and frames the newness as an invitation, not a failure: "You are all caught up. Hersciety is new, and you are early. Follow a few people, or be one of the first voices here," with a Compose affordance and a link to the suggested-accounts module. This is the "be the first voice" founding posture the Phase 2 spec already set for empty states (P2 section 9.6, section 14 point 10), applied to Discover. It reads as early-days energy, never as a broken feed.
- **No fake liveliness.** The sparse states never invent activity, never show placeholder accounts, and never pad the feed with system noise to look busier than it is. A founding member can tell the difference between "early and real" and "fake and desperate," and the former builds the trust this platform runs on.

## 13. Safety filtering in Discover, and staying undiscoverable

Discover is the widest public surface, so the member-facing safety controls apply here with full force, and the one new privacy control the brief asks for lives here.

- **Block and mute hard-filter Discover.** An account you have blocked or muted never appears in your Discover, in either direction: you do not see them, and, for blocks, they do not see you (the block already removes your profile and posts from the blocked person's surfaces at the data layer). Blocking is mutual invisibility, and Discover is not an exception to it. This is a hard server-side filter, identical to the Following and thread read paths, which already exclude muted and blocked authors.
- **Hide ("show me less") down-ranks, it does not hard-filter.** Per P2 section 4.8, hide is the lightest negative signal and means "show me less from this account," not "block." In Discover, a hidden account's posts are strongly suppressed and pushed down, consistent with the P2 spec's statement that in Phase 2B's ranked Discover a hidden account is "shown noticeably less." Hide is a tuning signal, not a wall, and it never notifies the other person.
- **A member can keep herself out of Discover.** The brief asks for a way for a member to be found only by people she gives her handle to. Phase 2B adds one privacy control, in Settings, Privacy (extending P2 section 8.2): **"Discoverability: suggest my account and posts in Discover."** When a member turns this off, her posts are excluded from every member's Discover ranking and her account is excluded from the suggested-accounts module, so she is not surfaced to strangers. She remains fully reachable by **exact `@handle`** through people search (which is exact-and-prefix handle only, as locked), so the people she chooses to give her handle to can still find and follow her. This is the "found only by people I give my handle to" posture, expressed as one clear toggle with a plain-language caption beneath it: "When this is off, your posts and account will not be suggested to people who do not already follow you. People who know your @handle can still find you."

**One genuine default question, flagged and not decided here.** Whether Discoverability defaults on or off is a values call for the owner, and it is a real one, not invented homework (section 17). Default on makes Discover work for the tiny founding network and matches the already-pseudonymous public model (handle-forward, legal name never shown); default off is the maximally cautious posture for a platform whose users include people hiding from someone, at the cost of a Discover feed that cannot see most of the cohort. The design supports either; the recommendation leans to default on with the opt-out made prominent at signup and in Settings, because the public surface is already pseudonymous and the legal name is already structurally protected, so being discoverable by handle and posts is a materially smaller exposure than the legal-name exposure the product already guards against. The owner should make this call with that framing in front of her.

---

## 14. Accessibility notes specific to Phase 2B

Everything in the Phase 2 accessibility specification (P2 section 12) is inherited unchanged: 44x44 minimum targets, visible focus (2px `focus-ring`, 2px offset), full keyboard operation, focus-trapped and Escape-dismissable modals that restore focus to their trigger, reduced-motion fallbacks, and colour independence. The additions specific to the surfaces in this document:

- **Every status and priority chip carries its meaning in its word and its glyph, never in colour alone** (section 2.2). A screen-reader user hears "Critical" and "Actioned"; a low-vision user reads the label and sees the glyph shape; the semantic colour is reinforcement only, the same exemption basis as the thread rail (P2 section 2.3, 12.6).
- **The console's destructive confirmations are focus-trapped `role="dialog"` modals** with the safe choice holding default focus, Escape to cancel, and focus returned to the triggering control on close, exactly as the member block confirmation already works (P2 section 10.2). The ban typed-gate field is a labelled input; the destructive button exposes its disabled state to assistive tech and announces, when it enables, that confirmation is now possible.
- **The in-case thread context (3.2) conveys nesting with correct heading and list structure and an explicit "replying to @handle" relationship, not by indentation alone** (P2 section 12.4), and the reported reply is marked for assistive tech with a label ("Reported reply"), not only by its colour band.
- **The account-status banners and the suspended and banned screens (8.3) are announced and are not dependent on colour**; the state is carried in the text ("suspended until 12 Oct"), and the reference code on the banned appeal path is exposed character by character via `aria-label` exactly as the age-gate reference code is (P2 section 17.3), so "4F2A" is not misread as a word.
- **The queue-volume summary and the Critical dot are reachable and announced but never steal focus**, the same rule the Phase 2 spec applies to the new-posts pill and toasts (P2 section 12.2).

## 15. Motion notes specific to Phase 2B

All motion inherits the existing durations and easings and degrades under reduced motion (P2 section 13). Phase 2B adds no new motion. Specifically: the console's two-pane list-to-detail selection is an instant content swap on desktop and the standard push slide on mobile (P2 section 1.4); confirmation modals use the existing modal fade-plus-scale (240, enter) and bottom sheets the existing sheet slide (320, enter); toasts after an enforcement action use the existing toast slide-plus-fade (180, base); the in-case thread-context expander opens with the same restraint as the rest of the product, and under reduced motion it is instant. There are no decorative, looping, or attention-seeking animations in the console or in Discover; a moderation tool that animates for delight would be exactly wrong, and a discovery feed that animates to pull engagement would violate the whole positive-signal posture.

## 16. Tokens: what Phase 2B adds, and what it deliberately does not

**Phase 2B introduces no new color, type, spacing, radius, elevation, or motion token.** Both surfaces are built entirely from the inherited system (P2 section 2, section 15) plus two documented compositions of existing tokens. This is deliberate: the strongest way to keep a privileged surface and a wide public surface feeling like the same calm product is to deny them any private palette of their own.

The two compositions, listed explicitly as the brief requires, are reuse, not new tokens:

- **Status chip** (section 2.2): a neutral chip on `surface` with a `border` hairline outline, a `text-secondary` or `text-tertiary` label, and a leading Phosphor glyph whose Fill colour is the semantic token for that state (`accent` for New and In review, `success` for Actioned, `warning` for Escalated, `text-tertiary` for No action). The label text uses measured neutral pairings (`text-secondary` on `surface` 7.25; `text-tertiary` on `surface` 4.88 light / 5.11 dark, both from the base system). The glyph colour is reinforcement, exempt from 1.4.11, because the word carries the meaning.
- **Priority chip** (section 2.2): identical in construction, except the single Critical chip is the one filled chip, `danger-fill` with a white label, measured 5.62 light / 4.83 dark (P2 section 2.3). High and Normal use the neutral construction.

Every other pairing this document relies on is already measured and is reused verbatim:

| Pairing | Used for | Light | Dark | Source |
|---|---|---|---|---|
| `accent` on `accent-subtle` | console identity strip label, In-review chip | 6.03 | 5.55 | P2 2.3 |
| `text-secondary` on `accent-subtle` | identity strip role caption | 6.52 | 6.90 | P2 2.3 |
| ~~`text-primary` on `accent-subtle`~~ | ~~sealed-case and setup-task card body~~ | ~~14.35~~ | ~~13.20~~ | Removed — the sealed owner-conflict lane and the independent-contact setup task no longer exist; see section 7. |
| white on `danger-fill` | Critical chip, destructive buttons' fill | 5.62 | 4.83 | P2 2.3 |
| `danger` on `surface-raised` | destructive action rail items on the popover | 5.62 | 5.49 | P2 2.3 |
| `text-tertiary` on `surface` | counts, times, locked duration chips | 4.88 | 5.11 | P2 2.3 |
| `text-tertiary` on `surface-raised` | removed-content stub text | 4.88 | 4.58 | base |
| `border-strong` on `surface` | typed-gate input outline, duration field | 3.47 | 3.52 | P2 2.3 |
| `text-primary` on `surface-raised` | reference-code block on the appeal path | 16.91 | 13.27 | P2 2.3 |
| `text-primary` on `background` | banned terminal screen body | 14.90 | (base) | base |
| `text-secondary` on `background` | account-status and appeal copy | 6.77 | 8.46 | P2 2.3 |
| `accent` on `background` | appeal `mailto:` link | 6.26 | 6.80 | P2 2.3 |
| `warning` on `surface` | restriction banner glyph and caption | 4.74 | (base) | P2 2.3 |

Nothing here is new to measure. If the owner or a future revision ever decides the status set deserves to be promoted from a documented composition to real named tokens, that is a tidy-up, not a design change, and it would not alter a single ratio above.

## 17. Open questions that genuinely need the owner

Kept short and real. Everything else in this document is a professional design decision already made.

1. ~~**Name an independent contact for reports that name the Owner (section 7).**~~ **RESOLVED BY OWNER DECISION, 2026-10-05 — and resolved the other way.** Reports naming the Owner go to the normal admin report panel, visible to her, and every report also emails a traceable copy to `safety@unitedfeminist.com`. No independent contact exists or is pending; do not re-raise this.

2. **Discoverability default: on or off (section 13).** Whether a member is suggested in Discover by default. Recommendation: default on, with a prominent opt-out at signup and in Settings, on the grounds that the public surface is already pseudonymous and the legal name is already structurally protected, so handle-and-post discoverability is a much smaller exposure than the one the product already guards. A real values call, framed, for the owner to confirm or flip. *(Decided 2026-10-07: discoverable by default, with a settings toggle to turn it off.)*

These are the only two. Every other call in this document (the calm queue-volume treatment, the case-grouping model, the in-case thread context, the per-action confirmation gradient, the typed ban gate, the de-identified ban-evasion toggles, the full Discover signal set and refusals) is made here and does not need the owner's time.

---

## 18. Summary of deliverables for the Phase 2B build

An engineer implementing Phase 2B from this document builds, for the moderation console: the role-gated console surface reached from the account menu with its calm identity strip (section 1); the case-grouped report queue with triage-state and priority chips, filtering and sorting, and queue volume shown without alarm (section 2); the report detail view that renders a reported reply in its thread context without leaving the console, protects reporter identity while surfacing report-abuse, and limits bulk action to the two non-destructive operations (section 3); the enforcement ladder (dismiss, warn, remove, restrict, suspend, ban) with role gating, the 7-day suspension boundary expressed as a property of the duration control rather than an after-the-fact error, Admin-only permanent ban, and the Owner-only child-safety and law-enforcement escalation (section 4); the irreversibility rule applied as a per-action confirmation gradient with distinct verbs, placements, weights, and a typed `@handle` gate on the one unrecoverable action (section 5); the moderator-facing ban-evasion controls that extend a ban to future accounts through de-identified category toggles and never expose a raw identifier, with the honest-limit note on the surface (section 6); the owner-decided handling of reports that name the Owner — the normal admin panel plus a traceable email copy of every report to safety@ (section 7); and the audit and accountability surfaces, the Owner's hash-verified audit viewer, the member-facing "what happened to me" states, and the appeals path on both ends (section 8).

For Discover: the positive-signal ranking layered onto the existing Home Following-and-Discover tab without touching the shell (sections 9, 10); the explicit refusal of conflict, negative-attention, and person-finding signals (section 11); the warm, people-first, never-fake cold-start and sparse states (section 12); and the safety filtering plus the one new Discoverability privacy control that lets a member be found only by the people she gives her handle to (section 13).

It stays within the existing token system, adding no new token and only two documented compositions of existing ones (section 16), and both of section 17's owner decisions are now made (section 17). Every moderation surface identifies every person by `@handle` and never by legal name (constraint 0.1), and no destructive action is ever distinguishable from its neighbour by so little that a reflex can fire the wrong one (constraint 0.2). Those two constraints are the whole reason this part of the product has to be built with more care than any other, and they are not negotiable.
