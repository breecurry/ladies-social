# Design, Phase 2C: Direct Messages (reworked — NOT end-to-end encrypted)

Status: CURRENT. This document replaces the E2E design of 2026-10-07 in
full. The owner reversed the end-to-end encryption decision on
2026-10-09; the rework landed 2026-10-05 (migration
`20261021000001_dm_remove_e2e.sql`). The feature remains DARK at two
layers until the Owner flips it.

---

## 0. The owner decision that governs everything here

Direct messages on Hersciety are **not end-to-end encrypted**, by
deliberate decision of the platform owner. The platform owner CAN read
message content. This is treated as a feature, not a confession:

- Members are told plainly, up front, on every Messages surface, that
  their messages are not private from the platform owner.
- Messages may be disclosed to authorities in matters involving
  trafficking or sexual exploitation, including of minors. Making
  exploitation *visible* to the platform is the point.
- The known trade-off — a database breach would expose message content,
  and these members are often hiding from specific people — has been
  weighed and accepted by the owner. The mitigation is the access
  hardening in §5, not encryption.

This decision is final. Do not re-propose E2E in any form, and do not
propose a cryptographic review — there is no cryptography left to
review.

### 0.1 Hard constraint one: the legal name never appears in any DM surface

Unchanged from every other phase. `display_name` is a real legal name;
every DM surface — inbox, thread, requests, notifications, report
evidence, moderation transcript — identifies members by @handle only.
Suite 09 asserts this structurally against `pg_proc`.

### 0.2 Hard constraint two: honesty in copy

Every DM surface says exactly what is true. The disclosure (§2) is
never softened, never a tooltip. It is dismissible on a fixed cycle
(owner decision, 2026-10-06; see §2) — never silently hidden, and any
failure to read or write its dismissal state shows it. "Delete" says
who still has a copy. A refusal never reveals a block.

---

## 1. What was removed, and why

The entire cryptographic layer existed to make messages unreadable to
the server. The server reads them now, so all of it went:

| Removed | Was |
|---|---|
| `src/lib/dm/crypto.ts` | X3DH + Double Ratchet on @noble/* (615 lines) |
| `src/lib/dm/store.ts`, `client.ts` | IndexedDB plaintext store + protocol orchestration |
| `user_devices`, `one_time_prekeys` | device key registry + prekey supply (0007/0020) |
| `dm_register_device`, `dm_add_prekeys`, `dm_my_device`, `dm_prekey_bundle`, `dm_active_device` | device/prekey machinery |
| Message franking (`frank_hash`, `K_frank`, verification in `file_dm_report`) | proof-of-sending for content the server could not read — pointless once the server stores the content itself |
| Safety numbers / VerifyDialog / key-change notices | verification UX for keys that no longer exist |
| The one-device-per-account limit | a consequence of E2E key management. **Phone + laptop now simply work.** |
| `@noble/ciphers`, `@noble/curves`, `@noble/hashes` | the crypto dependencies (nothing else imported them) |

`dm_messages` now stores a readable `body` (text, 1–2000 characters)
instead of `header` / `ciphertext` / `frank_hash`. There were 0 rows
in every DM table when the reshape landed; nothing was migrated
because nothing existed.

---

## 2. The member-facing disclosure

Rendered by `src/components/dm/DmDisclosure.tsx` as a banner on the
inbox and on every thread (including the new-message composer, which
is a thread surface). Verbatim:

> **Your messages are not private from Hersciety.** Direct messages
> are not end-to-end encrypted. The platform owner and moderators can
> read them, and every one of those reads is logged. Messages may be
> disclosed to authorities in matters involving trafficking or sexual
> exploitation, including of minors.

Rules: plain English, no euphemism, not a tooltip, identical copy
everywhere. The "every read is logged" clause is load-
bearing — it is enforced by `mod_dm_evidence()` (§5.3) and must never
outlive that enforcement.

**Dismissal (owner decision, 2026-10-06; the original always-on
decision was 2026-10-05).** The banner carries an X. Dismissing it
hides it on BOTH surfaces (inbox and every thread — one account-level
state) for a minimum of 45 days, then it returns at full prominence
and can be dismissed again, indefinitely. The quiet period is the
single constant `DM_DISCLOSURE_QUIET_DAYS` in
`src/lib/dm/disclosure.ts`. Mechanics, all server-side:

- State lives on `dm_settings` (`disclosure_dismissed_at`,
  `disclosure_dismissed_version`), per ACCOUNT — not localStorage —
  so the quiet period holds across devices and cookie clears. Absent
  row or null columns read as "never dismissed".
- The show/hide decision is `dm_disclosure_should_show()` (migration
  `20261026000001`), evaluated against the database clock and
  resolved in the server page, passed to the clients as a prop (no
  flash). Show when ANY of: never dismissed, dismissed version <
  `DM_DISCLOSURE_VERSION`, or dismissed more than the quiet period
  ago.
- The VERSION exists so a changed disclosure overrides the timer: if
  the copy materially changes (because staff access behaviour
  changed), bump `DM_DISCLOSURE_VERSION` in the same commit and every
  member sees the new text immediately, mid-quiet-period or not.
- FAIL TOWARD SHOWING: migration not applied, RPC error, unreadable
  state, failed persist — every failure path shows the banner. The X
  says what it does ("Dismiss this notice (it will return in 45
  days)"); the re-show is exactly as prominent as the first show.

---

## 3. Who may message whom (unchanged owner decisions)

All of this survived the rework exactly as designed and is enforced in
`dm_route()` / `dm_send_message()`, below the app:

- The main inbox receives only from people the recipient follows.
- Everyone else gets **exactly one silent message request**: no
  notification, no badge, preview-only, no second message until
  accepted. The conversation row itself is the one-request cap —
  declining hides the row but keeps it, so no path yields a second
  request.
- The recipient cannot reply to a request without explicitly
  accepting it.
- Settings (`dm_settings`, own-row RLS): who can send a request
  (everyone / people you follow / no one), a global DM off switch,
  read receipts (default off).
- **Block, DMs off, and "no one" raise the IDENTICAL refusal**, so a
  blocked person cannot distinguish a block.
- An existing conversation stays readable on both sides across a
  block (the history may be the evidence the blocker needs), but
  sending stops.

---

## 4. The surfaces

- `/messages` — inbox, Primary + Requests tabs. Rows now carry an
  honest server-side preview (`last_body`, truncated to 160 chars,
  respecting the member's own delete-for-me horizon) — under E2E the
  preview had to be decrypted on-device; that machinery is gone.
- `/messages/[id]` — the thread. Polls `dm_fetch_messages` (readable
  bodies), sends via `dm_send_message(recipient, body)`. 2000-char
  cap, Enter-sends on desktop, honest composer states (waiting /
  request bar / can-no-longer-reply).
- `/messages/new/[userId]` — composer against a picked member; first
  send creates the conversation.
- Recipient picker: @handle search only, honest about where the
  message will land ("will arrive as a request" / "can't message").
- Notifications: `message` type, accepted conversations only, **never
  any message content in the notification row** (shoulder-surfing
  safety — kept deliberately even though the server could now include
  it), one unread notification per sender, per-type pref and
  per-conversation mute honoured.
- All surfaces 404 while the flag is off.

---

## 5. Access hardening — the mitigation that replaces E2E

This section is the owner's accepted answer to "the platform can read
messages." It is not optional and future changes must preserve it.

### 5.1 RLS everywhere, zero direct reads of content

`dm_conversations`, `dm_participant_state`, `dm_messages`,
`dm_report_evidence`: RLS enabled, **zero policies, zero direct
privileges** for anon / authenticated / service_role. The SECURITY
DEFINER functions (all with pinned `search_path`) are the only path,
and each one verifies the caller participates in the conversation it
touches. `dm_settings` alone is member-writable (own row only).

### 5.2 Staff access to content is narrow

The owner and moderators reach message content through **exactly one
function**: `mod_dm_evidence(p_target)` — the evidence attached to
reports about a member. There is no browse-all-conversations surface,
deliberately. If one is ever needed it must follow the same pattern:
SECURITY DEFINER, pinned search_path, tier check, audit row per call.

### 5.3 Every staff content read is audited

`mod_dm_evidence()` writes a `dm.content_read` row to the hash-chained
`audit_log` on every call that returns content: who read, whose
messages, how many, when. Access is accountable, never invisible.
Suite 09 asserts the row is written and that a refused member read
writes nothing.

### 5.4 Encryption at rest — what is actually true

Supabase encrypts all customer data at rest with AES-256 (and in
transit with TLS). This is infrastructure-level, always on, cannot be
disabled, and is not configurable per project at this tier. It
protects against stolen disks and leaked physical media. It does NOT
protect against anyone who reaches the database with credentials —
that is what §5.1–§5.3 are for. **No further at-rest protection is
available on this tier**; column-level encryption would be
application-level key management, i.e. re-building a piece of what was
just removed, and is not part of this design.

### 5.5 The honest residual risk

Direct SQL access (the owner in the Supabase dashboard, or an
attacker with stolen credentials) bypasses RLS and the audit trail.
That is inherent to a server-readable design and is the accepted
trade-off of §0. The audit guarantee in the disclosure covers reads
through the product.

---

## 6. Reporting a DM

The reporter selects 1–10 messages; `file_dm_report()` **snapshots
them server-side** into `dm_report_evidence` (body, sender, recipient,
timestamp copied from the real rows). Nothing the reporter types is
ever presented as the accused's words — under E2E that guarantee
needed franking cryptography; now it is simply "the server copies its
own rows."

- A message id from another conversation voids the whole report.
- The snapshot table stays separate from `dm_messages` because
  evidence must survive the messages (accounts and conversations
  cascade-delete; moderation records carry retention obligations).
  `message_id` is deliberately not a foreign key.
- Same duplicate guard, hourly cap, staff routing, csam auto-escalate,
  and safety@ email copy (no reporter, no message text) as
  `file_report()`.
- The moderation console renders the transcript via `DmEvidence`
  (@handle only) and tells the moderator the read was audit-logged.

---

## 7. Retention and deletion (unchanged semantics, honest copy)

- "Delete conversation" is delete-for-me: hides the thread and moves
  the deleter's `cleared_before` horizon (messages AND preview). The
  other member keeps her copy, and the copy says so.
- A new message resurfaces the thread with only the new content.
- Message rows live until the conversation or an account is deleted
  (cascade). Report evidence snapshots persist per moderation
  retention (2 years).

---

## 8. The feature flag and go-live

Renamed: the old `dm_e2e_enabled` name claimed an encryption that no
longer exists.

1. **env `DM_ENABLED`** — read in `src/lib/dm/flag.ts`; gates every
   page, nav entry, and `/api/dm/*` route per environment.
2. **`app_config` key `dm_enabled` = `'true'::jsonb`** — checked
   inside every DM database function (`assert_dm_enabled()`), so a
   hand-crafted RPC is refused while off.

Both default OFF. The migration deliberately inserts nothing and
deletes any leftover `dm_e2e_enabled` row (a row under the old key
enables nothing — suite 09 proves it). Go-live order: apply migration
→ Grove-Test + Grove-Security pass → insert the `dm_enabled` row → set
`DM_ENABLED` in production env → redeploy.

⚠️ Preview and production share the live database: the DB flag is
shared; only the env var keeps one environment dark while the other
tests.

---

## 9. Deliberately not built (unchanged list, minus the E2E items)

Unsend / delete-for-everyone / per-message delete · bulk request
select · push notifications (no push infra platform-wide) · typing
indicators and presence (the server never emits them at all) · draft
persistence · desktop two-pane · message-content search (the server
could do it now; it is a product decision for later, not an
accident) · images in DMs (text-only; the image-DM preconditions from
the old design still apply, minus the E2E-specific ones — and note
server-side CSAM hash-scanning of DM images is now POSSIBLE, which
the old design had to give up).
