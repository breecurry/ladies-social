-- ============================================================
-- 0021 — Discover (Phase 2B, Part 2): the lightly-ranked Discover
-- feed, the suggested-accounts module, and the Discoverability
-- opt-out (docs/design-phase2b-moderation-and-discover.md §9-§13).
--
-- Forward-only and idempotent: safe against the live database where
-- 0001-0020 are applied, and safe to re-run.
--
-- 🚨 IDENTITY RULE, UNCHANGED AND STRUCTURAL: no function in this
-- migration SELECTs or references profiles.display_name. Discover is
-- the widest surface in the product and it identifies every member by
-- @handle only. Suite 10 asserts this against pg_proc.
--
-- 🚨 POSITIVE-SIGNAL-ONLY RANKING (locked owner decision). The score
-- uses ONLY: recency, the viewer's own explicit positive acts (likes
-- of an author's posts, follows), follow-graph proximity (who your
-- follows follow / liked), gently-damped aggregate like counts, and a
-- small time-limited cold-start lift for new authors. Deliberately and
-- permanently ABSENT: reply/comment volume, controversy or ratio
-- signals, report/block/mute counts as amplification, negative-
-- reaction velocity, dwell-before-protective-action, quote/pile-on
-- chains, and ANY contacts or who-viewed-whom signal (design doc §11).
-- Reports, blocks, and mutes only ever filter or suppress — never
-- boost. Do not add a negative-engagement signal here, ever.
--
-- 🚨 DISCOVERABILITY (locked owner decision 2026-10-07): ON by
-- default, with a settings toggle to turn it off. A member who opts
-- out is excluded from every member's Discover feed and from the
-- suggested-accounts module. She remains fully reachable by @handle
-- search and her Following-feed/profile/thread visibility is
-- untouched: the toggle controls being SURFACED to strangers, not
-- being visible to people who already know her handle.
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- 1. The Discoverability opt-out column. Default TRUE (owner
--    decision). Column-level UPDATE grant mirrors the 0009 pattern:
--    profiles carries per-column grants, RLS scopes the row to self.
-- ------------------------------------------------------------
alter table profiles add column if not exists discoverable boolean not null default true;
grant update (discoverable) on profiles to authenticated;

