# Hersciety: Hashtags, At-Mentions, and Reposts (Phase 2F) Design Specification

**Status:** Design specification. Docs only. This document creates no application code, no database migration, and no assets. It specifies three member-facing capabilities the owner asked for in one breath: hashtags that are parsed, searchable, and trending; at-mentions that are parsed, linked, and that notify; and reposts from the feed. A code pass and a schema pass should be buildable from this document plus the existing token system, the Phase 2 component conventions, and the schema already described in the architecture document, without the builder having to make product judgment calls. Where this document says a schema change is needed, it says so and leaves the migration to the build brief; it does not write SQL.

**Date:** 2026-10

**Design thesis (inherited, not reopened):** "Calm paper, sharp tools." Warm, low-glare sand neutrals carry content; one Iris-violet accent carries interaction. See P2 (the Phase 2 social-core spec). These three features add discovery and amplification inside that system. They do not redesign it, they do not touch the shell, and they add no new navigation slot.

**Locked context (do not reopen):** The @handle leads everywhere in the UI. `display_name` is the member's real legal name, is not public by default, and is opt-in only. No surface in this document ever pairs content with a legal name. Zero counts are hidden. People search is @handle only, and it stays that way; tag search is a separate axis and is not an excuse to add name search. Discover ranking is positive-signal-only: no controversy, ratio, reply-volume, or negative-velocity signals, and a repost may only ever be a positive signal. Blocks hide content bidirectionally. Reports go to the admin panel plus an email copy to safety@unitedfeminist.com; there is no external report recipient. The Owner account and the system account are unblockable. Numbers in this product are literal: 1 is 1 and 0 is 0, so nothing here hides a real count behind a suppression threshold, a k-anonymity floor, a withheld percentage, or any "not enough data" coyness. These are settled elsewhere and are treated here as fixed.

---

## 0. How to read this document

- **Tokens** are the CSS custom properties implemented in `src/app/globals.css`, named exactly as they appear there (for example `--accent`, `--accent-subtle`, `--surface`, `--surface-raised`, `--radius-md`, `--thread-rail`). This spec adds zero new tokens. Section 21 confirms it with the measured contrast table.
- **Contrast** is the WCAG 2.x relative-luminance method on sRGB throughout. Every ratio here is a number already measured in the base system or in P2 section 2.3, reused verbatim. Pass thresholds: 4.5:1 for normal text, 3:1 for large text and for non-text graphics that are the sole identifier of meaning.
- **Components** this document reuses by name are the ones the Phase 2 build already shipped: the post card and its action row (P2 section 4.2), the overflow menu (P2 section 3.4), the composer (P2 section 5), the toast (P2 section 3.5), the identity block (P2 section 3.2), the segmented tabs (P2 section 4.1), the people-search surface (P2 section 9.4), the notifications list, the follow control and its optimistic undo toast (P2 section 4.9), and the empty-state pattern (P2 section 9). Where this spec needs one of them it reuses it rather than inventing a parallel one.
- **House style:** plain prose, ASCII only, no em or en dashes and no smart quotes. Cross references read as "P2 section X" for the Phase 2 social-core spec, "P2B section X" for the moderation-and-discover spec, "P2D section X" for the admin-dashboard spec, "P2E section X" for the profile-pictures spec, and "the architecture document, section X" for the technical blueprint.

### 0.1 What exists today, verified against the repository

Reading the live code changes what has to be designed. The three features are at three very different stages.

- **At-mentions are roughly four-fifths built, on the server.** `create_post()` (migration `20261005000001_social_core.sql`, hardened by `20261006000001`) parses mentions out of the post body with a word-boundary regex, resolves each `@token` against a real profile whose status is `active` or `restricted`, dedupes repeats, skips the author mentioning herself, never creates a mention across a block (it calls `blocked_either`), and only writes a `mention` notification when the mentioned member has not muted the poster and has the `mention` notification preference on. The `post_mentions` join table ships. The `mention` value of `notif_type` ships. The notifications surface already renders a mention as "@handle mentioned you" and links to the post. The `mentioned` value of `reply_control` is powered by this same table. The server side is good work and this spec keeps it.
- **The client rendering of mentions is naive and must be fixed.** `src/components/post/PostBody.tsx` splits the body on `/(@[a-z0-9_]{3,30})/gi` and turns every `@word`-shaped string into a link to `/u/{that word}`, with no check that the handle exists and no word boundary. So `@notarealhandle` renders as a live link to a 404, and a future member who later claims that handle would silently inherit old links. There is no hashtag rendering at all. There is no autocomplete anywhere. Section 10 fixes this.
- **Hashtags do not exist in any form.** No parsing, no storage, no rendering, no tag page, no search axis, no trending. This is greenfield and is the largest part of this document.
- **Reposts do not exist, but the shape was already drawn.** The architecture document's schema blueprint carries a `reshares` table, a `posts.quoted_post_id` column, a `posts.reshare_count` column, and `reshare` and `quote` values of `notif_type`, but the architecture document states plainly that none of those are shipped and that they arrive additively with the feature. The post card's action row today has only Reply and Like; the Repeat glyph that P2 section 4.2 specified was not built. P2 section 4.4 already designed how a reshare and a quote render. The API blueprint reserves `POST` and `DELETE /api/posts/{id}/reshare`. So reposts are specified-but-unbuilt, and this document finishes the specification and makes the plain-repost-versus-quote call.
- **Search is @handle only and is a single box.** `SearchClient.tsx` debounces into the `search_people` RPC, matches handles, and renders people rows. Its placeholder reads "Search by @handle." There is no post search and no tag search. This is the surface tag search extends, carefully, in section 5.
- **The site is fully gated and not indexed.** Every member surface redirects to login when logged out and the whole site serves `noindex`, so nothing in this document is visible to the open web. The brand share card is the wordmark, never member content.

### 0.2 The constraint that dominates this entire design

These three features are, between them, the platform's main amplification and summoning tools, and amplification is where a safety-first platform is most easily turned against its own members. A hashtag that trends is, by definition, the most-seen word on the platform, and a trending surface is a brigade target. A mention is a direct summons that lands as a notification, which is the classic way a harasser reaches past a block attempt or drags a woman into a pile-on. A repost takes one person's words and puts them in front of an audience she did not choose. Members of this platform are hiding from specific people, so every one of these has to be designed so that it amplifies what members positively choose and never becomes a channel for someone to find, summon, or swarm a person who is trying not to be found.

So safety is not a section at the end of this document; it is the spine of every feature. Three rules recur and are stated once here so they do not have to be re-argued at each surface:

1. **Distinct people, not raw volume.** Everywhere something is counted for amplification (trending especially), the unit is the distinct person, never the raw action, so one determined account cannot manufacture reach.
2. **A block is a wall in both directions, always.** No feature here ever lets a blocked relationship leak around the block: not a mention notification, not a repost, not a trending tag populated only by a blocked account.
3. **Numbers are honest and never coy.** The owner's standing rule is that every count is literal. Nothing here hides a real number behind a threshold or a "too early to show" message. Thinness is handled by honest framing and good empty states, never by withholding the truth.

If a visual choice ever conflicts with one of these three rules, the rule wins and the visual is redrawn.

---

## 1. Summary of decisions

For the reader who wants the answers before the reasoning.

