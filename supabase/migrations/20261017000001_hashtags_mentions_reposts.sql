-- ============================================================
-- 0025 — Hashtags, at-mentions, and reposts (Phase 2F).
-- Design: docs/design-phase2f-hashtags-mentions-reposts.md.
--
-- Forward-only and idempotent: safe against the live database where
-- 0001-0024 are applied, and safe to re-run.
--
-- 🚨 IDENTITY RULE, UNCHANGED AND STRUCTURAL: no function in this
-- migration SELECTs or references profiles.display_name. Every read
-- shape identifies people by @handle only. Suite 14 asserts it.
--
-- OWNER DECISIONS HONOURED HERE (2026-10-09, do not re-litigate):
--   1. BOTH plain reposts AND quote-posts ship, as ordinary first-class
--      features. A quote-post is a normal post that carries
--      quoted_post_id; it has no extra gating, cooldown, or friction.
--   2. "Who can mention you" defaults to EVERYONE, with
--      People-you-follow and No-one one tap away.
--
-- The abuse controls the design specifies are all here:
--   - mentions: bidirectional block wall (existing), mute suppression
--     (existing), the three-way mention policy, and a cap of 10
--     mention notifications per post (the post still renders and the
--     mentions still link past the cap; only the pings stop).
--   - trending: ranked by DISTINCT PEOPLE in a 48-hour window,
--     recency-weighted — never raw post volume, so one account cannot
--     manufacture a trend. No suppression thresholds, no k-floors:
--     real counts always show (owner rule: numbers are literal).
--   - tags: staff suppression in two audited, reversible tiers —
--     de-trend (moderator+) and block (admin+).
--   - reposts: a repost renders only while the original is visible,
--     its author reachable, and no block exists between the viewer
--     and either party NOR between the reposter and the original
--     author. Same wall for the embedded card of a quote-post.
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- 1. Enum additions and new enums (guarded for idempotency).
--    'reshare' and 'quote' are referenced only inside plpgsql bodies
--    below, never in DML in this file, so adding them in the same
--    transaction is safe (the 0020 pattern).
-- ------------------------------------------------------------
alter type notif_type add value if not exists 'reshare';
alter type notif_type add value if not exists 'quote';

do $$ begin
  if not exists (select 1 from pg_type where typname = 'tag_status') then
    create type tag_status as enum ('active', 'detrended', 'blocked');
  end if;
  if not exists (select 1 from pg_type where typname = 'mention_policy') then
    create type mention_policy as enum ('everyone', 'followed', 'no_one');
  end if;
end $$;

-- ------------------------------------------------------------
-- 2. "Who can mention you" (design §12). Default Everyone (owner
--    decision). Column-level UPDATE grant mirrors `discoverable`:
--    profiles carries per-column grants, RLS scopes the row to self.
-- ------------------------------------------------------------
alter table profiles add column if not exists
  mention_policy mention_policy not null default 'everyone';
grant update (mention_policy) on profiles to authenticated;

-- ------------------------------------------------------------
-- 3. Hashtag storage (design §3): a canonical tag entity, a per-post
--    join, and a trending snapshot. All three are function-only
--    tables: RLS enabled, zero policies, zero direct app-role grants
--    (the avatar_media lockdown pattern). Every read goes through the
--    SECURITY DEFINER functions below, which carry the block and
--    visibility filters.
-- ------------------------------------------------------------
create table if not exists tags (
  id         bigint generated always as identity primary key,
  tag        text not null unique
             check (char_length(tag) between 1 and 64),
  status     tag_status not null default 'active',
  created_at timestamptz not null default now()
);

create table if not exists post_tags (
  post_id bigint not null references posts (id) on delete cascade,
  tag_id  bigint not null references tags (id) on delete cascade,
  primary key (post_id, tag_id)
);
create index if not exists idx_post_tags_tag on post_tags (tag_id, post_id desc);

create table if not exists trending_tags (
  tag_id          bigint primary key references tags (id) on delete cascade,
  score           double precision not null,
  distinct_people integer not null,
  window_start    timestamptz not null,
  computed_at     timestamptz not null default now()
);

alter table tags          enable row level security;
alter table post_tags     enable row level security;
alter table trending_tags enable row level security;
revoke all on tags          from anon, authenticated, service_role;
revoke all on post_tags     from anon, authenticated, service_role;
revoke all on trending_tags from anon, authenticated, service_role;

-- The one canonical fold: strip a leading '#', Unicode-normalize
-- (NFC), lowercase. Matching is case-insensitive; display inside a
-- post body preserves the author's casing (a client concern).
create or replace function internal.fold_tag(p text) returns text
language sql immutable set search_path = public, extensions, pg_temp as $$
  select lower(normalize(ltrim(coalesce(p, ''), '#'), nfc))
$$;
revoke execute on function internal.fold_tag(text) from public, anon, authenticated, service_role;

-- ------------------------------------------------------------
-- 4. Reposts (design Part 3): the reshares table follows the likes
--    pattern — direct RLS-checked writes, a counter + notification
--    trigger, and read-time visibility rules in the feed functions.
--    posts gains the blueprint's quoted_post_id and reshare_count.
-- ------------------------------------------------------------
alter table posts add column if not exists quoted_post_id bigint references posts (id);
alter table posts add column if not exists reshare_count integer not null default 0;

