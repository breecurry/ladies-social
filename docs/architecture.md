# United Feminist — Technical Architecture, Data Model & Phased Delivery Plan

**Status:** Living blueprint. Phase 1 (identity, open signup, roles, audit) is built and migrated; everything from §2's social schema onward is planned, not built. Where this document and `supabase/migrations/` disagree, the migrations are authoritative.
**Date:** 2026-10-01 (membership model updated 2026-10-02)
**Scope:** unitedfeminist.com, a social platform built as a safe space for women and their allies (Threads-class feature set). **Open registration: everyone is welcome, no invite, no vouch, no approval queue, no gender screening of any kind.** Enforcement is conduct-based and after the fact: bullying and harassment are banable offenses, and the Owner can ban any account including new accounts a banned person creates (ban-evasion detection is load-bearing). 18+, real name collected but displayed only by opt-in / @handle in feed, DMs with photo upload in V1, mobile-first responsive web, native apps later off the same API.

This document builds on, and does not contradict, the locked decisions in the project memory files (`ladiessocial-project.md`, `ladiessocial-security-architecture.md`, `ladiessocial-e2e-and-roles.md`, `ladiessocial-design-system.md`). The design system is complete and is built-to, not redesigned.

---

# 0. EXECUTIVE SUMMARY

## The stack in one paragraph

**Next.js 15+ (App Router) on Vercel** for the web app and API layer; **Supabase** (managed Postgres + Auth + Realtime) as the backbone, with **Row Level Security as the actual enforcement layer** — which is exactly what the "role grants enforced at the database layer" requirement demands; **Cloudflare R2** for all media (zero egress — this is the single most important cost decision in the document), served exclusively through the **Cloudflare CDN** on the owner's existing Cloudflare-registered domain (satisfying the CSAM-scanning routing requirement); **Supabase Realtime** (Broadcast channels) for DM and notification delivery; **Postgres-native full-text search**; **pg_cron + a Postgres job table** for background work; **AWS S3 with Object Lock** as the tiny write-once vault for daily audit-log exports. Moderation vendors per the already-costed security report: Cloudflare CSAM scanning (free) + PhotoDNA (free) + Hive AI triage (metered).

Estimated infrastructure cost: **~$65–75/mo at 500 users, ~$130–180/mo at 5,000, ~$600–1,000/mo at 50,000** (details and the things that get expensive suddenly are in §1.4).

## The three biggest architectural judgment calls

1. **Supabase as the backbone instead of a bespoke Node API + separately hosted Postgres.** One vendor provides the database, authentication, and real-time transport, and its Row Level Security model lets us enforce the Owner-only role grants, the DM privacy rules, and the audit-log immutability *in the database itself* — not in application code that a bug can bypass. For a solo non-engineer owner, every additional moving part is a liability; this is the fewest moving parts that still meets the security requirements. The trade-off is vendor coupling, mitigated by the fact that everything is plain Postgres + SQL migrations and can be exported wholesale.

2. **All media lives in Cloudflare R2 with image variants pre-generated at upload — never transformed on the fly, never proxied through the app host.** Media egress is the classic cost bomb that kills small social platforms (S3-style egress at ~$0.09/GB means a modestly successful image feed costs thousands/month). R2 charges **zero egress at any volume**. Additionally: because we must re-encode every image anyway to strip EXIF (a locked safety requirement), generating the 3 serving sizes in the same step costs nothing and avoids Cloudflare's per-transformation metering (~$300/mo at 50k users if done on-the-fly). DM images get **PhotoDNA hash-checking at upload time as the primary CSAM control**, with Cloudflare's CDN-level scan as the second net — because relying on a CDN cache scan for private, authenticated media is not a guarantee we can prove.

3. **Deliberately un-clever read paths: fan-out-on-read feeds and adjacency-list threading on a single Postgres.** At ≤50,000 users, a well-indexed single Postgres answers "posts from people I follow" and "give me this whole thread" in milliseconds. Fan-out-on-write (per-user inbox tables), external search engines, and Redis caches are all *deferred*, with the schema designed so adding them later touches nothing existing. The owner cannot debug a distributed system; she will never need to debug one she doesn't have.

---

# 1. STACK RECOMMENDATION

Each choice below is defended against the stated alternatives. All prices verified October 2026 against vendor pricing pages; anything not directly verifiable is marked **UNCERTAIN**.

## 1.1 Choices and defenses

**Frontend: Next.js (App Router) — over SvelteKit.**
Both are credible. SvelteKit produces smaller bundles and is genuinely pleasant, but Next.js wins on the criteria that matter *for this owner*: it is the most heavily documented web framework in existence, has the deepest pool of battle-tested patterns for exactly this app shape (infinite feeds, optimistic likes, auth-gated routes, server components for fast first paint on mobile), first-class Supabase integration guides, and the largest talent pool if the owner ever hires. The design system's tokens are framework-agnostic and port cleanly. SvelteKit's ecosystem is thinner precisely in the areas this project leans on (auth helpers, upload handling, WebAuthn libraries). "Boring and well-documented" is a stated constraint; Next.js is the boring choice. The app ships as a responsive PWA (installable, web push) — which also satisfies "mobile-first web now, native later off the same API."

**Backend/API: Supabase (managed Postgres + Auth) + Next.js route handlers for server logic — over plain Postgres-on-a-managed-host, and over a standalone Node API.**
- *Plain managed Postgres (Neon/RDS/etc.)* gives us a database and nothing else: auth, session management, realtime, and storage all become separate builds or separate vendors. Rejected: strictly more moving parts for no capability gain.
- *A standalone Node API service* (Express/Fastify on Railway/Fly) means running and monitoring a server 24/7, plus hand-rolling auth. Rejected for a solo non-engineer owner.
- *Supabase* bundles Postgres 15+, an auth service (email, phone OTP via Twilio integration, MFA with WebAuthn factors, JWT with configurable expiry and server-side refresh-token revocation — all required by the roles design), and Realtime, for $25/mo. Crucially, Supabase makes **Row Level Security the default posture**, and RLS is how we meet the hard requirement that role grants and audit-log immutability are enforced *below* the application layer. The documented Supabase trap — `service_role` bypasses RLS — is handled by policy: service-role keys live only in server-side code paths, never in anything client-reachable, and the truly sensitive writes (role grants, audit appends, evidence filing) go through `SECURITY DEFINER` functions so even the app's normal server credentials cannot write those tables directly.
- Server logic that must not live in the client (franking verification, signup triage, media pipeline, moderation actions) lives in Next.js route handlers on Vercel — same repo, same deploy, no second service.

**Database: PostgreSQL 15+ (Supabase-managed).** Non-controversial. Full DDL in §2.

**File/media storage: Cloudflare R2 — over Supabase Storage and S3.**
R2: $0.015/GB-month, writes $4.50/M, reads $0.36/M, **egress $0**. Supabase Storage bills egress at $0.09/GB past 250GB — at 50k users serving images that is hundreds to thousands per month. S3 same problem plus CloudFront complexity. R2 also keeps all media on Cloudflare, which composes perfectly with the mandatory Cloudflare CDN serving path. Two buckets: a **staging bucket** (raw uploads land here, never served) and a **media bucket** (only EXIF-stripped, scanned, re-encoded output). DM media sits in the same media bucket under access-controlled paths served via a Cloudflare Worker that validates a short-lived signed token.

