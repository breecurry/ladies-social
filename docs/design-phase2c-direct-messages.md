# Design, Phase 2C: Direct Messages

This document designs the direct messaging surface for Hersciety. It is a design specification, not application code and not a migration. It extends the token system and the patterns already implemented in `src/app/globals.css` and set out in `docs/design-phase2-social-core.md` (hereafter P2) and `docs/design-phase2b-moderation-and-discover.md` (hereafter P2B). It does not redesign the shell and it introduces no new design patterns without saying so plainly.

Direct messages were wrongly scoped out of the build. They are not a later addition. The platform's Terms of Service already contains a seven-subsection DM chapter (section 7.1 through section 7.8), the Privacy Policy has an entire standalone section titled "Direct Messages: An Important Disclosure," and the owner personally overruled a security recommendation about DM encryption. The written documents describe DMs as a shipped feature. The product has none. This design closes that gap.

One fact governs every decision below, and it is stated here so it is never forgotten in a layout argument: **members of this platform are hiding from specific people, exes, stalkers, and family.** A DM system is the single most dangerous surface a platform like this can build, because it is the one place the person a member is hiding from can try to reach her directly. The design is drawn for that member first and everyone else second.

---

## 0. How to read this document

- **Tokens** are the CSS custom properties already implemented in `src/app/globals.css` and enumerated in P2 section 2: `background`, `surface`, `surface-raised`, `border`, `border-strong`, `text-primary`, `text-secondary`, `text-tertiary`, `accent`, `accent-fill`, `accent-subtle`, `on-accent`, `success`, `success-subtle`, `warning`, `warning-fill`, `danger`, `danger-fill`, `danger-subtle`, `focus-ring`, `scrim`, the eight type roles, the base-4 spacing scale, the radius scale (sm 6, md 10, lg 14 for cards and DM bubbles, xl 20 for modals, 2xl 28 for bottom sheets, full for avatars and pills), the elevation scale (e1 cards, e2 popovers and toasts, e3 modals and sheets, plus sticky), the motion durations and easings, and the Phosphor icon set with Regular weight inactive and Fill weight active.
- **This document adds no new color, type, spacing, radius, elevation, or motion token.** Section 22 states this explicitly and lists the two bubble compositions it builds from existing tokens. Every foreground and background pairing it relies on is already measured, either in the base system or in P2 section 2.3; section 22 lists each pairing and the measured ratio it reuses.
- **References** use the form "P2 section 4.2" and "P2B section 3.2" to match the house style of the two specs this extends.
- **The two hard constraints in 0.1 and 0.2, and the threat model in 0.3, govern every surface in this document.** They are not style. Read them first.

### 0.1 Hard constraint one: the legal name never appears in any DM surface

`display_name` is the member's real legal name. It is nullable, trigger-locked to be either NULL or the member's own verified legal name, and its public display is opt-in and off by default (P2 section 3.2, and the identity migration). This is the most dangerous thing in the product to get wrong, and DMs multiply the danger, because a DM is a private channel where a member feels she is talking to one known person and a careless build would feel entitled to "show who she is really talking to."

Every DM surface in this document identifies every person, sender and recipient alike, by **`@handle` only**. There is no inbox row, no conversation header, no message request, no composer recipient field, no push notification, no system line, and no DM report in this document that renders `display_name`. The @handle leads everywhere, exactly as it does in the feed, threads, notifications, and search. A member can hold an entire conversation, accept or decline a request, and report a message without the legal name of any party appearing anywhere. If a future revision feels the urge to "show the real name so you know who you are talking to," that urge is the violation. Write it down and stop.

The opt-in legal-name display, where a member has chosen to show hers publicly (P2 section 7.1), follows her into DMs the same way it does the feed: it appears only on her profile, reached by tapping her @handle, never inline in a conversation, a request, or a notification.

### 0.2 Hard constraint two: the irreversibility rule

On 2026-10-06 the owner destroyed a live production database because an irreversible one-click action offered two choices that differed only by letter case. This is now a product rule and a hard constraint, stated once in P2B section 0.2 and binding here without re-derivation:

**Every destructive or irreversible action in this product must differ from its neighbour by more than casing or colour. It must differ by a distinct verb, a distinct placement, and a distinct visual weight.**

DMs contain several destructive actions that sit close together, Delete, Leave, Block, and Report, and a naive menu would stack them as near-identical red rows. They are not allowed to be. Everywhere below:

- A destructive action and its cancel are never a matched pair that reads the same. The safe choice is a left-aligned ghost control with an active, reassuring verb ("Keep conversation", "Cancel"); the destructive choice is a right-aligned filled `danger-fill` control with a specific destructive verb ("Delete for me", "Block @handle").
- Delete, Leave, and Block are never three adjacent rows differing only by word. They carry different verbs, different glyphs, different placement in the menu, and Block carries a confirmation the lighter actions do not.
- The one unrecoverable DM action, "Delete for me" of an entire conversation, states its honest consequence in words before it fires (19.3), because unlike a removable post it cannot be restored from the server under end-to-end encryption.

### 0.3 The threat model that governs every default

The member this design protects is being contacted, or trying not to be contacted, by a specific person. That single fact decides the defaults, not engagement metrics:

1. A person she is hiding from must not be able to make her phone buzz, light up, or show a name on a lock screen (section 16).
2. A stranger must not be able to flood her with messages or learn anything about her by messaging her (sections 6, 10, 16).
3. She must be able to shut messaging down completely and permanently for any one person, and broadly for everyone she has not chosen (sections 6, 7, 14).
4. When she reports a threat in her inbox, the report must reach a human who can act, and the platform must be honest about exactly what it can and cannot see (Part 1, section 15).

Every default in this document resolves toward the member's safety, even at a cost to reach and growth. That trade is the product.

---

# PART 1. THE ENCRYPTION DECISION

This is the load-bearing decision in the whole document, so it is placed first, because it shapes every surface that follows. It is also an unresolved conflict that the owner must settle, and this part is written to let her settle it from an honest account rather than to settle it for her. It presents the conflict exactly, shows that end-to-end encryption and the ability to act on a report are not mutually exclusive, lays out three concrete options with honest trade-offs, recommends one, and states plainly the one capability that is given up.

## 1. The conflict, stated exactly

Three positions are currently in contradiction.

1. **Grove-Security recommended non end-to-end encryption.** TLS in transit, AES-256 at rest, the platform holds the keys, and DM content is readable by the platform, in practice only when reported, so that reported harassment can actually be investigated. This is the safest-to-moderate posture and the cheapest to build.

2. **The written Terms of Service already tells members DMs are not end-to-end encrypted.** ToS section 7.6 states, in the document members click "I agree" on, that "Direct messages are not end-to-end encrypted" and that "Every image sent in a direct message is automatically scanned for child sexual abuse material using automated hash-matching." Privacy Policy section 5 says the same in a standalone bold line. The documents describe the non-E2E design as shipped.

3. **The owner wants end-to-end encryption, and she was right on the facts.** She pushed back on the claim that E2E and moderation are mutually exclusive, in her own words: "plenty of platforms use e2e encryption in their DM's. that doesn't sound right at all." She is correct. WhatsApp, Signal, iMessage, and Messenger are end-to-end encrypted and still act on abuse reports. The reconciliation they use is client-side reporting: the reporting member's own device, which can read the messages, attaches the decrypted content to the report. The platform never needs to read the channel to act on a complaint about it.

The earlier framing that E2E and moderation cannot coexist was wrong, and the owner caught the error. This part is built on the corrected understanding.

## 2. What E2E plus moderation together actually require

End-to-end encryption means the platform cannot read a message in transit or at rest; only the sender's and recipient's devices hold the keys. Acting on a report under that constraint requires three mechanisms, all of which are established practice, not invention.

- **Client-side report with attached evidence.** The platform cannot pull a conversation it cannot read. Instead, when a member reports messages, her device, which can read them, attaches the specific decrypted messages to the report. The member is consenting, in that moment, to share exactly those messages, and nothing else is exposed. This is how Signal, WhatsApp, and Messenger handle abuse reports today.