create table if not exists reshares (
  user_id    uuid   not null references profiles (user_id) on delete cascade,
  post_id    bigint not null references posts (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);
create index if not exists idx_reshares_post on reshares (post_id);
create index if not exists idx_reshares_user_time on reshares (user_id, created_at desc);

alter table reshares enable row level security;

-- Your own repost rows are yours to see and remove; you can repost
-- any post you can see that is not your own and whose author is not
-- across a block from you. (Reposting your own post is redundant —
-- design §15 — and is refused structurally.)
drop policy if exists reshares_own_read on reshares;
create policy reshares_own_read on reshares for select
  using (user_id = auth.uid());
drop policy if exists reshares_own_insert on reshares;
create policy reshares_own_insert on reshares for insert
  with check (
    user_id = auth.uid()
    and is_active_member()
    and exists (select 1 from posts p
                where p.id = post_id
                  and p.deleted_at is null
                  and p.visibility = 'visible'
                  and p.author_id <> auth.uid()
                  and not internal.blocked_either(auth.uid(), p.author_id))
  );
drop policy if exists reshares_own_delete on reshares;
create policy reshares_own_delete on reshares for delete
  using (user_id = auth.uid());
revoke all on reshares from anon;
revoke update on reshares from authenticated;
revoke all on reshares from service_role;

-- Counter + notification. 'reshare' notifications are positive and on
-- by default, pref-gated like every other type, and honour the same
-- protections: never to yourself, never across a block, not when the
-- author has muted the reposter (design §18).
create or replace function on_reshare_change() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_author uuid;
begin
  if tg_op = 'INSERT' then
    update posts set reshare_count = reshare_count + 1
      where id = new.post_id
      returning author_id into v_author;
    if v_author is not null
       and v_author <> new.user_id
       and not blocked_either(v_author, new.user_id)
       and not exists (select 1 from mutes where muter_id = v_author and muted_id = new.user_id)
       and notif_enabled(v_author, 'reshare') then
      insert into notifications (user_id, actor_id, type, post_id)
      values (v_author, new.user_id, 'reshare', new.post_id);
    end if;
    return new;
  end if;
  update posts set reshare_count = greatest(reshare_count - 1, 0) where id = old.post_id;
  return old;
end $$;
revoke execute on function on_reshare_change() from public, anon, authenticated, service_role;

drop trigger if exists trg_reshares_change on reshares;
create trigger trg_reshares_change after insert or delete on reshares
  for each row execute function on_reshare_change();

-- ------------------------------------------------------------
-- 5. A third-party block check for the read paths. public.
--    blocked_either is caller-scoped (0014 P1-1) and raises when the
--    caller is neither party — correct for RPC surfaces, but the
--    repost rules need "is there a block between the reposter and the
--    original author?", where the viewer is neither. This helper has
--    NO app-role EXECUTE at all: it is callable only from inside the
--    SECURITY DEFINER read functions (which execute as the migration
--    owner), so it cannot be used to probe the block graph.
-- ------------------------------------------------------------
create or replace function internal.blocked_pair(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (
    select 1 from blocks
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a)
  )
$$;
revoke execute on function internal.blocked_pair(uuid, uuid) from public, anon, authenticated, service_role;

-- ------------------------------------------------------------
-- 6. create_post: quote-posts, hashtag indexing, the mention policy,
--    and the mention-notification cap. New parameter p_quote, so the
--    old 3-argument signature is dropped (PostgREST must never see an
--    ambiguous overload) and grants are restated below.
-- ------------------------------------------------------------
drop function if exists create_post(text, bigint, reply_control);
create or replace function create_post(
  p_body          text,
  p_parent        bigint default null,
  p_reply_control reply_control default 'everyone',
  p_quote         bigint default null
) returns bigint
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me             uuid := auth.uid();
  v_parent         posts%rowtype;
  v_parent_author  uuid; -- captured separately: plpgsql errors on field access
                         -- of a never-assigned record even behind short-circuit OR
  v_quote_author   uuid;
  v_id             bigint;
  v_mention        uuid;
  v_mpolicy        mention_policy;
  v_handle         text;
  v_tag            text;
  v_tag_id         bigint;
  v_tag_count      integer := 0;
  v_mention_notifs integer := 0;
begin
  if v_me is null then
    raise exception 'Not signed in.';
  end if;
  if not exists (select 1 from profiles where user_id = v_me and status = 'active') then
    raise exception 'Your account cannot post right now.';
  end if;
  if p_body is null or btrim(p_body) = '' then
    raise exception 'Post cannot be empty.';
  end if;
  if char_length(p_body) > 500 then
    raise exception 'Posts are limited to 500 characters.';
  end if;

  if p_parent is not null then
    select * into v_parent from posts
      where id = p_parent and deleted_at is null and visibility = 'visible';
    if not found then
      raise exception 'That post is unavailable.';
    end if;
    v_parent_author := v_parent.author_id;
    if blocked_either(v_me, v_parent_author) then
      raise exception 'That post is unavailable.';
    end if;
    -- P2-4: cap thread depth. get_thread's recursive walk must never be
    -- asked to chase an unbounded chain. The message is for humans.
    if v_parent.depth >= 30 then
      raise exception 'This conversation has reached its depth limit. Reply a little higher up the thread to continue it.';
    end if;
    if v_parent_author <> v_me then
      if v_parent.reply_control = 'followed' and not exists (
           select 1 from follows
           where follower_id = v_parent_author and followee_id = v_me) then
        raise exception 'Only people the author follows can reply to this post.';
      end if;
      if v_parent.reply_control = 'mentioned' and not exists (
           select 1 from post_mentions
           where post_id = p_parent and mentioned_user_id = v_me) then
        raise exception 'Only mentioned people can reply to this post.';
      end if;
    end if;
  end if;

  -- Quote-posts: a quote is a new root post carrying a pointer to the
  -- quoted post. It needs only what any read of that post needs: the
  -- post is visible and no block stands between the two members.
  -- Quoting your own post is allowed (adding your own later words to
  -- your own earlier ones is ordinary use).
  if p_quote is not null then
    if p_parent is not null then
      raise exception 'A post cannot be both a reply and a quote.';
    end if;
    select author_id into v_quote_author from posts
      where id = p_quote and deleted_at is null and visibility = 'visible';
    if v_quote_author is null then
      raise exception 'That post is unavailable.';
    end if;
    if blocked_either(v_me, v_quote_author) then
      raise exception 'That post is unavailable.';
    end if;
  end if;

  insert into posts (author_id, parent_post_id, body, reply_control, quoted_post_id)
  values (v_me, p_parent, p_body, p_reply_control, p_quote)
  returning id into v_id;

  if p_parent is not null then
    update posts set reply_count = reply_count + 1 where id = p_parent;
    -- Reply notification (never to self; mutes/blocks/prefs honoured).
    if v_parent_author <> v_me
       and not exists (select 1 from mutes where muter_id = v_parent_author and muted_id = v_me)
       and notif_enabled(v_parent_author, 'reply') then
      insert into notifications (user_id, actor_id, type, post_id)
      values (v_parent_author, v_me, 'reply', v_id);
    end if;
  end if;

  -- Quote notification (never to self; mutes/blocks/prefs honoured).
  if p_quote is not null
     and v_quote_author <> v_me
     and not exists (select 1 from mutes where muter_id = v_quote_author and muted_id = v_me)
     and notif_enabled(v_quote_author, 'quote') then
    insert into notifications (user_id, actor_id, type, post_id)
    values (v_quote_author, v_me, 'quote', v_id);
  end if;

  -- Mentions: @handle tokens resolved against real, unblocked accounts.
  -- P1-5: the '@' must sit at the start of the text or after a
  -- non-word character ("noreply@cat" is an email-shaped string, not a
  -- mention of @cat); the boundary class is Unicode-aware so it agrees
  -- exactly with the client renderer and the hashtag rule. Repeats
  -- dedupe to one row and one notification; mentions never cross a
  -- block. New here (design §12): the mentioned member's own
  -- "Who can mention you" policy decides whether she becomes a
  -- mentioned participant at all, and at most 10 mention notifications
  -- fire per post — past the cap the mentions still resolve and link,
  -- but no further pings land (the anti-pile-on bound).
  for v_handle in
    select distinct lower(m[1])
    from regexp_matches(p_body, '(?:^|[^[:alnum:]_])@([A-Za-z0-9_]{3,30})', 'g') m
  loop
    select user_id, profiles.mention_policy into v_mention, v_mpolicy from profiles
      where handle = v_handle::citext
        and status in ('active', 'restricted')
        and user_id <> v_me;
    if v_mention is not null
       and not blocked_either(v_me, v_mention)
       and (v_mpolicy = 'everyone'
            or (v_mpolicy = 'followed' and exists (
                  select 1 from follows
                  where follower_id = v_mention and followee_id = v_me))) then
      insert into post_mentions (post_id, mentioned_user_id)
      values (v_id, v_mention)
      on conflict do nothing;
      -- Do not double-notify the parent author (she already got
      -- 'reply') or the quoted author (she already got 'quote').
      if (p_parent is null or v_mention <> v_parent_author)
         and (p_quote is null or v_mention <> v_quote_author)
         and v_mention_notifs < 10
         and not exists (select 1 from mutes where muter_id = v_mention and muted_id = v_me)
         and notif_enabled(v_mention, 'mention') then
        insert into notifications (user_id, actor_id, type, post_id)
        values (v_mention, v_me, 'mention', v_id);
        v_mention_notifs := v_mention_notifs + 1;
      end if;
    end if;
    v_mention := null;
    v_mpolicy := null;
  end loop;

  -- Hashtags (design §2): '#' at a word boundary, then letters,
  -- numbers, and underscores with at least one letter; folded to the
  -- canonical form; capped at 64 characters per tag and 30 distinct
  -- tags indexed per post (extra tags still render as text, they just
  -- do not count toward anything — the anti-stuffing backstop).
  for v_tag in
    select distinct internal.fold_tag(left(m[1], 64))
    from regexp_matches(p_body, '(?:^|[^[:alnum:]_])#([[:alnum:]_]+)', 'g') m
    where left(m[1], 64) ~ '[[:alpha:]]'
  loop
    exit when v_tag_count >= 30;
    insert into tags (tag) values (v_tag) on conflict (tag) do nothing;
    select id into v_tag_id from tags where tag = v_tag;
    insert into post_tags (post_id, tag_id) values (v_id, v_tag_id)
    on conflict do nothing;
    v_tag_count := v_tag_count + 1;
  end loop;

  return v_id;
end $$;

-- ------------------------------------------------------------
-- 7. The shared card shape, rebuilt. Every feed read function now
--    returns, per post: the repost count and the viewer's own repost
--    state; the resolved mentions (member id + current handle,
--    filtered to reachable, unblocked accounts) so the client links
--    exactly the tokens the server treated as mentions (design §10);
--    and the quoted post as a small jsonb object (or an unavailable
--    stub when the quoted post is deleted, removed, its author
--    unreachable, or a block stands between viewer and quoted author
--    OR between the quoting author and the quoted author).
--    Return shapes change, so the old functions are dropped and
--    grants restated (the 0014 pattern).
-- ------------------------------------------------------------

-- Per-post resolved mentions for the renderer. Internal (no app-role
-- EXECUTE): called only from inside the DEFINER read functions, with
-- the viewer id passed explicitly.
create or replace function internal.post_mentions_json(p_post bigint, p_viewer uuid)
returns jsonb
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', mp.mentioned_user_id,
           'handle', pr.handle::text)),
         '[]'::jsonb)
  from post_mentions mp
  join profiles pr on pr.user_id = mp.mentioned_user_id
  where mp.post_id = p_post
    and pr.status in ('active', 'restricted')
    and not internal.blocked_pair(p_viewer, mp.mentioned_user_id)
