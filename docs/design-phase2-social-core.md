# United Feminist, Phase 2: Visual and UX Design Direction for the Social Core

**Status:** Design specification for the Phase 2 build. This document defines look, feel, information architecture, component anatomy, states, and rules. It is not code and does not define components in a framework. An engineer should be able to build Phase 2 from this plus the existing token system without guessing.

**Date:** 2026-10-02

**Design thesis (inherited, not reopened):** "Calm paper, sharp tools." A warm, low-glare sand neutral canvas carries the content; a single Iris-violet accent carries interaction; safety and capability sit one tap away, always labeled, never buried. Warmth lives in the neutrals, never in pink.

**Reference product:** Threads, for its philosophy only (simple reading surface, sophisticated capability underneath). The visual and structural language here is deliberately distinct from Threads. See section 15.

**What Phase 2 is:** posting, the home feed, threaded replies, likes, reshares, follows, profiles, people search, in-app notifications, the settings area, and first-class block/mute/report. Direct messages, image upload, and the algorithmic "For You" feed are later phases and are referenced here only where the shell has to leave room for them.

---

## 0. How to read this document

- **Tokens** are the ones already implemented in `src/app/globals.css`. They are named exactly as the CSS custom properties and Tailwind theme names in that file (for example `surface`, `text-secondary`, `accent-subtle`, `radius-lg`, `shadow-e1`, `text-body-lg`). Where this document proposes a change or addition, it is called out in section 16 and nowhere else silently.
- **Spacing** uses the base-4 scale already defined: 0, 2, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64, 80 (pixels).
- **Type roles** are the eight already defined: display, title, heading, body-lg, body, label, caption, micro. Content (posts) is body-lg at 17px. UI chrome is body at 15px. This content-dominant hierarchy is deliberate and is kept.
- **Contrast:** every new foreground/background pairing introduced here is listed with its measured ratio in section 2.3. The target is WCAG 2.2 AA: 4.5:1 for normal text, 3:1 for large text (greater than or equal to 18.66px bold or 24px regular) and for non-text UI boundaries that are the sole identifier of a control.
- **Icons** are Phosphor (MIT). Regular weight is the inactive state; Fill weight is the active or selected state. Named glyphs in this document map to real Phosphor icons.

---

## 1. The application shell

The shell is the frame every screen lives in. It must work as responsive web first and must translate cleanly to native later, so nothing in it depends on a web-only affordance (no hover-only actions, no right-click menus, no keyboard-only paths without a visible equivalent).

### 1.1 Three navigation destinations plus compose

There are exactly five primary surfaces. Keeping the set small is the whole point of the "simple surface" thesis.

1. **Home** (the feed). Glyph: House.
2. **Search** (people now, posts in Phase 5). Glyph: MagnifyingGlass.
3. **Compose** (the action, not a destination). Glyph: PencilSimple inside a raised accent control.
4. **Notifications.** Glyph: Bell, with an unread count.
5. **Profile** (your own). The avatar itself is the nav item, no generic icon.

Settings is reached from Profile and from an account menu, not from the primary nav. It is a management surface, not a browsing destination, so it does not earn a top-level slot.

### 1.2 Desktop and large tablet (greater than or equal to lg, 1024px)

Three-column frame, centered on the viewport:

- **Left rail, fixed width 240px.** Vertical nav. Each item is an icon plus a label at `text-label`, laid out in a row, min height 44px, padding 12px horizontal. The active item uses the Fill-weight icon, `accent` text color, and a 2px `accent` indicator bar on the inner edge (left edge of the rail content). Inactive items use Regular icons and `text-secondary`. Hover raises the row background to `surface-raised` in light and lifts one surface step in dark (see 1.6 on hover). Below the nav sits a single raised **Compose button**: full width of the rail minus 16px padding each side, `accent-fill` background, `on-accent` label, `radius-full`, min height 48px, `shadow-e1`. At the very bottom, an **account control**: avatar plus @handle plus a CaretUp, opening a small menu (Settings, Switch appearance, Log out).
- **Center column, the feed, fixed max width 600px.** This is the reading measure, roughly 66 characters at 17px. It never grows wider, so posts stay readable on a 27-inch monitor. Gutters of 24px separate it from the rails.
- **Right rail, 320px, appears only at xl (1280px) and up.** In Phase 2 it holds a persistent **Search field** at the top (so search is reachable without leaving the feed) and a **"Getting started" checklist** card for new accounts (see 10.5). It is additive: at lg the feed simply centers with the left rail and no right rail, and nothing is lost because search also exists as a left-rail destination. The right rail must never hold anything that is the only way to reach a function.

The overall page background is `background`. The feed column sits on `background` with its cards on `surface` (see section 5). Rails sit on `background` with no card chrome, so the eye reads one calm plane with the content column raised slightly out of it.

### 1.3 Mobile and small tablet (less than lg)

- **Bottom tab bar, fixed, 5 slots:** Home, Search, Compose, Notifications, Profile. Height 56px plus the device safe-area inset at the bottom. Background `surface`, top hairline `border`, `shadow-sticky`. Each tab is a 44x44 minimum target centered in its slot. Active tab: Fill icon, `accent`. Inactive: Regular icon, `text-secondary`. The Notifications tab shows a count badge (see 4.6). The Compose slot is visually weighted: its icon sits inside a 44px `accent-fill` rounded square (`radius-md`) with `on-accent` glyph, so compose reads as the primary action even in a flat row. Labels under icons are optional and off by default to save vertical space; the icons are standard enough and each has an `aria-label`. If user testing shows confusion, labels turn on at `text-micro`.
- **Top bar, 48px, sticky, `shadow-sticky`.** Left: contextual. On the feed it shows the wordmark "United Feminist" at `text-heading`. On a thread or profile it shows a back affordance (CaretLeft, 44x44) plus the screen title at `text-heading`. Right: contextual overflow or a single contextual action. The top bar is deliberately thin because the feed is the star.
- Compose is also reachable as a floating action is **not** used on top of the bottom bar, to avoid two compose entry points competing. The bottom-bar Compose slot is the single mobile entry point.

### 1.4 Movement between surfaces

- Tapping a primary nav item switches surface with an instant crossfade of content (no slide between top-level tabs; slides are reserved for push navigation into detail). Scroll position per tab is preserved when you return to it.
- Tapping a post opens the **thread view** as a push (slide-in from the right on mobile, in-place on desktop with the thread replacing the feed column). A back affordance always returns to the exact feed scroll position.
- Tapping an avatar or @handle anywhere opens that **profile** as a push.
- The composer opens as an overlay (modal on desktop, bottom sheet on mobile) over whatever surface you are on, so composing never loses your place. See section 6.
- Settings opens as a full push surface with its own internal nav (see section 9).

### 1.5 The frame and reading rhythm

One vertical rhythm governs the whole app: 4px base, with 16px as the default breathing unit between unrelated blocks and 8px to 12px between related elements inside a block. The feed column has 0 horizontal padding on its outer edge at desktop (cards carry their own padding) and 0 on mobile as well, with cards spanning edge to edge on small screens (see 5.3 on the mobile density choice).

### 1.6 Hover and row-fill rule (applies shell-wide)

Reserve the Iris accent for things that are interactive-and-selected or that represent the brand. Do not tint every hover purple; on a dense feed that becomes noisy and starts to read as decoration rather than meaning. The rule:

- **Navigation and controls** (nav rows, menu items, tabs): hover and selected states may use `accent-subtle` and `accent`.
- **Content rows** (post cards, list rows, conversation rows): hover uses a neutral surface step, not accent. In light, a hovered post card goes from `surface` to `surface-raised`. In dark, it lifts one surface step (`surface` to `surface-raised`). This keeps the feed calm and makes the accent meaningful when it does appear (links, the active like, the compose button).

---

## 2. Token foundation

### 2.1 What is inherited unchanged

The entire existing token system is built to, not redesigned. That means: the two themes and all their color values; the eight-step type scale; the base-4 spacing scale; the radius scale (sm 6, md 10, lg 14 for cards, xl 20 for modals, 2xl 28 for bottom sheets, full for avatars and pills); elevation e1 for cards, e2 for popovers and toasts, e3 for modals and sheets, plus the sticky treatment; the motion durations and easings; the Phosphor icon set with Regular-inactive and Fill-active; and the breakpoints sm 480, md 768, lg 1024, xl 1280.

### 2.2 What Phase 2 adds

One new decorative token and two derived helpers. Full reasoning is in section 16. In brief:

- `--thread-rail`: the reply-nesting guide color, Iris accent at approximately 16% alpha. Decorative only.
- `--skeleton-base` and `--skeleton-sheen`: loading-placeholder colors derived from existing neutrals (see section 12). Decorative only.

No new text color, no new accent, no new semantic color is introduced. Everything readable reuses an existing, already-measured token.

### 2.3 New contrast pairings introduced in Phase 2, with measured ratios

These are the foreground/background combinations this document relies on that were not already enumerated in the base system. All pass WCAG 2.2 AA for their use. Ratios computed with the sRGB WCAG formula.

| Pairing | Use | Light | Dark |
|---|---|---|---|
| text-primary on accent-subtle | Welcome card and announcement card body text | 14.35 | 13.20 |
| text-secondary on accent-subtle | Secondary copy inside accent-subtle cards | 6.52 | 6.90 |
| accent on accent-subtle | Links and labels inside accent-subtle cards | 6.03 | 5.55 |
| danger on danger-subtle | Destructive menu item and inline danger text on a tinted row | 4.83 | 6.20 |
| warning on surface | Composer counter in the soft-limit band | 4.74 | (uses warning on surface, see base) |
| text-tertiary on surface | Timestamps, counts, metadata | 4.88 | 5.11 |
| border-strong on surface | Input, segmented-control, and sole-identifier control outlines (non-text, target 3:1) | 3.47 | 3.52 |
| accent on background | Links and active icons sitting directly on the page background (rails) | 6.26 | 6.80 |

The `--thread-rail` color is intentionally below 3:1. It is exempt from WCAG 2.2 success criterion 1.4.11 because it is not the sole means of conveying reply nesting: indentation and each reply card's own `border-strong` boundary carry the structure, and the rail is reinforcement. A low-vision user who cannot see the rail still reads the thread correctly from the indentation steps and the card boundaries. See 7.3.

---

## 3. Shared component primitives

These are the small parts every screen reuses. Defining them once keeps the feed, threads, and profiles consistent.

### 3.1 Avatar

- Shape: `radius-full`. Sizes: 48px (post card, profile row), 40px (reply, compact lists), 32px (nested reply, notifications), 24px (inline mentions, stacked facepiles), 96px (profile header on mobile), 128px (profile header on desktop).
- No photo state: a solid `accent-subtle` fill with the member's first handle letter in `accent`, at a weight and size proportional to the avatar. This is the default for a brand-new platform where most people have not uploaded a photo, so it must look intentional, not broken. The letter is centered, `micro`-to-`heading` sized by avatar size.
- Every avatar is a link to the profile and carries an `aria-label` of the @handle.

### 3.2 Identity block (the single most important recurring unit)

This is where the locked identity rule lives, so it is specified exactly. The identity block appears on every post card, reply, notification, and list row.

