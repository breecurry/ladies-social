-- ------------------------------------------------------------
-- 0032 — Multi-part threads ("Add to thread").
--
-- Implements the data layer of docs/design-multi-part-threads.md:
-- a member writes past 500 characters by publishing a connected run
-- of her own posts (a "chain"), each part its own post of up to 500
-- characters, each a reply to the one before it. A chain is NOT a new
-- record: it is the maximal run of consecutive same-author posts down
-- a reply spine starting at a top-level post (design section 10),
-- recognised at read time. Continuation tie-break: the earliest
-- same-author direct reply, ordered (created_at, id) — the id breaks
-- the tie because every part of an atomically published chain shares
-- one transaction timestamp (now() is transaction-fixed).
--
-- What this migration adds:
--   1. internal.chain_head_of / internal.chain_info — the single
--      chain-detection source every surface calls (design section 21).
--   2. chain_head(p_post) — public resolver: a mid-chain entry point
--      maps to its chain head; anything else maps to itself. Also the
--      client's feature probe for graceful pre-migration degradation.
--   3. create_thread(p_bodies, ...) — the atomic multi-part publish
--      (design section 14): every part inserted through create_post
--      (so every per-part check is reused verbatim) in ONE
--      transaction, all-or-nothing, with a client-supplied
--      idempotency key so a retry after a lost response cannot
--      double-post. Keys are honoured for 24 hours.
--   4. get_thread gains spine_seq (the structural chain position,
--      hidden parts included) so the thread view can render the spine
--      flat with live "Part k of N" labels and honest removed-part
--      markers. Same arguments, so no PostgREST ambiguity.
--   5. feed_following / feed_discover / feed_hashtag / profile_posts
--      gain chain_index + chain_count (null unless the post belongs
--      to a chain of 2+ readable parts) for the "Show this thread,
--      N parts" affordance and the "Part k of N" cue on reposted
--      mid-chain parts. profile_posts additionally SUPPRESSES chain
--      continuation parts from the Replies tab (design section 13):
--      they are the thread, not replies, and must never read as
--      "replying to yourself". Genuine replies to other members and
--      non-spine self-replies are untouched.
--
-- Every function recreated here keeps its argument signature exactly;
-- only return shapes change, so each is dropped by its one exact
-- signature first and its grants are re-applied in full below. No
-- second signature of anything is left behind.
--
-- The composer caps a chain at 25 parts. That number derives from the
-- create_post depth cap of 30 (a reply to a post at depth >= 30 is
-- refused): 25 parts put the last part at depth 24 and leave five
-- depth steps for other people's replies. Do not raise it.
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- 1. Chain detection (internal; EXECUTE for no app role).
-- ------------------------------------------------------------

-- The chain head of a post: walking up from p_post, every step must
-- stay with one author AND the lower post must be its parent's
-- earliest same-author direct reply (the spine tie-break, design
-- section 10.1). Returns the top-level ancestor when the whole path
-- qualifies — i.e. when p_post is a chain part (a head is trivially a
-- chain part of itself) — and NULL otherwise. Soft-deleted rows stay
-- on the spine structurally (design section 16: deleting part 3 of 5
-- must not orphan parts 4 and 5); readability is counted separately.
create or replace function internal.chain_head_of(p_post bigint)
returns bigint
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with recursive up as (
    select p.id, p.parent_post_id, p.author_id
    from posts p
    where p.id = p_post
    union all
    select pp.id, pp.parent_post_id, pp.author_id
    from posts pp
    join up u on pp.id = u.parent_post_id
    where pp.author_id = u.author_id
      and u.id = (select c.id from posts c
                  where c.parent_post_id = pp.id
                    and c.author_id = pp.author_id
                  order by c.created_at, c.id
                  limit 1)
  )
  select u.id from up u where u.parent_post_id is null
$$;
revoke execute on function internal.chain_head_of(bigint)
  from public, anon, authenticated, service_role;