$$;
revoke execute on function internal.post_mentions_json(bigint, uuid) from public, anon, authenticated, service_role;

-- The embedded card of a quote-post. NULL when the post quotes
-- nothing; {"unavailable": true} when the quoted post may not be
-- shown (the quoting member's own words always remain; only the
-- embedded card yields). p_author is the QUOTING post's author: a
-- block between the two authors severs the embedded card for every
-- viewer, the quote analogue of the repost rule in design §17.
create or replace function internal.quoted_json(p_quoted bigint, p_author uuid, p_viewer uuid)
returns jsonb
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select case
    when p_quoted is null then null
    else coalesce((
      select case
        when q.deleted_at is not null
          or q.visibility <> 'visible'
          or qpr.status not in ('active', 'restricted')
          or internal.blocked_pair(p_viewer, q.author_id)
          or internal.blocked_pair(p_author, q.author_id)
        then jsonb_build_object('unavailable', true)
        else jsonb_build_object(
          'unavailable', false,
          'id', q.id,
          'author_id', q.author_id,
          'handle', qpr.handle::text,
          'founding', qpr.founding_member,
          'body', q.body,
          'created_at', q.created_at)
      end
      from posts q
      join profiles qpr on qpr.user_id = q.author_id
      where q.id = p_quoted
    ), jsonb_build_object('unavailable', true))
  end