- **Sender attribution the recipient can prove, and the reporter cannot fabricate.** Without this, a client-side report is just the reporter's unverifiable claim about what someone said. The accepted cryptographic answer is message franking (Facebook shipped it in 2016; Grubbs, Lu and Ristenpart formalised it, CRYPTO 2017). Each message carries a committing tag that lets the platform, at report time, verify two things at once: that the attached plaintext is exactly what was sent (the reporter did not fabricate or edit it) and that it was sent by the accused account (the sender cannot deny it). One caution the build must honour: the committing construction must be a committing AEAD or the HMAC-key construction, never raw AES-GCM, because raw AES-GCM franking was broken by the "invisible salamanders" attack (Dodis et al., CRYPTO 2018). This is an engineering requirement on the crypto, surfaced here only so the design of the report flow (section 15) can promise "verified" honestly.

- **An honest account of what the platform genuinely cannot see.** Under E2E the platform cannot read an unreported message, cannot proactively scan message content, cannot search DMs server-side, and cannot put message content into a push notification. The design must tell members this plainly rather than imply a privacy it cannot deliver, and must tell moderators that a DM report's evidence is only what the reporter attached (section 15). The honesty is the feature: a platform for survivors should not claim to read inboxes it cannot read, nor hide that reporting means handing over the messages.

With these three in place, the owner's goal and the moderation goal are both met: the platform cannot read the channel, and it can still act, with cryptographically verified evidence, on a report.

## 3. The options, with honest trade-offs

### Option A. Non-E2E, as the ToS currently describes

The platform holds the keys. DMs are encrypted in transit (TLS) and at rest (AES-256), and the platform can technically read any message, in practice gated by policy to reports, credible-safety investigations, CSAM scanning, and legal process.

- **For it:** simplest and cheapest to build; no external crypto audit; enables proactive, server-side CSAM hash-scanning of DM images (the capability section 7.6 currently promises); enables server-side search, server-generated link previews, rich push with content, trivial multi-device, and trivial new-device history; and the legal documents already match it, so no rewrite is needed.
- **Against it:** the platform can read every member's private messages. "We do not read your messages" is a policy promise, not a technical guarantee. A server compromise, a hostile insider, a subpoena, or a future change of heart exposes the entire corpus of DMs. For a userbase whose defining need is to be safe from a specific person, "trust us not to look" is a materially weaker promise than "we cannot look." And it is the posture the owner explicitly rejected after being shown the moderation objection was false.

### Option B. End-to-end encryption now, text-only, with franking and client-side reporting (recommended)

DMs are end-to-end encrypted from the first release. Text ships first; the platform cannot read messages. Reporting works through client-side report-with-evidence and franking (section 2). This is the architecture the owner asked for and the one section 2 shows is compatible with moderation.

- **For it:** gives the owner the posture she wants and that the threat model argues for. The platform genuinely cannot read unreported DMs, which is the strongest promise this product can make to a woman hiding from someone. Reports still work, with cryptographically verified evidence. A post-quantum handshake (hybrid X25519 plus ML-KEM-768, the approach Signal uses) defeats "harvest now, decrypt later." Content-less push is forced, which happens to be exactly the safe default this userbase needs anyway (section 16), so a constraint and a safety goal align.
- **Against it, stated honestly:** it is more engineering than Option A, and the crypto must be built on a permissively licensed implementation, not the official Signal library, which is AGPLv3 and would force the whole product open-source. An external cryptographic audit is mandatory before the encryption ships; rolling a ratchet without one is how E2E projects get quietly broken. Browser end-to-end encryption is materially weaker than native, roughly 60 to 80 percent of the security, because web app code is re-downloaded on roughly every connection, so a compromised server can serve hostile JavaScript that reads plaintext above the crypto layer; the mitigations (strong CSP, subresource integrity, httpOnly and Secure and SameSite cookies) are real reduction, not a cure, and the honest framing is the same one WhatsApp Web and Messenger Web accept. Multi-device and new-device history are the parts that make E2E ship late and must be scoped deliberately (section 13, section 19). And it gives up one capability, stated in full in section 4.

### Option C. Non-E2E interim now, migrate to E2E later

Ship Option A to meet the urgency, on a schema built so that turning on E2E later is a configuration change rather than a rewrite (the empty `user_devices` and `one_time_prekeys` tables already in the migrations exist precisely for this), then migrate to Option B.

- **For it:** fastest path to shipping any DMs; defers the crypto audit and the hard multi-device work; keeps the legal documents correct for now.
- **Against it, and this is why it is not recommended for this userbase:** the interim is not a neutral waiting room, it is the highest-risk period. During it the platform holds everyone's keys, the cohort is small, and the founder is personally handling escalations; a breach then exposes exactly the people the product promised to protect. The migration is not as clean as "flip a flag" for message history: messages written under server keys cannot be retroactively made unreadable to the server, so either old history stays server-readable forever or it is dropped at migration. And it forces the legal documents to be rewritten twice, once to describe the interim and once to describe E2E, which doubles the chance the documents and the practice drift apart, the precise failure mode that already bit this project once (the ToS omitted the DM-scanning disclosure for a time). It is the right answer only if shipping a DM this quarter outweighs every one of those costs, and for a platform whose entire promise is safety from a specific person, it does not.

## 4. Recommendation, and precisely what capability is given up

**Recommended: Option B. End-to-end encrypt DMs from the first release, text-only, with franking and client-side report-with-evidence.** Build every surface and flow in this document now; gate the encryption itself on the mandatory external audit; ship the moment the audited crypto lands. Do not ship a non-E2E interim (Option C) for this userbase, and do not ship the readable-by-the-platform posture (Option A) the owner already rejected on sound reasoning.

The decisive reasons: the owner was right that E2E and moderation coexist, so the original reason for non-E2E has fallen away; the threat model wants "we cannot look" over "we promise not to look"; and the one capability E2E gives up does not exist yet.

**The one capability that is given up under E2E, stated plainly:** proactive, server-side scanning of DM images for child sexual abuse material (CSAM) by automated hash-matching. The platform cannot scan content it cannot read. ToS section 7.6 currently promises exactly this scanning of every DM image. Under E2E that promise cannot be kept.

But the loss is not incurred at launch, and this is the heart of the recommendation. **The platform has no image upload anywhere, in posts or in DMs, and this first DM release is text-only.** There are no DM images to scan, so turning on E2E for text costs zero CSAM-scanning capability today. The loss crystallises only if and when DM images are ever enabled, which is a separate, gated decision designed in section 17. What remains true under E2E regardless: public images, once image upload exists at all, are still scanned (they are not E2E), reports of DM content are still acted on with verified evidence, and a CSAM match surfaced through a report still routes to the Owner-only NCMEC and law-enforcement escalation (P2B section 4.8). Also given up, and all acceptable here: server-side DM full-text search (DMs are not searchable by content, only, at most, by @handle of the correspondent, client-side), server-generated link previews (client-side or none), message content inside push notifications (which this design suppresses by default anyway, section 16), and seamless history on a new device (section 13, section 19).

## 5. The documents that must be rewritten to match, whichever way she goes

This is flagged explicitly because it is load-bearing and easy to forget: **today the Terms of Service and the Privacy Policy both describe the non-E2E design.** If the owner chooses E2E (Option B, recommended), the following sections state things that will no longer be true and must be rewritten before launch. If she chooses to keep non-E2E (Option A), these sections are already correct and need no change, but the design surfaces in Parts 2 through 5 that assume "the platform cannot read this" (notably the report-consent copy in section 15 and the push rationale in section 16) must instead be written in the Option A voice. Either way, the documents and the build must be reconciled; they cannot stay as they are while the product changes under them.

Sections that describe the non-E2E design, by number:

- **ToS section 7.6, "Technical access and automated scanning."** States "Direct messages are not end-to-end encrypted" and "Every image sent in a direct message is automatically scanned for child sexual abuse material." Both become false under E2E. Full rewrite: DMs are end-to-end encrypted; the platform cannot read them; reporting works by the member's device attaching the messages; DM images (when they exist) are not proactively scanned, with the honest CSAM consequence disclosed.
- **ToS section 7.7, "Safety investigations."** States that administrators "may access the content of direct messages when investigating a credible safety concern, even when no member has filed a report." Under E2E this is technically impossible and must be removed, not merely narrowed. (It already carries an `[OWNER DECISION REQUIRED]` block; E2E resolves it by deletion.)
- **ToS section 7.3, "Privacy of messages,"** and **section 7.4, "Reporting and safety."** The signpost in 7.3 to "7.6 through 7.8" must be updated. Section 7.4 says a reported message "may be accessed by our moderation team"; under E2E it is accessed only because the reporting member's device provides it, which is a different and more honest statement and must be reworded.
- **ToS section 7.8, "Legal process."** The platform can still be compelled, but under E2E it can only produce what it holds, which is ciphertext it cannot read plus metadata, not message content. The clause should say what it can actually produce rather than imply it can hand over readable messages.
- **Privacy Policy section 5, "Direct Messages: An Important Disclosure."** The entire section is written in the non-E2E voice: "Direct messages are not end-to-end encrypted," "the platform can access," "All images sent in direct messages are automatically scanned," "administrators can technically access DM content when investigating credible safety concerns." Full rewrite to the E2E posture, keeping the section's honesty, which is its best quality.
- **Privacy Policy section 2.5, "Direct messages."** States the platform stores "the text content of your messages" and "images you send." Under E2E it stores ciphertext it cannot read; reword.
- **Privacy Policy section 6, "CSAM Detection and Mandatory Reporting."** States the platform "scans every image uploaded to it, public posts and direct messages." The "and direct messages" clause becomes false under E2E (and moot while DMs are text-only). Rewrite so the scanning claim covers public images only, with the DM position disclosed honestly.