-- ------------------------------------------------------------
-- 2. feed_discover(): recent root posts from across Hersciety,
--    freshness-forward, nudged by the viewer's positive signals.
--
--    Hard filters (never ranked past): the viewer must be an active
--    or restricted member; root posts only, undeleted, visible;
--    author active or restricted; author discoverable; mutual blocks
--    and mutes exclude entirely; the viewer's own posts are absent
--    (you do not discover yourself).
--
--    Soft signal: "show me less" (hidden_accounts) multiplies the
--    score down hard but does NOT hard-filter (P2 spec §4.8: hide is
--    a tuning signal, not a wall).
--
--    Score = recency × (1 + positive boosts) × hide-suppression.
--    Freshness dominates by construction: every boost is a bounded
--    multiplier on a decaying base, so Discover stays honestly
--    describable as "recent posts from across Hersciety" and a
--    heavily-liked old post cannot pin itself to the top.
--
--    Pagination is offset-based (a ranked order has no stable keyset
--    cursor); the candidate pool is capped at the 400 newest eligible
--    roots, which on this network is the whole platform for a long
--    time to come.
-- ------------------------------------------------------------
create or replace function feed_discover(
  p_limit  integer default 20,
  p_offset integer default 0
) returns table (
  id             bigint,
  author_id      uuid,
  author_handle  text,
  author_founding boolean,
  body           text,
  reply_control  reply_control,
  like_count     integer,
  reply_count    integer,
  viewer_liked   boolean,
  viewer_follows boolean,
  created_at     timestamptz
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with candidates as (
    select p.id, p.author_id, pr.handle::text as author_handle,
           pr.founding_member, p.body, p.reply_control,
           p.like_count, p.reply_count, p.created_at,
           pr.created_at as author_since
    from posts p
    join profiles pr on pr.user_id = p.author_id
    where exists (select 1 from profiles me
                  where me.user_id = auth.uid() and me.status in ('active', 'restricted'))
      and p.parent_post_id is null
      and p.deleted_at is null
      and p.visibility = 'visible'
      and pr.status in ('active', 'restricted')
      -- THE OPT-OUT: a member who turned Discoverability off never
      -- surfaces in anyone's Discover, full stop.
      and pr.discoverable
      and p.author_id is distinct from auth.uid()
      and not blocked_either(auth.uid(), p.author_id)
      and not exists (select 1 from mutes m
                      where m.muter_id = auth.uid() and m.muted_id = p.author_id)
    order by p.created_at desc, p.id desc
    limit 400
  ),
  scored as (
    select c.*,
           -- Freshness base: 1.0 now, halved at 24h, quartered at 72h.
           (1.0 / (1.0 + extract(epoch from (now() - c.created_at)) / 86400.0))
           * (1.0
              -- Your explicit affinity: you follow the author…
              + case when exists (select 1 from follows f
                                  where f.follower_id = auth.uid()
                                    and f.followee_id = c.author_id)
                     then 0.40 else 0 end
              -- …or you have liked her other posts (capped so one
              -- superfan session cannot monopolise the feed).
              + 0.30 * least((select count(*) from likes l
                              join posts lp on lp.id = l.post_id
                              where l.user_id = auth.uid()
                                and lp.author_id = c.author_id), 5)
              -- Graph proximity: authors your follows vouch for…
              + 0.15 * least((select count(*) from follows f1
                              join follows f2 on f2.follower_id = f1.followee_id
                              where f1.follower_id = auth.uid()
                                and f2.followee_id = c.author_id), 5)
              -- …and this post liked by people you follow.
              + 0.10 * least((select count(*) from likes l
                              join follows f on f.followee_id = l.user_id
                              where f.follower_id = auth.uid()
                                and l.post_id = c.id), 5)
              -- Aggregate endorsement, log-damped so a small account's
              -- loved post is not buried by a big account's okay one.
              + 0.20 * ln(1 + greatest(c.like_count, 0))
              -- Cold-start fairness: a new author's fresh posts get a
              -- modest, time-limited lift so new voices surface at all.
              + case when c.author_since > now() - interval '14 days'
                          and c.created_at > now() - interval '7 days'
                     then 0.25 else 0 end)
           -- "Show me less": strong suppression, never a wall.
           * case when exists (select 1 from hidden_accounts h
                               where h.hider_id = auth.uid()
                                 and h.hidden_id = c.author_id)
                  then 0.15 else 1.0 end
           as score
    from candidates c
  )
  select s.id, s.author_id, s.author_handle, s.founding_member,
         s.body, s.reply_control, s.like_count, s.reply_count,
         exists (select 1 from likes l
                 where l.post_id = s.id and l.user_id = auth.uid()),
         exists (select 1 from follows f
                 where f.follower_id = auth.uid() and f.followee_id = s.author_id),
         s.created_at
  from scored s
  order by s.score desc, s.created_at desc, s.id desc
  offset least(greatest(coalesce(p_offset, 0), 0), 400)
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

-- ------------------------------------------------------------
-- 3. suggested_accounts(): the people-first cold-start module
--    (design doc §12). Accounts the viewer does not follow, drawn
--    from graph proximity, her own like affinity, and the founding
--    cohort. Same PersonRow shape as search_people so the existing
--    row component renders it. Excludes: self, already-followed,
--    blocked (either direction), muted, hidden ("show me less" means
--    exactly that), opted-out (discoverable = false), and the system
--    account (it is a platform voice, not a person to meet).
-- ------------------------------------------------------------
create or replace function suggested_accounts(
  p_limit integer default 5
) returns table (
  user_id        uuid,
  handle         text,
  founding       boolean,
  bio            text,
  viewer_follows boolean
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select pr.user_id, pr.handle::text, pr.founding_member, pr.bio,
         false -- by construction: only never-followed accounts are suggested
  from profiles pr
  where exists (select 1 from profiles me
                where me.user_id = auth.uid() and me.status in ('active', 'restricted'))
    and pr.user_id is distinct from auth.uid()
    and not pr.is_system
    and pr.status in ('active', 'restricted')
    -- THE OPT-OUT, again: never suggest someone who opted out.
    and pr.discoverable
    and not exists (select 1 from follows f
                    where f.follower_id = auth.uid() and f.followee_id = pr.user_id)
    and not blocked_either(auth.uid(), pr.user_id)
    and not exists (select 1 from mutes m
                    where m.muter_id = auth.uid() and m.muted_id = pr.user_id)
    and not exists (select 1 from hidden_accounts h
                    where h.hider_id = auth.uid() and h.hidden_id = pr.user_id)
  order by
    -- Vouched-for by your own chosen graph first…
    least((select count(*) from follows f1
           join follows f2 on f2.follower_id = f1.followee_id
           where f1.follower_id = auth.uid()
             and f2.followee_id = pr.user_id), 5) desc,
    -- …then authors whose posts you have liked…
    least((select count(*) from likes l
           join posts lp on lp.id = l.post_id
           where l.user_id = auth.uid()
             and lp.author_id = pr.user_id), 5) desc,
    -- …then the founding cohort, then recent voices, deterministically.
    pr.founding_member desc,
    (select max(p.created_at) from posts p
     where p.author_id = pr.user_id
       and p.deleted_at is null
       and p.visibility = 'visible') desc nulls last,
    pr.created_at asc,
    pr.user_id asc
  limit least(greatest(coalesce(p_limit, 5), 1), 20)
$$;

-- ------------------------------------------------------------
-- 4. EXECUTE lockdown, same posture as every other member-session
--    read function: authenticated only. (create or replace preserves
--    ACLs on re-run, but a fresh create grants to PUBLIC under the
--    default privileges, so revoke explicitly and idempotently.)
-- ------------------------------------------------------------
revoke execute on function feed_discover(integer, integer)  from public, anon, service_role;
revoke execute on function suggested_accounts(integer)      from public, anon, service_role;
grant  execute on function feed_discover(integer, integer)  to authenticated;
grant  execute on function suggested_accounts(integer)      to authenticated;