$$;
revoke execute on function internal.quoted_json(bigint, uuid, uuid) from public, anon, authenticated, service_role;

-- Following feed: root posts from the people you follow (and you),
-- now interleaved with reposts by the people you follow (and you).
-- A post appears ONCE however many followed people reposted it, with
-- the reposters aggregated for the attribution line (design §16); its
-- cursor position is its most recent appearance (sort_at). A repost
-- renders only while the original is visible, its author reachable,
-- no block stands between the viewer and either party, and no block
-- stands between the reposter and the original author (design §17).
drop function if exists feed_following(timestamptz, integer, bigint);
create or replace function feed_following(
  p_before    timestamptz default null,
  p_limit     integer default 20,
  p_before_id bigint default null
) returns table (
  id              bigint,
  author_id       uuid,
  author_handle   text,
  author_founding boolean,
  body            text,
  reply_control   reply_control,
  like_count      integer,
  reply_count     integer,
  reshare_count   integer,
  viewer_liked    boolean,
  viewer_reshared boolean,
  viewer_follows  boolean,
  created_at      timestamptz,
  sort_at         timestamptz,
  reshared_by     jsonb,
  mentions        jsonb,
  quoted          jsonb
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with entries as (
    -- Your own and followed authors' root posts, in their own right.
    select p.id as post_id, p.created_at as sort_at, null::uuid as resharer_id
    from posts p
    where p.parent_post_id is null
      and p.deleted_at is null
      and p.visibility = 'visible'
      and (p.author_id = auth.uid() or exists (
            select 1 from follows f
            where f.follower_id = auth.uid() and f.followee_id = p.author_id))
    union all
    -- Reposts by you and the people you follow.
    select r.post_id, r.created_at, r.user_id
    from reshares r
    where (r.user_id = auth.uid() or exists (
            select 1 from follows f
            where f.follower_id = auth.uid() and f.followee_id = r.user_id))
      and not internal.blocked_pair(auth.uid(), r.user_id)
      and not exists (select 1 from mutes m
                      where m.muter_id = auth.uid() and m.muted_id = r.user_id)
  ),
  eligible as (
    select e.post_id, e.sort_at, e.resharer_id,
           rp.handle::text as resharer_handle
    from entries e
    join posts p on p.id = e.post_id
    join profiles pr on pr.user_id = p.author_id
    left join profiles rp on rp.user_id = e.resharer_id
    where p.deleted_at is null
      and p.visibility = 'visible'
      and pr.status in ('active', 'restricted')
      and not internal.blocked_pair(auth.uid(), p.author_id)
      and not exists (select 1 from mutes m
                      where m.muter_id = auth.uid() and m.muted_id = p.author_id)
      and (e.resharer_id is null
           -- a repost never resurfaces your own post to you, and it
           -- yields entirely when reposter and author are walled off
           or (p.author_id <> auth.uid()
               and rp.status in ('active', 'restricted')
               and not internal.blocked_pair(e.resharer_id, p.author_id)))
  ),
  grouped as (
    select e.post_id,
           max(e.sort_at) as sort_at,
           coalesce(jsonb_agg(e.resharer_handle order by e.sort_at desc)
                      filter (where e.resharer_id is not null),
                    '[]'::jsonb) as reshared_by
    from eligible e
    group by e.post_id
  )
  select p.id, p.author_id, pr.handle::text, pr.founding_member,
         p.body, p.reply_control, p.like_count, p.reply_count, p.reshare_count,
         exists (select 1 from likes l where l.post_id = p.id and l.user_id = auth.uid()),
         exists (select 1 from reshares r where r.post_id = p.id and r.user_id = auth.uid()),
         (p.author_id = auth.uid() or exists (
            select 1 from follows f
            where f.follower_id = auth.uid() and f.followee_id = p.author_id)),
         p.created_at,
         g.sort_at,
         g.reshared_by,
         internal.post_mentions_json(p.id, auth.uid()),
         internal.quoted_json(p.quoted_post_id, p.author_id, auth.uid())
  from grouped g
  join posts p on p.id = g.post_id
  join profiles pr on pr.user_id = p.author_id
  where exists (select 1 from profiles me
                where me.user_id = auth.uid() and me.status in ('active', 'restricted'))
    and (p_before is null
         or (p_before_id is null and g.sort_at < p_before)
         or (p_before_id is not null and (g.sort_at, p.id) < (p_before, p_before_id)))
  order by g.sort_at desc, p.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

-- Profile posts: the Posts tab now interleaves the member's reposts
-- with her own posts by repost time, each marked is_reshare for the
-- attribution line (design §16). The Replies tab is unchanged in
-- meaning. Repost rows apply the full §17 suppression rules.
drop function if exists profile_posts(uuid, boolean, timestamptz, integer, bigint);
create or replace function profile_posts(
  p_user      uuid,
  p_replies   boolean default false,
  p_before    timestamptz default null,
  p_limit     integer default 20,
  p_before_id bigint default null
) returns table (
  id              bigint,
  author_id       uuid,
  author_handle   text,
  author_founding boolean,
  body            text,
  reply_control   reply_control,
  like_count      integer,
  reply_count     integer,
  reshare_count   integer,
  viewer_liked    boolean,
  viewer_reshared boolean,
  created_at      timestamptz,
  sort_at         timestamptz,
  is_reshare      boolean,
  mentions        jsonb,
  quoted          jsonb,
  parent_author_handle text,
  parent_excerpt       text
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with items as (
    select p.id as post_id, p.created_at as sort_at, false as is_reshare
    from posts p
    where p.author_id = p_user
      and ((p_replies and p.parent_post_id is not null)
           or (not p_replies and p.parent_post_id is null))
      and p.deleted_at is null
      and p.visibility = 'visible'
    union all
    select r.post_id, r.created_at, true
    from reshares r
    join posts p on p.id = r.post_id
    join profiles ppr on ppr.user_id = p.author_id
    where r.user_id = p_user
      and not p_replies
      and p.deleted_at is null
      and p.visibility = 'visible'
      and ppr.status in ('active', 'restricted')
      and not internal.blocked_pair(auth.uid(), p.author_id)
      and not internal.blocked_pair(p_user, p.author_id)
  )
  select p.id, p.author_id, pr.handle::text, pr.founding_member,
         p.body, p.reply_control, p.like_count, p.reply_count, p.reshare_count,
         exists (select 1 from likes l where l.post_id = p.id and l.user_id = auth.uid()),
         exists (select 1 from reshares r where r.post_id = p.id and r.user_id = auth.uid()),
         p.created_at,
         i.sort_at,
         i.is_reshare,
         internal.post_mentions_json(p.id, auth.uid()),
         internal.quoted_json(p.quoted_post_id, p.author_id, auth.uid()),
         -- P2-6: parent context requires the parent to be VISIBLE, not
         -- merely undeleted — a moderation-removed parent must never
         -- surface its author or text as context.
         case when p.parent_post_id is null then null
              else coalesce((select ppr.handle::text
                             from posts pp join profiles ppr on ppr.user_id = pp.author_id
                             where pp.id = p.parent_post_id
                               and pp.deleted_at is null
                               and pp.visibility = 'visible'
                               and not blocked_either(auth.uid(), pp.author_id)), '') end,
         case when p.parent_post_id is null then null
              else coalesce((select left(pp.body, 120) from posts pp
                             where pp.id = p.parent_post_id
                               and pp.deleted_at is null
                               and pp.visibility = 'visible'
                               and not blocked_either(auth.uid(), pp.author_id)), '') end
  from items i
  join posts p on p.id = i.post_id
  join profiles pr on pr.user_id = p.author_id
  where exists (select 1 from profiles me
                where me.user_id = auth.uid() and me.status in ('active', 'restricted'))
    and pr.status in ('active', 'restricted')
    and not blocked_either(auth.uid(), p_user)
    and (p_before is null
         or (p_before_id is null and i.sort_at < p_before)
         or (p_before_id is not null and (i.sort_at, p.id) < (p_before, p_before_id)))
  order by i.sort_at desc, p.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

-- Thread view: same tombstone semantics as before, with the new card
-- fields. Tombstoned rows carry zeroed counts, empty mentions, and no
-- quoted card.
drop function if exists get_thread(bigint);
create or replace function get_thread(p_post bigint)
returns table (
  id              bigint,
  parent_post_id  bigint,
  depth           smallint,
  author_id       uuid,
  author_handle   text,
  author_founding boolean,
  body            text,
  reply_control   reply_control,
  like_count      integer,
  reply_count     integer,
  reshare_count   integer,
  viewer_liked    boolean,
  viewer_reshared boolean,
  unavailable     boolean,
  created_at      timestamptz,
  mentions        jsonb,
  quoted          jsonb
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with recursive sub as (
    select p.* from posts p where p.id = p_post
    union all
    select c.* from posts c join sub s on c.parent_post_id = s.id
  ),
  shaped as (
    select s.*,
           pr.handle::text as h,
           pr.founding_member as fm,
           (s.deleted_at is not null
             or s.visibility <> 'visible'
             or pr.status not in ('active', 'restricted')
             or blocked_either(auth.uid(), s.author_id)
             or exists (select 1 from mutes m
                        where m.muter_id = auth.uid() and m.muted_id = s.author_id))
           as hidden
    from sub s
    join profiles pr on pr.user_id = s.author_id
  )
  select sh.id, sh.parent_post_id, sh.depth,
         case when sh.hidden then null else sh.author_id end,
         case when sh.hidden then '' else sh.h end,
         case when sh.hidden then false else sh.fm end,
         case when sh.hidden then '' else sh.body end,
         sh.reply_control,
         case when sh.hidden then 0 else sh.like_count end,
         sh.reply_count,
         case when sh.hidden then 0 else sh.reshare_count end,
         (not sh.hidden) and exists (select 1 from likes l
                                     where l.post_id = sh.id and l.user_id = auth.uid()),
         (not sh.hidden) and exists (select 1 from reshares r
                                     where r.post_id = sh.id and r.user_id = auth.uid()),
         sh.hidden,
         sh.created_at,
         case when sh.hidden then '[]'::jsonb
              else internal.post_mentions_json(sh.id, auth.uid()) end,
         case when sh.hidden then null
              else internal.quoted_json(sh.quoted_post_id, sh.author_id, auth.uid()) end
  from shaped sh
  where exists (select 1 from profiles me
                where me.user_id = auth.uid() and me.status in ('active', 'restricted'))
    -- P2-2: a blocked person gets an empty result for the whole thread,
    -- never a page-rendering tombstone that confirms the post exists.
    and exists (select 1 from posts rp
                where rp.id = p_post
                  and not blocked_either(auth.uid(), rp.author_id))
  order by sh.depth, sh.created_at
  limit 500
$$;

-- Discover: same hard filters and positive-signal-only score as the
-- 0021 build, with the two repost signals design §18 adds — the
-- reshare count as a gently log-damped aggregate endorsement
-- (exactly like the like count) and "authors whose posts you have
-- reposted" as a personal affinity signal (exactly like your likes).
-- Reposts remain only ever a lift, never a penalty.
drop function if exists feed_discover(integer, integer);
create or replace function feed_discover(
  p_limit  integer default 20,
  p_offset integer default 0
) returns table (
  id              bigint,
  author_id       uuid,
  author_handle   text,
  author_founding boolean,
  body            text,
  reply_control   reply_control,
  like_count      integer,
  reply_count     integer,
  reshare_count   integer,
  viewer_liked    boolean,
  viewer_reshared boolean,
  viewer_follows  boolean,
  created_at      timestamptz,
  mentions        jsonb,
  quoted          jsonb
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with candidates as (
    select p.id, p.author_id, pr.handle::text as author_handle,
           pr.founding_member, p.body, p.reply_control,
           p.like_count, p.reply_count, p.reshare_count,
           p.quoted_post_id, p.created_at,
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
              -- …or you have reposted her posts (design §18: the
              -- repost twin of the like-affinity signal above).
              + 0.30 * least((select count(*) from reshares r
                              join posts rp on rp.id = r.post_id
                              where r.user_id = auth.uid()
                                and rp.author_id = c.author_id), 5)
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
              -- Aggregate repost endorsement, same damping (§18).
              + 0.20 * ln(1 + greatest(c.reshare_count, 0))
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
         s.body, s.reply_control, s.like_count, s.reply_count, s.reshare_count,
         exists (select 1 from likes l
                 where l.post_id = s.id and l.user_id = auth.uid()),
         exists (select 1 from reshares r
                 where r.post_id = s.id and r.user_id = auth.uid()),
         exists (select 1 from follows f
                 where f.follower_id = auth.uid() and f.followee_id = s.author_id),
         s.created_at,
         internal.post_mentions_json(s.id, auth.uid()),
         internal.quoted_json(s.quoted_post_id, s.author_id, auth.uid())
  from scored s
  order by s.score desc, s.created_at desc, s.id desc
  offset least(greatest(coalesce(p_offset, 0), 0), 400)
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

-- ------------------------------------------------------------
-- 8. Tag pages and tag search (design §4, §5).
-- ------------------------------------------------------------

-- The tag-page header: canonical tag, status, and its honest post
-- count (visible posts by reachable authors; blocks are per-viewer
-- and do not bend a global count). A tag nobody has used returns
-- status 'active' with 0 posts, which the page renders as the warm
-- empty state.
create or replace function get_tag(p_tag text)
returns table (tag text, status tag_status, post_count bigint)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with folded as (select internal.fold_tag(p_tag) as tag)
  select f.tag,
         coalesce(t.status, 'active'::tag_status),
         coalesce((select count(*)
                   from post_tags pt
                   join posts p on p.id = pt.post_id
                   join profiles pr on pr.user_id = p.author_id
                   where pt.tag_id = t.id
                     and p.deleted_at is null
                     and p.visibility = 'visible'
                     and pr.status in ('active', 'restricted')), 0)
  from folded f
  left join tags t on t.tag = f.tag
  where exists (select 1 from profiles me
                where me.user_id = auth.uid() and me.status in ('active', 'restricted'))
    and f.tag <> ''
$$;

-- The tag page stream: newest first, every post carrying the tag
-- (roots and replies alike), with the same block, mute, and
-- visibility walls as every feed. A blocked tag returns nothing (the
-- page shows the neutral unavailable state from get_tag's status).
create or replace function feed_hashtag(
  p_tag       text,
  p_before    timestamptz default null,
  p_limit     integer default 20,
  p_before_id bigint default null
) returns table (
  id              bigint,
  author_id       uuid,
  author_handle   text,
  author_founding boolean,
  body            text,
  reply_control   reply_control,
  like_count      integer,
  reply_count     integer,
  reshare_count   integer,
  viewer_liked    boolean,
  viewer_reshared boolean,
  viewer_follows  boolean,
  created_at      timestamptz,
  mentions        jsonb,
  quoted          jsonb
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select p.id, p.author_id, pr.handle::text, pr.founding_member,
         p.body, p.reply_control, p.like_count, p.reply_count, p.reshare_count,
         exists (select 1 from likes l where l.post_id = p.id and l.user_id = auth.uid()),
         exists (select 1 from reshares r where r.post_id = p.id and r.user_id = auth.uid()),
         (p.author_id = auth.uid() or exists (
            select 1 from follows f
            where f.follower_id = auth.uid() and f.followee_id = p.author_id)),
         p.created_at,
         internal.post_mentions_json(p.id, auth.uid()),
         internal.quoted_json(p.quoted_post_id, p.author_id, auth.uid())
  from tags t
  join post_tags pt on pt.tag_id = t.id
  join posts p on p.id = pt.post_id
  join profiles pr on pr.user_id = p.author_id
  where exists (select 1 from profiles me
                where me.user_id = auth.uid() and me.status in ('active', 'restricted'))
    and t.tag = internal.fold_tag(p_tag)
    and t.status <> 'blocked'
    and p.deleted_at is null
    and p.visibility = 'visible'
    and pr.status in ('active', 'restricted')
    and not blocked_either(auth.uid(), p.author_id)
    and not exists (select 1 from mutes m
                    where m.muter_id = auth.uid() and m.muted_id = p.author_id)
    and (p_before is null
         or (p_before_id is null and p.created_at < p_before)
         or (p_before_id is not null and (p.created_at, p.id) < (p_before, p_before_id)))
  order by p.created_at desc, p.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

-- Tag search (design §5): a '#'-prefixed query prefix-matches the
-- canonical tag index — a find-the-tag search, never a search inside
-- post bodies, and entirely separate from people search, which stays
-- @handle-only. Suppressed tags (either tier) never appear as
-- suggestions. Also serves the composer's '#' autocomplete.
create or replace function search_tags(
  p_query text,
  p_limit integer default 20
) returns table (tag text, post_count bigint)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with q as (
    select term,
           replace(replace(replace(term, '\', '\\'), '%', '\%'), '_', '\_') as pat
    from (select internal.fold_tag(p_query) as term) s
  )
  select t.tag,
         (select count(*)
          from post_tags pt
          join posts p on p.id = pt.post_id
          join profiles pr on pr.user_id = p.author_id
          where pt.tag_id = t.id
            and p.deleted_at is null
            and p.visibility = 'visible'
            and pr.status in ('active', 'restricted'))
  from tags t, q
  where exists (select 1 from profiles me
                where me.user_id = auth.uid() and me.status in ('active', 'restricted'))
    and q.term <> ''
    and t.tag like q.pat || '%' escape '\'
    and t.status = 'active'
  order by (t.tag = q.term) desc, t.tag
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

-- ------------------------------------------------------------
-- 9. Trending (design §6): the 48-hour rolling window, scored by
--    DISTINCT PEOPLE (never raw volume), recency-weighted, written to
--    the snapshot and read from it. A repost of a tagged post counts
--    the reposter as a participant in that tag, once, like any other
--    person. There is deliberately NO minimum-participation floor:
--    a tag one person used trends with its honest count of 1.
-- ------------------------------------------------------------
create or replace function compute_trending_tags() returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  delete from trending_tags;
  insert into trending_tags (tag_id, score, distinct_people, window_start, computed_at)
  select part.tag_id,
         -- Each distinct person contributes a recency weight based on
         -- her latest use: 1.0 now, ~0.37 a day ago, ~0.14 at the
         -- window's edge. Summing per-person weights keeps the unit
         -- "people", freshly weighted — one account posting fifty
         -- times still contributes exactly one person.
         sum(exp(-extract(epoch from (now() - part.latest)) / 86400.0)),
         count(*)::integer,
         now() - interval '48 hours',
         now()
  from (
    select uses.tag_id, uses.person_id, max(uses.used_at) as latest
    from (
      select pt.tag_id, p.author_id as person_id, p.created_at as used_at
      from post_tags pt
      join posts p on p.id = pt.post_id
      join profiles pr on pr.user_id = p.author_id
      where p.created_at > now() - interval '48 hours'
        and p.deleted_at is null
        and p.visibility = 'visible'
        and pr.status in ('active', 'restricted')
      union all
      select pt.tag_id, r.user_id, r.created_at
      from post_tags pt
      join posts p on p.id = pt.post_id
      join reshares r on r.post_id = pt.post_id
      join profiles rr on rr.user_id = r.user_id
      where r.created_at > now() - interval '48 hours'
        and p.deleted_at is null
        and p.visibility = 'visible'
        and rr.status in ('active', 'restricted')
    ) uses
    group by uses.tag_id, uses.person_id
  ) part
  join tags t on t.id = part.tag_id
  where t.status = 'active'
  group by part.tag_id;
end $$;
revoke execute on function compute_trending_tags() from public, anon, authenticated, service_role;

-- The member-facing read. Volatile on purpose: when the snapshot is
-- older than 15 minutes it refreshes it first (advisory-locked so
-- concurrent requests never double-compute), then reads it. pg_cron,
-- when present, keeps the snapshot warm on the same cadence; this
-- read-through refresh means trending is never stale or empty on an
-- environment where the cron job is not configured.
create or replace function get_trending_tags(p_limit integer default 5)
returns table (tag text, distinct_people integer)
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
begin
  if not exists (select 1 from profiles me
                 where me.user_id = auth.uid() and me.status in ('active', 'restricted')) then
    return;
  end if;
  if coalesce((select max(computed_at) from trending_tags),
              '-infinity'::timestamptz) < now() - interval '15 minutes' then
    if pg_try_advisory_xact_lock(hashtext('hersciety_trending_refresh')) then
      perform compute_trending_tags();
    end if;
  end if;
  return query
    select t.tag, tt.distinct_people
    from trending_tags tt
    join tags t on t.id = tt.tag_id
    where t.status = 'active'
    order by tt.score desc, tt.distinct_people desc, t.tag
    limit least(greatest(coalesce(p_limit, 5), 1), 20);
end $$;

-- Keep the snapshot warm where pg_cron exists (the 0010 pattern; a
-- stack without the extension relies on the read-through refresh).
do $do$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'hersciety-trending-tags',
      '*/15 * * * *',
      $cron$ select public.compute_trending_tags(); $cron$
    );
  end if;
end
$do$;

-- ------------------------------------------------------------
-- 10. Tag moderation (design §7): members report conduct, not tags;
--     staff suppress the tag itself in two proportional, reversible,
--     audited tiers. De-trend (moderator and above) removes a tag
--     from trending and search suggestions while its posts stay
--     reachable; block (admin and above) also replaces the tag page
--     with a neutral unavailable state. Neither touches any post or
--     any author — those stay on the ordinary per-post ladder.
-- ------------------------------------------------------------
create or replace function mod_detrend_tag(p_tag text, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_tag  text := internal.fold_tag(p_tag);
  v_prev tag_status;
begin
  if mod_actor_tier() < 1 then
    raise exception 'You do not have permission to take this action.';
  end if;
  select status into v_prev from tags where tag = v_tag;
  if v_prev is null then
    raise exception 'That topic is unavailable.';
  end if;
  if v_prev = 'blocked' then
    raise exception 'That topic is blocked; reinstating it is an admin action.';
  end if;
  update tags set status = 'detrended' where tag = v_tag;
  delete from trending_tags using tags t
    where trending_tags.tag_id = t.id and t.tag = v_tag;
  perform append_audit('tag.detrend', 'tag', v_tag,
                       jsonb_build_object('note', p_note),
                       jsonb_build_object('status', v_prev),
                       jsonb_build_object('status', 'detrended'));
end $$;

create or replace function mod_block_tag(p_tag text, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_tag  text := internal.fold_tag(p_tag);
  v_prev tag_status;
begin
  if mod_actor_tier() < 2 then
    raise exception 'You do not have permission to take this action.';
  end if;
  select status into v_prev from tags where tag = v_tag;
  if v_prev is null then
    raise exception 'That topic is unavailable.';
  end if;
  update tags set status = 'blocked' where tag = v_tag;
  delete from trending_tags using tags t
    where trending_tags.tag_id = t.id and t.tag = v_tag;
  perform append_audit('tag.block', 'tag', v_tag,
                       jsonb_build_object('note', p_note),
                       jsonb_build_object('status', v_prev),
                       jsonb_build_object('status', 'blocked'));
end $$;

-- Reinstating is as reversible as the design promises: a moderator
-- can lift a de-trend; lifting a block requires the admin breadth
-- that imposed it.
create or replace function mod_reinstate_tag(p_tag text, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_tag  text := internal.fold_tag(p_tag);
  v_prev tag_status;
begin
  select status into v_prev from tags where tag = v_tag;
  if v_prev is null then
    raise exception 'That topic is unavailable.';
  end if;
  if v_prev = 'active' then
    return;
  end if;
  if (v_prev = 'detrended' and mod_actor_tier() < 1)
     or (v_prev = 'blocked' and mod_actor_tier() < 2) then
    raise exception 'You do not have permission to take this action.';
  end if;
  update tags set status = 'active' where tag = v_tag;
  perform append_audit('tag.reinstate', 'tag', v_tag,
                       jsonb_build_object('note', p_note),
                       jsonb_build_object('status', v_prev),
                       jsonb_build_object('status', 'active'));
end $$;

-- The console's tag view (staff, reviewer and above): status, size,
-- 48-hour participation, and the brigade signal the design asks for —
-- the share of the window's participants whose accounts are under
-- seven days old, surfaced as calm information for a human to judge,
-- never acted on automatically.
create or replace function mod_tag_lookup(
  p_query text default null,
  p_limit integer default 20
) returns table (
  tag               text,
  status            tag_status,
  post_count        bigint,
  people_48h        integer,
  new_account_share numeric
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with q as (
    select case when coalesce(btrim(p_query), '') = '' then null
                else replace(replace(replace(internal.fold_tag(p_query),
                     '\', '\\'), '%', '\%'), '_', '\_') end as pat
  ),
  window_people as (
    select pt.tag_id, p.author_id as person_id
    from post_tags pt
    join posts p on p.id = pt.post_id
    where p.created_at > now() - interval '48 hours'
      and p.deleted_at is null and p.visibility = 'visible'
    union
    select pt.tag_id, r.user_id
    from post_tags pt
    join posts p on p.id = pt.post_id
    join reshares r on r.post_id = pt.post_id
    where r.created_at > now() - interval '48 hours'
      and p.deleted_at is null and p.visibility = 'visible'
  )
  select t.tag, t.status,
         (select count(*) from post_tags pt
          join posts p on p.id = pt.post_id
          where pt.tag_id = t.id
            and p.deleted_at is null and p.visibility = 'visible'),
         (select count(distinct wp.person_id)::integer
          from window_people wp where wp.tag_id = t.id),
         coalesce((select round(avg(case when pr.created_at > now() - interval '7 days'
                                          then 1 else 0 end), 2)
                   from (select distinct wp.person_id
                         from window_people wp where wp.tag_id = t.id) people
                   join profiles pr on pr.user_id = people.person_id), 0)
  from tags t, q
  where mod_actor_tier() >= 0
    and (q.pat is null or t.tag like q.pat || '%' escape '\')
  order by (t.status <> 'active') desc, t.tag
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

-- ------------------------------------------------------------
-- 11. EXECUTE lockdown. Member functions to authenticated only; the
--     staff functions re-check tier inside (the mod_* pattern);
--     internal helpers and the compute job get no app-role grants.
-- ------------------------------------------------------------
revoke execute on function create_post(text, bigint, reply_control, bigint)            from public, anon, service_role;
revoke execute on function feed_following(timestamptz, integer, bigint)                from public, anon, service_role;
revoke execute on function profile_posts(uuid, boolean, timestamptz, integer, bigint)  from public, anon, service_role;
revoke execute on function get_thread(bigint)                                          from public, anon, service_role;
revoke execute on function feed_discover(integer, integer)                             from public, anon, service_role;
revoke execute on function get_tag(text)                                               from public, anon, service_role;
revoke execute on function feed_hashtag(text, timestamptz, integer, bigint)            from public, anon, service_role;
revoke execute on function search_tags(text, integer)                                  from public, anon, service_role;
revoke execute on function get_trending_tags(integer)                                  from public, anon, service_role;
revoke execute on function mod_detrend_tag(text, text)                                 from public, anon, service_role;
revoke execute on function mod_block_tag(text, text)                                   from public, anon, service_role;
revoke execute on function mod_reinstate_tag(text, text)                               from public, anon, service_role;
revoke execute on function mod_tag_lookup(text, integer)                               from public, anon, service_role;

grant execute on function create_post(text, bigint, reply_control, bigint)             to authenticated;
grant execute on function feed_following(timestamptz, integer, bigint)                 to authenticated;
grant execute on function profile_posts(uuid, boolean, timestamptz, integer, bigint)   to authenticated;
grant execute on function get_thread(bigint)                                           to authenticated;
grant execute on function feed_discover(integer, integer)                              to authenticated;
grant execute on function get_tag(text)                                                to authenticated;
grant execute on function feed_hashtag(text, timestamptz, integer, bigint)             to authenticated;
grant execute on function search_tags(text, integer)                                   to authenticated;
grant execute on function get_trending_tags(integer)                                   to authenticated;
grant execute on function mod_detrend_tag(text, text)                                  to authenticated;
grant execute on function mod_block_tag(text, text)                                    to authenticated;
grant execute on function mod_reinstate_tag(text, text)                                to authenticated;
grant execute on function mod_tag_lookup(text, integer)                                to authenticated;