1. **A hashtag is `#` at a word boundary, then at least one Unicode letter plus optional letters, numbers, and underscores, up to 64 characters.** A pure-number or pure-underscore token is not a tag. Matching is case-insensitive on a folded canonical form; display preserves the author's casing inside a post. Section 2.
2. **Hashtags are stored as a canonical tag entity plus a per-post join, parsed at post time in the same place mentions are parsed.** Section 3. This powers tag pages, tag search, and trending with one index each, and gives moderation a single place to suppress a tag.
3. **Tag pages live at `/t/<canonical-tag>`, show the tag's posts newest first, honor every block and mute, and have a warm empty state.** Section 4.
4. **Tag search is a second search axis, triggered by a leading `#`, and it never touches people search, which stays @handle only.** Section 5.
5. **Trending ranks tags by the count of distinct people using them over a 48-hour rolling window, recency-weighted, recomputed about every 15 minutes into a small snapshot table.** It lives on the Search surface and in the desktop right rail, needs no new nav slot, shows up to five entries compactly, and on a tiny network shows the real tags with their real small counts under honest founding-cohort framing, never a "not enough data" message. Section 6.
6. **A hashtag is moderated by suppressing the tag, in two tiers: de-trend (moderator and above) and block the tag page entirely (admin and above), both audited.** Members do not report a tag directly; they report the conduct in a post, as today. Brigading is defended by the distinct-person count, an anomaly flag for human review, and the existing signup defenses. Section 7.
7. **Mention parsing on the server is kept as is; the client is fixed to link only resolved mentions and to render hashtags.** Section 10.
8. **The composer gains mention autocomplete:** a popover near the field on desktop, a strip docked above the keyboard on mobile, handle-only, ranked by your follow graph, blocked accounts excluded. Section 9. Hashtag suggestion is designed as an additive sibling.
9. **A blocked person cannot mention you; muting a person suppresses their mention notifications to you; and a new "Who can mention you" setting (Everyone, People you follow, No one) lets a targeted member limit mentions.** A single post can notify at most a bounded number of mentioned people, to blunt mass-mention pile-ons. Section 12.
10. **Mentioning a suspended, banned, deactivated, or non-existent handle renders as plain text, links to nothing, and notifies no one;** a mention re-links itself if the account becomes reachable again. Section 13.
11. **Ship plain repost now; defer quote-post.** Plain repost is pure positive endorsement and matches the owner's words ("repost what they see"); quote-post is the quote-dunk vector that P2B already refuses to amplify, and it can be added later with its own safety controls. Section 14.
12. **The repost control is the Repeat glyph in the action row; a plain repost is one optimistic tap with an undo toast, and undo is tapping it again.** Section 15.
13. **A repost renders as the original post card with a slim "@handle reposted" line above it, the original author's identity primary, and it appears interleaved in the reposter's profile Posts tab.** Section 16.
14. **A repost disappears the moment its original is deleted, removed, hidden, its author suspended or banned, or a block exists in either direction between the reposter and the original author.** No stub, no leak. Section 17.
15. **Reposts feed Discover exactly as likes do, as a positive aggregate signal and a positive affinity signal, never negative, and the original author gets a repost notification by default.** Section 18.
16. **`reply_control` does not restrict plain reposting;** reposting is amplification, not participation, and a plain repost cannot dunk. Section 19.
17. **Zero new design tokens.** Section 21.

---

# PART 1. HASHTAGS

## 2. Parsing rules: what is and is not a tag

A hashtag has to be defined precisely, because the parser runs server-side inside the post write path (where it decides what gets indexed and counted) and the renderer runs client-side (where it decides what turns violet and becomes tappable), and the two must agree exactly, the same way the mention parser and renderer must agree. The rules:

- **A tag begins with `#` at a word boundary.** The `#` must sit at the start of the post body or immediately after a character that is not a letter, number, or underscore. This is the identical rule the mention parser already enforces for `@` (the P1-5 hardening), and it is here for the same reason: `color#fff`, a URL fragment like `example.com/page#section`, and `C#` written mid-sentence must not become tags. Whitespace, punctuation, and the start of the string all open a tag; a letter or digit immediately before the `#` does not.
- **The tag body is at least one Unicode letter, then any run of Unicode letters, numbers, and underscores.** Concretely: after the `#`, the characters are drawn from the Unicode letter categories, the Unicode number categories, and the underscore, and the whole body must contain at least one letter. Allowing Unicode letters is deliberate and is a value decision for this community: members write in languages other than English, and a tag system that only accepts `[a-z]` quietly tells non-English speakers that the discovery layer is not for them. So `#salud`, `#nihongo` written in its own script, and accented tags are all first-class.
- **A pure-number or pure-underscore token is not a tag.** `#2024`, `#100`, and `#___` do not parse. Requiring at least one letter removes the most common noise (bare numbers that are rarely a real topic and that collide with ordinary writing like "see #3 above") and removes the ambiguous all-punctuation cases, with one clean rule rather than a list of exceptions.
- **Length cap: 64 characters in the tag body.** The post body is already capped at 500 characters, so a tag can never be enormous, but an explicit 64-character ceiling on the tag entity keeps the canonical key sane, keeps a tag label from dominating a trending row, and defuses a single 400-character "tag" used to pollute the index. A `#` followed by a run longer than 64 tag-characters parses as a 64-character tag and the overflow is ordinary body text, which is the least surprising behavior.
- **Case handling: fold for matching, preserve for reading.** The canonical identity of a tag is its body put through Unicode normalization (NFC) and case folding to lowercase. So `#SelfCare`, `#selfcare`, and `#SELFCARE` are one tag, and they share a tag page, a trending row, and a search match. Inside a post body, the tag renders exactly as the author typed it, because `#SelfCare` reads better than `#selfcare` and camel-casing is a real readability choice an author is entitled to make. On the canonical surfaces where a single label is needed (the tag page header, the trending list, the search result), the tag is shown in its canonical lowercase form with the `#`, so there is never an argument about whose casing wins. This split (fold to match, preserve to read in-body, canonical to label) is the standard, least-astonishing behavior and it is decided here; it is not an owner question.
- **Where tags may appear: anywhere in the post body.** Tags are parsed from the body text, exactly like mentions; there is no separate "tags" field and the author does not tag a post in a special step. A tag inside a URL or mid-word is excluded by the word-boundary rule above. Tags are not parsed from the bio or from the display name in this phase (bios are out of scope, section 24).
- **At most a bounded number of distinct tags are indexed per post.** A post that carries dozens of tags is almost always tag-stuffing aimed at the trending surface. The parser indexes at most 30 distinct tags from a single post; any beyond that still render as text but are not stored in the join table and do not count toward anything. This is a storage and abuse guard. It is a backstop, not the main defense: the real anti-stuffing control is that trending counts distinct people, not tag occurrences (section 6), so stuffing a post with tags buys the author nothing regardless.

The parser produces, for each post, a deduplicated set of canonical tags (capped at 30), which the write path stores (section 3). Repeats of the same tag in one post collapse to one.

## 3. Storage and model shape (conceptual)

The builder implements this; the shape and the reasoning are what matter here, so the right thing gets built and so the migration can be assigned.

- **A canonical tag entity.** A `tags` table keyed by the folded canonical string (unique), carrying the canonical string, a display string (the canonical lowercase form is a fine default), a moderation status (section 7: `active`, `detrended`, or `blocked`), and a created-at timestamp. Why a first-class entity rather than parsing tags on every read: a stable tag id lets the join, the trending snapshot, and the moderation status all reference one row; it lets a tag be suppressed exactly once instead of per-post; and it makes "all posts with this tag" and "how many distinct people used this tag in the last 48 hours" into indexed queries instead of full-table text scans.
- **A per-post join.** A `post_tags` table of (post_id, tag_id), primary-keyed on the pair, written inside `create_post()` at post time, in the same loop that already resolves mentions. This is the exact pattern `post_mentions` already uses, so it fits the codebase without a new concept. An index on tag_id serves the tag page; the join plus the posts table serves the windowed distinct-author query for trending.
- **A trending snapshot.** A small `trending_tags` table holding, per tag in the current window, the computed score, the distinct-person count, the window bound, and the computed-at time. It is rewritten by a scheduled job (section 6) and read directly by the trending surface, so a member's request never runs the aggregate; it reads a handful of precomputed rows. This mirrors the architecture document's approach to the For-You candidate table (section 3.6): periodically materialize, read cheaply.
- **No per-tag follow in this phase.** There is no "follow this hashtag" relationship and therefore no tag-follow notification. Tags are a discovery and search axis now, not a subscription; following a tag is a clean additive feature later and is out of scope (section 24).