The one sentence worth protecting through any rewrite is Privacy Policy section 5's honest framing of the design choice. Under E2E its logic inverts, from "we chose the design that can respond to reports over the one that cannot" to "we chose the design that cannot read your messages, and we can still respond to what you report to us," but the plain-spoken honesty must survive. It is the sentence that makes the whole architecture defensible.

---

# PART 2. WHO MAY MESSAGE WHOM

## 6. Default permissions and the Requests area

The ToS section 7.2 already promises members a separate Requests area for messages from members they do not follow, and that they are "not required to open or respond to message requests." This design honours that promise and hardens it for the threat model.

**The recommended default, and the argument for it.** The safest default is the one that protects a woman from being contacted, or even noticed, by someone she is hiding from, without making the product unusable for legitimate first contact. That default is:

- **Your main inbox receives messages only from people you follow.** Following someone is an affirmative act that means "I am open to this person." Nobody you have not followed can place a message in your primary inbox.
- **Anyone you do not follow can send exactly one message request,** which arrives in the separate **Requests** area, never the main inbox.
- **A message request produces no notification and no unread badge, by default.** A stranger cannot make your phone buzz or light up. The request sits silently in Requests until you choose to look. This is the single most important property for the threat model: the person you are hiding from cannot get your attention, cannot prove you are on the platform by watching for a read receipt (there are none to requests, section 16), and cannot escalate.
- **A request is one message until you accept.** The sender cannot send a second message, cannot send many, and cannot flood the Requests area. The first message shows as a limited preview (16). Only if you accept does the conversation open and further messages become possible. This caps harassment at exactly one line of text that you may never see.
- **You choose who may send you a request at all,** in Messages settings (section 7): **Everyone**, **People you follow** (which effectively turns requests off, since people you follow already reach your inbox), or **No one**. The default is Everyone-into-silent-Requests, because the silent, single-message, no-notification design already neutralises the stalker vector while preserving the one legitimate case, a real new acquaintance reaching out, that a flat "No one" default would break.
- **A blocked person can send nothing,** not a message, not a request. Block is absolute (section 14).

Why not default to "No one"? Because the request design already removes the harm: a stranger gets one silent line in a folder the member never has to open, with no notification, no read receipt, and no ability to follow up. Defaulting to "No one" would also silence the legitimate first contact the product exists to enable, and a member who wants that protection has it one tap away. Why not default to the main inbox being open to everyone, the plainest reading of ToS section 7.2? Because an open main inbox means the person she is hiding from lands in the same place as her friends, with a notification, which is the exact harm the threat model forbids. The Requests area, silent and single-message, is the honouring of section 7.2 that a safety-first platform should ship: the area exists, it receives from non-followers, and it is built so that receiving from a non-follower cannot hurt her.

**One subtlety the build must get right:** following someone does not retroactively pull their old request into your inbox without your seeing it; and unfollowing someone you had been messaging does not delete the conversation (it stays in your inbox; you chose it once). Permission changes govern new contact, never silently rewrite existing threads.

## 7. Locking DMs down entirely

A member must be able to shut messaging down, broadly and specifically, and find the controls where she expects them: in Settings, under Safety, adjacent to the block and mute controls that already live there (P2 section 8.2), and mirrored inside a conversation (section 14).

Messages settings, in the Safety group:

- **Who can message you.** A single-select: People you follow (the default for the main inbox, non-negotiable, not a setting that can be loosened to "anyone in my inbox"), with the request layer governed separately below.
- **Who can send you a message request.** Everyone (default) / People you follow / No one. Choosing "No one" means only people you follow can ever reach you, and no request can arrive from anyone else. This is the hard lockdown, one tap, plainly labelled.
- **Turn off direct messages.** A single switch that stops all incoming messages and requests entirely, from everyone including people you follow, and hides the Messages surface from your own nav. Existing conversations are retained and readable but no new message can arrive. The copy is honest: "You will not receive any messages or requests while this is off. Your existing conversations are kept." This is the nuclear option, and it is reversible; it uses a plain switch, not a destructive confirmation, because turning messaging back on is harmless.
- **Read receipts,** off by default (section 16). **Typing indicators,** off by default. **Active-now presence,** off by default and never shown to anyone you do not follow (P2 already sets presence off by default platform-wide).

These controls differ by distinct labels and live in distinct rows; none is a rephrase of its neighbour. "Who can send you a request: No one" and "Turn off direct messages" are genuinely different (the first still lets people you follow reach you; the second stops everything), and the copy says so.

---

# PART 3. THE SURFACES

## 8. Where DMs live in the shell

The shell is fixed and is not redesigned. The mobile bottom bar stays at exactly five slots, Home, Search, Compose, Notifications, Profile (P2 section 1.1), and this document does not add a sixth. Direct messages reach the member through conventional, already-present entry points, so no muscle memory has to be relearned:

- **Mobile and small tablet.** The Messages entry is an icon in the **right contextual slot of the Home top bar** (P2 section 1.3 specifies this slot as "contextual overflow or a single contextual action"). Glyph: `ChatCircle`, Regular weight, 44x44 target, top-right of the feed, exactly where Instagram and Threads place the DM entry. Tapping it pushes the Messages surface as a full screen with its own internal nav and a back affordance to the feed (the standard push pattern, P2 section 1.4). The bottom bar is untouched. Messages is also reachable from the account menu, so it is never orphaned if the member is deep in another surface.
- **Desktop and large tablet.** The left rail gains one destination row, **Messages**, with the `ChatCircle` glyph (Fill when active), placed between Notifications and Profile, using the exact rail-row treatment P2 section 1.2 already defines (icon plus `text-label`, 44px min height, active uses Fill plus `accent` plus the 2px inner indicator bar). The three-column frame, the 600px reading measure, and the compose button are unchanged. Selecting Messages replaces the centre column with the conversation list and opens a detail pane for the selected conversation, the same two-pane behaviour the moderation console uses (P2B section 1), inside the same centered frame.

This is the one deliberate, owner-visible extension of P2 section 1.1's "exactly five primary surfaces": Messages becomes a sixth destination on desktop and a top-bar entry on mobile. It is justified by the fact that DMs were wrongly scoped out and are core product, and it is placed exactly where every mainstream platform places it, so it adds no novelty. It does not alter the constrained surface, the mobile five-slot bottom bar. If the owner would rather DMs not occupy a left-rail slot on desktop, the fallback is the same top-bar-style entry on the feed's header on desktop; the left-rail row is the recommendation because desktop has the vertical room and it matches X and Instagram on the web.

**The unread indicator.** The Messages entry carries an unread indicator for conversations with new messages, using the same convention as the Notifications badge the owner chose (P2 section 4.6): a `danger-fill` count badge with a white numeral, measured 5.62 light / 4.83 dark, counting unread conversations (not messages). It carries no content and no @handle, ever. A member who prefers not to show a count can switch the Messages indicator to a plain dot in Messages settings; the count is the default to match convention. Message requests never contribute to this count and never show a badge (section 6); a stranger can never make the member's Messages icon light up.

## 9. The conversation list (the inbox)

The inbox is the Messages landing surface. It reads as the same calm paper as the feed: rows on `surface`, `border` hairline separators, the identity block from P2 section 3.2.

Layout, one row per conversation, min height 72px, 16px vertical padding:

- **Avatar** at 48px (P2 section 3.1), the correspondent's, a link to their profile.
- **Primary line: the correspondent's `@handle`** at `text-label`, `text-primary`. No legal name, ever (0.1). For an unread conversation the handle is weight 600 and carries a small leading `accent` dot; for a read conversation it is weight 500 and no dot.
- **Secondary line: a one-line preview of the last message** at `text-body`, `text-secondary` when unread (slightly stronger) and `text-tertiary` when read, truncated to one line. The preview is the last message's text only; it never shows the legal name. For a message you sent, it is prefixed "You: ". When DM images eventually ship (section 17), an image message previews as "Photo" with a small `Image` glyph, never a thumbnail in the list (a thumbnail in a list is a shoulder-surfing leak).
- **Timestamp** of the last message at `text-caption`, `text-tertiary`, right-aligned on the first line.
- **Overflow** (`DotsThree`, 44x44) on the far right, opening the conversation overflow menu (section 14).

Behaviour:

- **Tabs at the top of the inbox: Primary and Requests.** A segmented control (the existing pattern, P2 section 3.6). Primary is the default and holds conversations with people you follow and requests you have accepted. Requests holds message requests from non-followers (section 10). The Requests tab shows a plain `text-secondary` count ("Requests 3") only when the member is viewing the inbox, never as a push or a badge on the Messages icon.
- **Swipe accelerators** (touch), consistent with P2 section 10.3: swiping left on a conversation row reveals Mute (silence this conversation) and Block (in `danger`, routed through the block confirmation, section 14). Swipe is an accelerator; every action is also in the overflow, which is the discoverable, keyboard-reachable, screen-reader-reachable route.
- **Search within Messages** is by correspondent @handle only, not by message content (content is unreadable to the server under E2E, and searching message text on-device is a later enhancement, not a launch feature). The search field sits at the top of the inbox, reusing the existing input styling (`border-strong` outline, 3.47 / 3.52).

## 10. The Requests area, filtering, and bulk handling

The Requests tab is where messages from people the member does not follow land. It is drawn so that the member is in total control and is never harmed by its contents.

- Each request row looks like an inbox row (section 9) but shows **only a limited preview**: the sender's @handle, their avatar, and a one-line, truncated preview of their single message. Because a request is one message until accepted (section 6), there is never a thread here, only the one line.
- **Opening a request does not notify the sender and does not send a read receipt** (section 16). The member can read the one line, look at the sender's public profile (by tapping the @handle, exactly as anywhere else), and decide, with the sender learning nothing.
- **Per-request actions**, laid out as distinct controls, never as same-weight twins (0.2): **Accept** (a `secondary` button, moves the conversation to Primary and lets both sides message), **Delete** (a right-aligned `danger` control, removes the request from your view; the sender is not told), and, in the overflow, **Block and delete** (removes the request and blocks the sender, section 14) and **Report** (section 15). "Accept" and "Delete" are genuinely different verbs in different weights; there is no pair that reads alike.
- **Bulk handling of unwanted requests.** The Requests tab has a "Select" affordance that turns rows into a multi-select (row checkboxes, the pattern from P2B section 2.2). The bulk bar offers exactly two safe operations: **Delete all selected** and **Delete and block all selected**. Both are reversible-enough to batch in the sense that deleting a request destroys nothing the member created and blocking is itself reversible (section 14); but because "delete and block" touches other accounts, the bulk bar states the count in its verb ("Delete and block 12") and the member confirms once. There is no bulk Accept (accepting is an affirmative, per-person act and should never be a sweep), and there is no bulk Report (reporting needs a reason per case, section 15). This lets a member who returns to a brigade of unwanted requests clear them in one gesture without ever opening a single one.
- **A quiet, honest empty state** when there are no requests: "No message requests." in `text-secondary` on `background` (6.77 / 8.46), centered, with a one-line explanation that requests from people she does not follow will appear here and will never notify her. No illustration, no "Invite friends" prompt; this is a safety surface, not a growth surface.

## 11. The thread (conversation) view

The thread is the reading-and-writing surface for one conversation. It reuses the design system's message-bubble decision (from the design system memory and P2's radius scale, where `radius-lg` 14 is the bubble radius): asymmetric, corner-tightened bubbles, an accent-tinted sent bubble, deliberately not the iMessage look.

Layout:

- **Header,** sticky, 48px on mobile (the top bar, with a back affordance), a slim header on desktop: the correspondent's **avatar (32px) and `@handle`** at `text-heading`, tapping either opens their profile as a side peek on desktop or a push on mobile (never navigating away mid-conversation on desktop). An **active-now line** appears only if both parties have opted into presence (off by default); otherwise nothing. The header's right side holds the conversation overflow (`DotsThree`, section 14). **No legal name in the header** (0.1).
- **Encryption affordance,** quiet and honest: directly under the header, on a new or freshly opened conversation, a single centered system line at `text-caption`, `text-secondary` on `background` (6.77 / 8.46), with a small `LockSimple` glyph: "Messages are end-to-end encrypted. Hersciety cannot read them." Tapping it opens a short plain-language explanation and the verification affordance (section 13). This line is reassurance, not decoration, and it is the honest counterpart to the Privacy Policy rewrite in section 5; under Option A (non-E2E) this line must not appear, and the explanation must instead state plainly that the platform can access messages under the circumstances the Privacy Policy describes.
- **Message bubbles.** The scroll area sits on `background`. Each message is a bubble at `radius-lg` with one corner tightened toward its side (the corner nearest the avatar column), the convention that makes a run of messages read as a column from one speaker:
  - **Received** bubbles are `surface-raised` fill, `text-primary` body at `body-lg` (17px, the primary reading size the type scale assigns to DM text), measured 16.91 light / 13.27 dark. Left-aligned.
  - **Sent** bubbles are `accent-subtle` fill (the accent tint the design system calls for), `text-primary` body at `body-lg`, measured 14.35 light / 13.20 dark. Right-aligned. This is a tint, not a loud accent fill, so a conversation stays calm paper and does not turn violet.
  - Consecutive messages from one sender are grouped with 2px between them and 12px between groups; the avatar shows once per group (on received groups), never on every bubble.
  - Timestamps are `text-caption`, `text-tertiary`, shown on the last bubble of a group or on tap, not on every bubble (density, P2 section 4.3 rhythm).
  - **Delivery and read state** is minimal and privacy-respecting: a sent message shows "Sent" and, only if the recipient has read receipts on, "Read" at `text-caption`, `text-tertiary`, under the last sent bubble. It never shows "Delivered" timing that could be used to infer when a member is awake and online. Read receipts are off by default (section 16), so by default a sent message shows only "Sent".
- **System lines** (key-change notices, "You blocked @handle", "You can no longer reply to this conversation") are centered `text-caption`, `text-tertiary` or `text-secondary` on `background`, never bubbles, so they read as state, not speech.
- **The jump target on open** is the first unread message, with a thin "New messages" divider (a hairline `border` with a centered `text-caption` label), so a member returning to a long conversation lands where she left off. Reading the thread marks it read and sends a read receipt only if she has them on.

## 12. The composer

The DM composer is a conventional message input, not the post composer (which is a sheet, P2 section 5). It sits pinned to the bottom of the thread view.