- **Primary line: `@handle`**, at `text-label` weight 600, `text-primary`. The @ is part of the string and is not dimmed. This is the forward identity everywhere in the feed, threads, notifications, and search. The handle is the clickable name.
- **Secondary, same line, after the handle: a middot and the relative timestamp** at `text-caption`, `text-tertiary` (for example `@maya · 2h`).
- **No legal name appears in the feed, ever.** The legal name is a profile-only, opt-in element (see 8.2). There is no code path in any feed, thread, notification, search result, or list row that renders `display_name`. The feed reads from `handle` only. This is a hard rule: a mistake here is a safety incident, not a cosmetic bug.
- **Founding-member badge** (optional, from the schema's `founding_member` boolean, which carries zero privileges): a small `accent-subtle` pill with `accent` text at `text-micro`, reading "Founding", placed after the timestamp. It is a cohort marker, not a verification claim, and it must never be confused with a legal-name display. If the owner prefers not to surface it at launch, it is a single flag.

### 3.3 Icon button

- Target: minimum 44x44 touch, with the live glyph at 20px to 24px centered. Default `text-secondary`, hover `text-primary` on a neutral row-fill (content context) or `accent` on `accent-subtle` (control context, per 1.6). Pressed: scale 0.97 for 120ms (killed under reduced motion).
- Every icon button has a visible-on-focus ring (2px `focus-ring`, 2px offset) and an `aria-label`. Icon-only buttons additionally get a tooltip on desktop after a short delay, but the tooltip is never the only label.

### 3.4 Overflow menu

- Trigger: DotsThree icon button. Opens a popover (desktop, `shadow-e2`, `radius-md`) or a bottom sheet (mobile, `radius-2xl` top, `shadow-e3`).
- Items are icon-plus-label rows at `text-body`, min height 44px. Destructive items use `danger` text. The Safety group (see section 11) is always pinned at the top of this menu for any content authored by someone other than the viewer, above generic actions like Copy link.

### 3.5 Toast

- Appears bottom-center on mobile (above the tab bar) and bottom-left on desktop. `surface-raised`, `shadow-e2`, `radius-md`, `text-body`. Carries an optional single inline action (for example "Undo" after a mute). Auto-dismiss after 5s; the action pauses dismissal on focus. Enter and exit are slide-plus-fade at `base` duration (opacity-only under reduced motion). Toasts announce via an `aria-live` polite region.

### 3.6 Button and pill (from the existing kit, with Phase 2 additions)

The existing Button variants (primary, secondary, danger, ghost) stand. Phase 2 adds one **follow control** pattern that is used often enough to standardize:

- **Follow (not following):** `secondary` style (bordered, `border-strong`, `surface` fill, `text-primary` label), label "Follow".
- **Following (hover or focus reveals Unfollow):** filled low-emphasis using `accent-subtle` background and `accent` text, label "Following". On hover or focus it swaps to a `danger`-text "Unfollow" so the destructive outcome is visible before the tap. On mobile, where there is no hover, tapping "Following" opens a small confirm sheet ("Unfollow @handle?") rather than unfollowing instantly, so a mis-tap does not silently drop a follow.
- Min height 36px in compact rows, 44px as a standalone control. Pill shape (`radius-full`).

---

## 4. The home feed

The feed is the single most important screen and the one the owner called dead. It is dead today only because Phase 2 does not exist yet. The job here is to define a feed that is alive and calm at the same time, and that still feels intentional when it is nearly empty (see section 10).

### 4.1 Feed structure

- **Feed header (sticky under the top bar).** A two-item segmented control: **Following** and **Discover**. Following is the reverse-chronological feed of people you follow and is the default. Discover is a lightweight reverse-chronological stream of recent public posts from across the platform (not the algorithmic For You feed, which is Phase 5). Discover exists in Phase 2 specifically so that a new account with zero follows still has something real to read on day one. The segmented control uses `border-strong` for the track, `accent` text plus a 2px `accent` underline for the active segment, and `text-secondary` for the inactive. Switching segments crossfades at `fast`.
- **Composer entry affordance** sits at the very top of the Following feed on desktop and tablet: a single-line, tap-to-expand prompt row (see 6.2). On mobile the top-of-feed prompt is also present but secondary to the bottom-bar Compose button.
- **The post list:** a vertical stack of post cards.
- **New-posts pill:** when new posts arrive above the current scroll position, a floating pill ("3 new posts", `accent-fill`, `on-accent`, `radius-full`, `shadow-e2`) appears pinned near the top center. Tapping it scrolls to top and loads them. It never auto-jumps the reader. Under reduced motion the scroll is instant rather than animated.

### 4.2 Post card anatomy

A post card is the atomic unit. Top to bottom, left to right:

1. **Avatar**, 48px, top-left, links to profile.
2. **Identity block** (3.2): `@handle` primary, `· 2h` after it, optional Founding pill. On the far right of this row, a **DotsThree overflow** icon button (44x44), which opens the overflow menu with Safety pinned at top (section 11).
3. **Body text**, `text-body-lg` (17px), `text-primary`, with generous line height (26px). Max 500 characters per the data model. Links, @mentions, and #hashtags render in `accent`; mentions and hashtags are tappable. Body preserves line breaks. A post that is only a reshare or quote renders the quoted card inline (see 4.4).
4. **Media** (Phase 3, but the slot is defined now): below the body, a `radius-md` image block constrained to the card width, max height roughly 1.5x the card width, with a blurhash placeholder. In Phase 2 this slot is simply absent.
5. **Action row:** four actions, evenly spaced, each a 44x44 target with a Regular Phosphor glyph plus a count at `text-caption` `text-tertiary`:
   - **Reply** (ChatCircle). Opens the composer in reply mode.
   - **Reshare** (Repeat). Tapping opens a tiny two-item sheet: Reshare, or Quote. Active (you have reshared) uses Fill plus `success` or `accent`; pick `accent` to keep the color story tight.
   - **Like** (Heart). Active uses Fill plus `accent`. The like pop animation (scale 1 to 1.15 to 1 over 240ms) fires on activation; under reduced motion it is an instant fill swap.
   - **Share / copy link** (optional in Phase 2; if included, Export or LinkSimple glyph, opening the native share sheet or copying the permalink).
   - Counts are hidden when zero rather than showing "0", so an empty new platform does not read as a wall of zeros. The glyph alone is shown until the first interaction exists.
6. The entire card (except interactive children) is a tap target that opens the thread view.

### 4.3 Density, rhythm, and separators

This is where the feed earns "calm paper."

- **Card padding:** 16px on all sides on desktop and tablet; 16px on mobile as well.
- **Separation between cards:** the design uses a hybrid of card and row. Posts are **not** fully detached floating cards with large gaps (that wastes vertical space and reads as heavy), and they are **not** borderless hairline rows (that is the Threads pattern and is too flat and too close to Threads trade dress). Instead:
  - Each post sits on `surface`.
  - Posts are separated by a **single `border` hairline** that runs the full width of the feed column, with no rounded corners between adjacent posts.
  - The feed column as a whole has a `radius-lg` outer boundary on desktop and tablet (so the column reads as one calm sheet of paper), with `shadow-e1` and a `border` outline. On mobile the column is edge to edge with no outer radius.
  - The result: a continuous reading surface, gently raised off the page, with quiet internal dividers. It is denser than detached cards, warmer and more structured than hairline rows, and visually its own thing.
- **Vertical rhythm inside a card:** 12px between the identity row and the body, 12px between body and the action row. The action row glyphs align to a 4px grid.

### 4.4 Quote and reshare rendering

- **Reshare (no added text):** a slim attribution line above an otherwise normal post card, at `text-caption` `text-tertiary` with a Repeat glyph: "@you reshared". The underlying post renders as a standard card.
- **Quote:** your post renders normally, and the quoted post renders inside it as a **nested compact card**: `surface-raised` fill (or `background` in dark to step down), `border`, `radius-md`, 12px padding, 40px avatar, identity block, and body truncated to about 4 lines with a "Show more" affordance. The nested card is tappable to the quoted thread. It never nests more than one level deep in the feed (a quote of a quote shows only the immediate quoted post).

### 4.5 Reply-control indicator

Posts carry a reply-control setting (Everyone, People you follow, Mentioned only). When a post is not open to everyone, a small `text-caption` `text-tertiary` line with a Users or At glyph appears just above the action row: "People @maya follows can reply" or "Only mentioned people can reply". This sets expectations before someone taps Reply and finds they cannot post.

### 4.6 Counts and badges

- Notification unread count: a `danger-fill`-free, `accent-fill` numeric badge with `on-accent` text at `text-micro`, capped at "9+". Placed on the Bell icon. Using accent rather than red keeps alerts from feeling like errors and keeps the palette coherent. (Red is reserved for destructive and error states.)
- Like, reply, and reshare counts: `text-caption` `text-tertiary`, hidden at zero.

---

## 5. The post composer

The composer must be fast, forgiving, and unmistakably safe to use. It appears in two forms from one component.

### 5.1 Inline prompt (entry affordance)

At the top of the Following feed and on the profile's own posts tab, a single collapsed row: the viewer's 40px avatar, a `text-body` `text-tertiary` placeholder ("Share something with the community"), and a small disabled-looking (but focusable) compose glyph. Tapping anywhere on the row, or focusing it via keyboard, expands it in place into the full composer on desktop, or opens the bottom sheet on mobile.

### 5.2 Full composer surface

- **Desktop:** a centered modal, `surface-raised`, `radius-xl`, `shadow-e3`, max width 560px, with a `scrim` behind it. A Close (X) at top-left, the title "New post" at `text-heading` centered or left, and the primary **Post** button at top-right.
- **Mobile:** a bottom sheet, `radius-2xl` top corners, `shadow-e3`, sliding up at `sheet` duration (320ms, opacity-only under reduced motion). Same header controls. The sheet can grow to full height as content and the keyboard appear.
- **Body field:** `text-body-lg` (17px, matching how the post will read), auto-growing from about 3 lines, `text-primary`, placeholder in `text-tertiary`. The field is the focus on open; the keyboard is summoned immediately on mobile.
- **Avatar** of the author sits to the left of the field at 40px, grounding whose voice this is.

### 5.3 Empty state of the composer

When empty, the composer shows the avatar, the placeholder prompt, and a dimmed Post button (disabled until there is non-whitespace content). Below the field sits the action bar (5.5). Nothing shouts. The empty composer should feel like a clean sheet, not a form.

### 5.4 Character handling

- The limit is 500 characters (data model). There is **no visible counter until the user is within the last 60 characters** (the soft-limit band). Showing a counter from character one makes every post feel like a constraint; revealing it late keeps the surface calm while still protecting the limit.
- At 440 to 500 characters: a small numeric remaining-count appears near the Post button in `warning` color on `surface` (measured 4.74:1), counting down.
- At the limit: the count turns `danger`, further input is prevented (not silently truncated), and the Post button is disabled with an inline `text-caption` `danger` note "You have reached the 500-character limit."
- The counter is also exposed to assistive tech via `aria-live` polite, announced only when it changes within the soft-limit band, so screen-reader users are not spammed.

### 5.5 Composer action bar and the audience control

Below the field, a single row:

- **Left: attachment affordances.** An Image glyph (ImageSquare) for photo attach. In Phase 2 this is present but disabled with a tooltip "Photos arrive soon" if media is not yet shipped, or hidden entirely if the team prefers not to show a dead control. Recommended: hide it in Phase 2 and introduce it in Phase 3, so nothing looks broken. (Flagged as an open decision in section 18.)
- **Left, second: the audience / reply-control chip.** A pill at `text-label` with a Users glyph showing the current reply control: "Everyone can reply" by default. Tapping opens a small menu: Everyone, People you follow, Mentioned only. This is surfaced in the composer, not buried in settings, because who can reply is a safety decision made per post. The chip uses `accent-subtle` plus `accent` when set to anything other than Everyone, so a restricted audience is visible at a glance.
- **Right: the Post button** (`primary`, `accent-fill`). Disabled while empty or over limit.

### 5.6 Reply mode

When the composer is opened from a Reply action, the surface is identical with three differences: the header reads "Reply", a compact one-line preview of the post being replied to sits above the field ("Replying to @handle: first line of their post, truncated", `text-caption` `text-tertiary`), and the audience chip is replaced by the parent post's reply control shown as read-only context. On post, the reply is inserted into the thread optimistically (see section 12.4).

### 5.7 Draft safety

Closing the composer with unsent content prompts a tiny confirm ("Discard this post?") with Keep editing and Discard. A single-level draft is retained in memory for the session so an accidental dismissal is recoverable. This matters more on a platform where people may be composing something difficult.

---

## 6. Thread and conversation view

The data model allows arbitrary reply depth (adjacency list with denormalized `root_post_id` and `depth`). The design must make depth legible without becoming an unreadable staircase on a phone.

### 6.1 The decision: support three visible levels, then re-root

- **Inline, show depth 0, 1, and 2** (the root post and two levels of nested replies). That is enough to read a real exchange (a reply and a counter-reply) in context.
- **At depth 3 and beyond, collapse.** A reply that would render at depth 3 is replaced by a **"View N more replies" pill** at the depth-2 position. Tapping it opens a **re-rooted focused thread view**: the tapped subtree's top post becomes the new root at depth 0, and its replies lay out fresh from there with three more inline levels available. This is how arbitrary depth stays readable: the UI always shows at most three levels, and going deeper is an explicit navigation that resets the indentation budget. Every post has a permalink and can be opened as its own root, so there is no depth at which content becomes unreachable.

### 6.2 Thread layout

- **The root post** renders at full size at the top of the thread view: 48px avatar, identity block, body at `text-body-lg`, a slightly larger action row, and a metadata line below the body (full timestamp, for example "9:41 AM · 2 Oct 2026", at `text-caption` `text-tertiary`).
- **A reply composer prompt** sits directly under the root ("Reply to @handle"), collapsed like 5.1, so replying is the obvious next action.
- **Replies** render below, each as a reply card.

### 6.3 Nesting visuals (the deliberate divergence from Threads)

- **Indentation step:** 16px per level on mobile, 24px per level at md and up. So depth 2 is indented 32px (mobile) or 48px (desktop) from the thread's left edge. This is bounded because only three levels ever show.
- **Guide rail:** for each level of indentation, a 2px vertical `--thread-rail` line runs down the left gutter of that level, with a short curved elbow (about 10px radius) turning in toward the top-left of each reply's avatar. This reads like the indent guides in a code editor, not like avatars strung on a continuous spine. The rail is reinforcement; the indentation and each reply card's own boundary are the real structure.
- **Avatars sit inside each reply's header**, 40px at depth 1 and 32px at depth 2, never mounted on the rail. This is the clearest structural break from Threads, which hangs avatars on a vertical thread-line.
- **Reply card surface:** replies sit on `surface` with a `border` top hairline separating siblings, same as the feed, so the thread reads as one continuous sheet with indentation, not as a pile of detached bubbles.
- **Collapsing a subtree:** a caret affordance at the left of any reply with children collapses or expands that subtree inline (within the three-level budget). Collapsed state shows "@handle and N replies" as a single `text-caption` row, so a long thread can be skimmed.

### 6.4 Continuity and orientation

- A thin **"continued from" chip** appears at the top of a re-rooted focused view: a CaretLeft affordance plus "Replying to @rootauthor", linking back up to the parent context. The user is never stranded one level deep without a way back up the tree.
- Load more siblings at any level with a "View N more replies" row at `text-label` `accent`.

---

## 7. Profile pages

Profiles are where identity is richest and where the opt-in legal name lives. This is the one surface that may show a legal name, and only when the member has opted in.

### 7.1 Header

- **Banner:** optional. In Phase 2, default to no banner image; use a calm `accent-subtle`-to-`surface` vertical wash or simply `surface` as the header background. No florals, no decorative flourish. (A banner upload can arrive with media in Phase 3.)
- **Avatar:** 96px on mobile, 128px on desktop, `radius-full`, overlapping the banner/header boundary by about one third, with a 3px `surface` ring so it reads cleanly against any background.
- **Identity, in this exact order:**
  1. **`@handle`** at `text-title` weight 700, `text-primary`. The handle is the headline of the profile, consistent with handle-forward identity.
  2. **Legal name, only if opted in**, immediately under the handle at `text-body` `text-secondary`. If the member has not opted in (the default), this line is simply absent. There is no placeholder, no "name hidden" label, nothing that hints a name exists. Absence is the privacy-preserving default and must look completely intentional.
  3. **Founding pill** (if applicable) on the same line as the handle or just beneath.
- **Bio:** up to 300 characters, `text-body`, `text-secondary`, below identity.
- **Metadata row:** joined date (MonthYear) at `text-caption` `text-tertiary`. No location field in Phase 2 (location is a doxxing vector and should be opt-in and deliberate if ever added).
- **Primary action:** for other people's profiles, the Follow control (3.6) plus a **Message** button (disabled until DMs ship in Phase 4; hide rather than show disabled, per the same principle as the composer image button). For your own profile, an **Edit profile** button (`secondary`).
- **Safety affordance:** on every profile that is not your own, a dedicated **Shield icon button** (44x44) sits in the header action area, next to the overflow. See section 11. This is not hidden in an overflow menu; it is a first-class header control.

### 7.2 Follower and following presentation

- Two counts sit in a row under the header: "**N** Followers" and "**N** Following", each tappable to a list. Counts use `text-label` for the number and `text-caption` `text-tertiary` for the word. At zero, show "0 Followers" plainly; do not hide it, because on a new platform zero is honest and expected, and the empty list has its own friendly state (section 10.4).
- Follower and following **lists** are rows: 40px avatar, identity block (@handle, and the opted-in legal name only if that person opted in), a one-line bio preview at `text-caption` `text-tertiary`, and a Follow control on the right. Each row has its own overflow with the Safety group.
- **Who can see these lists:** follower and following lists are visible to signed-in members by default. (Whether a member can hide their following list is a privacy control worth offering; flagged in section 18.)

### 7.3 Tabs

A segmented tab strip under the header, same active-state treatment as the feed segments (accent text plus 2px accent underline):

- **Posts** (default): the member's top-level posts, reverse chronological.
- **Replies:** the member's replies, each shown with a one-line parent context so they are not orphaned.
- **Likes:** default **off and private**. A member's likes are not public by default on this platform; exposing them is a harassment and surveillance vector. If offered at all, it is an opt-in, self-only-by-default control. For Phase 2, show only Posts and Replies tabs publicly; the member can see their own liked posts from within Settings or a self-only view. (Flagged in section 18.)
- **Media:** deferred to Phase 3.

### 7.4 Your own profile

Identical layout with Edit profile in place of Follow and Message, no Shield (you cannot block yourself), and an additional affordance to reach Settings. The own-profile header is where a member confirms how they appear to others, including a clear, reassuring statement of their current name visibility (see 9.3).

---

## 8. The settings area

The owner called settings bad. The fix is primarily information architecture, not styling: the right groups, in the right order, with privacy and safety controls easy to find rather than buried.

### 8.1 Layout

- **Desktop:** a two-pane settings surface. Left: a 240px category list (reusing the rail pattern). Right: the selected category's controls on `surface` cards. The selected category uses the active-row treatment.
- **Mobile:** a single list of categories; tapping pushes into that category's detail; a back affordance returns to the list. Standard platform settings pattern.
- Controls: labeled rows with the control on the right (toggle, segmented control, or a chevron into a sub-screen). Each row is at least 44px tall, label at `text-body` `text-primary`, helper text at `text-caption` `text-tertiary` under the label. Toggles use `accent-fill` when on.

### 8.2 Category order and contents (the information architecture)

Order is deliberate: the things a member under stress needs fastest come first.

1. **Account.** @handle (display, with the rules on whether it can change), email and phone (verified, shown masked, managed here), password, and account deactivation and deletion at the very bottom (deletion behind a confirm). Deactivation and deletion must exist and be findable; a platform for people escaping harassment must make leaving as easy as joining.

2. **Privacy.** This is high in the list on purpose.
   - **Name visibility:** the opt-in legal-name control. It states plainly: "Your legal name was verified when you joined. Members see @handle by default. Showing your legal name is your choice and you can turn it off at any time." A single toggle, default off. When on, a live preview shows exactly how the profile will read. This control already exists in Phase 1 (`set_display_name_visibility`) and is kept, moved into this group, and given the preview.
   - **Search and discoverability:** whether your profile is findable by search engines (the `search_indexable` opt-in, default off) and whether it appears in in-platform people search.
   - **Who can reply to your posts by default** (the default audience for the composer's reply-control chip).
   - **Who can mention you / tag you.**
   - **Following list visibility** (if offered, see 18).

3. **Safety.** Co-equal with Privacy and immediately after it, so safety controls are two taps from anywhere, never buried.
   - **Blocked accounts:** the full list, each with an Unblock control. Managed here and also actionable in context (section 11).
   - **Muted accounts and muted words:** lists, each removable.
   - **Message requests and who can message you** (wiring for Phase 4, shown now as "People you follow" by default).
   - **Report history:** the status of reports you have filed (open, reviewed, action taken), so reporting does not feel like shouting into a void. This directly supports the trust the community guidelines promise.
   - A prominent link to the Community Guidelines and to "How reporting works".

4. **Notifications.** Per-type toggles (replies, mentions, likes, reshares, new followers, messages) mapped to the `notification_prefs` JSONB. Web-push enable. Sensible defaults: mentions and replies on, likes batched.

5. **Appearance.** Theme: System, Light, Dark (the token system already supports all three via `[data-theme]`). Reduced motion is honored from the OS automatically and noted here as "Following your system setting" with no redundant toggle unless user testing asks for one.

6. **About and legal.** Community Guidelines, Terms, Privacy Policy, version, and a clear path to contact safety@ and appeals@.

### 8.3 Settings tone

Helper text is plain and non-patronizing, matching the guidelines' voice. Destructive or sensitive controls (deletion, turning name visibility on) use a confirm step and, for name visibility specifically, a preview so the member sees the consequence before committing.

---

## 9. Empty states and first-run

This is half the owner's complaint and it is a design opportunity, not a problem to hide. A founding cohort of 10 to 50 people guarantees sparse surfaces for weeks. Every empty surface must feel deliberate and inviting, never broken.

### 9.1 Principles for every empty state

- Use `display` or `title` type for a warm one-line headline, `text-body` `text-secondary` for one supporting sentence, a single clear primary action, and a simple line-weight Phosphor illustration glyph (not a cute mascot, not a flower). The illustration is one or two Phosphor glyphs at large size in `text-tertiary` or `accent`, never a decorative scene.
- Never show a spinner where emptiness is the real, correct state. A spinner says "loading"; an empty state says "nothing here yet, and that is fine."
- Always give the member something to do next.

### 9.2 Empty home feed

- **Following tab, no follows yet:** headline "Your feed is waiting". Body: "Follow a few people and their posts show up here. In the meantime, see what the community is sharing." Primary action: a button that switches to **Discover**. Secondary: "Find people to follow" into search. Below the message, seed the view with the Discover stream so the screen is never literally blank.
- **Following tab, you follow people but they have not posted:** headline "Quiet in here for now". Body: "The people you follow have not posted yet. Be the one who starts." Primary action: Compose.
- **Discover, genuinely empty (truly nobody has posted):** headline "Be the first voice". Body: "Nothing has been posted yet. Write the first post and set the tone." Primary action: Compose. This is the true cold-start state for the very first session of the very first member, and it should feel like an invitation to found something, not like a server error.

### 9.3 Empty notifications

Headline "No notifications yet". Body: "When someone follows you, replies, or mentions you, it shows up here." Illustration: Bell glyph. No action needed; this one is allowed to be calm and actionless.

### 9.4 Empty search

- **Before a query:** show recent searches (if any) and a short "Suggested people to follow" list seeded from the founding cohort, so search is useful before you type. Headline if nothing to suggest: "Find your people". Body: "Search by @handle or name."
- **No results:** headline "No matches for 'query'". Body: "Check the spelling, or try a different handle." Never a bare "0 results".

### 9.5 Zero-follower and zero-post profile

- **Your own, zero posts:** the Posts tab shows "You have not posted yet" with a Compose action. The header still looks complete (avatar, handle, counts at zero), so the profile reads as a real identity, not a stub.
- **Zero followers:** "0 Followers" is shown plainly; tapping it shows "No followers yet. They will appear here." No shame framing, no "nobody follows you" phrasing.
- **Someone else's sparse profile:** same calm treatment; a new member's empty profile must not look suspicious or broken, since on an open platform most profiles will be new.

### 9.6 First-session experience

The first session is the make-or-break moment the owner reacted to. The flow after a member first lands:

1. **A one-card welcome at the top of the feed** (dismissible, `accent-subtle` background, `text-primary` body at 14.35:1 light / 13.20:1 dark). It reads, in the guidelines' voice: "Welcome. This is a space built for women's safety and the people who stand with them. Here is how to get started." It contains a 3-step **Getting started checklist**.
2. **Getting started checklist** (also persisted in the right rail on desktop until complete):
   - **Say hello.** Write your first post. (Opens composer.)
   - **Find people.** Follow a few accounts so your feed fills up. (Opens search or a suggested-people list.)
   - **Make it yours.** Add a photo and a line of bio. (Opens Edit profile.)
   Each item checks off as done and the card removes itself when all three are complete or when dismissed.
3. **No forced tour, no modal gauntlet, no gating.** The member lands directly in a usable Discover feed with the welcome card on top. Registration is fully open, so there is no pending state, no approval wait, no vouch prompt, and none of that language appears anywhere (see section 17 on removing the stale Phase 1 copy).
4. **A quiet, one-time pointer to safety tools:** the first time a member opens any profile or post overflow, a single non-blocking tooltip highlights the Shield affordance: "Block, mute, and report live here, always one tap away." Shown once, dismissible, never repeated.

---

## 10. Safety UI as first-class

This platform exists for people who need block, mute, and report to work under stress. These controls are fast, obvious, and consistent, and they are never three levels deep in an overflow.

### 10.1 The Shield affordance

- A dedicated **Shield icon button** (Phosphor Shield, 44x44) appears in two fixed places: the **profile header** (section 7.1) and, pinned to the top of, **every post and reply overflow menu** for content you did not author.
- Tapping the Shield opens the **Safety menu**: a focused list, each item an icon plus label at `text-body`, min 44px:
  - **Mute @handle** (SpeakerSimpleSlash). Silent, reversible, no notification to anyone. "You will not see their posts or notifications from them. They are not told."
  - **Block @handle** (Prohibit), in `danger` text. "They cannot see your profile or posts, follow you, or message you. They are not told."
  - **Report @handle or this post** (Flag), in `danger` text. Opens the report flow (10.4).
- Block and Report sit in `danger` color and are pinned above any generic actions. Mute is neutral. The three safety actions always appear in this same order, in this same place, everywhere, so muscle memory works.

### 10.2 Swipe actions

On touch, swiping left on a feed post, a notification row, or (later) a conversation row reveals two quick actions: **Mute** (neutral) and **Block** (danger). This gives a one-gesture escape without opening any menu. Swipe actions are mirrored by the overflow menu so there is always a non-gesture path (accessibility and desktop).

### 10.3 Block and mute behavior and feedback

- **Block:** immediate, optimistic. The blocked person's content disappears from the viewer's surfaces at once. A toast confirms ("Blocked @handle") with an Undo. Blocking is silent: the blocked person receives no notification. (The data model enforces that the Owner and the system account cannot be blocked; the Shield simply does not offer Block on those two accounts, and no error is ever shown to explain why, to avoid drawing attention.)
- **Mute:** immediate, optimistic, silent, with an Undo toast. Muted content is removed from feed and notifications; on a profile you visit directly, a muted person's posts appear behind a "You muted @handle. Show posts?" reveal, so muting is not a trap you cannot see out of.

### 10.4 Reporting flow

Reporting must be quick but must gather enough to be actionable, and it must feel like it goes somewhere.

1. **Reason selection** (maps to the `report_reason` enum, minus the stale `male_account` value, see section 17): a single-select list with plain-language labels and one-line descriptions: Harassment or bullying, Hate speech, Threat of violence, Sharing private information (doxxing), Sexual content or harassment, Impersonation, Spam or scam, Self-harm, Something else. CSAM has its own clearly separated, prominent path with gentle, serious copy.
2. **Optional detail:** a short free-text field (up to 2000 chars per the model), "Anything else we should know?"
3. **Immediate options after submitting:** offer Block and Mute right there ("Reports are reviewed by our team. Do you also want to block @handle?"), so the member leaves the flow protected, not just heard.
4. **Confirmation:** "Thanks. Our team will review this. You can see the status in Settings, Safety, Report history." This closes the loop the community guidelines promise and is why Report history exists in Settings.
5. **Tone:** serious, brief, never flippant, never bureaucratic. No "Oops!" No exclamation points on a report confirmation.

### 10.5 Report-against-power edge

The member never needs to know about routing. The flow is identical whether the reported account is an ordinary member, a moderator, or the Owner. Routing (standard, admin-only, owner-conflict) is handled server-side per the architecture; the UI shows the same calm confirmation in all cases. A report about the Owner must not reveal that it is handled differently.

---

## 11. Loading, error, and offline states

### 11.1 Skeletons, not spinners, for content

- **Feed, thread, profile, and search load** with **skeleton placeholders**: gray-neutral blocks shaped like the real content (avatar circle, two text lines, action row), using `--skeleton-base` with a slow left-to-right sheen in `--skeleton-sheen`. The shimmer runs at about 1.2s, respects reduced motion (static blocks, no sheen, under reduced motion). Skeletons show the expected shape, so the layout does not jump when real content arrives.
- **Spinners** are reserved for short, bounded, in-place waits where no shape is known yet: a button's own busy state (a 16px spinner replacing the label, with the button kept at full width so it does not resize), pull-to-refresh, and "loading more" at the end of a feed.
- The distinction: a surface loads with skeletons; an action resolves with a spinner.

### 11.2 Optimistic actions

Like, reshare, follow, mute, and block apply instantly in the UI and reconcile with the server in the background. If the server rejects or the network fails, the UI rolls back the single affected control and shows a quiet inline note or toast ("Could not like that. Tap to retry."). Posting a new post or reply inserts it optimistically with a subtle "sending" opacity (about 0.6) until confirmed, then settles to full opacity; on failure it shows a Retry affordance on that item without losing the typed content.

### 11.3 Error states and tone

- **Inline errors** (a failed action) are quiet, specific, and actionable: what happened, and the one thing to do next. "Could not load replies. Retry." No stack traces, no codes shown to members.
- **Full-surface errors** (a feed that could not load at all) use the empty-state layout (section 9.1) with an error headline and a Retry button: "Something went wrong loading your feed. Retry." Tone is calm and non-alarming. Never blame the member.
- **Permission or state errors** (for example trying to reply where reply-control forbids it) are explained in plain language before the action when possible (the reply control is shown on the card, 4.5), and gracefully if reached anyway.
- **Rate-limit or moderation blocks** (for example a post withheld pending a scan in later phases) are explained honestly and without shame.

### 11.4 Offline

- A thin, persistent, non-blocking banner appears under the top bar when the connection drops: "You are offline. We will reconnect automatically." `warning-fill` with `on-warning-fill` text (already a measured pairing), `text-caption`. It does not cover content and it removes itself on reconnect.
- Content already loaded stays readable offline. Actions that need the network (post, like, follow) queue optimistically where safe and show the offline banner; destructive or safety actions (block, report) are attempted immediately and, if they cannot complete, tell the member clearly rather than silently queueing, because a member blocking someone under stress needs to know whether it actually happened.
- As a PWA, the app shell and last-loaded feed are cached so a cold open while offline shows the last state plus the banner, not a blank error.

---

## 12. Accessibility specification

This is stated, not assumed. The base system is already WCAG 2.2 AA in both themes; Phase 2 keeps it there.

### 12.1 Touch targets

Every interactive element has a minimum 44x44 CSS-pixel target, including icon buttons, action-row glyphs, tabs, and list-row affordances, even when the visible glyph is 20 to 24px. Where visual density wants a smaller glyph, the target is expanded with padding, not shrunk.

### 12.2 Focus

- Visible focus on every interactive element: 2px `focus-ring`, 2px offset (already the global default in `globals.css`). Focus is never removed, only styled.
- Logical focus order follows reading order. In the three-column desktop shell, focus order is: skip link, left rail nav, compose, feed content, right rail. A **"Skip to feed" skip link** is the first focusable element.
- Modals and sheets (composer, menus, confirms) **trap focus** while open, restore focus to the trigger on close, and close on Escape.
- The new-posts pill, toasts, and the offline banner are reachable and announced but never steal focus.

### 12.3 Keyboard

- Everything doable by tap is doable by keyboard. Menus open on Enter or Space and are arrow-navigable. The feed is tabbable post to post; within a post, Tab reaches the actions.
- Optional single-key shortcuts (for example `n` for new post, `j`/`k` to move through the feed, `l` to like the focused post, `.` to open the focused post's safety menu) are a progressive enhancement, documented, and never the only way to do anything. They are disabled while a text field is focused.

### 12.4 Screen reader semantics

- Each post is a labeled article: "Post by @handle, 2 hours ago," then the body, then the actions as buttons with state ("Like, 3 likes" / "Liked, 4 likes"). Counts and the like-state change are announced via polite live regions, not on every keystroke.
- The identity block exposes the @handle as the accessible name; the legal name is exposed only on profiles where it is opted in, never in the feed, consistent with the visual rule.
- Thread nesting is conveyed with correct heading and list structure and an accessible "replying to @handle" relationship, not by indentation alone.
- Icon-only controls always carry an `aria-label`.

### 12.5 Reduced motion

When `prefers-reduced-motion: reduce` is set (already globally honored in `globals.css`): the like pop, the sheet slide, the skeleton sheen, the new-post pill motion, tab crossfades beyond a short opacity fade, and the press-scale are all suppressed or reduced to instant or short opacity-only transitions. No essential information is conveyed by motion alone.

### 12.6 Color independence

No state is conveyed by color alone. Active nav and tabs carry a weight and shape change (Fill icon, underline) in addition to the accent color. Danger actions carry a danger-specific icon and wording in addition to red. The thread rail is reinforced by indentation and card boundaries.

---

## 13. Motion specification

All of this inherits the existing durations (instant 0, fast 120, base 180, slow 240, sheet 320) and easings (standard, enter, exit), and all of it degrades under reduced motion per 12.5.

| Element | Motion | Duration | Easing |
|---|---|---|---|
| Button and icon press | scale 0.97 plus opacity | 120 (fast) | standard |
| Tab and segment switch | content crossfade | 120 (fast) | standard |
| Like activation | Heart scale 1 to 1.15 to 1, fill swap | 240 (slow) | enter |
| Bottom sheet (composer, menus) | slide up plus fade | 320 (sheet) | enter in, exit out |
| Modal (desktop composer) | fade plus scale 0.98 to 1 | 240 (slow) | enter |
| Toast | slide plus fade | 180 (base) | enter in, exit out |
| New-posts pill | fade and slight rise on appear | 180 (base) | enter |
| Skeleton sheen | left-to-right shimmer loop | about 1200 | linear, loop |
| Optimistic post settle | opacity 0.6 to 1 on confirm | 180 (base) | standard |

Motion is subtle and functional. There are no decorative, looping, or attention-seeking animations anywhere in the product.

---

## 14. How this is distinct from Threads (point by point)

The owner's concern is explicit: do not make this so similar to Threads that it creates legal exposure. Threads trade dress, at the level that matters, is its specific visual and structural language. Here is where United Feminist's social core diverges, point by point. The brand must never copy Threads' look; it should express the same philosophy in its own language.

1. **Palette.** Threads is a near-monochrome black-and-white surface with no brand color and no warmth. United Feminist is warm sand neutrals (`background` #F4F0EA light) carrying a single confident Iris-violet accent (#6D28D9 light, #A78BFA dark). The platform has a brand color; Threads deliberately does not.

2. **Dark theme.** Threads is pure black (#000) with pure white (#FFF) text. United Feminist's dark theme is warm charcoal (`background` #16130F, never pure black) with off-white text (#F4EFE7, never pure white) and uses surface-lift plus hairline borders instead of shadows for elevation. The two dark modes do not look alike.

3. **Typeface.** Threads uses a neutral system grotesque. United Feminist uses Hanken Grotesk, a humanist grotesque with visibly warmer, rounder letterforms, and sets content at 17px against 15px chrome for a deliberate content-dominant hierarchy.

4. **Post structure.** Threads posts are borderless rows separated by faint hairlines, with handle-forward identity. United Feminist posts sit on a single raised `surface` sheet with a `radius-lg` outer boundary and quiet internal `border` dividers: a hybrid of card and row that is neither Threads' detached cards nor its pure hairline rows. (Identity is handle-forward on both, which is a convention of text social products generally and is required by this product's own locked identity spec; the surrounding structure, color, and type make the card unmistakably different.)

5. **Threading.** Threads strings avatars on a continuous vertical thread-line (the "thread" metaphor its name is built on). United Feminist uses code-editor-style indent guide rails at `--thread-rail`, with a curved elbow into each reply and the avatar held inside the reply's own header, never mounted on a spine. This is the clearest structural divergence and it deliberately avoids the single most recognizable element of Threads' identity.

6. **Composer.** Threads opens a full-screen minimal composer. United Feminist uses a bottom sheet (mobile) or a contained modal (desktop) that surfaces the per-post reply-audience chip inline, foregrounding a safety decision Threads treats as a secondary setting.

7. **Iconography.** Threads uses the thin Instagram-family monoline icons. United Feminist uses Phosphor at a slightly heavier stroke, and signals active navigation by switching to Fill-weight glyphs plus an accent indicator bar, rather than by a subtle monoline color change.

8. **Navigation.** United Feminist's desktop shell is a labeled left rail with a raised accent Compose pill and an accent active-indicator, plus an optional right rail; its mobile bar weights the Compose slot with an accent-filled tile. Threads' chrome is a flatter, unlabeled icon row with no brand-colored action.

9. **Safety as chrome.** United Feminist promotes block, mute, and report to a dedicated labeled Shield affordance in every profile header and at the top of every content overflow, plus swipe actions. This is a structural, first-class safety surface that Threads does not present; it changes what the product foregrounds.

10. **Empty and first-run language.** United Feminist's empty states and first-run are a designed, branded, founding-cohort experience with a "be the first voice" posture and a safety pointer, specific to this product's purpose and community, not a generic social-app onboarding.

Taken together, the color system, dark-mode construction, typeface, post-surface treatment, threading metaphor, composer form, icon weighting, navigation chrome, and first-class safety surface make this a visually and structurally distinct product that shares only a design philosophy with Threads, not its trade dress. This is a design argument, not a legal opinion; a trademark and trade-dress review by counsel is still recommended before launch, as already flagged in the project's open items.

---

## 15. Tokens added or changed

Per the brief, nothing is silently diverged. Phase 2 proposes exactly this:

### 15.1 Added: `--thread-rail` (decorative)

- **Value:** Iris accent at approximately 16% alpha. Light: `rgba(109, 40, 217, 0.16)`. Dark: `rgba(167, 139, 250, 0.16)`.
- **Reason:** reply nesting needs a visible guide rail that reads as structure, not as an interactive accent and not as a divider border. A dedicated token keeps it from being a magic number scattered through components.
- **Contrast:** intentionally below 3:1 and therefore exempt from WCAG 2.2 1.4.11, because nesting is also conveyed by indentation and by each reply card's `border-strong` boundary (which meet 3:1), so the rail is reinforcement, not the sole signal. A user who cannot perceive the rail still reads the thread from indentation and card boundaries.

### 15.2 Added: `--skeleton-base` and `--skeleton-sheen` (decorative)

- **Values, derived from existing neutrals.** Light: base `#ECE6DC` (between `background` and `border`), sheen `#F6F2EC`. Dark: base `#262019`, sheen `#312A22`. These sit between the existing `surface` and `border` steps so skeletons read as placeholder-neutral in both themes.
- **Reason:** loading placeholders need a two-tone pair for the shimmer that is clearly non-content and theme-correct. Deriving from existing neutrals keeps them in family.
- **Contrast:** not applicable; placeholders carry no text and convey no information beyond "loading", which is also announced to assistive tech.

### 15.3 One existing token usage clarified, not changed

- The notification unread badge uses `accent-fill` plus `on-accent` (an existing, already-measured pairing: white on accent at 7.10 light, and `accent-fill` plus white at 5.70 dark), deliberately **not** `danger`. No token changes; this is a usage rule so alerts do not read as errors. Stated here so it is not mistaken for a new color.

No existing color, type, spacing, radius, elevation, or motion token is altered. The Phase 2 surfaces are built entirely from the inherited system plus the one decorative rail token and the two derived skeleton tones.

---

## 16. Existing implementation that works against good design (fix during the Phase 2 build)

These were found by reading the current repository. They are not cosmetic; several would actively break the Phase 2 experience or leak identity if carried forward unchanged.

1. **The posting permission gate contradicts open registration.** The architecture blueprint's `posts_insert` policy requires `trust_level <> 'pending_vouch'`. Under fully open registration, new accounts default to `pending_vouch` and would be silently unable to post, which is a first-run killer: a brand-new member hits "be the first voice," composes a post, and it fails for a reason the UI cannot explain. Resolve during Phase 2 by either dropping the trust gate on posting or auto-advancing a new account to a posting-eligible state at signup. The design assumes a new member can post immediately.

2. **The `male_account` report reason must go.** The `report_reason` enum includes `male_account`. With no gender screening and a conduct-based, fully open model, "this is a male account" is both unenforceable and in direct tension with the platform's stated non-screening posture. Remove it from the enum and from the reporting UI (section 10.4 already omits it). Conduct, not identity, is the basis for reports.

3. **Vestigial vouch and invite language in shipped UI.** `src/app/home/page.tsx`, `src/app/settings/page.tsx`, `src/components/SiteHeader.tsx`, and the `layout.tsx` metadata description all still speak of vouching, "Admission by vouching or review," and a "Vouches" nav item. Under open registration none of this is true for the member experience. All of it must be replaced with the Phase 2 feed, profile, and settings surfaces and copy. The "Vouches" primary nav item is removed.

4. **The app shell is a narrow single column with a text-link header.** `layout.tsx` centers content in `max-w-3xl` with a top header of text links. That is fine for Phase 1 forms and wrong for a social feed. Phase 2 replaces it with the three-column shell (left rail plus 600px feed plus optional right rail at xl) and the mobile bottom tab bar defined in section 1. The existing `SiteHeader` becomes the logged-out marketing header only.

5. **A stale, dangerous schema comment about the legal name.** `docs/architecture.md` still describes `display_name` as `not null` and "PUBLIC on the profile by spec." The live migration (`20261001000002_identity.sql`) is correct: `display_name` is nullable, a trigger forces it to be either NULL or exactly the verified legal name, and `set_display_name_visibility` toggles it, defaulting to handle-only. The migration is right; the architecture comment is a landmine that could lead a future build to publish legal names by default. Correct the document so it matches the opt-in rule and the implementation. (This is a documentation fix, but it directly protects the most sensitive identity decision in the product.)

6. **Global `robots: { index: false }` and the metadata description.** The current global no-index is appropriate while only admission surfaces exist and aligns with the default-private discoverability posture, so keep it as the default. But when public posts and profiles ship, indexing becomes a per-surface, opt-in decision (tied to `search_indexable`), not a single global switch. Plan for per-route control in Phase 2 rather than a blanket flag, and update the stale "Admission by vouching or review" description.

7. **Counts that would render as walls of zeros.** Any straightforward implementation of the action row will show "0" likes, "0" replies, "0" reshares on every post of a new platform, which is exactly the "wildly empty" feeling the owner reacted to. The design hides zero counts (section 4.2, 4.6); the build must follow that rule rather than rendering raw counts.

---

## 17. The three decisions I am least certain about

Stated honestly, with what would resolve each.

1. **Showing the Discover tab in Phase 2.** I added a platform-wide reverse-chronological Discover feed so a zero-follow new member has real content on day one, because an empty Following feed is the core of the owner's complaint. The risk: on an open-registration platform, an unfiltered public stream is also where spam, brigading, and bad actors are most visible to brand-new members before they have built a safe follow graph, and the moderation backbone is Phase 3, not Phase 2. It may be safer to launch Phase 2 with a curated "Suggested posts from the founding cohort" surface instead of a raw global stream. **To resolve:** a call from the owner and Grove-Security on whether an unmoderated public stream is acceptable during the Phase 2 window, or whether Discover should be a hand-curated founding-cohort surface until Phase 3 moderation exists.

2. **Whether the photo-attach and Message controls should appear-but-disabled or be hidden in Phase 2.** I recommended hiding both until their phases (media in Phase 3, DMs in Phase 4) so nothing looks broken, but a visible-but-disabled control with "coming soon" copy sets expectations and signals the roadmap. The two readings genuinely conflict: hidden feels more finished, disabled feels more honest about what is coming. **To resolve:** the owner's preference on whether to tease upcoming features in the UI or present only what works today. Low stakes, easily reversed.

3. **The Likes tab and following-list visibility defaults.** I defaulted a member's Likes to private and left following-list visibility as an open control, reasoning that both are surveillance and harassment vectors on a safety-focused platform. But hiding likes and follows also removes social signal that helps a small new community feel alive and discover each other, and other platforms expose both by default. I am not certain the maximally private default is right for the founding-cohort growth phase. **To resolve:** a product call weighing safety against discoverability, ideally informed by what the founding cohort actually wants, since they are the people the privacy default is meant to protect. This is a values question more than a design one, so it belongs to the owner.

---

## 18. Summary of deliverables for the Phase 2 build

An engineer implementing Phase 2 from this document builds: the three-column responsive shell and mobile tab bar (section 1); the shared primitives (section 3); the home feed with its card anatomy, density, separators, feed segments, and new-posts pill (section 4); the two-form composer with late-revealing counter and inline audience control (section 5); the thread view with three-level nesting, guide rails, and re-root collapse (section 6); profiles with handle-forward, opt-in-legal-name identity and tabs (section 7); the re-architected settings with privacy and safety high in the order (section 8); the full set of empty states and the first-run checklist and welcome card (section 9); the first-class Shield safety surface with swipe actions and the reporting flow (section 10); skeleton-based loading, optimistic actions, and calm error and offline states (section 11); and the stated accessibility and motion behavior throughout (sections 12 and 13). It stays visually distinct from Threads (section 14), adds only one decorative rail token and two derived skeleton tones (section 15), and corrects the seven implementation issues that work against the above (section 16).

Everything readable in this specification uses an existing, measured token, or a new pairing whose measured ratio is listed in section 2.3. The product should feel like a serious, calm, trustworthy piece of software that happens to be built for people who need its safety tools to work. That is the whole brief.