Every one of these is a schema change and is listed for the build brief in section 22. None of them touches an existing table's meaning; they are additive.

## 4. Tag pages

A hashtag anywhere in the product is tappable and leads to the tag's page.

- **Route.** `/t/<canonical-tag>`, where the path segment is the folded canonical form (lowercase). A request for a tag in any casing redirects to the canonical path, so there is exactly one URL per tag and links are stable. The `/t/` prefix is short, conventional, and does not collide with the existing `/u/` (profiles) and `/post/` routes.
- **Header.** The tag shown as `#canonicaltag` at `text-title`, `text-primary`, with, beneath it, a single honest line of context: the number of posts carrying the tag, shown plainly (for example "18 posts"). Because you are on the page, there is at least one post to see, so this count is never zero on a live tag; a tag with no visible posts falls to the empty state below rather than printing "0 posts." There is no follow-this-tag control in this phase.
- **Ordering: newest first.** The tag page is a reverse-chronological stream of the posts that carry the tag, which is the honest and predictable ordering for "what are people saying about this right now," and it matches the Following feed and the Phase 2 baseline Discover ordering. A "Top" ordering (the positive-signal ranking Discover already uses) is a clean additive tab later, but on a founding-cohort network Top and Latest would be nearly identical, so Latest-only ships first and Top is noted as additive (section 24). The card is the standard post card (P2 section 4.2), identical to the feed, including the Follow pill for authors you do not follow and the overflow menu for safety actions.
- **Safety filtering is the same as the feed.** The tag page is served by the same kind of block-aware, mute-aware read path the feed and thread views already use: it returns only posts whose visibility is `visible`, excludes posts by anyone you have blocked or who has blocked you (bidirectional), excludes muted authors, and respects the "show me less" down-rank the way Discover does. A member who has blocked her harasser never meets his posts on a tag page, even a tag he is flooding. This is a hard server-side filter, not a client hide.
- **Empty state.** If a tag has no posts you can see (a typo in the URL, a tag only ever used by accounts you block, or a tag nobody has used yet), the page shows the warm empty-state pattern (P2 section 9.1), never an error and never a bare "0 results": a one-line headline ("Nothing here with #tag yet"), a supporting line ("Be the first to post with it"), and a Compose action. A suppressed tag shows the neutral unavailable state instead (section 7).
- **It is a reading surface.** The tag page uses the 600px reading column and the same calm card-and-rule treatment as the feed, so it feels like the same product, not a separate search tool.

## 5. Tag search: a separate axis that leaves people search alone

People search is @handle only and must stay that way. That is the structural defense against turning discovery into a people-finder for someone hunting a specific woman, and it is locked. Tag search is a genuinely different axis (finding a topic, not finding a person) and it is added without weakening the people axis at all.

- **One box, two axes, disambiguated by a leading `#`.** The existing single search field stays. A query that begins with `#` is a tag search; any other query is a people search, matched on handle only, exactly as today. A bare query never becomes a content search or a name search; the only thing that unlocks the tag axis is the member deliberately typing `#`. This keeps the two axes cleanly separate: you cannot accidentally find a person by typing part of a topic, and you cannot find a topic by typing part of a handle.
- **What a tag search matches.** A `#`-prefixed query does a prefix match against the canonical tag index and returns matching tags (as rows: `#tag` plus its post count), each a link to that tag's page. It matches the tag index, not the text of posts; it is a "find the tag" search, not a "search inside posts" search. Full-text search inside post bodies is a separate, deferred feature (the architecture document scopes post FTS to Phase 5), and nothing here brings it forward. So tag search is a third thing, distinct from both @handle people search and from the deferred post-content search.
- **Discoverability without typing `#`.** The pre-query Search screen (which today shows "Find your people") gains the Trending module (section 6), so a member discovers tags by browsing what is trending and tapping, without having to know to type `#` first. Tapping a trending tag goes straight to its tag page.
- **Copy.** The search field placeholder changes from "Search by @handle" to "Search @handle or #topic" so both axes are discoverable, while the people results stay handle-only. The pre-query empty-state copy keeps "Find your people" and gains the Trending module beneath it.
- **Build note.** This needs a `search_tags` RPC alongside the existing `search_people`, prefix-matching the canonical tag column, returning tags and their post counts, excluding suppressed tags (section 7). The client routes a `#`-prefixed query to it and everything else to `search_people` unchanged. Listed in section 22.

## 6. Trending: the part that needs the most care

The owner asked for hashtags to be "trendable so people can see what others are talking about." Trending is the highest-stakes surface in this document for two reasons at once: it is a brigade magnet (whatever trends is the most-seen thing on the platform, so gaming it is worth effort), and it will be thin for a long time (a founding cohort produces very little, and trending must not look broken or embarrassing while the network is small). Both pressures are answered below, and neither is answered by hiding real numbers.

### 6.1 The window, the signal, and the refresh

- **Window: a 48-hour rolling window.** Trending reflects the last two days. Two days is wide enough that a small founding cohort will usually have something in it, and narrow enough that it reads as "what is happening now" rather than an all-time greatest-hits. The window is fixed, not adaptive; an adaptive window that silently widens when activity is low is exactly the kind of cleverness that becomes coy, and it is avoided.
- **Signal: the count of distinct people using the tag, recency-weighted.** A tag's trending score is built from the number of distinct accounts that used the tag in the window, not the number of times the tag was used. This is the single most important decision in the whole feature. Counting distinct people means that one account posting `#something` fifty times contributes exactly one to that tag's trend, so a lone spammer cannot manufacture a trend, and a sockpuppet ring is bounded by how many accounts it can stand up rather than how many posts it can send. It is the direct analogue of P2B's case-grouping insight, where many reports from few people are read as a brigade, not as damning volume. On top of the distinct-person count, a recency weight gives more pull to the last several hours than to the far edge of the window, so a tag four people used this morning outranks one four people used two days ago. A repost of a tagged post counts the reposter as a participant in that tag (a repost is a positive endorsement, section 18), counted once like any other person.
- **Refresh: recomputed about every 15 minutes by a scheduled job.** A pg_cron job (the architecture document already runs pg_cron and a jobs table, and already recomputes feed candidates on roughly this cadence) recomputes the windowed distinct-person scores and rewrites the `trending_tags` snapshot. Member requests read the snapshot, never the live aggregate, so trending is instant and the database is not asked to scan the join table on every page load. Trending is therefore honestly "as of a few minutes ago," which is standard and expected.

### 6.2 Where trending lives in the information architecture

Trending adds no navigation slot. The five primary surfaces are fixed (P2 section 1.1) and are not touched.

- **Primary home: the Search surface.** "See what others are talking about" is a discovery act and Search is already a primary destination (the MagnifyingGlass slot), so trending lives on the pre-query Search screen, above or beside the existing "Find your people" state. On mobile, where there is no right rail, this is the one home for trending, and it is reached in one tap on a nav slot that already exists.
- **Secondary home: the desktop right rail.** At xl and up the right rail already exists and already holds the search field and the "Getting started" checklist (P2 section 1.2), and it is explicitly additive (nothing is lost when it is absent at lg). A compact Trending module sits there, so a member browsing the feed on a wide screen sees trending without leaving Home. This is the conventional place a trending module lives on a desktop social product, and it costs no nav slot.
- **Not on the mobile feed.** Trending is not injected into the mobile feed or the bottom bar; it stays on Search and the desktop rail, so the feed stays the calm reading surface it is meant to be.

### 6.3 What it shows, and how many