- **Input:** a single growing text field, `body` at 15px for typed input growing to multi-line, `surface` fill with a `border-strong` outline (3.47 / 3.52), `radius-full` when single-line relaxing to `radius-lg` when multi-line, min 44px target. Placeholder: "Message" in `text-tertiary`.
- **Send:** an `accent-fill` circular icon button with an `on-accent` `PaperPlaneTilt` glyph, 44x44, enabled only when the field is non-empty. Enter sends on desktop (Shift-Enter for a newline); on mobile the Send button is the only send path, so the on-screen keyboard's return key inserts a newline rather than sending, preventing accidental sends.
- **Attach (future, section 17):** an `Image` glyph button sits to the left of the field, and in the text-only release it is **absent entirely**, not present-and-disabled, so nothing implies a capability the release does not have (this follows P2's practice of hiding not-yet-shipped controls rather than showing them dead, P2 section 16). When images ship, this is where the attach control appears, with no other layout change.
- **Composer in a request you have not accepted:** there is no composer. A request is one-message-until-accepted (section 6), so the recipient sees Accept / Delete / Block, not a reply field. The sender, having sent their one request, sees their own message with a `text-tertiary` system line "Waiting to be accepted" and no further send ability until acceptance. Honest, and it caps abuse.
- **Composer when you have blocked, or been blocked by, the correspondent:** the field is replaced by a centered `text-caption` system line, "You can no longer reply to this conversation," with no input (section 14). The member is never left typing into a void that silently fails.
- **Draft safety:** an unsent draft persists per conversation across navigation, the same guarantee P2 section 5.7 makes for the post composer.
- **New message (compose a new DM):** a `NotePencil` action at the top of the inbox opens a recipient picker, an @handle search field (handle only, P2's @handle-only search rule holds here too) with results that respect blocks and the recipient's own "who can message you" setting: if the recipient only accepts messages from people they follow and you are not followed, the picker shows, honestly, that your message will arrive as a request, not a failure after the fact. Selecting a recipient opens the thread (or the request composer) directly.

## 13. Sender attribution, key changes, and verification (the E2E surface)

These surfaces exist only under E2E (Option B). They are the member-facing expression of the franking and key-management machinery in section 2, kept calm and low-prominence, because for most members they should be invisible reassurance, and for the rare member in danger they are a real signal.

- **Verified sender, in the background.** Every message a member receives is cryptographically attributable to the sending account (section 2). The member does not see a "verified" stamp on every bubble (that would be noise); attribution surfaces only where it matters, in the report evidence (section 15), where the moderation console can show a quiet "Cryptographically verified" marker so a moderator knows the attached messages are genuine and genuinely from the accused.
- **Verify this conversation (safety number).** In the conversation overflow (section 14) and behind the encryption affordance (section 11), a "Verify @handle" screen shows a comparison code (a safety number, Signal's model) that two people can compare out of band to confirm no one is intercepting. It is optional, low-prominence, and never pushed; most members never open it, and the member in danger who wants certainty can.
- **Key-change notice, honest and un-alarming.** If a correspondent's device or identity key changes (a new phone, a reinstall, or, rarely, an interception attempt), the thread shows an inline centered system line at `text-caption`, `text-tertiary`: "@handle's security code changed." with a "Verify" affordance and a "Learn more" link. It is not a red modal and does not block the conversation, because the overwhelmingly common cause is a new phone and alarming every member on every phone upgrade would train them to ignore the one that matters. The "Learn more" copy is honest: a security code usually changes because the person got a new device, but if you were not expecting it you can verify before you say anything sensitive. This calm honesty is exactly calibrated to the threat model: a member who suspects she is being targeted gets the tell without being panicked on every routine change.
- **New device and lost history** are covered in section 19 (retention), because under E2E a new device does not automatically inherit old messages and the member must be told plainly rather than discover it as a loss.

---

# PART 4. SAFETY INSIDE DMS

## 14. Block, mute, report, leave, and delete inside DMs

The safety controls inside a conversation are the same controls the member already knows from the feed (P2 section 10), extended to the DM context, never duplicated as a parallel system. They live in the **conversation overflow** (`DotsThree`) in the thread header and, mirrored, in the inbox-row overflow (section 9). The menu is built from the P2 section 3.4 overflow primitive, and its order follows the same escalating convention as P2 section 10.1, generic first, negative actions escalating, destructive pair fenced at the bottom:

1. **View profile** (`User`). Neutral. Opens the correspondent's profile.
2. **Verify @handle** (`ShieldCheck`). Neutral. The safety-number screen (section 13). Present only under E2E.
3. *(divider)*
4. **Mute messages** (`BellSlash`). Neutral. Silences notifications for this one conversation; it stays in the inbox and you can still open it. Distinct from the account-level Mute in the feed, which hides someone's posts; this mutes only this conversation's notifications. Immediate, reversible, no confirmation, with an Undo toast (P2 section 3.5). Copy: "You will not be notified about this conversation. It stays in your inbox."
5. *(divider)*
6. **Delete conversation** (`Trash`). `danger` text and glyph. Removes the conversation from your view. Confirmed, and honest about what the other person keeps (section 19). This is the one unrecoverable DM action and its confirmation says so.
7. **Block @handle** (`Prohibit`). `danger` text and glyph. The heaviest relational action; confirmed (below). Distinct verb, distinct glyph, distinct from Delete above it.
8. **Report** (`Flag`). `danger` text and glyph, set apart as the final item so it reads as the most serious action, exactly as in the feed menu (P2 section 10.1). Opens the DM report flow (section 15).

**Delete, Block, and Report are three different verbs in three different weights with three different glyphs and three different consequences, and the irreversibility rule (0.2) forbids them from ever reading alike.** Delete removes the thread from your device; Block stops the person entirely; Report sends evidence to the safety team. None is a recolouring of another.

**Block, with a confirmation step** (mirroring P2 section 10.2 so the pattern is one pattern across the product):

- Selecting **Block @handle** opens a small confirmation (centered modal on desktop, bottom sheet on mobile): title "Block @handle?", body "They will not be able to message you, send you a request, see your profile or posts, or follow you. They will not be told." Actions: **Cancel** (ghost, left-aligned, holds default focus so a reflexive Enter does nothing) and **Block** (`danger-fill`, white label, right-aligned, measured 5.62 / 4.83). They differ by verb, fill, colour, and position at once.
- On confirm, block is immediate. Blocking is silent; the blocked person is never notified and never sees a "you have been blocked" state; from their side, messages simply stop delivering (below).

**How block interacts with existing threads** (the detail the brief calls out):

- After A blocks B, **B can no longer send to A**: B's composer is replaced by the system line "You can no longer reply to this conversation" (section 12). B is not told it was a block; the conversation simply becomes send-disabled from B's side, which is indistinguishable from A having turned messaging off, so a block cannot be used by B to confirm anything about A.
- **A keeps the existing conversation and its history.** It does not vanish from A's inbox on block, because that history may be exactly the evidence A needs to report (section 15), and silently destroying it would be a safety regression. A sees a system line in the thread, "You blocked @handle," and can still read, report, or delete the conversation on her own terms. If A prefers the thread gone from her inbox, she deletes it as a separate, deliberate act (section 19); block and delete are not the same action and are not bundled.
- Under E2E, **neither side can reach into the other's device.** Block stops new delivery; it does not and cannot delete the messages already on B's device. The design is honest about this rather than implying a reach the crypto forbids: the block confirmation promises what block actually does (stops future contact), not what it cannot do (erase B's copy of the past).
- Block reuses the existing `blocks` table and the `blocked_either()` relationship the social core already defines; the DM send path must check `blocked_either(sender, recipient)` and refuse, exactly as likes and follows already do. This is a build note, not a new mechanism (section 23).

**Leave** is a group-conversation action, and the first DM release is **1:1 only** (section 24 explains why, and flags it as a real owner question given the ToS plural hint). In a 1:1 there is no "leave"; the equivalents are Delete (remove it from your view) and Block (stop the person). "Leave conversation" is designed in principle for the group era, as a distinct destructive verb from Delete ("Leave" removes you from a shared thread and tells the other members you left; "Delete" removes the thread from your own view and tells no one), and it is specified now so that when group DMs arrive the two are never conflated. It does not ship in the text-only 1:1 release.

## 15. Reporting a DM, end to end, into the moderation console

Reporting a DM must be quick, must gather verifiable evidence, must be honest about what the member is sharing, and must land cleanly in the queue the moderation console already defines (P2B). It reuses the member-facing report flow of P2 section 10.4 and hands off to the case queue of P2B, with the differences E2E and the private context demand.

**The member-facing flow** (opened from the conversation overflow, section 14, or from a long-press on a single message):

1. **What you are reporting.** The flow opens on the specific message long-pressed, or, from the conversation overflow, on a "Report this conversation" that pre-selects the most recent messages. The member can **add or remove messages from the selection**; the selection is shown as the exact bubbles that will be sent. Default selection is the reported message plus a few surrounding messages for context (the franking research is explicit that a report needs a configurable context window; a single line out of context is often unreadable, P2B section 3.2 makes the same point for replies). Copy: "We include a few messages around this one for context. Remove any you do not want to share."
2. **The honest consent line, which is the heart of E2E reporting.** Above the reason list, in `text-secondary`: "Hersciety cannot read your messages. To report them, your app will send the messages you selected to our safety team." This is the one place the member explicitly chooses to breach her own end-to-end encryption, for exactly these messages, and she is told so plainly. Under Option A (non-E2E) this line is replaced with the honest Option A statement that the team can access the reported messages.
3. **Reason selection,** the same single-select as P2 section 10.4, mapping to the `report_reason` enum (harassment, hate, violence_threat, doxxing, csam, ncii, spam, impersonation, self_harm, other), with plain-language labels and one-line descriptions. CSAM has its own clearly separated, serious path (and under E2E the only way a DM-image CSAM case ever reaches the platform is a member reporting it, section 4 and section 17).
4. **Optional detail,** a short free-text field (the `reports.details` column caps at 2000 characters), "Anything else we should know?"
5. **Immediate protection,** offered on submit exactly as in the feed flow: "Do you also want to block @handle?" so the member leaves protected, not merely heard. Under the DM threat model this is more important, not less, and Block is offered by default.
6. **Confirmation,** the same calm, non-flippant close as P2 section 10.4: "Thanks. Our team will review this. You can see the status in Settings, Safety, Report history." No exclamation points on a report confirmation.

**What crosses to the server, under E2E:** the selected message plaintext (the member chose to share it), each message's franking token, and the metadata the `reports` table already holds (reporter, accused, reason, detail, time). The franking token lets the server verify, at report time, that the plaintext is exactly what was sent and that it was sent by the accused account (section 2): the reporter cannot fabricate, the sender cannot deny. Nothing else about the conversation crosses; the platform still cannot read the messages the member did not attach.

**The hand-off into the moderation console** (P2B), stated so the two documents do not drift:

- A DM report creates a **case** in the existing queue (P2B section 2.1), grouped by accused @handle. The `report_subject` enum must gain a `message` value; the enum's own migration comment already anticipates this ("'message' arrives with DMs"), so this is expected, not a surprise (section 23).
- The **case detail** (P2B section 3.1) renders the reported messages as a **read-only DM transcript**: the same bubble components as section 11 (received and sent, @handle-only, `body-lg` text), with the **reported message marked** by the 2px `accent` left edge and faint `accent-subtle` band and a `text-caption` `accent` "Reported message" label, exactly as P2B section 3.2 marks a reported reply. Every party is shown by @handle only (0.1). The action row (reply, like) is absent, as it is for all console content (P2B section 3.2): a moderator judges, she does not participate, and she certainly cannot message from inside a case.
- A quiet **"Cryptographically verified"** marker sits on the transcript (section 13), present only when the franking check passed, so a moderator can trust the evidence is genuine and genuinely the accused's. If a franking check fails, the report is marked as unverifiable and the transcript is shown as the reporter's unverified claim, not as established fact; this is the design expression of "the reporter cannot fabricate."
- **The honest limit the console must carry:** unlike a public-post case, where the moderator can pull the whole thread for context (P2B section 3.2), a DM case's evidence is **only what the reporter attached.** The platform cannot decrypt the rest of the conversation. The case detail states this in a single `text-caption` line, "This is the evidence the reporter shared. Hersciety cannot see the rest of this conversation," so a moderator never assumes missing context is hiding something and never believes she can request more. This is a real difference from public moderation and the console must show it, not paper over it.
- The **enforcement ladder** (P2B section 4) applies unchanged, with one honesty note: "Remove content" on a public post removes it from every public surface, but a DM message already sits on both parties' devices and cannot be reached under E2E, so for a DM case the meaningful actions are the account-level ones (warn, restrict, suspend, ban) against the sender, not "remove this message from the recipient's phone." The console's DM-case action rail omits "Remove content" as inapplicable, or labels it honestly as removing only the platform's retained ciphertext, and leads with the account-level ladder. A `csam` or credible `violence_threat` reason routes to Critical priority and, for CSAM, to the Owner-only NCMEC and law-enforcement escalation (P2B section 4.8), exactly as any other CSAM case does.
- **Routing** (standard, admin_only, owner_conflict) is computed server-side by the existing `file_report()` logic and is invisible to the reporter (P2 section 10.5, P2B section 2.5). A DM report whose accused is the Owner follows the owner-conflict path (P2B section 7) with no difference the reporter can detect.

## 16. Notifications, and the lock-screen problem

This matters enormously for this userbase and is designed as a safety surface, not a growth lever. The governing scenario: the member's phone may be visible to the person she is hiding from, over her shoulder, on a shared device, or on a lock screen glanced at across a table. A notification that reveals a message, or even that a message exists from a named person, can be the disclosure that gets her hurt.

**Push and lock-screen previews, three levels, defaulting to the safest:**

- **No preview (default).** A push shows only "Hersciety" and a generic line, "New message." No @handle, no content, no count. Someone glancing at the lock screen learns only that the app had activity, which is the same thing a weather alert reveals. This is the default **for everyone**, because on this platform the safe assumption is that the phone is not private.
- **Sender only (opt-in).** "Message from @handle." Reveals who, never what. @handle only, never the legal name (0.1).
- **Sender and preview (opt-in).** "@handle: " plus the first line of the message. The richest, and off by default.

The member chooses the level in Messages settings, and the choice is explained in one honest line: "If someone else might see your phone, keep previews off." Under E2E this default is also the only thing the server can do unaided: the server holds only ciphertext, so a content-rich push must be assembled on the device after decryption (the service worker decrypts and rewrites the notification, the model WhatsApp Web and Signal use), which means "No preview" is both the safest choice and the natural one. A constraint and a safety goal align, which is the happiest kind of design.

**Message requests never notify.** A message request from someone the member does not follow produces no push, no badge, and no sound, by default and regardless of preview level (section 6). A stranger, which includes the person she is hiding from if she has not followed him, cannot make her phone do anything. This is the single most important notification rule in the document.

**In-app indicators** carry no content: the Messages icon's unread count (section 8) is a number of conversations, never a name or a message; an unread inbox row bolds the @handle and shows a one-line preview only once the member is already looking at her own inbox, which is a surface she controls, not a lock screen anyone can see.

**Read receipts, typing indicators, and presence are off by default** (section 7) and are never shown to non-followers or to message requests. A member can read a request, or a message, without the sender learning she did, so no one can use a read receipt to confirm she is on the platform, is awake, or saw the message. This denies a stalker the feedback loop that a default-on read receipt would hand him.

**Notification settings for DMs** live with the rest of notification preferences (P2's settings IA) and reuse the per-type `notification_prefs` mechanism the social core already has (a `message` or `dm` type must be added to the `notif_type` enum and the prefs, section 23). The member can turn DM notifications off entirely, mute any one conversation (section 14), and set the preview level, all in plain-labelled rows that differ from one another by function, not by rephrasing.

---

# PART 5. FORWARD COMPATIBILITY AND STATE

## 17. Images in DMs: designed for, not built

The platform has no image upload anywhere, in posts or DMs. This first DM release is **text only.** The surface is designed so that text ships now and images slot in later with no redesign, and so that the thing that must be true before images are safe is stated, not assumed.

**What is already reserved for images, so adding them is additive, not a rework:**

- The composer's attach control has a defined home, to the left of the input (section 12), absent in the text release, appearing with no other layout change.
- The inbox preview has a defined non-leaking form for an image message, "Photo" with a small `Image` glyph, never a thumbnail in the list (section 9).
- The thread bubble has room for an image bubble at `radius-lg`, inside the existing bubble composition, no new token.
- The report flow already treats a selected item as "a message"; an image message is just a message whose content is an image, and the franking and client-side-report path (section 15) covers it unchanged.

**What must be true before DM images are safe to enable, stated plainly as a gate, not a wish:**

1. **Image upload must exist at all,** which it does not today anywhere in the product. This is a prerequisite for DM images and for public images alike.
2. **The CSAM posture for E2E DM images must be decided and the legal documents must match it.** Under E2E the platform cannot proactively scan DM images, so the only path by which a DM-image CSAM case reaches the platform is a member reporting it (section 4, section 15). That is the same posture Signal and WhatsApp hold, and it is defensible under 18 U.S.C. 2258A because the platform has no actual knowledge of content it cannot read, but it is uncomfortable and it must be a deliberate, documented, attorney-reviewed decision before a single DM image is allowed, not a default that arrives with a feature flag. Client-side scanning of DM images is explicitly not recommended (it catches only known hashes, not novel or AI-generated CSAM, it was withdrawn by Apple after backlash, and no mainstream E2E messenger mandates it for DMs).
3. **A working path to receive a report and act on it must exist,** which is the moderation console (P2B) plus the DM report flow (section 15). A detection-or-report capability without a reporting-and-preservation workflow is the anti-pattern to forbid: the correct pipeline on any CSAM match is remove from view, preserve the evidence in a locked store, and file the report, never a hard delete, because a hard delete destroys the evidence the law requires be preserved for a year.
4. **Public image scanning must be live first.** Before DM images (which cannot be scanned under E2E) are enabled, the easier case, public images, which can and must be scanned (Cloudflare plus PhotoDNA at upload), should be proven working, so the platform has demonstrated the full detect, preserve, report pipeline on the case where it is possible before shipping the case where it is not.
5. **Image-specific DM privacy must be designed:** EXIF and location metadata stripped from every DM image on the device before send (an image's embedded GPS coordinates are a doxxing vector on a platform for people hiding their location), no thumbnails on lock screens or in previews, and an honest statement that under E2E a recipient's copy of an image, like any message, cannot be unsent from her device after she has it.

Until all five are true, the attach control stays absent and DMs stay text only. This is not a limitation to hide; it is the responsible sequence, and the design is built to make adding images a small, safe, additive step when the gate is cleared.

## 18. Empty states, loading, errors, and offline

These follow P2 section 9 and section 11 exactly; DMs add only the specifics.

- **Empty inbox:** calm and non-salesy, "No messages yet." in `text-secondary` on `background` (6.77 / 8.46), centered, with a one-line explanation that conversations with people she follows appear here and requests from others go to the Requests tab. A single quiet action, "Start a conversation" (opens the recipient picker, section 12). No facepile of "people you may know," which the threat model forbids (a contact-suggestion surface can expose the member to the person she is hiding from; P2B section 11 already refuses "people you may know").
- **Empty Requests:** section 10.
- **Empty thread** (a conversation that exists but has no messages yet, for example right after you open a new one): the encryption affordance (section 11) and the composer, nothing else; no placeholder bubbles.
- **Loading:** **skeletons, not spinners,** for the inbox and the thread (P2 section 11.1): grey-neutral `--skeleton-base` rows shaped like conversation rows and like bubble runs, with the slow sheen that respects reduced motion. A short, bounded wait (sending a message) uses the message's own optimistic state, not a spinner (below).
- **Optimistic send:** a sent message appears instantly in the thread at about 0.6 opacity with a `text-caption` "Sending" state, settling to full opacity and "Sent" on confirmation (P2 section 11.2). On failure it shows a Retry affordance on that message without losing the typed text, and it never silently disappears.
- **Errors:** quiet, specific, actionable, never a code or a stack trace (P2 section 11.3). "Could not send. Tap to retry." A failed report says so and preserves the member's selection and reason so she does not have to redo it.
- **Offline:** the thin non-blocking banner under the top bar (P2 section 11.4), "You are offline. We will reconnect automatically," `warning-fill` with ink text. Already-loaded conversations stay readable offline. A message composed offline queues optimistically and sends on reconnect. But a **safety action taken offline is attempted immediately and reports its real result:** if a member blocks someone while offline and it cannot complete, she is told clearly rather than left believing a block landed that did not, because a member blocking someone under stress needs to know whether it actually happened (this is the exact rule P2 section 11.4 states for block and report, applied to DMs).

## 19. Retention and deletion UX: what "delete" means, honestly

This is where the product must be most honest, because deletion in a messaging app is where people hold the strongest and most mistaken beliefs. Under E2E, each party holds their own copy of a conversation on their own device, and the platform cannot reach into anyone's device. The design tells the truth about that rather than implying a control the architecture does not grant.

### 19.1 Deleting a single message

Two distinct, differently-named actions, never a pair that reads alike (0.2):

- **Delete for me.** Removes the message from your devices. The other person still has their copy. Honest copy at the point of action: "This removes the message from your devices. @handle will still have their copy."
- **Unsend (delete for everyone),** available for a message you sent, within a short window after sending (the WhatsApp model). It sends a request the recipient's app honours by removing the message. Honest copy: "This asks @handle's app to remove the message. If they already saw it, or use an older version, they may still have it." The honesty is deliberate: unsend is best-effort, not a guarantee, and promising a guarantee would be a lie that gets a member hurt when the recipient screenshotted the message a minute earlier.

### 19.2 Deleting an image message (future, section 17)

Same two actions, with the added honest line that an image, once on the recipient's device, cannot be pulled back by unsend if she already has it, and that she may have saved it. No implication of reach the crypto forbids.

### 19.3 Deleting an entire conversation

**Delete conversation** (the fenced `danger` item, section 14) removes the whole thread from your view and your devices. It is the one unrecoverable DM action, because under E2E there is no server copy to restore it from. Its confirmation (centered modal on desktop, bottom sheet on mobile) states the consequence in words before the destructive button, following the irreversibility rule: title "Delete this conversation?", body "This removes the conversation from your account and your devices. You cannot get it back. @handle will still have their copy of the conversation." Actions: **Keep conversation** (ghost, left, default focus) and **Delete for me** (`danger-fill`, right, measured 5.62 / 4.83). The verbs differ, the weights differ, the positions differ; nothing here can be misfired by reflex.

### 19.4 What the other person still sees

Stated once, plainly, because it governs all of the above: **you can delete your copy; you cannot delete theirs.** Deleting a message or a conversation on your side does not remove it from the other person's device, exactly as deleting a text message from your own phone does not erase it from the phone of the person you texted. Unsend is the only action that reaches the other side, it is best-effort and time-limited, and the member is told so every time she uses it. This is the honest account the brief asks for, and it is in the copy at the moment of action, not buried in a help page.

### 19.5 Retention and account deletion

The specific retention periods are a legal and policy decision (Privacy Policy section 8 currently brackets "DM retention after account deletion" as unresolved, and the owner plus counsel must set it); the design's job is to make the UX honest regardless of the number chosen:

- **What the platform retains:** under E2E, only ciphertext it cannot read, plus metadata (who messaged whom and when). The Privacy Policy rewrite (section 5) must say this instead of today's "we store the text content of your messages."
- **On account deletion:** the member's own device copies go with her devices; the ciphertext the platform held is deleted per the retention policy; and the people she messaged **still have the messages she sent them,** the same way a text message stays on someone's phone after she deletes hers. The account-deletion flow must say this in plain words, so a member deleting her account is not misled into believing she has erased herself from everyone else's inbox: "People you messaged will still have the messages you sent them. Deleting your account does not remove messages from their devices." A member whose entire reason for being here is control over who can reach her deserves to know the exact limit of what deletion does, at the moment she does it.
- **Evidence that has been reported** and is subject to a preservation obligation (notably a CSAM report, which carries a one-year federal preservation requirement) is retained for that period regardless of a deletion request, exactly as the Privacy Policy section 6 already states for public content; the deletion flow discloses this rather than implying a reported-and-preserved item is erased.

---

## 20. Accessibility specification

Stated, not assumed, consistent with P2 section 12, which the base system already meets in both themes.

- **Touch targets:** every interactive element is a minimum 44x44 CSS pixels, including the Messages entry icon, the inbox-row overflow, the send button, per-request Accept and Delete, and the message long-press affordance (which also has a visible overflow equivalent, never a gesture-only path).
- **Focus:** visible 2px `focus-ring` with 2px offset on every control (the global default). The composer, the recipient picker, the report sheet, and every confirmation modal trap focus while open, restore focus to the trigger on close, and close on Escape. In the desktop two-pane Messages surface, focus order is the conversation list, then the open thread, then the composer; a skip affordance jumps to the composer.
- **Keyboard:** everything doable by tap is doable by keyboard. The conversation overflow opens on Enter, Space, or Down-arrow and is arrow-navigable (the P2 section 3.4 menu contract). Enter sends in the composer on desktop, Shift-Enter inserts a newline; this is announced so a screen-reader user knows the send key.
- **Screen reader semantics:** the inbox is a labelled list; each conversation row announces "Conversation with @handle, N unread, last message [preview]." A message bubble announces its sender by @handle and its text, with sent and received distinguished by more than visual alignment (an accessible "You said" / "@handle said" prefix), so the sender is never conveyed by bubble side alone. The @handle is the accessible name throughout; the legal name is never exposed in any DM accessible name (0.1). System lines (encryption notice, key-change notice, "you blocked") are announced via a polite live region, not as speech bubbles.
- **Reduced motion:** the bubble-settle opacity, the sheet slide, the swipe elastic, and the skeleton sheen all degrade to instant or short opacity-only transitions under `prefers-reduced-motion` (P2 section 12.5). No DM state is conveyed by motion alone.
- **Colour independence:** unread is carried by a bold @handle and a dot, not colour alone; the sent and received bubbles differ in alignment and corner and accessible prefix, not only in tint; destructive menu items carry a danger glyph and a specific verb, not only red (P2 section 12.6). The encryption lock and the key-change notice carry text, not an icon alone.

## 21. Motion specification

Inherits P2's durations (instant 0, fast 120, base 180, slow 240, sheet 320) and easings, degrading under reduced motion per section 20.

| Element | Motion | Duration | Easing |
|---|---|---|---|
| Send button press | scale 0.97 plus opacity | 120 (fast) | standard |
| Message appears (optimistic) | opacity 0.6 to 1 on confirm | 180 (base) | standard |
| Incoming message | subtle rise and fade on insert | 180 (base) | enter |
| Conversation overflow (sheet) | slide up plus fade | 320 (sheet) | enter in, exit out |
| Block or delete confirmation (modal) | fade plus scale 0.98 to 1 | 240 (slow) | enter |
| Swipe-to-reveal (inbox row) | elastic reveal of Mute and Block | tracks the finger | standard |
| Toast (Undo after mute) | slide plus fade | 180 (base) | enter in, exit out |
| Tab switch (Primary / Requests) | content crossfade | 120 (fast) | standard |
| Skeleton sheen | left-to-right shimmer loop | about 1200 | linear, loop |

Motion is subtle and functional. There are no decorative, looping, or attention-seeking animations in DMs, and nothing animates on a message arriving that would draw a bystander's eye to the screen.

## 22. Tokens: what this document adds, and what it deliberately does not

**This document adds no new color, type, spacing, radius, elevation, or motion token.** It builds two bubble compositions from existing tokens, in the same way P2B built two chip compositions from existing tokens:

- **Received bubble:** `surface-raised` fill, `text-primary` body at `body-lg`, `radius-lg` with the avatar-side corner tightened. Measured `text-primary` on `surface-raised`: 16.91 light / 13.27 dark.
- **Sent bubble:** `accent-subtle` fill, `text-primary` body at `body-lg`, `radius-lg` with the opposite corner tightened. Measured `text-primary` on `accent-subtle`: 14.35 light / 13.20 dark.

Every other pairing this document relies on is already enumerated and measured in P2 section 2.3 or the base system:

| Pairing | Use here | Light | Dark |
|---|---|---|---|
| text-primary on surface-raised | received bubble, popover and modal body | 16.91 | 13.27 |
| text-primary on accent-subtle | sent bubble | 14.35 | 13.20 |
| text-secondary on background | empty-state copy, encryption and system lines | 6.77 | 8.46 |
| text-tertiary on surface | timestamps, read state, previews | 4.88 | 5.11 |
| danger on surface-raised | Delete, Block, Report menu items | 5.62 | 5.49 |
| danger-fill plus white | Block and Delete-for-me confirm buttons; the Messages unread count badge | 5.62 | 4.83 |
| accent on surface-raised | the Undo action in a toast; the "Reported message" marker in a case | 7.10 | 5.58 |
| accent on accent-subtle | the "Following" style and accent labels on a tint | 6.03 | 5.55 |
| text-secondary on accent-subtle | secondary copy on an accent-subtle surface | 6.52 | 6.90 |
| border-strong on surface | composer and search input outlines (non-text, 3:1 target) | 3.47 | 3.52 |

If the owner later wants the Messages unread indicator to be a dot rather than a count, that uses the existing `accent` or `danger-fill` with no new token. Nothing in DMs introduces a value that is not already measured for its use.

## 23. Build notes the implementation must honour (no SQL here, flags only)

This is a design document and writes no migration. These are the data-layer facts the build must get right, surfaced so the design and the schema do not drift. They are flags, not code.

- **`report_subject` needs a `message` value.** The enum is currently `('post', 'user')` and its own migration comment says "'message' arrives with DMs." A DM report (section 15) is a message report, and the case queue (P2B) must render it as a transcript, not as a post.
- **`notif_type` needs a DM value** (`message` or `dm`). The enum is currently `('follow', 'like', 'reply', 'mention', 'system')` with no message type, and the per-type `notification_prefs` mechanism must carry a DM toggle and the preview-level setting (section 16).
- **The `reports` table needs a way to reference the reported message(s).** It currently references `subject_post_id` and `subject_user_id`; a DM report references neither a public post nor only an account, it references specific messages whose evidence (plaintext plus franking token) the reporter attached. The build must store that evidence in a form the console can render and that preserves the franking verification.
- **The DM message tables are where the empty `user_devices` and `one_time_prekeys` tables finally get used.** Those two tables were created unpopulated precisely for the E2E device and prekey flow (migration 0007 says so and says not to remove them). An E2E build populates them; a non-E2E build (Option A) leaves them empty and holds server keys. The message store itself needs ciphertext and franking columns from day one regardless of which option ships, so that the moderation evidence path (section 15) is built once.
- **The DM send path must enforce the existing block and permission rules:** refuse when `blocked_either(sender, recipient)` is true (section 14), route to Requests versus inbox per the recipient's "who can message you" and "who can send a request" settings (section 6, section 7), and enforce the one-message-until-accepted cap on requests server-side, not only in the client.
- **Presence, typing, and read receipts default off** and must never be emitted to non-followers or to requests (section 16); this is a server-enforced default, not a client preference that a modified client could override.

## 24. Open questions that genuinely need the owner

Short, real, and each one a decision only she can make. Nothing invented.

1. **The encryption decision (Part 1).** End-to-end encrypt DMs (recommended Option B, text-only, with franking and client-side reporting), keep the non-E2E posture the documents already describe (Option A), or ship non-E2E now and migrate later (Option C, not recommended). This is the load-bearing call and everything else follows from it. The design is built to serve whichever she chooses; the recommendation is E2E, and the one capability it gives up, proactive CSAM scanning of DM images, is not in use today because DMs are text-only and the platform has no image upload (section 4).
2. **1:1 only, or group DMs too, in the first release?** This design ships 1:1 only, because end-to-end group chat is materially harder (a different protocol family) and is the part that makes E2E projects ship late. But ToS section 7.3 refers to "the recipient(s)," plural, so if she intends group DMs at launch, the crypto choice and the timeline both change, and "Leave conversation" (section 14) becomes a shipping action rather than a reserved one. Her call, because it changes the engineering shape, not just the UI.
3. **The documents must be rewritten to match whichever encryption choice she makes (section 5).** This is not a design question, but it is a decision she must make consciously and hand to counsel: under E2E, ToS sections 7.6, 7.7, 7.3, 7.4, and 7.8 and Privacy Policy sections 5, 2.5, and 6 all state things that will no longer be true. They cannot stay as written while the product changes under them.

## 25. Summary of deliverables for the Phase 2C build

- A Messages surface reached from the Home top bar on mobile and a left-rail destination on desktop, with the mobile five-slot bottom bar untouched (section 8).
- A conversation inbox with Primary and Requests tabs, @handle-only identity, content-free unread indicators, and swipe accelerators that duplicate the overflow, never replace it (section 9, section 10).
- A Requests area that is silent, single-message-until-accepted, preview-only, with safe bulk delete and delete-and-block, and no notification ever (section 6, section 10, section 16).
- A thread view with asymmetric accent-tinted sent bubbles and surface-raised received bubbles, an honest encryption affordance, calm key-change notices, and read state off by default (section 11, section 13).
- A composer that cannot accidentally send on mobile, hides the not-yet-built attach control rather than disabling it, and tells the member plainly when she cannot reply because of a block (section 12, section 14).
- Safety controls, mute, delete, block, report, and the reserved group-era leave, that obey the irreversibility rule and reuse the feed's overflow pattern, with block's interaction with existing threads specified (section 14).
- A DM report flow that is honest about breaching the member's own encryption to report, attaches a configurable context window with cryptographically verified evidence, and lands as a `message` case in the moderation console with the honest "this is only what the reporter shared" limit (section 15).
- Notification defaults built for a phone that is not private: no preview and no sender by default, requests never notify, read receipts off (section 16).
- An image path designed for but not built, with the five conditions that must be true before it is safe to enable (section 17).
- Honest deletion and retention UX: delete your copy, not theirs; unsend is best-effort; account deletion does not erase what you sent from other people's devices, and the copy says so at the moment of action (section 19).
- Zero new tokens; two bubble compositions of existing, measured tokens (section 22).
- The encryption recommendation, the capability it gives up, the documents that must be rewritten, and three genuine owner questions, all surfaced and none ducked (Part 1, section 5, section 24).