**Real-time transport (DMs + notifications): Supabase Realtime, Broadcast channels — over Ably, Pusher, and self-hosted WebSockets.**
- **Supabase Realtime (chosen):** included in the $25 Pro plan — 500 peak concurrent connections and 5M messages/mo, then **$10 per additional 1,000 peak connections and $2.50/M messages**. Private channels are authorized with RLS — the same security model as everything else. Design rules that keep it cheap and correct: use **Broadcast** (explicit publish per conversation/user channel), never per-row `postgres_changes` subscriptions (fan-out multiplies billable messages and melts the free quota); treat realtime as a *delivery hint* — Postgres is the source of truth and clients reconcile over REST on reconnect, so a dropped WebSocket message can never lose a DM.
- **Ably (runner-up):** free 6M msgs/mo, then $29/mo base + $2.50/M messages + $1.00/M connection-minutes. Better delivery guarantees (ordering, resume, 99.999% SLA). The upgrade path if Supabase Realtime ever disappoints — the transport is isolated behind one client module precisely so this swap is contained.
- **Pusher Channels (rejected):** Sandbox free tier caps at 200k messages/*day* and hard-blocks with 403s when exceeded; $49/mo for 500 connections, $299/mo for 2,000. Worse economics than both alternatives at every scale here.
- **Self-hosted WebSockets (rejected):** a 24/7 stateful service the owner cannot operate.

**Background jobs: pg_cron (built into Supabase) + a Postgres `jobs` table — over Inngest/Trigger.dev/QStash.**
The job load is modest and tolerant of minute-granularity: notification digests, feed-score recomputation, audit-log export, scan retries, report-velocity anomaly detection. pg_cron schedules; a Vercel cron-invoked route handler (or Supabase Edge Function) drains the job table with `FOR UPDATE SKIP LOCKED`. Zero new vendors, zero cost, transactional with the data it operates on. If job complexity ever grows real (it may not), Inngest is the managed upgrade — but do not start there.

**Search: Postgres full-text search (tsvector/GIN) + pg_trgm for handle/name lookup — over Meilisearch/Typesense/Algolia.**
50,000 users is *small* by search standards; Postgres FTS over posts plus trigram matching on handles/display-names is instant at this scale and costs nothing. Algolia at this document volume would run hundreds/month for no user-visible benefit. Revisit only if search relevance becomes a real complaint at scale.

**Caching: none beyond CDN + framework caching, deliberately.**
Cloudflare caches static assets and public media; Next.js caches rendered output where safe. No Redis in V1 — the feed queries it would cache are already fast at this scale, and a cache is one more thing to invalidate wrongly. Upstash Redis (~$10/mo) is the designated add-on if/when feed latency data says so.

**Hosting: Vercel Pro ($20/mo) — over Netlify and Cloudflare Pages.**
Next.js is Vercel's own framework; the sharp-based image processing in route handlers, cron invocation, and preview deployments all work with zero configuration. Netlify ($19/mo) is an acceptable substitute; Cloudflare Pages/Workers is cheapest but its runtime cannot run `sharp` (native binary) which the EXIF-strip pipeline needs. Critical cost rule enforced by architecture: **no media bytes ever flow through Vercel** (no Next/Image optimizer, no proxying) — HTML/JSON only, which keeps Vercel comfortably inside its included 1TB transfer at every scale modeled here. Set Vercel spend management alerts + pause threshold on day one (it is not on by default).

**CDN: Cloudflare (Free plan to start), proxying `unitedfeminist.com` and `media.unitedfeminist.com`.**
Mandatory, already decided, and the domain is already registered with Cloudflare. The free plan includes the CSAM scanning tool (all plans), DDoS mitigation, and WAF basics. Cloudflare Pro ($25/mo) is an optional later upgrade (better WAF rules, image polish) — not required for launch.

**Email (transactional — verification, security alerts, digest): Resend.** Free to 3k emails/mo (covers launch), $20/mo at 50k emails. Any equivalent (Postmark, SES) is fine; Resend has the least setup friction.

**Phone verification: Twilio Verify**, ~$0.05–0.10 per verification (one-time per signup), as already costed in the security report.

**Moderation stack (already decided in the security report, restated for completeness):** Cloudflare CSAM Scanning (free, all plans) + Microsoft PhotoDNA Cloud (free, apply ~1 week) + Hive Moderation ($3.00/1k images, $0.50/1k text) + Perspective API (free) as a text pre-filter. NCMEC CyberTipline registration **before** any image upload ships.

**Audit-log WORM export: AWS S3 + Object Lock (compliance mode), 7-year retention.**
The roles file calls for daily export to an immutable store. R2's lack of S3-style Object Lock is the one place R2 doesn't fit (R2 "bucket lock" retention may now exist — **UNCERTAIN**, verify at build; if confirmed, consolidate onto R2). The data is kilobytes/day; S3 cost is pennies. WORM storage that even the Owner cannot alter is the point — owner-tamperable logs are worthless in a dispute involving the Owner.

## 1.2 Why not [obvious alternatives] — quick table

| Alternative | Verdict |
|---|---|
| SvelteKit | Capable, but thinner ecosystem exactly where this project leans (auth, uploads, WebAuthn); smaller hiring pool |
| Firebase | Operation-based billing is unpredictable for feed-read-heavy apps; no SQL, no RLS-grade row security; no self-host exit |
| Neon/PlanetScale + separate auth | More vendors, more glue, no realtime; Supabase's bundle is cheaper in total |
| Ably/Pusher from day one | $29–49/mo for capability Supabase includes at $0 marginal cost; keep Ably as the designated upgrade |
| Algolia / Meilisearch Cloud | Real money for no benefit under ~10⁶ documents; Postgres FTS is fine |
| AWS end-to-end | Maximum flexibility, maximum ways for a solo non-engineer to get hurt (IAM, egress, no spend cap culture) |

## 1.3 Monthly cost at three scales

Assumptions: DAU ≈ 30% of registered; peak concurrent ≈ 10% of DAU; ~20% of posts carry an image; images stored as re-encoded master + 3 variants ≈ 700KB per upload total; DM volume typical of a small tight-knit network. Costs are infrastructure only — human T&S time is flagged separately.

**At 500 users (~150 DAU, ~50 peak concurrent):**

| Item | $/mo |
|---|---|
| Supabase Pro (Micro compute covered by credit) | 25 |
| Vercel Pro | 20 |
| Cloudflare Free + CSAM tool | 0 |
| R2 (≤20GB, modest ops) | 0–1 |
| Hive triage (~5k images, sampled text) | 10–20 |
| Resend (≤3k emails) | 0 |
| S3 WORM audit export | ~1 |
| Twilio Verify (per-signup, not recurring) | ~$0.08/signup |
| **Total** | **≈ $65–75** |

**At 5,000 users (~1,500 DAU, ~300–500 peak concurrent):**

| Item | $/mo |
|---|---|
| Supabase Pro + Small compute (+$5) + realtime at/near included quota | 30–45 |
| Vercel Pro (within credit/included) | 20–30 |
| R2 (~150–300GB stored) | 3–6 |
| Hive (~15k images/mo + text on reports & new accounts) | 50–80 |
| Resend | 20 |
| S3 WORM | ~1 |
| **Total** | **≈ $130–180** |

**At 50,000 users (~15,000 DAU, ~3,000–5,000 peak concurrent):**

| Item | $/mo |
|---|---|
| Supabase: base + Medium/Large compute ($50–100 net) + realtime overage (~4.5k extra peak conns ≈ $45; ~20M msgs ≈ $37) + API egress + db storage | 180–280 |
| Vercel: seats + edge requests/transfer overage (mitigated by Cloudflare caching in front) | 60–200 |
| R2 (~1.5–2.5TB stored; egress still $0) | 25–45 |
| Hive (~135k images/mo if fully scanned → trust-tiered sampling) | 150–400 |
| Resend / email | 20–90 |
| S3 WORM | ~2 |
| **Total** | **≈ $600–1,000** |
| Part-time human T&S (the security report's ~5,000-user threshold has long passed) | separate, real, budget it |

## 1.4 Things that get expensive suddenly — the honest flags

1. **Media egress — the classic killer — is engineered out** by R2's $0 egress. But it silently comes *back* if anyone ever routes images through the app host or framework image optimizer (Vercel transfer $0.15/GB past 1TB). Architectural rule: media bytes travel R2 → Cloudflare → user, full stop.
2. **On-the-fly image transformations** bill per unique transformation ($0.50/1k after 5k free). Scales with upload volume → ~$300/mo at 50k users. Engineered out by pre-generating variants at upload (free, since we re-encode for EXIF anyway).
3. **Supabase Realtime fan-out:** one event delivered to 500 clients bills as 500 messages. A naive `postgres_changes` subscription on a hot table can burn the 5M quota in days. Engineered out by Broadcast-only, per-conversation/per-user channels, and disconnecting hidden tabs.
4. **Supabase MAU past 100,000** bills ≈ $0.00325/MAU (≈ $490/mo at 250k MAU). Not a V1 problem; flagging so growth past ~100k is a planned budget event, not a surprise invoice.
5. **Hive moderation scales linearly with content volume** if everything is scanned. The knob: scan 100% of media from new/low-trust accounts, sample established accounts, always scan anything reported. The schema records scan decisions so the sampling rate is tunable without code changes.
6. **Vercel has no hard spend cap by default.** Configure spend management alerts + auto-pause at a threshold on day one.
7. **Supabase Pro's spend cap is ON by default** — which protects the budget but will *throttle the product* (e.g. realtime refusals) if quotas are hit. Decide deliberately when to switch it off; set billing alerts either way.

---

# 2. COMPLETE DATABASE SCHEMA

PostgreSQL 15+ / Supabase. Conventions: `auth.users` is Supabase-managed (identities, emails, password hashes, sessions, refresh tokens — see §2.9); everything below is in `public`. All timestamps `timestamptz`. All tables get RLS **enabled**; tables without a listed policy are deny-by-default and reachable only through `SECURITY DEFINER` functions or server-side (service-role) code paths — that is deliberate.

The five E2E-readiness decisions from the roles file are all present: (1) `message_content.ciphertext` from day one; (2) per-message franking (`frank_hash`) from day one; (3) `user_devices` + `one_time_prekeys` created now, empty; (4) `messages` (metadata) split from `message_content` (ciphertext) so RLS treats them differently; (5) short JWTs + server-side refresh revocation (config, §2.9).

```sql
-- ============================================================
-- EXTENSIONS
-- ============================================================
create extension if not exists pgcrypto;      -- digest() for hash chaining
create extension if not exists citext;        -- case-insensitive handles/emails
create extension if not exists pg_trgm;       -- handle/name search
-- pg_cron enabled via Supabase dashboard for scheduled jobs

-- ============================================================
-- ENUMS
-- ============================================================
create type system_role      as enum ('owner','admin','moderator','ts_reviewer');
create type trust_level      as enum ('member','established');
create type account_status   as enum ('active','restricted','suspended','banned','deactivated','deleted');
create type post_visibility  as enum ('visible','pending_scan','removed_moderation','removed_author');
create type reply_control    as enum ('everyone','followed','mentioned');
create type media_scan       as enum ('pending','clear','flagged','blocked');
create type msg_kind         as enum ('text','image','system');
create type member_state     as enum ('active','request','left');
create type report_subject   as enum ('post','message','user');
-- Report reasons are CONDUCT-based only. There is deliberately no
-- reason for reporting someone's perceived gender: the platform does
-- no gender screening and membership is open, so such a report has no
-- enforceable basis and would only invite members to police each
-- other's identities. (A 'male_account' value existed in an earlier
-- draft of this enum and was removed for exactly that reason.)
create type report_reason    as enum ('harassment','hate','violence_threat','doxxing','csam','ncii',
                                      'spam','impersonation','self_harm','other');
create type report_status    as enum ('open','in_review','actioned','dismissed','escalated');
create type report_routing   as enum ('standard','admin_only','owner_conflict');
create type mod_action_kind  as enum ('warn','remove_content','restrict','suspend','ban','unban',
                                      'reinstate_content','note');
create type notif_type       as enum ('follow','like','reply','mention','reshare','quote',
                                      'dm_request','system');

-- ============================================================
-- IDENTITY: profiles + private PII split
-- 🚨 display_name (the member's REAL LEGAL NAME) IS NOT PUBLIC BY DEFAULT.
--    Public display is OPT-IN. The default public identity is the @handle
--    alone. This is deliberate pseudonymity-with-accountability: the platform
--    knows exactly who everyone is, but a member hiding from a stalker is not
--    exposed to the whole internet by signing up.
--    This block previously read "Real name (display_name) is PUBLIC on the
--    profile by spec" and declared the column NOT NULL. That was WRONG and
--    contradicted the shipped migration. It is corrected below to match
--    20261001000002_identity.sql, which is authoritative.
-- Phone, IPs, fingerprints are PRIVATE -> separate table, Owner-only RLS.
-- ============================================================
create table profiles (
  user_id        uuid primary key references auth.users(id) on delete restrict,
  handle         citext not null unique check (handle ~ '^[a-z0-9_]{3,30}$'),
  -- NULLABLE on purpose. NULL = handle-only (the default). A trigger
  -- (enforce_display_name_is_legal_name) permits only NULL or the member's
  -- own verified legal name, so this can never become a nickname field.
  display_name   text   check (display_name is null or char_length(display_name) between 1 and 60),
  bio            text   check (char_length(bio) <= 300),
  avatar_media_key text,                      -- R2 key, served via Cloudflare
  -- 'member' from the moment the account exists (open registration);
  -- 'established' is a later trust tier (e.g. media-scan sampling).
  trust_level    trust_level not null default 'member',
  founding_member boolean not null default false,   -- badge only, zero privileges
  is_system      boolean not null default false,    -- the "United Feminist" account
  status         account_status not null default 'active',
  status_expires_at timestamptz,              -- for timed restrictions/suspensions
  search_indexable boolean not null default false,  -- opt-IN to search engines
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index idx_profiles_handle_trgm on profiles using gin (handle gin_trgm_ops);
create index idx_profiles_name_trgm   on profiles using gin (display_name gin_trgm_ops);

create table user_private (
  user_id        uuid primary key references profiles(user_id) on delete cascade,
  legal_name     text not null,
  dob            date not null,
  email          citext not null,             -- triage copy; auth.users is authoritative
  phone_e164     text,                        -- reserved for phone verification (under evaluation)
  phone_verified_at timestamptz,
  age_attested_at   timestamptz not null default now(),  -- 18+ legal attestation
  device_fingerprint_hash bytea,
  signup_ip      inet,
  last_login_ip  inet,
  last_login_at  timestamptz,
  signup_flags   jsonb                        -- bot pre-filter auto-flags, when any fired
);

-- Ban-evasion blocklist: hashes only, never raw identifiers.
-- With open registration this is LOAD-BEARING: it is the mechanism
-- behind "I can ban whoever I want including any new accounts they may
-- make." Signups matching a banned hash are silently refused.
create table banned_identifiers (
  id           bigint generated always as identity primary key,
  kind         text not null check (kind in ('email_hash','phone_hash','device_hash')),
  value_hash   bytea not null,
  source_user_id uuid references profiles(user_id),
  reason       text,
  created_at   timestamptz not null default now(),
  unique (kind, value_hash)
);

-- The former INVITATIONS & VOUCHING section is gone: the admission
-- gate was removed on 2026-10-02 (owner decision: "all are welcome").
-- Registration is open; enforcement is conduct-based, after the fact.
-- Dropped with it: invitations, inviter_strikes, waitlist_applications,
-- waitlist_vouches, admission_applications, vouch_requests,
-- privilege_grants (auto_admit existed only for vouching), and the
-- pending_vouch trust level. See migrations 0011 and 0012.

-- ============================================================
-- SOCIAL GRAPH
-- ============================================================
-- PHASE 2A IMPLEMENTATION NOTE (migration 20261005000001_social_core.sql
-- is authoritative for everything below through notifications):
--   * Shipped: follows, blocks (mutual-hard, with a SECURITY DEFINER
--     blocked_either()/blocked_by() pair used inside RLS), mutes,
--     hidden_accounts ("show me less", a Discover/ranking signal that
--     deliberately does NOT filter the Following feed), text-only posts
--     (adjacency list + trigger-maintained root/depth), post_mentions,
--     likes, reports (via file_report(), routing computed server-side),
--     notifications + notification_prefs.
--   * Posts are written ONLY via create_post()/delete_post(); reports
--     ONLY via file_report(); direct writes are REVOKEd from
--     authenticated AND service_role.
--   * Every feed/thread/search/list read function returns the author's
--     @handle only; display_name is structurally absent from all
--     return shapes (the legal-name rule enforced below the app layer).
--   * RESHARES/QUOTES ARE NOT SHIPPED: posts has no quoted_post_id or
--     reshare_count and there is no reshares table yet. That schema
--     arrives ADDITIVELY with the reshare feature (a forward-only
--     migration adds the columns, table, and notif_type values); the
--     DDL below is the blueprint for that moment, not current truth.
--   * Similarly deferred to their features: report_subject's 'message'
--     value and the reshare/quote/dm notif_type values (the shipped
--     enums are post/user and follow/like/reply/mention/system).
create table follows (
  follower_id  uuid not null references profiles(user_id) on delete cascade,
  followee_id  uuid not null references profiles(user_id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
create index idx_follows_followee on follows (followee_id);  -- "who follows me"
-- (follower_id, followee_id) PK already serves "who do I follow"

create table blocks (
  blocker_id   uuid not null references profiles(user_id) on delete cascade,
  blocked_id   uuid not null references profiles(user_id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index idx_blocks_blocked on blocks (blocked_id);

create table mutes (
  muter_id     uuid not null references profiles(user_id) on delete cascade,
  muted_id     uuid not null references profiles(user_id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (muter_id, muted_id),
  check (muter_id <> muted_id)
);

-- Enforce: the Owner's account and the system account cannot be blocked.
-- (Locked product decision. Blocking also never impedes moderation, because
-- moderation is a system capability that does not consult the blocks table.)
create or replace function forbid_blocking_protected() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from profiles p where p.user_id = new.blocked_id and p.is_system) then
    raise exception 'This account cannot be blocked.';
  end if;
  if exists (select 1 from role_assignments ra
             where ra.user_id = new.blocked_id and ra.role = 'owner' and ra.revoked_at is null) then
    raise exception 'This account cannot be blocked.';
  end if;
  return new;
end $$;
create trigger trg_blocks_protected before insert on blocks
  for each row execute function forbid_blocking_protected();

-- ============================================================
-- POSTS & THREADING  (adjacency list + denormalized root/depth)
-- ============================================================
create table posts (
  id             bigint generated always as identity primary key,
  author_id      uuid not null references profiles(user_id),
  parent_post_id bigint references posts(id),
  root_post_id   bigint not null,             -- = id for roots; set by trigger
  depth          smallint not null default 0,
  body           text not null check (char_length(body) <= 500),
  quoted_post_id bigint references posts(id), -- quote-posts
  reply_control  reply_control not null default 'everyone',
  like_count     integer not null default 0,
  reply_count    integer not null default 0,
  reshare_count  integer not null default 0,
  visibility     post_visibility not null default 'visible',
  created_at     timestamptz not null default now(),
  edited_at      timestamptz,
  deleted_at     timestamptz
);
create index idx_posts_author_time on posts (author_id, created_at desc)
  where deleted_at is null and parent_post_id is null;      -- profile tab + feed source
create index idx_posts_thread      on posts (root_post_id, created_at)
  where deleted_at is null;                                  -- whole-thread fetch
create index idx_posts_parent      on posts (parent_post_id);
create index idx_posts_fts         on posts using gin (to_tsvector('english', body));
create index idx_posts_recent      on posts (created_at desc)
  where deleted_at is null and parent_post_id is null and visibility = 'visible';

create or replace function set_post_thread_fields() returns trigger
language plpgsql as $$
declare parent record;
begin
  if new.parent_post_id is null then
    new.root_post_id := new.id;  -- identity value is assigned before BEFORE-row triggers
    new.depth := 0;
  else
    select root_post_id, depth into parent from posts where id = new.parent_post_id;
    new.root_post_id := parent.root_post_id;
    new.depth := parent.depth + 1;
  end if;
  return new;
end $$;
create trigger trg_posts_thread before insert on posts
  for each row execute function set_post_thread_fields();

create table post_media (
  id           uuid primary key default gen_random_uuid(),
  post_id      bigint not null references posts(id) on delete cascade,
  ordinal      smallint not null default 0,
  r2_key       text not null,                 -- master; variants derive by suffix
  content_type text not null,
  width        integer, height integer, bytes integer,
  blurhash     text,
  alt_text     text check (char_length(alt_text) <= 1000),
  scan_status  media_scan not null default 'pending',
  created_at   timestamptz not null default now(),
  unique (post_id, ordinal)
);

create table likes (
  user_id    uuid   not null references profiles(user_id) on delete cascade,
  post_id    bigint not null references posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);
create index idx_likes_post on likes (post_id);

create table reshares (
  user_id    uuid   not null references profiles(user_id) on delete cascade,
  post_id    bigint not null references posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);
create index idx_reshares_post on reshares (post_id);
create index idx_reshares_user_time on reshares (user_id, created_at desc);

-- Counter maintenance via AFTER triggers on likes/reshares/posts(replies);
-- single-statement UPDATEs, acceptable write amplification at this scale.

-- ============================================================
-- DIRECT MESSAGES
-- metadata (messages) split from content (message_content):
-- E2E-readiness decision #4 -- RLS treats them differently, and a future
-- E2E phase changes WHAT goes in ciphertext, not the schema.
-- ============================================================
create table conversations (
  id          uuid primary key default gen_random_uuid(),
  created_by  uuid not null references profiles(user_id),
  created_at  timestamptz not null default now(),
  last_message_at timestamptz
);

create table conversation_members (
  conversation_id uuid not null references conversations(id) on delete cascade,
  user_id         uuid not null references profiles(user_id) on delete cascade,
  state           member_state not null default 'active',   -- 'request' = quarantined inbox
  last_read_message_id bigint,
  notifications_muted boolean not null default false,
  joined_at       timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
create index idx_conv_members_user on conversation_members (user_id, state);

create table messages (
  id              bigint generated always as identity primary key,
  conversation_id uuid not null references conversations(id) on delete cascade,
  sender_id       uuid not null references profiles(user_id),
  kind            msg_kind not null default 'text',
  created_at      timestamptz not null default now(),
  deleted_at      timestamptz                 -- soft-delete; ciphertext retained per retention policy
);
create index idx_messages_conv on messages (conversation_id, id desc);

create table message_content (
  message_id        bigint primary key references messages(id) on delete cascade,
  ciphertext        bytea not null,   -- P1: AES-256-GCM under server key (K_frank || plaintext inside)
  nonce             bytea not null,
  key_id            smallint not null,          -- server key version; enables rotation; 0 = client-encrypted (P2)
  encryption_scheme smallint not null default 1, -- 1 = server-held key, 2 = E2E (future)
  frank_hash        bytea not null    -- SHA-256(frank); franking from DAY ONE (decision #2)
);
-- Franking construction (per security memory -- salamander-safe):
--   frank = HMAC-SHA256(K_frank, plaintext || sender || recipient || timestamp)
--   K_frank rides INSIDE the ciphertext; server stores only SHA-256(frank).
--   NEVER raw AES-GCM as the committing primitive.

create table message_media (
  id           uuid primary key default gen_random_uuid(),
  message_id   bigint not null references messages(id) on delete cascade,
  r2_key       text not null,
  content_type text not null,
  width        integer, height integer, bytes integer,
  blurhash     text,
  scan_status  media_scan not null default 'pending',  -- PhotoDNA at upload, ALWAYS, DMs included
  created_at   timestamptz not null default now()
);

-- E2E-READY, EMPTY IN PHASE 1 (decision #3) -- populated only when E2E ships
create table user_devices (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references profiles(user_id) on delete cascade,
  device_name       text,
  identity_key_pub  bytea,
  signed_prekey_pub bytea,
  signed_prekey_sig bytea,
  created_at        timestamptz not null default now(),
  revoked_at        timestamptz
);
create table one_time_prekeys (
  id          bigint generated always as identity primary key,
  device_id   uuid not null references user_devices(id) on delete cascade,
  prekey_pub  bytea not null,
  consumed_at timestamptz
);

-- ============================================================
-- REPORTS & MODERATION
-- ============================================================
create table reports (
  id              uuid primary key default gen_random_uuid(),
  reporter_id     uuid not null references profiles(user_id),
  subject_type    report_subject not null,
  subject_post_id    bigint references posts(id),
  subject_message_id bigint references messages(id),
  subject_user_id    uuid references profiles(user_id),   -- the accused, always set
  reason          report_reason not null,
  details         text check (char_length(details) <= 2000),
  routing         report_routing not null default 'standard',
  -- 'admin_only'     when the accused holds moderator/ts_reviewer role
  -- 'owner_conflict' when the accused IS the Owner -> external escalation path (see §3.5)
  ai_triage_score numeric(4,3),
  ai_triage_label text,
  status          report_status not null default 'open',
  assigned_to     uuid references profiles(user_id),
  created_at      timestamptz not null default now(),
  resolved_at     timestamptz,
  resolved_by     uuid references profiles(user_id),
  resolution_note text,
  check (num_nonnulls(subject_post_id, subject_message_id) <= 1)
);
create index idx_reports_queue on reports (status, routing, created_at);
create index idx_reports_accused on reports (subject_user_id, created_at desc);
-- Brigading signal: >=10 reports on one account within 1h is a coordinated-attack
-- signal, not 10 valid reports (threat model #2). Computed by a scheduled job.

-- DM report evidence: the ONLY path by which any staff member ever sees DM content.
-- Populated exclusively by the SECURITY DEFINER function file_message_report(),
-- which re-verifies the frank against the stored frank_hash before accepting.
create table message_report_evidence (
  report_id   uuid not null references reports(id) on delete cascade,
  message_id  bigint not null references messages(id),
  plaintext   text not null,
  k_frank     bytea not null,
  frank       bytea not null,
  frank_verified boolean not null,
  is_context  boolean not null default false,   -- ±3-message context window
  created_at  timestamptz not null default now(),
  primary key (report_id, message_id)
);

create table moderation_actions (
  id              uuid primary key default gen_random_uuid(),
  actor_id        uuid references profiles(user_id),  -- null when actor_kind='system_ai'
  actor_kind      text not null default 'human' check (actor_kind in ('human','system_ai')),
  action          mod_action_kind not null,
  target_user_id  uuid references profiles(user_id),
  target_post_id  bigint references posts(id),
  target_message_id bigint references messages(id),
  report_id       uuid references reports(id),
  reason          text not null,
  duration        interval,                    -- restrict <=7d for moderators (enforced in grant fn)
  expires_at      timestamptz,
  created_at      timestamptz not null default now(),
  reversed_by     uuid references profiles(user_id),
  reversed_at     timestamptz
);
create index idx_mod_actions_target on moderation_actions (target_user_id, created_at desc);
create index idx_mod_actions_actor  on moderation_actions (actor_id, created_at desc);

-- CSAM events: Owner-only. Preservation >= 1 year (18 U.S.C. 2258A(h), REPORT Act).
create table csam_events (
  id            uuid primary key default gen_random_uuid(),
  detected_at   timestamptz not null default now(),
  source        text not null check (source in ('photodna','cloudflare','hive','user_report','manual')),
  user_id       uuid references profiles(user_id),
  media_r2_key  text,
  content_hash  bytea,
  account_suspended_at timestamptz,            -- auto-suspend on detection (threat model #4)
  ncmec_report_id text,
  reported_to_ncmec_at timestamptz,
  preserve_until timestamptz not null,          -- detected_at + >= 1 year
  notes         text
);

-- ============================================================
-- ROLES  (Owner-only grants, enforced BELOW the app layer)
-- ============================================================
create table role_assignments (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(user_id),
  role        system_role not null,
  granted_by  uuid not null references profiles(user_id),
  granted_at  timestamptz not null default now(),
  revoked_at  timestamptz,
  revoked_by  uuid references profiles(user_id)
);
create unique index uq_active_role on role_assignments (user_id, role) where revoked_at is null;
create unique index uq_single_owner on role_assignments (role) where role = 'owner' and revoked_at is null;

-- Layer 1: trigger -- even a path that somehow gets INSERT cannot grant
-- unless granted_by is the active Owner; the owner role itself is never grantable.
create or replace function enforce_owner_only_grants() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.role = 'owner' then
    raise exception 'The owner role cannot be granted.';   -- seeded by migration only
  end if;
  if not exists (select 1 from role_assignments
                 where user_id = new.granted_by and role = 'owner' and revoked_at is null) then
    raise exception 'Only the Owner may grant or revoke roles.';
  end if;
  return new;
end $$;
create trigger trg_roles_owner_only before insert or update on role_assignments
  for each row execute function enforce_owner_only_grants();

-- Layer 2 (the stronger one, per the roles design): the app's DB roles get NO
-- write access at all. Grants flow only through SECURITY DEFINER functions
-- called from the Owner endpoint after passkey/MFA re-auth (AAL2). Even SQL
-- injection in an admin endpoint cannot escalate.
revoke insert, update, delete on role_assignments from authenticated, anon;

create or replace function grant_role(p_target uuid, p_role system_role) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from role_assignments
                 where user_id = auth.uid() and role = 'owner' and revoked_at is null) then
    raise exception 'Only the Owner may grant roles.';
  end if;
  if p_role = 'owner' then raise exception 'The owner role cannot be granted.'; end if;
  -- AAL2 (recent MFA step-up) required; Supabase exposes the claim in the JWT
  if coalesce(auth.jwt()->>'aal','aal1') <> 'aal2' then
    raise exception 'Re-authentication required for role changes.';
  end if;
  insert into role_assignments (user_id, role, granted_by) values (p_target, p_role, auth.uid());
  perform append_audit('role.grant', 'user', p_target::text,
                       jsonb_build_object('role', p_role));
end $$;
-- revoke_role() mirrors this, sets revoked_at/revoked_by, and the API layer
-- immediately kills the target's sessions (short JWT window bounds exposure).

-- Helper predicates (STABLE, used in RLS policies)
create or replace function is_owner() returns boolean language sql stable security definer
  set search_path = public as
  $$ select exists (select 1 from role_assignments
                    where user_id = auth.uid() and role = 'owner' and revoked_at is null) $$;
create or replace function is_moderator_or_above() returns boolean language sql stable security definer
  set search_path = public as
  $$ select exists (select 1 from role_assignments
                    where user_id = auth.uid() and role in ('owner','admin','moderator')
                      and revoked_at is null) $$;

-- ============================================================
-- NOTIFICATIONS
-- ============================================================
create table notifications (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references profiles(user_id) on delete cascade,
  actor_id   uuid references profiles(user_id),  -- null for system notices
  type       notif_type not null,
  post_id    bigint references posts(id) on delete cascade,
  message_id bigint references messages(id) on delete cascade,
  created_at timestamptz not null default now(),
  read_at    timestamptz
);
create index idx_notifications_user on notifications (user_id, created_at desc);
create index idx_notifications_unread on notifications (user_id) where read_at is null;

create table notification_prefs (
  user_id    uuid primary key references profiles(user_id) on delete cascade,
  prefs      jsonb not null default '{}'::jsonb   -- per-type toggles; web-push subscription ids
);

-- ============================================================
-- BACKGROUND JOBS (pg_cron drains via worker endpoint)
-- ============================================================
create table jobs (
  id          bigint generated always as identity primary key,
  kind        text not null,
  payload     jsonb not null default '{}'::jsonb,
  run_after   timestamptz not null default now(),
  attempts    smallint not null default 0,
  max_attempts smallint not null default 5,
  locked_at   timestamptz,
  completed_at timestamptz,
  failed_at   timestamptz,
  last_error  text
);
create index idx_jobs_due on jobs (run_after) where completed_at is null and failed_at is null;

-- ============================================================
-- AUDIT LOG (append-only, hash-chained)
-- ============================================================
create table audit_log (
  seq         bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  actor_id    uuid,
  actor_role  text not null,
  action      text not null,          -- e.g. 'role.grant', 'mod.ban', 'owner.contact_view', 'csam.ncmec_filed'
  target_type text,
  target_id   text,
  detail      jsonb not null default '{}'::jsonb,
  ip          inet,
  session_id  text,
  prev_hash   bytea not null,
  row_hash    bytea not null
);

create or replace function audit_hash_chain() returns trigger
language plpgsql security definer set search_path = public as $$
declare last_hash bytea;
begin
  select row_hash into last_hash from audit_log order by seq desc limit 1;
  new.prev_hash := coalesce(last_hash, '\x00'::bytea);
  new.row_hash := digest(
      coalesce(new.actor_id::text,'') || new.actor_role || new.action ||
      coalesce(new.target_type,'') || coalesce(new.target_id,'') ||
      new.detail::text || new.occurred_at::text || encode(new.prev_hash,'hex'),
      'sha256');
  return new;
end $$;
create trigger trg_audit_chain before insert on audit_log
  for each row execute function audit_hash_chain();

-- Immutability: no UPDATE/DELETE path exists for ANY application role.
revoke update, delete on audit_log from authenticated, anon;
-- (Also revoked from the app's service paths; only INSERT via append_audit().)

create or replace function append_audit(p_action text, p_target_type text,
                                        p_target_id text, p_detail jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into audit_log (actor_id, actor_role, action, target_type, target_id, detail)
  values (auth.uid(),
          coalesce((select role::text from role_assignments
                    where user_id = auth.uid() and revoked_at is null
                    order by case role when 'owner' then 0 when 'admin' then 1
                                       when 'moderator' then 2 else 3 end limit 1),
                   'member'),
          p_action, p_target_type, p_target_id, coalesce(p_detail,'{}'::jsonb));
end $$;

-- Daily job exports the day's rows + chain head to AWS S3 Object Lock
-- (compliance mode, 7-year retention). The WORM copy is the source of truth
-- in any dispute involving actions the OWNER took.
```

## 2.1 Row Level Security — the security-critical policies

```sql
-- Enable RLS everywhere (deny-by-default on tables with no policy)
alter table profiles, user_private, follows, blocks, mutes,
  posts, post_media, likes, reshares,
  conversations, conversation_members, messages, message_content, message_media,
  user_devices, one_time_prekeys,
  reports, message_report_evidence, moderation_actions, csam_events,
  role_assignments, notifications, notification_prefs, jobs, audit_log,
  banned_identifiers
  enable row level security;
-- (Supabase: issue one ALTER per table; condensed here for readability.)

-- -------- profiles: public read within the platform, self-write
create policy profiles_read on profiles for select
  using (auth.uid() is not null and status <> 'deleted');
create policy profiles_self_update on profiles for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id
              and is_system = false            -- nobody self-promotes to system
              and status = status);            -- status changes only via moderation fns

-- -------- user_private: the subject and the Owner. Admins CANNOT see contact info.
create policy user_private_self on user_private for select
  using (auth.uid() = user_id);
create policy user_private_owner on user_private for select
  using (is_owner());                           -- every Owner read is also audit-logged at the API layer

-- -------- posts: readable by any authenticated member except where blocked
create policy posts_read on posts for select
  using (auth.uid() is not null
         and visibility = 'visible' and deleted_at is null
         and not exists (select 1 from blocks b
                         where b.blocker_id = posts.author_id and b.blocked_id = auth.uid()));
create policy posts_insert on posts for insert
  with check (auth.uid() = author_id
              and exists (select 1 from profiles p
                          where p.user_id = auth.uid()
                            and p.status = 'active'));
create policy posts_author_delete on posts for update
  using (auth.uid() = author_id);               -- soft-delete own posts
-- Moderator removals flow through SECURITY DEFINER mod functions, not this policy.

-- -------- messages metadata: conversation members only
create policy messages_members on messages for select
  using (exists (select 1 from conversation_members cm
                 where cm.conversation_id = messages.conversation_id
                   and cm.user_id = auth.uid()));

-- -------- message_content: conversation members ONLY. There is deliberately
-- NO moderator/admin/owner policy here. "NOBODY — not even Owner — can view
-- unreported DM content." Staff access to DM text exists exclusively via
-- message_report_evidence, which only the victim's report can populate.
create policy message_content_members on message_content for select
  using (exists (select 1 from messages m
                 join conversation_members cm on cm.conversation_id = m.conversation_id
                 where m.id = message_content.message_id
                   and cm.user_id = auth.uid()));
-- INSERT: server-side send path only (service role), after membership/block checks.

-- -------- message_report_evidence: moderation roles read; writes only via
-- file_message_report() which verifies the frank first.
create policy evidence_mod_read on message_report_evidence for select
  using (is_moderator_or_above()
         or exists (select 1 from role_assignments
                    where user_id = auth.uid() and role = 'ts_reviewer' and revoked_at is null));

-- -------- reports: reporter sees her own; queue visibility respects routing
create policy reports_own on reports for select
  using (reporter_id = auth.uid());
create policy reports_queue on reports for select
  using (
    (routing = 'standard'      and is_moderator_or_above())
    or (routing = 'admin_only' and exists (select 1 from role_assignments
                                           where user_id = auth.uid()
                                             and role in ('owner','admin') and revoked_at is null)
        and subject_user_id <> auth.uid())      -- never route a report to its accused
    or (routing = 'owner_conflict' and false)   -- NOT visible in-app even to Owner; external path (§3.5)
  );
create policy reports_create on reports for insert
  with check (reporter_id = auth.uid());

-- -------- role_assignments: visible to Owner and to the subject; writes: none (functions only)
create policy roles_visible on role_assignments for select
  using (is_owner() or user_id = auth.uid());

-- -------- audit_log: Owner reads; nobody updates/deletes (no such policies exist)
create policy audit_owner_read on audit_log for select using (is_owner());

-- -------- csam_events: Owner only
create policy csam_owner on csam_events for select using (is_owner());

-- -------- notifications: own rows
create policy notif_own on notifications for select using (user_id = auth.uid());
create policy notif_own_update on notifications for update using (user_id = auth.uid());

-- -------- blocks / mutes / follows / likes / reshares: own-row write, sensible read
create policy follows_read   on follows  for select using (auth.uid() is not null);
create policy follows_write  on follows  for insert with check (follower_id = auth.uid()
    and not exists (select 1 from blocks b where b.blocker_id = followee_id and b.blocked_id = auth.uid()));
create policy follows_delete on follows  for delete using (follower_id = auth.uid());
create policy blocks_own     on blocks   for all    using (blocker_id = auth.uid())
                                                    with check (blocker_id = auth.uid());
create policy mutes_own      on mutes    for all    using (muter_id = auth.uid())
                                                    with check (muter_id = auth.uid());
create policy likes_write    on likes    for insert with check (user_id = auth.uid());
create policy likes_delete   on likes    for delete using (user_id = auth.uid());
create policy likes_read     on likes    for select using (auth.uid() is not null);
-- reshares mirror likes.
```

## 2.2 Threading model — why adjacency list, not materialized path or closure table

**Chosen: adjacency list (`parent_post_id`) + two denormalized columns (`root_post_id`, `depth`), set once by trigger at insert.**

The read patterns, in order of heat:
1. **Feed** — top-level posts only. Threading irrelevant; served by `idx_posts_author_time`.
2. **Thread view** — "give me the *entire* conversation under this root." One indexed query: `WHERE root_post_id = $1 ORDER BY created_at` via `idx_posts_thread`; the tree is assembled in memory from `parent_post_id`. Threads on a Threads-class product are hundreds of rows at the extreme, not millions — in-memory assembly is microseconds. **No recursive CTE on the hot path, ever.**
3. **Reply counts / "view N more replies"** — denormalized `reply_count` plus `depth` (the design system shows 3 levels inline, then a focused thread view).

Against the alternatives:
- **Materialized path (ltree)** buys efficient *subtree* queries — `path <@ 'a.b.c'` — which we never need, because the UI always anchors on the root (fetch whole thread) or a single post (fetch direct children, served by `idx_posts_parent`). In exchange it costs path maintenance on every insert, a nonstandard extension in every query, and awkward keys.
- **Closure table** buys arbitrary ancestor/descendant queries at the cost of O(depth) rows per insert and a join on every read. Built for deep org-chart-style hierarchies; ours is capped shallow by the UI.
- Plain adjacency list *without* `root_post_id` would force recursive CTEs for thread assembly — that is the actual weakness of adjacency lists, and the single denormalized `root_post_id` column removes it entirely.

This is the least machinery that serves every read pattern with one index each. If a future native app wants partial-subtree pagination inside gigantic threads, add ltree then — it is an additive migration (backfill one column), not a restructure.

## 2.3 Sessions and refresh tokens

Supabase Auth owns `auth.sessions` and `auth.refresh_tokens` (rotation + reuse detection built in). Configuration, not schema (E2E-readiness decision #5):
- **JWT expiry 30 minutes** (Supabase-configurable, set by provisioning), refresh rotation on. Role revocation = revoke the user's refresh tokens server-side → dead within one 30-minute JWT window, matching the roles design.
- **Owner account:** WebAuthn/passkey. Supabase Auth passkeys are **beta as of May 2026** (experimental API); WebAuthn as an **MFA factor** (hardware security key → AAL2) is available. Plan: password + WebAuthn-factor MFA (YubiKey + platform authenticator) now, passkey-primary when GA; **no email-only recovery for the Owner**; printed one-time recovery codes; 4-hour inactivity cap and single-active-session enforced in middleware; `aal2` step-up re-auth required for role changes, permanent bans, audit reads, contact-info views, and CSAM filings (enforced in the SECURITY DEFINER functions, as shown in `grant_role`).

---

# 3. SYSTEM ARCHITECTURE

## 3.1 Request & auth flow

```
Browser (Next.js PWA)
   │  HTTPS (all traffic proxied through Cloudflare: WAF, DDoS, caching)
   ▼
Cloudflare ──► Vercel (Next.js)
                 ├─ Server Components / route handlers
                 │     • verify Supabase JWT (30-min expiry)
                 │     • business logic the client must not hold
                 ▼
               Supabase Postgres  ◄── RLS enforces per-row access on EVERY query,
                 │                    including any query a bug lets through
                 ├─ Supabase Auth (signup, phone OTP, MFA/AAL2, refresh rotation)
                 └─ Supabase Realtime (Broadcast; private channels authorized via RLS)

media.unitedfeminist.com ──► Cloudflare (cache + CSAM scan + Worker auth for DM media) ──► R2
```

Signup flow (open registration): email + password + legal name + date of birth + @handle → per-IP rate limit and handle availability → **ban-evasion check**: email and device-fingerprint hashes matched against `banned_identifiers`; a match is silently refused with a success-shaped, uniformly-timed response → bot pre-filter (disposable email domains, subnet velocity, profile-coherence heuristics) **auto-flags** the account but never blocks it → account created at `trust_level = 'member'`, active immediately → Supabase sends the confirmation email; the account cannot sign in until the address is confirmed. Device fingerprint hash + signup IP recorded. There is no admission step, no review queue, and no appearance or gender screening of any kind, by locked decision. Removal is conduct-based and after the fact.

## 3.2 Media upload pipeline (identical for posts, avatars, and DMs)

```
1. Client downsizes to ≤2048px long edge (canvas) — bandwidth courtesy, not a security step
2. POST /api/media/upload-ticket → auth + rate-limit + type/size checks
     → presigned PUT to R2 STAGING bucket (never publicly served)
3. Client PUTs file to staging; POST /api/media/{id}/commit
4. Server processing (Vercel route handler, sharp):
     a. decode; AUTO-ORIENT FIRST (orientation lives in EXIF)
     b. re-encode → EXIF/GPS/XMP stripped BEFORE anything is stored anywhere servable
        (locked requirement — stalker vector)
     c. generate variants: master 2048w, feed 1080w, thumb 320w + blurhash
     d. PhotoDNA hash check — ALL images, public AND DM (primary CSAM control)
        • hit → scan_status='blocked', account auto-suspended, csam_events row,
          Owner alerted, evidence preserved ≥1 year, NOTHING served
     e. Hive visual moderation per sampling policy (100% for new/low-trust accounts,
        sampled for established, always on report)
     f. write variants to R2 MEDIA bucket; delete staging object; scan_status='clear'
5. Serving: media.unitedfeminist.com (Cloudflare-proxied zone)
     • public post media: cached at edge, long Cache-Control, immutable keys
     • DM media: Cloudflare Worker validates short-lived signed token (issued only to
       conversation members) before reading R2
     → ALL image bytes pass through Cloudflare = CSAM scan requirement satisfied,
       and egress is $0
```

Why PhotoDNA-at-upload is primary and Cloudflare's scan is the second net: Cloudflare's free tool only inspects what passes through its CDN cache, and private authenticated DM media has unfavorable caching semantics — we cannot *prove* coverage. PhotoDNA at upload is deterministic: every image is checked before it is ever servable. (This beats the industry-common posture of not scanning DM media at all, and it is only possible because Phase 1 encryption is server-held — the documented "happy accident." If E2E ever ships, this scanning disappears and the CSAM posture must be formally re-opened.)

## 3.3 DM send path & real-time delivery

```
SEND: client → POST /api/conversations/{id}/messages
  1. membership + block + account-status checks (server-side)
  2. franking: K_frank (32B random) → frank = HMAC-SHA256(K_frank, plaintext‖sender‖recipient‖ts)
  3. encrypt: ciphertext = AES-256-GCM(server_key[key_id], K_frank ‖ plaintext)
  4. INSERT messages (metadata) + message_content (ciphertext, nonce, key_id, SHA-256(frank))
  5. Supabase Realtime Broadcast on private channel conversation:{id}
  6. notification row + (if subscribed) web push "New message from {name}" — no content in push

RECEIVE: subscribed client gets broadcast → renders envelope → fetches/decrypts via API.
  DB is source of truth; on reconnect the client reconciles from last_read_message_id.
  A lost WebSocket frame can never lose a message.

DM REQUESTS: conversation with a non-follower lands with member state='request'
  (quarantined Requests inbox per design system). No read receipts, sender not
  notified of viewing. Accept → 'active'; decline → closed silently.

REPORT: reporter's client submits {message_id, plaintext, K_frank, frank, ±3-message context}
  → file_message_report() recomputes HMAC and compares SHA-256(frank) to stored frank_hash
  → verified → evidence row + report (franking-verified badge in mod queue)
  → mismatch → rejected as fabrication.
  Moderators CANNOT reach DM content any other way (report-initiated access only —
  this is the structural control against moderator-as-stalker).
```

In Phase 1 the server *could* decrypt everything (it holds the keys — that is the point of reviewable DMs), but the moderation tooling is built exclusively on the franking/evidence path. The entire reporting UX, queue, and evidence log therefore gets built exactly once and survives an E2E upgrade unchanged.

## 3.4 Moderation pipeline

```
Report filed (post / user / DM-with-franking)
   │
   ├─ CSAM-class? → auto-suspend + quarantine media + csam_events + OWNER immediately
   │                (Owner personally owns NCMEC filing — not delegable)
   ▼
AI triage (minutes, job queue): Hive text/visual + Perspective → ai_triage_score
   ├─ score ≥ high threshold → auto-action: content hidden pending human review
   │                           + moderation_actions row (actor_kind='system_ai')
   ├─ mid band → human queue, priority-ordered
   └─ low band + low-signal reporter history → auto-dismiss with audit trail
   ▼
Moderator queue (routing-aware):
   • standard → moderators; admin_only (accused is a mod) → admins only
   • powers: warn / remove content / restrict ≤7 days / escalate   (NO permanent ban)
   ▼
Admin: restrictions >7d, permanent ban
Owner: legal reporting, law-enforcement contact, role consequences
   ▼
Every action → moderation_actions + append_audit() → hash chain → daily WORM export
Side effects: permanent bans hash the banned account's email/phone/device
fingerprint into banned_identifiers, so replacement accounts are refused at
signup (ban-evasion enforcement, load-bearing under open registration).
Anomaly job: report-velocity spike on one target (≥10/hr) → flagged as coordinated-
attack signal, queue de-prioritized, Owner notified — not treated as 10 valid reports.
```

## 3.5 Reports where the accused holds power

- **Accused is a moderator/T&S reviewer:** `routing='admin_only'`; the accused never sees the report; moderators cannot see each other's identities in tooling (per roles design).
- **Accused is an admin:** routed to Owner only.
- **Accused is the Owner:** `routing='owner_conflict'`. The report is acknowledged to the reporter, stored, and **not surfaced in any in-app queue — including the Owner's own**. A scheduled job forwards it to a pre-named **external contact** (the owner must designate one: her attorney or an agreed trusted third party) with a tamper-evident copy (the report row is in the hash-chained audit export). Honest limitation, stated plainly: on a solely-owned platform there is no technical mechanism that can discipline the Owner; this path provides *evidence integrity and an independent witness*, not enforcement. The owner must accept this explicitly (owner decision #4).

## 3.6 Feed generation — fan-out-on-read, and when that changes

**Following feed: fan-out-on-read (query-time).**
`SELECT … FROM posts WHERE author_id IN (my follows) AND parent_post_id IS NULL AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 30` with keyset pagination, served by `idx_posts_author_time`. At 50k users (median follows in the low hundreds), Postgres executes this in single-digit milliseconds. Fan-out-on-write (materializing a per-user inbox at post time) buys nothing here and costs a write-amplification pipeline, backfill-on-follow logic, and a repair story when it breaks — the kind of system the owner explicitly cannot operate.

**Algorithmic "For You" feed: periodically materialized candidates + read-time assembly.**
A pg_cron job (every ~10 min) scores recent posts (engagement velocity, recency decay, author diversity) into a small `feed_candidates` table (`post_id, score, computed_at` — created in the discovery phase). Read path: top candidates → subtract blocks/mutes/already-seen → light personalization (followed-graph proximity) → blend. Transparent, debuggable, no ML dependency; good enough until engagement data justifies more.

**When this must change:** fan-out-on-read degrades when (a) any account's follower count makes *other people's* feed queries slow — not applicable here; or (b) follow lists reach many thousands and p95 feed latency drifts past ~200ms at the database. Expected well past 100k users. The upgrade is additive: a `feed_items` inbox table + fan-out worker, hybrid approach (fan out normal accounts, read-merge celebrity accounts), touching no existing tables. The decision trigger is a measured p95, not a feeling.

## 3.7 Search

- **People:** pg_trgm over `handle` and `display_name` (prefix + fuzzy). Blocked users excluded; profiles are **not** search-engine-indexable by default (opt-in — threat model #3).
- **Posts:** Postgres FTS (`to_tsvector('english', body)`, GIN). Hashtag-style discovery rides the same index.
- Revisit (Meilisearch ~$30/mo or Typesense) only on measured relevance/latency complaints at scale.

---

# 4. API SURFACE

All endpoints HTTPS JSON under `/api`. Auth legend: **P** = public, **A** = authenticated member (active account), **M** = moderator+, **AD** = admin+, **O** = Owner (with AAL2 re-auth where marked ⚿). Cursor pagination throughout.

**Auth & session**
| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | /api/auth/signup | P | Open signup: email, password, legal name, date of birth, handle |
| POST | /api/auth/login | P | Password (+ MFA challenge when enrolled) |
| POST | /api/auth/logout | A | Revoke current session |
| POST | /api/auth/reauth | A | Step-up to AAL2 for privileged actions |
| GET | /api/me | A | Current user, roles, trust level, counts |

**Profiles & graph**
| GET | /api/profiles/{handle} | A | Public profile (respects blocks) |
| PATCH | /api/me/profile | A | Edit display name, bio, avatar |
| GET | /api/me/settings · PATCH same | A | Preferences incl. search-indexability opt-in |
| POST / DELETE | /api/users/{id}/follow | A | Follow / unfollow |
| GET | /api/profiles/{id}/followers · /following | A | Lists |

**Posts, threads, engagement**
| POST | /api/posts | A | Create post/reply/quote (body ≤500, media ids, reply_control) |
| GET | /api/posts/{id} | A | Single post |
| GET | /api/posts/{id}/thread | A | Full thread (root + tree) |
| DELETE | /api/posts/{id} | A (author) | Soft-delete own post |
| POST / DELETE | /api/posts/{id}/like | A | Like / unlike |
| POST / DELETE | /api/posts/{id}/reshare | A | Reshare / undo |
| GET | /api/posts/{id}/likes | A | Who liked |
| GET | /api/feed/following | A | Reverse-chron following feed |
| GET | /api/feed/foryou | A | Algorithmic feed |
| GET | /api/profiles/{id}/posts · /replies | A | Profile tabs |

**Media**
| POST | /api/media/upload-ticket | A | Validate; presigned PUT to staging |
| POST | /api/media/{id}/commit | A | Trigger strip/scan/variant pipeline |
| GET | /api/media/{id}/status | A | pending / clear / blocked |

**Search**
| GET | /api/search?q=&type=people\|posts | A | Trigram people search / FTS post search |

**Direct messages**
| GET | /api/conversations?filter=inbox\|requests | A | Conversation list |
| POST | /api/conversations | A | Start DM (non-follower → request state) |
| GET | /api/conversations/{id}/messages | A | Message history (decrypted server-side for members) |
| POST | /api/conversations/{id}/messages | A | Send (franking + encrypt + broadcast) |
| POST | /api/conversations/{id}/accept · /decline | A | Resolve a DM request |
| POST | /api/conversations/{id}/read | A | Advance read cursor |
| POST | /api/messages/{id}/report | A | Client-side report: plaintext + K_frank + frank + context |

**Notifications**
| GET | /api/notifications | A | List (unread first) |
| POST | /api/notifications/read | A | Mark read (ids or all) |
| PATCH | /api/me/notification-prefs | A | Per-type toggles |
| POST / DELETE | /api/push/subscription | A | Web-push (VAPID) subscribe/unsubscribe |

**Safety**
| POST / DELETE | /api/users/{id}/block | A | Block (silent; no notification to anyone) / unblock |
| POST / DELETE | /api/users/{id}/mute | A | Mute / unmute |
| GET | /api/me/blocks · /mutes | A | My lists |
| POST | /api/reports | A | Report post or user (DM path above) |
| GET | /api/reports/{id} | A (reporter) | Status of my report |

**Moderation (M)**
| GET | /api/mod/queue | M | Routing-aware, triage-prioritized queue |
| GET | /api/mod/reports/{id} | M | Full report + evidence (franking-verified for DMs) |
| POST | /api/mod/reports/{id}/action | M | warn / remove_content / restrict ≤7d / dismiss |
| POST | /api/mod/reports/{id}/escalate | M | To admin/Owner |
| GET | /api/mod/users/{id}/history | M | Prior reports & actions (no contact info) |

**Admin (AD)**
| GET / PATCH | /api/admin/config | AD | Thresholds and triage parameters |
| GET | /api/admin/analytics | AD | Aggregates (no PII) |
| POST | /api/admin/users/{id}/suspend | AD | Restriction >7 days |
| POST | /api/admin/users/{id}/ban · /unban | AD | Permanent ban / reinstate |
| GET | /api/admin/escalations | AD | Escalated queue |

**Owner (O)**
| POST | /api/owner/roles/grant · /revoke | O ⚿ | Via grant_role()/revoke_role() SECURITY DEFINER only |
| GET | /api/owner/audit-log | O ⚿ | Chained log + chain-verification status |
| GET | /api/owner/users/{id}/contact | O ⚿ | Email/phone (each access itself audit-logged) |
| GET | /api/owner/csam · POST /api/owner/csam/{id}/ncmec | O ⚿ | CSAM event log; record CyberTipline filing |
| POST | /api/owner/system-notice | O ⚿ | Publish as the unblockable "United Feminist" system account |

**Internal**
| POST | /api/internal/jobs/drain | cron secret | pg_cron-triggered worker |
| POST | /api/hooks/hive | signed webhook | Async scan callbacks |

---

# 5. PHASED DELIVERY PLAN

Sequence and dependencies only — no durations, no calendar. Each phase ends demonstrable. **Launch gate = end of Phase 6.** Owner-visible demos at every phase keep the build honest.

**Phase 0 — Approvals & provisioning** *(blocks everything)*
Owner approves this blueprint and answers the decision list (§7). Accounts provisioned: Supabase, Vercel, R2 + Cloudflare zone config, Twilio, Resend, AWS (S3 WORM bucket). PhotoDNA application submitted (lead time). **NCMEC CyberTipline registration initiated** (hard prerequisite for Phase 3). Trademark search commissioned. Attorney engaged for ToS/CSAM-posture review (documents already drafted — see legal memory file).
*Owner + Grove orchestrating; Grove-Deploy for provisioning; Grove-Security owns the NCMEC/PhotoDNA checklist.*

**Phase 1: Identity and the security skeleton** *(depends: 0)* **(BUILT, with the 2026-10-02 membership update applied)**
Shipped: identity/roles/audit schema migrations; Supabase Auth config (30-min JWTs, refresh rotation, required email confirmation); **open signup** (no inviter field, no admission step) with ban-evasion refusal and bot-signal auto-flagging; profiles; trust levels (`member` from signup); roles tables + DB-layer enforcement + `grant_role` path; audit log with hash chaining; Owner account hardening (TOTP MFA to AAL2; WebAuthn pending Supabase support); the "United Feminist" system account; app shell with design tokens applied. The original vouch/admission gate shipped in this phase and was then removed by migrations 0011/0012 when the owner opened registration.
Demonstrable: anyone can sign up and immediately see member surfaces; the Owner grants a moderator role from her account and the attempt from any other account fails *at the database*.
*Grove-Code builds; Grove-Security reviews gate + roles enforcement before merge; Grove-Design supplies shell polish; Grove-Deploy CI/CD + environments.*

**Phase 2 — Text social core** *(depends: 1)*
Ships: posts (text-only), threaded replies with the guide-rail nesting UI, likes, reshares, follows, following feed, profile tabs, people search, in-app notifications, block/mute (with the first-class Shield affordance and swipe actions from the design system), basic report filing into a minimal queue, reply controls (Everyone / Followed / Mentioned).
Demonstrable: a genuinely usable private text network for the founding cohort — this is the smallest thing that is honestly usable, and it is real daily-driver software.
*Grove-Code; Grove-Design review against the token spec (including the @handle-forward feed identity — the documented correction); Grove-Test starts the regression suite.*

**Phase 3 — Media pipeline & moderation backbone** *(depends: 2; gated on NCMEC registration + PhotoDNA approval)*
Ships: the full §3.2 pipeline (staging bucket → EXIF strip → variants → PhotoDNA → R2 → Cloudflare serving, with the Worker auth path for private media); images on posts + avatars; Hive + Perspective triage wiring; full moderation queue with routing, mod actions, report-velocity anomaly job; permanent bans feeding banned_identifiers (ban-evasion blocklist); CSAM response runbook wired (auto-suspend → Owner alert → preservation).
Demonstrable: image posts that are EXIF-clean and CSAM-screened; a working mod queue processing real reports end-to-end.
*Grove-Code; Grove-Security gates this phase — no image upload goes live without her sign-off on the NCMEC/PhotoDNA/runbook checklist; Grove-Deploy for Cloudflare Worker + cache config.*

**Phase 4 — Direct messages** *(depends: 3 — DM images reuse the pipeline; franking reviewed before merge)*
Ships: conversations, Requests quarantine inbox, message send path with franking + server-side AES-256-GCM, **DM photo attachments** (hard requirement), Supabase Realtime broadcast delivery with REST reconciliation, read cursors, DM reporting with franking verification + context window + evidence log, empty `user_devices`/`one_time_prekeys` tables shipped (E2E-ready).
Demonstrable: two members exchange text and photos in real time; a reported DM arrives in the mod queue cryptographically verified; a fabricated report is rejected.
*Grove-Code; Grove-Security line-review of the franking implementation (HMAC construction, not raw AEAD commitment) before merge; Grove-Test on delivery/reconnect edge cases.*

**Phase 5 — Discovery & algorithmic feed** *(depends: 2; parallelizable with 4 after 3)*
Ships: For You feed (candidate scoring job + blended read path), post FTS search, quote-posts, web push notifications, notification aggregation ("3 people liked…").
Demonstrable: both feed tabs live; push works on installed PWA.
*Grove-Code; Grove-Test on feed correctness (blocks/mutes never leak into For You).*

**Phase 6 — Launch hardening** *(depends: 4 + 5)*
Ships: WCAG 2.2 AA accessibility audit against the design system's measured ratios; load test at 10× founding-cohort scale; security review pass (RLS policy audit, rate limits, abuse paths, secrets hygiene); incident runbooks (DDoS, doxxing-of-owner, CSAM, deplatforming pressure — threat model #2 requires the owner's personal security + comms plan *before* launch); legal checklist (attorney-reviewed ToS + privacy policy live, placeholders filled); onboarding content + community guidelines surfaced in-product; Vercel/Supabase spend alerts configured.
Demonstrable: launch-ready build; founding cohort (10–50 personally-known first members) onboarded. **Launch.**
*Grove-Test leads; Grove-Security signs off; Grove-Content for onboarding/guidelines; Grove-Deploy for runbooks + monitoring.*

**Post-launch backlog (explicitly out of V1):** T&S reviewer tooling · moderator volume-anomaly dashboards for the Owner · E2E upgrade (requires: external crypto audit $15–50k, browser-key-storage decision, and **re-opening the DM CSAM posture** — the documented trap) · native iOS/Android off the same API · EU/UK expansion with GDPR workstream.

---

# 6. RISK REGISTER

| # | Risk | Why it hurts | Mitigation / trigger |
|---|---|---|---|
| 1 | **Supabase coupling** (auth, RLS, realtime in one vendor) | Migration later is real work; Supabase pricing/behavior changes propagate | Everything is plain Postgres + SQL migrations (pg_dump exits cleanly); auth is standard JWT; realtime isolated behind one client module with Ably as named fallback. Accepted deliberately — the alternative (more vendors, more glue) is riskier *for this owner* |
| 2 | **Cloudflare-scan coverage of private DM media is unprovable** (cache-based tool, authenticated content) | CSAM posture gap in the most sensitive surface | Already mitigated: PhotoDNA-at-upload is the primary control on 100% of images incl. DMs; Cloudflare is the second net. Verify actual scan behavior with Cloudflare during Phase 3. **UNCERTAIN** flag maintained until verified |
| 3 | **Supabase Realtime limits** (500 peak conns included; fan-out billing; best-effort delivery) | Silent realtime refusals look like "DMs are broken" | Broadcast-only design; disconnect hidden tabs; DB-as-source-of-truth reconciliation; monitor peak connections from day one; Ably swap is contained if ever needed |
| 4 | **Owner passkey support is beta in Supabase Auth** | The single most-attacked account depends on experimental API | Ship WebAuthn **MFA factor** (stable) + YubiKey now; adopt passkey-primary at GA; no email recovery for Owner regardless |
| 5 | **Single Postgres is the whole platform** | Outage = total outage; data loss = fatal | Supabase daily backups + **PITR add-on (~$100/mo) before launch is worth it — recommend at Phase 6**; weekly restore drill documented in runbooks |
| 6 | **Feed strategy ages out** at very large scale | p95 feed latency degrades gradually, then reputationally | Measured trigger (p95 > ~200ms at DB) → additive `feed_items` fan-out hybrid; no schema rework required. Do not build early |
| 7 | **Hot counters** (like_count on a viral post) | Row-lock contention under burst | Acceptable at modeled scale; if contention appears, switch that counter to periodic aggregation — contained change |
| 8 | **Moderation cost scales linearly with content** (Hive) | $400+/mo at 50k users if everything is scanned | Trust-tiered sampling policy with rates stored in config; reports always scanned; revisit vendor mix (AWS Rekognition at $1/1k for the crude tier) |
| 9 | **The E2E trap** (documented in memory): upgrading DMs to E2E silently kills DM-image CSAM scanning | Legal posture regression nobody notices | Blocked in the backlog: E2E work item *requires* re-opening CSAM posture + counsel; franking/evidence pipeline already E2E-compatible so the pressure to rush is low |
| 10 | **Reports against the Owner have no independent enforcement** | Governance gap on a solely-owned platform; also a credibility risk | §3.5 external-witness path (tamper-evident evidence + named external contact). Honest limitation — owner must accept it on the record (decision #4) |
| 11 | **Coordinated false-report brigading** (threat model #2, amplified by the explicitly political name) | Trans members especially targeted; queue weaponized | Velocity anomaly job treats spikes as attack signal; reporter-pattern weighting; mod queue shows reporter history; Owner alerted on spikes |
| 12 | **Open registration invites bots, spam, and ban evasion** (the gate that used to absorb this is gone, by owner decision) | Moderation load scales with abuse, not just with members; a banned harasser can try again with a fresh account | Ban-evasion blocklist checked at signup (email/device hashes, silently refused); per-IP rate limits; subnet-velocity and disposable-email auto-flagging; device fingerprinting raises the cost of return. Honest limit: fingerprinting loses to determined actors with clean devices; it raises cost, it does not make evasion impossible |
| 13 | **Vercel/Supabase usage billing without hard caps** | Surprise invoice during a traffic spike or attack | Spend alerts + Vercel pause threshold on day one; Supabase spend cap decision made consciously at launch (cap = throttling risk, no cap = billing risk; recommend cap ON until launch, OFF with alerts after) |
| 14 | **Trademark on "United Feminist" never cleared** (flagged in memory, still open) | Rebrand after launch is expensive and demoralizing | Owner decision #6 — search before money goes into branding |

---

# 7. DECISIONS THE OWNER MUST MAKE (plain language)

1. **Approve the overall plan and budget.** Roughly **$65–75/month** to start, growing with the community (≈ $130–180/month at five thousand members; ≈ $600–1,000/month at fifty thousand, at which point part-time human help for safety reviews also becomes a real cost). Yes/no on this plan.

2. **RESOLVED 2026-10-02.** Nobody is ever judged by photo, appearance, or gender to get in, because there is no admission screening at all anymore. The owner removed the gate entirely: registration is open and removal is conduct-based. The earlier warning about appearance review (the Giggle/Tickle fact pattern) stands permanently: appearance screening must never be reintroduced in any form.

3. **Approve the lawyer touchpoints before launch:** (a) review of the already-drafted Terms of Service and the privacy policy, (b) sign-off on the child-safety-reporting posture before photo uploads go live, (c) a quick trademark search on "United Feminist" before money goes into branding. These are three contained engagements, not a retainer.

4. **Name the outside person who receives complaints made about *you*.** If a member ever reports the Owner's own account, that report should go to someone who isn't you — typically your attorney or a trusted third party — with a tamper-proof copy kept automatically. Who is that person?

5. **Owner-account security, in your hands:** buy a hardware security key (~$50), register it plus your phone/laptop login, and print the one-time recovery codes and store them somewhere safe (not email). Losing access to your account cannot be fixable by email alone — that's deliberate, because your account controls everything.

6. **Pick your Founding Cohort:** the 10–50 people you personally know and will bring in first. Registration is open, so there is no invite mechanism to manage; this is simply about who you personally ask to join early, because a community's first members set its tone. Choosing well-connected women (organizers, community-builders) still matters. Start writing the list.

7. **Decide the data-safety add-on at launch:** roughly **$100/month extra** buys point-in-time database recovery — the ability to rewind the entire platform to any second if something goes badly wrong. Recommended from launch day; your call on the spend.

---
*Identity, open signup, roles and audit (Phase 1 plus the open-registration migrations) are built and live in `supabase/migrations/`, which is authoritative where it and this document differ. The social-core SQL from §2 onward is the proposed schema for later phases, not a deployed migration.*