- **Up to five entries in the compact module**, each a row: the tag as `#canonicaltag` at `text-label` in `accent` (a link to the tag page), and a short honest descriptor at `text-caption` `text-tertiary` (for example "6 people" or "12 posts"; the people count is the more honest descriptor given the distinct-person signal, and it is the one recommended). Keeping the compact module to five entries means a thin network is not stretched into a long sparse list that advertises its own emptiness.
- **A "See more" link to a full trending page** that lists up to about twenty tags in the same row format, for the member who wants the whole picture. On a tiny network the full page is simply short, which is fine.
- **Ranked by score, highest first.** The order is the recency-weighted distinct-person score from 6.1. There is deliberately no ordering by raw post volume, because that would reward the spammer the distinct-person count is designed to defeat.

### 6.4 How trending behaves on a 2-member platform versus a 5,000-member one, honestly

This is the part the brief is most concerned about, and it is answered without a single suppression threshold, k-anonymity floor, withheld percentage, or "not enough data" message, because the owner has ruled all of those out and she is right to: a count of 1 is shown as 1.

- **On a 2-member (or 5-member) founding platform.** In any given 48 hours the window might hold zero, one, two, or three tags, each used by one or two people. The module shows exactly those tags, with their exact counts. A tag used by one person shows its real count; 1 is 1. What keeps this from reading as broken is framing, not suppression: the module header is plain ("Trending"), and because the whole product already wears its newness with intent (the founding-cohort empty states in P2 section 9 and the "early and real, never fake and desperate" posture in P2B section 12), a short honest list of real topics reads as a young community, not a failure. A trending list with two real tags and real small counts is a healthy new network; a trending list padded with fake activity to look busy is the thing that destroys trust, and it is never done here (6.5).
- **When the window is genuinely empty.** If nobody has used any tag in 48 hours, the module does not say "not enough data" and does not hide anything, because there is nothing to hide; it shows the warm empty state (P2 section 9.1): a one-line invitation ("No topics yet") and a supporting line ("Add a #hashtag to a post and start one"), with a Compose action. This is an honest statement that the real count is zero, framed as an invitation, which is exactly the allowed and encouraged pattern everywhere else in the product. It is the opposite of coyness: coyness hides a real number behind "too few to show," and this states the real number (zero) plainly and asks the member to change it.
- **On a 5,000-member platform.** The same algorithm now has dozens of candidate tags in every window; the compact module shows the top five by score, the full page shows twenty, the counts are large, and the recency weight keeps the list turning over through the day. Nothing about the surface changes; only the data got richer. The distinct-person signal that was protecting a 2-member platform from a single spammer is the same signal protecting a 5,000-member platform from a coordinated ring, just at a larger scale.

The honest summary: trending is one algorithm that produces a short true list when the platform is small and a rich true list when the platform is large, and it never lies about size in either direction.

### 6.5 No fake liveliness, ever

The sparse states never invent activity, never seed placeholder tags, and never pad the list to look busier than the platform is. This is the same rule P2B section 12 sets for Discover, and it is restated here because trending is where the temptation to fake momentum is strongest. A founding member can tell the difference between "early and real" and "fake and desperate," and only the former earns the trust this platform runs on.

## 7. Moderating a hashtag

A trending surface is a brigading target and an abuse vector (a slur weaponized into a tag, a doxxing campaign organized under a hashtag, a pile-on rallied around one), so moderation of tags is designed explicitly rather than left as an afterthought.

### 7.1 Members report conduct, not tags

There is no "report this hashtag" control for members, and that is deliberate. A hashtag is a word, not an account or a piece of content, and reporting is conduct-based on this platform (a report always names a post or a person, routes to the admin panel, and emails a copy to safety@unitedfeminist.com, with no external recipient; this is locked). A member who sees a tag being used to abuse reports the post or the person using it, through the overflow menu that already exists on every card (P2 section 10). The report captures that post, and a moderator reviewing the case sees the tags the post carries. So abusive use of a tag arrives in the moderation console through the normal, already-built conduct path, attached to a real accused account, with no new member-facing flow and no new place for the report machinery to be gamed.

### 7.2 Staff suppress the tag itself, in two proportional tiers

What members cannot do (act on the word itself) staff can, because sometimes the tag as an amplification unit is the problem, independent of any single post. Suppression has two tiers, following the proportional-friction principle of the enforcement ladder (P2B section 5):

- **De-trend (moderator and above).** Removes the tag from the trending snapshot and from tag-search suggestions, so it is no longer amplified, while leaving its posts individually reachable (each post is still subject to the ordinary per-post ladder). This is the light, common action, the tag analogue of "remove from view without destroying," and it is scoped to moderators because it is a visibility control, not an account action. A de-trended tag simply never appears in trending again unless a staff member reinstates it.
- **Block the tag (admin and above).** The stronger action, for a tag that is itself abusive (a slur, a tag whose only purpose is harassment or doxxing). A blocked tag is removed from trending and search, and its tag page is replaced with a neutral unavailable state ("This topic is not available") rather than listing posts. It is scoped to admins because it acts on a whole topic at once, which is a broader stroke than any single-post action, and breadth is exactly what the role gating is for (P2B section 1). Blocking a tag does not by itself remove the underlying posts or action their authors; those are separate per-post and per-account decisions on the ordinary ladder, because a tag can be abused by some and used innocently by others, and the blunt instrument of "delete everyone who used this word" is wrong.
- **Both are reversible and both are audited.** De-trend and block both write to the hash-chained `audit_log` through `append_audit`, exactly as every other enforcement action does, so tag suppression is on the same accountable record as a removal or a suspension. Reinstating a tag is the ordinary distinct-verb confirmation (P2B section 5), not a typed gate, because it is reversible and low-stakes.

### 7.3 Brigade defenses, designed in