-- Everything a surface needs to label one post's chain membership:
-- the head, the post's live position among READABLE parts (deleted or
-- moderation-removed parts keep their place on the spine but drop out
-- of the numbering, design section 10.2), the live readable count,
-- and whether the post is a continuation (part 2+ — the Replies-tab
-- suppression test). Exactly one row, nulls when p_post is not on a
-- chain spine.
create or replace function internal.chain_info(p_post bigint)
returns table (
  head_id         bigint,
  part_index      integer,
  part_count      integer,
  is_continuation boolean
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with recursive head as (
    select internal.chain_head_of(p_post) as id
  ),
  down as (
    select p.id, 1 as seq, p.author_id,
           (p.deleted_at is null and p.visibility = 'visible') as readable
    from posts p
    join head h on p.id = h.id
    union all
    select c.id, d.seq + 1, d.author_id,
           (c.deleted_at is null and c.visibility = 'visible')
    from down d
    join posts c on c.parent_post_id = d.id
    where c.author_id = d.author_id
      and c.id = (select c2.id from posts c2
                  where c2.parent_post_id = c.parent_post_id
                    and c2.author_id = d.author_id
                  order by c2.created_at, c2.id
                  limit 1)
  ),
  numbered as (
    select d.id, d.readable,
           sum(case when d.readable then 1 else 0 end)
             over (order by d.seq) as live_idx
    from down d
  )
  select h.id,
         (select n.live_idx::integer from numbered n
          where n.id = p_post and n.readable),
         (select count(*)::integer from numbered n where n.readable),
         (h.id is not null and h.id <> p_post)
  from head h
$$;
revoke execute on function internal.chain_info(bigint)
  from public, anon, authenticated, service_role;

-- ------------------------------------------------------------
-- 2. The public resolver (and the client's feature probe).
-- ------------------------------------------------------------

-- Opening any part of a chain must land the reader at the top of the
-- thought (design section 11.1): the thread page calls this first and
-- then get_thread on the result. For a post that is not a chain part
-- it returns the post id unchanged; for a missing post it returns
-- NULL; for a viewer with a block in either direction it returns NULL
-- (get_thread would return nothing anyway — this never says more than
-- the thread itself would).
drop function if exists chain_head(bigint);
create or replace function chain_head(p_post bigint)
returns bigint
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select case
    when not exists (select 1 from profiles me
                     where me.user_id = auth.uid()
                       and me.status in ('active', 'restricted'))
      then null
    when not exists (select 1 from posts p where p.id = p_post)
      then null
    when exists (select 1 from posts p
                 where p.id = p_post
                   and blocked_either(auth.uid(), p.author_id))
      then null
    else coalesce(internal.chain_head_of(p_post), p_post)
  end
$$;

-- ------------------------------------------------------------
-- 3. Atomic multi-part publish.
-- ------------------------------------------------------------

-- One row per publish attempt a client asked to make retry-safe.
-- Written only inside create_thread (same transaction as the posts,
-- so a failed publish rolls its key back too and a retry re-runs in
-- full); rows older than 24 hours are swept opportunistically on the
-- next create_thread call. No app role touches this table directly.
create table if not exists internal.thread_idempotency (
  user_id      uuid        not null,
  key          uuid        not null,
  head_post_id bigint,
  created_at   timestamptz not null default now(),
  primary key (user_id, key)
);
alter table internal.thread_idempotency enable row level security;
revoke all on internal.thread_idempotency
  from public, anon, authenticated, service_role;

-- The atomic publish (design section 14): all parts in one
-- transaction, each inserted through create_post so EVERY existing
-- per-part check — author-active, the 500-character cap, the
-- empty-body refusal, mention parsing and notification caps, hashtag
-- indexing, reply controls, and the depth cap — applies to every part
-- with zero duplicated logic. Any error anywhere rolls the whole
-- chain back: a member ends with N parts live or with zero.
--
-- Idempotency: the client sends one uuid per publish attempt and
-- keeps it for retries of that same attempt. The key row is inserted
-- FIRST (on conflict do nothing), which serialises concurrent
-- duplicates on the primary key: the loser waits for the winner's
-- transaction, then reads the committed head and returns it instead
-- of posting a second copy. A key row with a null head cannot outlive
-- its transaction (the head is set before commit; failure rolls the
-- row back), so the defensive raise below should never fire.
drop function if exists create_thread(text[], reply_control, bigint, uuid);
create or replace function create_thread(
  p_bodies        text[],
  p_reply_control reply_control default 'everyone',
  p_quote         bigint default null,
  p_key           uuid default null
) returns bigint
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me       uuid := auth.uid();
  v_body     text;
  v_prev     bigint := null;
  v_head     bigint := null;
  v_id       bigint;
  v_existing bigint;
begin
  if v_me is null then
    raise exception 'Not signed in.';
  end if;
  if p_bodies is null or coalesce(array_length(p_bodies, 1), 0) = 0 then
    raise exception 'Post cannot be empty.';
  end if;
  -- 25 parts, derived from the depth cap of 30: the last part lands
  -- at depth 24, leaving five levels for other people's replies.
  if array_length(p_bodies, 1) > 25 then
    raise exception 'A thread is limited to 25 parts.';
  end if;

  if p_key is not null then
    -- Keys are honoured for 24 hours; sweep the stale ones here so no
    -- scheduled job is needed.
    delete from internal.thread_idempotency
      where created_at < now() - interval '24 hours';

    insert into internal.thread_idempotency (user_id, key)
    values (v_me, p_key)
    on conflict (user_id, key) do nothing;
    if not found then
      select t.head_post_id into v_existing
        from internal.thread_idempotency t
        where t.user_id = v_me and t.key = p_key;
      if v_existing is not null then
        return v_existing;
      end if;
      raise exception 'Could not post your thread. Nothing was posted. Try again.';
    end if;
  end if;

  -- Part 1 is a top-level post (and carries the quote when the
  -- composer opened in quote mode); every later part replies to the
  -- part before it. The chosen reply audience applies to every part
  -- (design section 8.2).
  foreach v_body in array p_bodies loop
    v_id := create_post(
      v_body,
      v_prev,
      p_reply_control,
      case when v_prev is null then p_quote else null end
    );
    if v_head is null then
      v_head := v_id;
    end if;
    v_prev := v_id;
  end loop;

  if p_key is not null then
    update internal.thread_idempotency
       set head_post_id = v_head
     where user_id = v_me and key = p_key;
  end if;

  return v_head;
end $$;

-- ------------------------------------------------------------
-- 4. get_thread gains spine_seq. Same arguments; return shape grows,
--    so the one existing signature is dropped and recreated.
-- ------------------------------------------------------------

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
  quoted          jsonb,
  -- The post's structural position on the author's chain spine
  -- (1-based, hidden parts included so the client can place an honest
  -- removed-part marker), or null for everything off the spine.
  -- Computed only when p_post is a top-level post — a chain starts at
  -- a top-level post by definition (design section 10), and mid-chain
  -- entries resolve to the head through chain_head() first.
  spine_seq       integer
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with recursive sub as (
    select p.* from posts p where p.id = p_post
    union all
    select c.* from posts c join sub s on c.parent_post_id = s.id
  ),
  spine as (
    select p.id, 1 as seq, p.author_id
    from posts p
    where p.id = p_post and p.parent_post_id is null
    union all
    select c.id, s.seq + 1, s.author_id
    from spine s
    join posts c on c.parent_post_id = s.id
    where c.author_id = s.author_id
      and c.id = (select c2.id from posts c2
                  where c2.parent_post_id = c.parent_post_id
                    and c2.author_id = s.author_id
                  order by c2.created_at, c2.id
                  limit 1)
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
              else internal.quoted_json(sh.quoted_post_id, sh.author_id, auth.uid()) end,
         sp.seq::integer
  from shaped sh
  left join spine sp on sp.id = sh.id
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

-- ------------------------------------------------------------
-- 5. feed_following gains chain_index + chain_count. Otherwise the
--    0025/0026 body, verbatim.
-- ------------------------------------------------------------

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
  quoted          jsonb,
  -- "Part k of N" for a post on a chain of 2+ readable parts (a chain
  -- head reads 1 of N; a reposted mid-chain part reads its own k).
  -- Null for an ordinary post, so pre-chain clients and rows degrade
  -- to exactly the old card.
  chain_index     integer,
  chain_count     integer
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
         internal.quoted_json(p.quoted_post_id, p.author_id, auth.uid()),
         case when ci.part_count >= 2 then ci.part_index end,
         case when ci.part_count >= 2 then ci.part_count end
  from grouped g
  join posts p on p.id = g.post_id
  join profiles pr on pr.user_id = p.author_id
  left join lateral internal.chain_info(p.id) ci on true
  where exists (select 1 from profiles me
                where me.user_id = auth.uid() and me.status in ('active', 'restricted'))
    and (p_before is null
         or (p_before_id is null and g.sort_at < p_before)
         or (p_before_id is not null and (g.sort_at, p.id) < (p_before, p_before_id)))
  order by g.sort_at desc, p.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

-- ------------------------------------------------------------
-- 6. profile_posts: chain_index + chain_count, and the Replies tab
--    suppression of chain continuations (design section 13). The
--    Posts tab and the Reposts tab are otherwise the 0026 body,
--    verbatim.
-- ------------------------------------------------------------

drop function if exists profile_posts(uuid, boolean, boolean, timestamptz, integer, bigint);
create or replace function profile_posts(
  p_user      uuid,
  p_replies   boolean default false,
  p_reposts   boolean default false,
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
  parent_excerpt       text,
  chain_index     integer,
  chain_count     integer
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with items as (
    select p.id as post_id, p.created_at as sort_at, false as is_reshare
    from posts p
    where p.author_id = p_user
      and not p_reposts
      and ((p_replies and p.parent_post_id is not null)
           or (not p_replies and p.parent_post_id is null))
      and p.deleted_at is null
      and p.visibility = 'visible'
      -- Design section 13: a chain continuation is the thread, not a
      -- reply — it never appears on the Replies tab as a
      -- "replying to yourself" row. Genuine replies to other members
      -- (and non-spine self-replies) pass untouched.
      and (not p_replies
           or not exists (select 1 from internal.chain_info(p.id) ci
                          where ci.is_continuation))
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
                               and not blocked_either(auth.uid(), pp.author_id)), '') end,
         case when ci.part_count >= 2 then ci.part_index end,
         case when ci.part_count >= 2 then ci.part_count end
  from items i
  join posts p on p.id = i.post_id
  join profiles pr on pr.user_id = p.author_id
  left join lateral internal.chain_info(p.id) ci on true
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

-- ------------------------------------------------------------
-- 7. feed_discover: chain_index + chain_count (Discover serves only
--    top-level posts, so an index is always 1 — the columns exist so
--    every feed row shape carries the same chain fields). Otherwise
--    the 0025 body, verbatim. A chain's length is NOT a ranking
--    signal (P2B section 11); the score is untouched.
-- ------------------------------------------------------------

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
  quoted          jsonb,
  chain_index     integer,
  chain_count     integer
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
         internal.quoted_json(s.quoted_post_id, s.author_id, auth.uid()),
         case when ci.part_count >= 2 then ci.part_index end,
         case when ci.part_count >= 2 then ci.part_count end
  from scored s
  left join lateral internal.chain_info(s.id) ci on true
  order by s.score desc, s.created_at desc, s.id desc
  offset least(greatest(coalesce(p_offset, 0), 0), 400)
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

-- ------------------------------------------------------------
-- 8. feed_hashtag: chain_index + chain_count. The tag stream carries
--    roots AND replies, so a chain part that mentions a tag surfaces
--    here out of context — the cue is how the reader learns there is
--    a whole thread. Otherwise the 0025 body, verbatim.
-- ------------------------------------------------------------

drop function if exists feed_hashtag(text, timestamptz, integer, bigint);
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
  quoted          jsonb,
  chain_index     integer,
  chain_count     integer
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
         internal.quoted_json(p.quoted_post_id, p.author_id, auth.uid()),
         case when ci.part_count >= 2 then ci.part_index end,
         case when ci.part_count >= 2 then ci.part_count end
  from tags t
  join post_tags pt on pt.tag_id = t.id
  join posts p on p.id = pt.post_id
  join profiles pr on pr.user_id = p.author_id
  left join lateral internal.chain_info(p.id) ci on true
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

-- ------------------------------------------------------------
-- 9. EXECUTE lockdown (the 0025 pattern), re-applied in full for
--    every function this migration dropped or created.
-- ------------------------------------------------------------

revoke execute on function chain_head(bigint)                                          from public, anon, service_role;
revoke execute on function create_thread(text[], reply_control, bigint, uuid)          from public, anon, service_role;
revoke execute on function get_thread(bigint)                                          from public, anon, service_role;
revoke execute on function feed_following(timestamptz, integer, bigint)                from public, anon, service_role;
revoke execute on function profile_posts(uuid, boolean, boolean, timestamptz, integer, bigint) from public, anon, service_role;
revoke execute on function feed_discover(integer, integer)                             from public, anon, service_role;
revoke execute on function feed_hashtag(text, timestamptz, integer, bigint)            from public, anon, service_role;

grant execute on function chain_head(bigint)                                           to authenticated;
grant execute on function create_thread(text[], reply_control, bigint, uuid)           to authenticated;
grant execute on function get_thread(bigint)                                           to authenticated;
grant execute on function feed_following(timestamptz, integer, bigint)                 to authenticated;
grant execute on function profile_posts(uuid, boolean, boolean, timestamptz, integer, bigint)  to authenticated;
grant execute on function feed_discover(integer, integer)                              to authenticated;
grant execute on function feed_hashtag(text, timestamptz, integer, bigint)             to authenticated;