- **The distinct-person count is the first wall** (section 6.1): manufacturing a trend requires manufacturing people, not posts, which is far more expensive and is already fought at signup.
- **An anomaly flag for human review, not auto-removal.** Reusing the architecture document's report-velocity anomaly pattern (section 3.4), a scheduled job watches for a tag whose participation spikes abnormally from a cluster of very new or otherwise suspicious accounts, and flags it for a human in the moderation console as a calm signal ("this tag is spiking from new accounts"), the way the console already surfaces a reporter who has filed many reports in a day (P2B section 3.3). It does not auto-suppress, because auto-suppression on a velocity heuristic would hand a brigade the power to silence a genuine topic by making it look suspicious, and because this product's stance is that a human makes the call (P2B's calm-console principle). The flag informs; the moderator decides.
- **The existing signup defenses carry the weight against sockpuppets.** Ban-evasion hashing, per-IP rate limits, subnet-velocity and disposable-email auto-flagging already raise the cost of standing up the many accounts a distinct-person trend would require (the architecture document, section 3.1 and risk 12). Trending leans on those rather than inventing its own account-creation defenses.
- **No threshold that hides real data.** There is deliberately no "a tag must have N distinct people before it can trend" floor, because the owner has ruled out suppression thresholds and withheld counts, and because such a floor is exactly the "not enough data" coyness the brief forbids. A tag trends on its real recency-weighted distinct-person score; if that score is small because the platform is small, the surface shows it small and honest (section 6.4). The defense against gaming is the distinct-person unit and the human-reviewed anomaly flag, not a hidden minimum.

---

# PART 2. AT-MENTIONS

## 8. Parsing: keep the server, it is already right

The server-side mention parser in `create_post()` is correct and is not reopened. For the record, so the client (section 10) can be built to match it exactly, the parser: finds `@token` only at a word boundary (start of body or after a non-word character), where the token is 3 to 30 characters of `[A-Za-z0-9_]`; lowercases and deduplicates; resolves each token against a profile whose status is `active` or `restricted`; never resolves the author mentioning herself; never creates a `post_mentions` row or a notification across a block in either direction; and only writes a `mention` notification when the mentioned member has not muted the poster and has the `mention` preference on. The client renderer must apply the same word boundary and the same handle shape so that what looks like a mention is what the server treated as one.

The only server additions this document asks for are the "Who can mention you" preference gate and the per-post mention-notification cap, both in section 12, and both are small additions to this existing loop rather than a new mechanism.

## 9. Mention autocomplete in the composer

Typing a full handle from memory is error-prone and is how a mention ends up pointed at the wrong person or at nobody. The composer gains autocomplete.

- **Trigger.** As the member types `@` at a word boundary followed by one or more handle characters, an autocomplete surface appears offering matching accounts. It queries after the first character or two, debounced the way people search already is (the 300ms debounce in `SearchClient`), and it dismisses on a space, on Escape, or when the token stops looking like a handle.
- **Desktop presentation.** A popover anchored to the composer, shown just below the text field (anchoring precisely to the caret is a nicety, not a requirement; below the field is predictable and avoids covering what the member is typing). It is `surface-raised`, `shadow-e2`, `radius-md`, the same construction as the existing audience menu in the composer, so it needs no new component style.
- **Mobile presentation.** A horizontal-scrolling or short vertical strip docked directly above the composer action bar, which on mobile sits above the on-screen keyboard. The keyboard owns the bottom of the screen while typing, so the suggestions go between the field and the keyboard where the thumb already is, rather than in a popover the keyboard would cover. This is the conventional mobile mention-picker placement.
- **What a result shows.** Each row is the standard identity block at small size: the member's avatar (avatar-sm, P2E section 3) and the `@handle` at `text-label`, nothing else. No legal name, ever, consistent with handle-forward identity. An optional one-line bio preview at `text-caption` `text-tertiary` is acceptable if it helps disambiguate two similar handles, but the handle is the identity.
- **Ranking.** People you follow first, then accounts that follow you, then handle-prefix matches across the platform, so the common case (mentioning someone you actually interact with) is a near-instant single tap. This reuses the follow-graph signal the people search already has access to.
- **Blocked accounts are excluded.** An account you have blocked, or that has blocked you, never appears in autocomplete, because you cannot mention across a block anyway (section 8) and offering the suggestion would both mislead you and surface a person the block is meant to hide.
- **Selecting inserts `@handle` plus a trailing space** and dismisses the surface, so the member keeps typing without a manual space.
- **Accessibility.** The autocomplete is a listbox pattern tied to the text field (`aria-controls`, `aria-activedescendant`), arrow keys move the active option, Enter selects, Escape dismisses, and the whole thing is operable from the keyboard; every row is a 44px target. It never steals focus from the field; it decorates it.
- **Hashtag suggestion is an additive sibling.** The same surface, triggered by `#` instead of `@`, can suggest existing canonical tags as the member types, which has real value: it steers members toward the tag that already exists rather than fragmenting a topic across `#selfcare` and `#self_care`. It is designed to reuse the exact same autocomplete surface and the `search_tags` RPC. The recommendation is to ship mention autocomplete first (it is the one the brief asks for and the one with the clearest safety role) and add hashtag suggestion as a fast follow once the tag index exists; both are specified so the builder can do them together if that is cheaper.

## 10. Rendering and linking: fix the client

The post body renderer is replaced so that it links only real mentions and renders hashtags, and so it never produces a dead link or drifts.

- **Link only resolved mentions.** A mention in the body renders as an `accent` link to `/u/{handle}` only when it corresponds to a real, currently-reachable account; an `@token` that does not resolve renders as plain `text-primary` text, not a link. The authoritative source of "which tokens are real mentions" is the stored `post_mentions` for the post (which already hold the resolved member ids, set at post time), joined to the current profile to get the current handle and current status. This has three good consequences: a mention of a made-up handle is plain text instead of a link to a 404; a mention never silently re-points if someone later claims that handle, because the link is built from the stored member id, not from re-parsing the body text; and the displayed handle is always the mentioned member's current handle even if she has since changed it. Section 13 covers what happens when the resolved member is no longer reachable.
  - Build note: this means the feed, thread, and profile read functions must return, per post, the resolved mentions (member id plus current handle, filtered to reachable status), so the client can style and link exactly those tokens. This is a small addition to the read shapes and is listed in section 22. Until it lands, the safe interim behavior is to apply the server's word-boundary and handle-shape rules on the client so at least the regex matches the server, but the resolved-mention join is the correct end state.
- **Render hashtags.** A hashtag in the body (parsed with the same rules as the server, section 2) renders as an `accent` link to `/t/<canonical-tag>`, with the author's original casing preserved in the visible text and the canonical lowercase form used in the href. A `#token` that does not meet the tag rules (a pure number, a URL fragment) renders as plain text.
- **Appearance.** Mentions and hashtags both use `accent` on the post card's `surface` background, measured 6.26:1 light and 6.80:1 dark (P2 section 3.6), which clears AA for normal text in both themes. They are the only colored runs in body text, so they read clearly as "tappable" without underlining everything; an underline appears on hover and on focus. Tapping a mention or hashtag stops the card's own tap handler (the body links already call `stopPropagation`, as the current mention link does) so following a link never also opens the thread.
- **Accessibility of the links.** A mention link's accessible name is the `@handle`; a hashtag link's accessible name spells the tag clearly (for example "hashtag selfcare") so a screen reader does not read the `#` as "pound" mid-sentence or run a camel-cased tag together confusingly. Both are ordinary focusable links in reading order.

## 11. Notifications

Mentions reuse the notification system that already exists; nothing new is invented.

- **The notification.** When a member is mentioned, she gets a `mention` notification (the type already ships) reading "@handle mentioned you," with the post excerpt and a link to the post, exactly as the notifications surface already renders it. The actor is shown by avatar and `@handle` only, never a legal name.
- **Preferences.** Mention notifications are gated by the existing per-type preference in `notification_prefs` (the `mention` key), surfaced in Settings, Notifications (P2 section 8.2), and on by default, because being told you were addressed is a core, expected behavior. The server already honors this preference in `create_post`.
- **No notification across the protections.** The server already suppresses the mention notification when a block exists either way, when the mentioned member has muted the poster, or when the preference is off. Section 12 adds the "Who can mention you" gate to that same set of checks. The notification is the harassment-relevant surface (it is the ping that reaches a person), so the abuse controls in section 12 act primarily on whether the notification fires.

## 12. Abuse controls for mentions (non-negotiable on this product)

Mentions are a classic harassment vector: the summons that reaches past a block attempt, the tag-in that drags a woman into a pile-on. These controls are not optional polish; they are why the feature can ship on this platform at all.

- **A blocked person cannot mention you, in either direction, and this already works.** Because `create_post` checks `blocked_either` before writing a `post_mentions` row or a notification, a person you have blocked (or who has blocked you) who types `@you` produces no mention row and no notification, and the post itself is hidden from you by the block (the `posts_read` policy excludes blocked authors). So the block is a complete wall: he cannot ping you, and you do not see the attempt. This is the bidirectional block behavior the rest of the codebase uses, and mentions already honor it; this document confirms it as a requirement, so a future refactor cannot quietly drop the check.
- **Muting a person suppresses their mention notifications to you.** The server already declines to notify when the mentioned member has muted the poster. So if you mute someone, their mention of you does not light up your notifications, which is the correct soft-mute behavior (mute means "I do not want to hear from them"). Mute is soft, so if you deliberately visit the post you would still see the mention; mute quiets the ping, it does not rewrite history. This matches how mute already works for feed posts (P2 section 10.3).
- **A new setting: "Who can mention you."** P2 section 8.2 already reserved this control in the Privacy group; this document specifies it. Options, as a three-way choice: **Everyone** (default), **People you follow**, and **No one**. When set to "People you follow," a mention by an account you do not follow creates no mention notification and does not add you as a mentioned participant; when set to "No one," no mention ever notifies you. The control acts on the notification and on mentioned-participant status, which is where the harassment lives; the mention text in the body still renders as a link to your public profile, because your handle is public by design and hiding the rendered link would not remove the exposure (the post is already visible) while breaking ordinary reading. The default is Everyone because the platform has to be usable and because conventional behavior is the muscle-memory default (P2 section 0.1), with the stricter options one tap away for anyone being targeted. This mirrors the DM posture (P2C), where the default is permissive-but-safe and the member can tighten it. Whether the default should instead be "People you follow" is a genuine values call and is the one mention question put to the owner in section 23.
  - Build note: this is a key in `notification_prefs` (or a small dedicated column), read inside `create_post`'s mention loop in the same breath as the existing mute and preference checks. Listed in section 22.
- **A bounded number of mention notifications per post.** A single post that mentions twenty people to summon a crowd is a pile-on tool. The write path notifies at most a bounded number of mentioned members per post (ten is the recommended cap); beyond that, the post still renders and the mentions still link, but no further notifications fire. This blunts the mass-summon without affecting the ordinary case of mentioning one or two people, and it is a simple count in the existing loop. Repeated mention-harassment across many separate posts is conduct, handled by block and by report through the existing overflow menu, and by the mention-limit setting above.

Together these give a targeted member a graduated set of defenses: mute to quiet one person's pings, "People you follow" to quiet everyone she has not chosen, "No one" to turn mentions off entirely, and block to make the whole relationship disappear, with the pile-on cap protecting everyone by default.

## 13. Mentioning a suspended, banned, deactivated, or non-existent handle

A mention should never link to a dead end or notify someone who cannot participate. The rule is one rule, applied by rendering links from the stored resolved mentions joined to current status (section 10), so correctness falls out of the data rather than being special-cased per state:

- **A non-existent handle** (`@madeup`, or the reserved misspelling `@herciety`, which has no real account) never resolved at post time, so there is no `post_mentions` row, nothing to notify, and nothing to link; it renders as plain text. Honest and self-correcting.
- **A suspended, banned, deactivated, or deleted account** does not satisfy the "currently reachable" (active or restricted) status that the render-time join requires, so a mention of such an account renders as plain text and links to nothing while that state holds, and no notification was or is sent. Because the link is computed at render time from the stored member id joined to the member's current status, a mention of a member who was active when mentioned and is later suspended stops linking while she is suspended and links again automatically if she is restored, with no edit to the post and no stored-state drift. A banned or deleted account never becomes reachable again, so the mention stays plain text permanently, which is correct: it points at nobody who can be reached.
- **Why plain text rather than a disabled-looking link.** A grayed-out "this account is unavailable" affordance on a mention would both clutter the body and, for a suspended or banned account, quietly advertise that account's enforcement state to anyone reading, which is exactly the kind of status leak the moderation design works to avoid (P2B constraint 0.1 keeps enforcement state off public surfaces). Plain text says nothing about why the handle does not link, which is the private-by-default behavior.

---

# PART 3. REPOSTS

## 14. Plain repost versus quote-post: the recommendation

The brief asks for a recommendation and says not to assume both ship. The recommendation is clear.

**Ship plain repost now. Defer quote-post.** The reasoning, in order of weight:

1. **Quote-post is the quote-dunk vector, and this product has already decided not to amplify it.** P2B section 11 explicitly refuses "quote-dunk and pile-on chains" as a ranking signal and names them a harassment vector: "A quote post that drives a crowd onto an original author is a harassment vector, not a discovery signal." Shipping quote-post now, on a safety-first platform built for women some of whom are hiding from a specific person, would add the single most abuse-prone amplification mode the product has, before the moderation tooling and the community norms are mature. Plain repost, by contrast, adds no words of its own; it is pure "I endorse this, see it too," so it structurally cannot be a dunk.
2. **The owner asked for plain repost, in her own words.** Her request was to "repost what they see in their feed." That is plain reposting: carry a post to your audience unchanged. She did not ask for quote-commentary, and the brief is explicit that both must not be assumed.
3. **Plain repost is the clean positive signal the ranking already wants.** Discover is positive-signal-only and a repost may only ever be a positive signal (locked). A plain repost is an unambiguous positive endorsement, exactly like a like, and it slots into the existing ranking without introducing anything negative (section 18). A quote-post's engagement is the ambiguous case the ranking already refuses, because a quote can be a pile-on whose engagement must not lift either the quote or, through it, its target.
4. **Quote-post remains a clean additive feature later.** The schema blueprint already reserves `posts.quoted_post_id` and the `quote` notification type, so adding quote-post later is additive, not a restructure. When it is added it should arrive with its own safety design: a quote-audience control, honoring the spirit of the original poster's `reply_control` (a member who limited who can reply very likely also wants to limit who can amplify-with-commentary), and a notification posture that does not help assemble a crowd. None of that is needed to ship plain repost now, and attaching it to this phase would slow the thing the owner actually asked for.

So this document specifies plain repost fully, and designs the repost control so that the quote option has an obvious, already-placed home for when it ships (section 15), without building it. This is a recommendation; the owner can choose to ship both, and section 23 puts the choice to her.

## 15. The repost interaction, from the feed

- **Where the control lives.** The post card action row (P2 section 4.2) gains the Repeat glyph between Reply and Like, the third action P2 section 4.2 always intended and the Phase 2 build did not yet add. It is a 44px target with the glyph and, once there is activity, a count at `text-caption` `text-tertiary`, hidden at zero like every other count (locked rule).
- **Tapping it.** Tapping the Repeat glyph opens a small two-item sheet (bottom sheet on mobile, small popover on desktop, the same constructions the overflow menu already uses): **Repost** and **Quote**. With quote-post deferred (section 14), the Quote item is present but disabled with a quiet "Quote arrives soon" caption, or omitted entirely at the build's discretion; the recommendation is to omit it until quote ships so there is no dead control, and to add it in place when quote is built. If the owner elects to ship both, Quote opens the composer in quote mode (the composer with the original rendered as a nested compact card above the field, per P2 section 4.4).
- **A plain repost is one optimistic tap.** Choosing Repost applies immediately and optimistically: the Repeat glyph fills and turns `accent` (the active treatment the like action already uses), the count increments, and a toast confirms "Reposted" with an **Undo** action, held a little longer than the default toast the way the follow undo is (P2 section 4.9), because its job is to catch a mis-tap. There is no confirmation dialog; a plain repost is reversible and low-stakes, so it gets the same optimistic, undo-backed treatment as like and follow, not the friction of a modal.
- **Undo.** Undo is either the toast's Undo action in the seconds after, or tapping the now-active Repeat glyph again at any later time, which removes the repost optimistically and clears the active state. Removing your own repost is cheap and unconfirmed, because undoing something you did should be as cheap as doing it (the same principle as the follow undo).
- **You cannot repost your own post.** Reposting your own post is redundant (it already sits on your profile and in your followers' feeds) and reads as self-promotion noise, so the Repeat control on your own card offers no Repost (the overflow menu's own-post actions are unchanged). This is a small decision made here, not an owner question.
- **Accessibility.** The Repeat control carries an `aria-label` that includes state and count ("Repost, 3 reposts" / "Reposted, 4 reposts"), announces the state change politely on activation, and the two-item sheet is a focus-trapped menu like the overflow menu. Under reduced motion the fill is an instant swap with no animation, matching the like action.

## 16. How a repost renders, and attribution

- **In the feed.** A repost renders as the original post card, unchanged in its anatomy, with a slim attribution line above it at `text-caption` `text-tertiary` with the Repeat glyph: "@handle reposted" (or "@you reposted" for your own). The card below is the original author's: the original author's avatar, `@handle`, timestamp, body, and counts, and tapping it opens the original thread. Attribution is therefore layered correctly: the small line credits the reposter for bringing it to you, and the card itself keeps the original author as the primary identity, so a repost never misrepresents whose words these are. If the original author is someone you do not follow (common in the Following feed, where you follow the reposter but not the author), the card shows the Follow pill, exactly as P2 section 4.7 already anticipated.
- **Deduplication.** If several people you follow repost the same original, it appears once in your feed, attributed to the people-you-follow who reposted it: "@handle reposted" when it is one, and "@handle and N others reposted" when it is several. Showing the same post many times because many people you follow reposted it would be noise; collapsing it to one card with aggregated attribution is the conventional and calmer behavior.
- **On a profile.** A member's reposts appear in her profile's Posts tab, interleaved with her own posts in reverse chronological order by repost time, each carrying the "@handle reposted" attribution line so it is never confused with something she wrote. This is the conventional profile-timeline behavior (reposts live in the main timeline, visibly marked) and it keeps the Posts tab the complete picture of what she has put in front of people, authored or amplified. A dedicated "Reposts" tab is the alternative, and it is noted (section 24) as a clean option if the owner later prefers reposts kept separate, but interleaving in Posts matches muscle memory and is the recommendation.
- **Counts.** The reshare count shows on the Repeat control, hidden at zero. A repost does not get its own separate like and reply counts; interacting with the card interacts with the original post, because the repost is a pointer to that post, not a copy of it.

## 17. What happens to a repost when the original changes state

A repost is a pointer to a post, so its visibility is entirely derived from the original's state and from the relationships involved. A repost renders only when all of the following hold, and it silently does not render otherwise; there is no "this was deleted" stub, because a stub on every stale repost would be noise and, for a removed post, would re-surface the fact of removal.

- **The original must be visible.** If the original is deleted by its author (`removed_author` or a set `deleted_at`) or removed by moderation (`removed_moderation`), the repost shows nothing. A reposter is not penalized for having reposted something later taken down; her repost simply yields no card. For a moderation removal this is also the correct safety behavior: the content is gone from every public surface, and a repost must not be a side door back to it.
- **The original author must be reachable.** If the original author is suspended, her posts are hidden while the suspension holds (P2B section 8.3), so reposts of them are hidden too and reappear automatically if she is reinstated. If she is banned or deleted, her content is gone permanently, so reposts of it never render again. Deactivation hides like suspension.
- **No block between the viewer and either party.** Standard bidirectional block filtering: you never see a repost by someone you have blocked or who has blocked you, and you never see a repost of a post by someone you have blocked or who has blocked you. The block is a wall around both the reposter and the original author from the viewer's side.
- **No block between the reposter and the original author.** This is the less obvious one and it matters. If a block exists in either direction between the reposter and the original author, the repost is suppressed everywhere. This prevents a blocked person from continuing to carry and amplify the content of someone who blocked her (attaching her name to that author's words against the author's wishes), and it prevents the reposter from using a repost as a way to keep engaging with someone she has blocked. A block between two people dissolves the amplification link between them in both directions.

All of these are read-time filters in the repost-aware feed and profile read functions, built from the pieces that already exist: the `visibility` check, the author-status check, and `blocked_either`. They are listed for the build in section 22. The principle is that a repost never has more reach or more persistence than the original and the relationships would allow on their own.

## 18. Reposts, Discover ranking, and notifying the author

- **A repost is a positive signal in Discover, exactly like a like.** Discover ranking is positive-signal-only and a repost may only ever be a positive signal (locked). P2B section 10 already names both halves of how reposts should count, it just could not wire them because the schema was not there yet (the Discover build scoped reshares out honestly for that reason). This feature adds the schema, so Discover now includes: the reshare count on a post as a positive aggregate endorsement (used gently, reach-normalized, the same way the like count is, so a small account's genuinely-reposted post is not buried under a big account's merely-okay one), and "authors whose posts you have reposted" as a personal affinity signal alongside "authors you have liked and followed." Both are additions to the existing positive-signal set, not a new kind of ranking.
- **Never a negative signal, and the quote-dunk refusal stands.** A repost count is only ever used to lift, never to penalize, and the refusals in P2B section 11 are unchanged. Because this phase ships plain repost only, there is no quote engagement to tempt the ranking into amplifying a pile-on; if quote ever ships, its engagement must continue to be refused as an amplification signal (P2B section 11 already says so), so a quote-dunk can never lift either the quote or its target.
- **The original author is notified of a repost, by default.** A repost sends the original author a `reshare` notification (the type is reserved in the blueprint and ships with this feature), reading "@handle reposted your post," with a link to the post. It is a positive, welcome signal, so it is on by default, gated by a per-type preference in `notification_prefs` like every other notification, and it honors the same protections every notification does: never to yourself, never across a block, and not when the author has muted the reposter. Like other high-volume positive notifications (likes), it is a candidate for batching later ("@handle and N others reposted your post"); batching is an additive refinement and is not required for first ship. Default-on is a small decision made here, not an owner question.

## 19. Interaction with the existing reply_control setting

`reply_control` (Everyone, People you follow, Mentioned only) governs who may **reply** to a post. It does not govern who may **repost** it, and plain repost is available on any post the viewer can see regardless of its reply_control. The reasoning: reply_control is about participation in the conversation, and a plain repost adds no words to the conversation; it is amplification, the same "voice" as a like, which reply_control also does not restrict. A member who has set "only people I follow can reply" has limited the conversation, not forbidden endorsement, and a plain repost cannot turn into a dunk because it carries no commentary. So:

- A plain repost is allowed even on a post you could not reply to (for example a post whose author restricted replies to "mentioned only" and did not mention you). Reposting is not replying.
- There is deliberately no separate "who can repost me" control in this phase. Plain repost, having no commentary, does not create the harm that such a control would guard against, and adding a control nobody needs is friction. This is a decision made here.
- The nuance for the future: quote-post does add commentary and therefore can dunk, so if quote ships it must respect an audience control and should honor the spirit of reply_control (a poster who limited replies likely wants to limit quote-amplification too), as section 14 notes. That is a quote-post concern, not a plain-repost concern, and it does not affect anything shipping now.

---

# PART 4. CROSS-CUTTING

## 20. Accessibility

Everything in the Phase 2 accessibility specification (P2 section 12) is inherited unchanged: 44x44 minimum targets, visible focus (2px `--focus-ring`, 2px offset), full keyboard operation, focus-trapped and Escape-dismissable overlays that restore focus to their trigger, reduced-motion fallbacks, and color independence. The additions specific to these three features:

- **Mentions and hashtags in body text** are ordinary focusable links in reading order; the mention's accessible name is the `@handle`, and the hashtag's accessible name spells the tag clearly ("hashtag selfcare") so the `#` is not read as "pound" and a camel-cased tag is not run together. Their `accent`-on-`surface` color (6.26 light, 6.80 dark) is reinforced by an underline on hover and focus, so "this is a link" is never carried by color alone.
- **Mention autocomplete** is a listbox tied to the text field (`aria-controls`, `aria-activedescendant`), arrow-navigable, Enter to select, Escape to dismiss, 44px rows, and it never steals focus from the field (P2 section 12.2's rule for surfaces that assist without grabbing focus).
- **The repost control** exposes its state and count in its accessible name ("Repost, 3 reposts" / "Reposted, 4 reposts"), announces the state change on a polite live region, and its two-item sheet is a focus-trapped menu like the overflow menu. The attribution line ("@handle reposted") is real text, so a screen-reader user hears who reposted, not just a visual glyph.
- **Trending** rows are a list of links; each row's accessible name is the tag and its count ("hashtag selfcare, 6 people"), so the count is conveyed, not just shown. The module is reachable and announced but does not steal focus (same rule as the new-posts pill and toasts).
- **Tag page** uses the same post-article semantics as the feed (P2 section 12.4), with the tag as the page heading.
- **Motion** is all inherited: the repost fill reuses the like activation (or an instant swap under reduced motion), the autocomplete and the two-item sheet reuse the existing popover and sheet motions, and trending has no motion of its own. Nothing here adds a new animation.

## 21. Tokens: zero added, with the measured contrast table

These features introduce **no new design token**. Every surface is a composition of existing, already-measured tokens.

- Mention and hashtag links: `--accent` on `--surface` (the post card). Existing.
- Autocomplete popover and the two-item repost sheet: `--surface-raised`, `--shadow-e2`, `--radius-md`, with hovered and active rows in `--accent-subtle`. Existing.
- Trending module and tag labels: `--accent` on `--surface` (Search) or on `--background` (right rail); counts in `--text-tertiary`. Existing.
- The repost active state: `--accent` fill on the Repeat glyph, the same treatment the like action already uses. Existing.
- Tag-page header and empty states: the existing type scale and the P2 section 9 empty-state pattern. Existing.
- Suppressed-tag unavailable state and de-trend/block confirmations: the existing confirmation and neutral-state patterns (P2 section 10.2, P2B section 5). Existing.

**Measured contrast (WCAG 2.x sRGB; ratios reused from P2 section 2.3 and the base system):**

| Foreground | Background | Light | Dark | Threshold | Verdict |
| --- | --- | --- | --- | --- | --- |
| mention / hashtag link `--accent` | post card `--surface` | 6.26 | 6.80 | 4.5 | pass |
| trending tag link `--accent` | right rail `--background` | 6.26 | 6.80 | 4.5 | pass |
| autocomplete / sheet row text `--text-primary` | `--surface-raised` | 16.91 | 13.27 | 4.5 | pass |
| active / selected row `--accent` text | `--accent-subtle` | 6.03 | 5.55 | 4.5 | pass |
| undo action `--accent` | toast `--surface-raised` | 7.10 | 5.58 | 4.5 | pass |
| count / descriptor `--text-tertiary` | `--surface` | 4.88 | 5.11 | 4.5 | pass |

Nothing here is new to measure. The `--thread-rail`, `--skeleton-base`, and `--skeleton-sheen` tokens from Phase 2 are untouched; no color, type, spacing, radius, elevation, or motion token is added or changed.

## 22. Build handoff: the schema changes to assign

Context for the later schema and code passes. This document does not write migrations; it names what a migration must add so the build brief can assign one, per the project's rule that migrations are serialized and owned.

**Schema pass (hashtags, additive):**

- A `tags` entity table: folded canonical string (unique key), display string, moderation status (`active` / `detrended` / `blocked`), created-at. Section 3.
- A `post_tags` join (post_id, tag_id), written inside `create_post()` in the same loop that resolves mentions, applying the parse rules in section 2 (word boundary, at least one Unicode letter, 64-character cap, at most 30 distinct tags per post, dedupe, fold to canonical). Index tag_id for the tag page. Section 3.
- A `trending_tags` snapshot table (tag_id, score, distinct-person count, window bound, computed-at), rewritten by a pg_cron job that computes the 48-hour recency-weighted distinct-person score (sections 6.1, 6.3). Reuse the jobs/pg_cron machinery the architecture document already describes.
- A `search_tags` RPC: prefix match on the canonical column, return tags and post counts, exclude suppressed tags (sections 5, 7).
- A tag-page read function: posts for a tag, newest first, filtered by `visibility = 'visible'`, by `blocked_either` in both directions, by mutes, and by the "show me less" down-rank, returning the author's `@handle` only (never `display_name`), matching every other feed read function's shape (section 4).
- Staff suppression functions: de-trend (moderator and above) and block-tag (admin and above), each setting the tag status and writing `append_audit` (section 7).

**Schema pass (mentions, small additions to an existing path):**

- Return resolved mentions (member id plus current handle, filtered to reachable status) in the feed, thread, and profile post read shapes, so the client links only real mentions and never drifts (section 10).
- A "Who can mention you" preference (a `notification_prefs` key or a small column), read inside `create_post`'s mention loop alongside the existing mute and preference checks (section 12).
- A per-post cap on mention notifications (recommended 10) in that same loop (section 12).

**Schema pass (reposts, additive, blueprint already reserves the shapes):**

- The `reshares` table, the `posts.reshare_count` column and its counter maintenance, and the `reshare` notification type, all of which the architecture document's blueprint already describes as the additive migration this feature triggers (the architecture document, section 2).
- Reshare create and delete paths (block-aware, disallowing self-repost), and the `reshare` notification (default on, pref-gated, honoring block/mute/self), section 15 and 18.
- Repost-aware feed and profile read functions that interleave reposts with attribution and apply the full suppression rules in section 17 (original visible, author reachable, no block in either direction between viewer and either party, and no block between reposter and original author), deduplicating multiple reposters.
- The Discover ranking additions: reshare count as a positive aggregate signal and reposted-authors as a positive affinity signal, mirroring the existing like signals (section 18).

**Code pass:**

- The `PostBody` renderer rewrite (link only resolved mentions, render hashtags), the mention and hashtag autocomplete surfaces (section 9), the Repeat action and its two-item sheet (section 15), the repost attribution rendering (section 16), the tag page (section 4), the tag-search routing in the search client and the "Search @handle or #topic" copy (section 5), the Trending module on Search and in the right rail (section 6), the "Who can mention you" control in Settings, Privacy (section 12), and the staff tag-suppression controls in the moderation console (section 7).

## 23. What genuinely needs the owner

Short, and only the calls this design cannot settle on its own. Each has a marked recommendation.

1. **Plain repost now, or both plain repost and quote-post now?**
   - (a) **Ship plain repost now; add quote-post later with its own safety controls.** [recommended, section 14]
   - (b) Ship both plain repost and quote-post in this phase.
   - Recommendation (a), because quote-post is the quote-dunk harassment vector the product has already decided not to amplify (P2B section 11), the owner's own words asked for plain reposting ("repost what they see"), and quote-post is cleanly additive later.

2. **Default for "Who can mention you."**
   - (a) **Everyone, with the stricter options one tap away.** [recommended, section 12]
   - (b) People you follow, as the cautious default.
   - (c) No one.
   - Recommendation (a), because the platform has to be usable and conventional (P2 section 0.1) and the targeted member has mute, the two stricter settings, and block available immediately; this mirrors the DM default posture (P2C). This is a real values call and the owner may reasonably choose (b) given the threat model.

Everything else in this document is a design decision already made here, with its reasoning: the tag parse rules and canonical casing, the `/t/` route and tag-page ordering, the single-box two-axis search, the 48-hour recency-weighted distinct-person trending algorithm and its placement and thin-cohort behavior, the two-tier tag suppression and who can do it, the mention render fix, the autocomplete design, the mention-notification cap, the repost interaction and attribution, the repost lifecycle rules, the repost-as-positive-signal ranking and the default-on repost notification, the no-self-repost rule, and reply_control's independence from plain reposting. None of those needs the owner's time.

## 24. Out of scope, deliberately

- **Quote-post.** Recommended for a later phase (section 14), not built here. Its schema column is already reserved, so it is additive when it comes, and it must arrive with its own audience control and pile-on-safe notification posture.
- **Following a hashtag.** No per-tag subscription or tag-follow notification in this phase (section 3). A clean additive feature later.
- **A "Top" ordering on tag pages.** Latest (reverse-chronological) ships first; Top (positive-signal ranked, reusing Discover's ranking) is noted as additive (section 4), deferred because on a founding cohort it would be nearly identical to Latest.
- **Hashtags and mentions outside the post body.** Bios and display names are not parsed for tags or mentions in this phase (section 2); bios are a separate surface.
- **Post full-text (content) search.** Tag search finds tags, not text inside posts; searching the body of posts remains the Phase 5 feature the architecture document already scopes (section 5). Nothing here brings it forward, and people search stays @handle only.
- **A dedicated "Reposts" profile tab.** Reposts interleave in the Posts tab (section 16); a separate tab is noted as a clean alternative if the owner later prefers them kept apart.
- **Batched repost and mention notifications** ("@handle and N others reposted your post"). An additive refinement noted in section 18; first ship sends them individually, pref-gated, like likes today.
- **The actual component code, API routes, RPCs, and database migrations.** This is a design specification; those are the code and schema passes it hands off to in section 22.

Design done.
