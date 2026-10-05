-- ------------------------------------------------------------
-- 0026 — The profile Reposts tab, and the hashtag cap at 40.
--
-- 1. profile_posts gains p_reposts (default false, so every existing
--    call is unchanged): when true, the list is ONLY the member's
--    reposts, newest repost first. The Posts tab keeps interleaving
--    reposts exactly as before. Every §17 visibility rule — blocks in
--    both directions, suspended authors, deleted or removed originals,
--    the viewer's own standing — is the same code path as before; the
--    new flag only switches off the own-posts branch.
--
-- 2. The hashtag cap drops from 64 to 40 characters (Owner decision,
--    2026-10). A #token longer than 40 is not a hashtag: create_post
--    does not index it (no truncation either — the old behavior
--    indexed the first 64 characters) and the client renders it as
--    muted, inert text, the same treatment as an unresolved mention.
--    The client tokenizer in src/lib/text.ts mirrors this rule
--    character-for-character. Existing over-40 rows are removed
--    defensively before the tighter constraint lands (the cascade
--    cleans post_tags and trending_tags); at the time of writing the
--    tags table is effectively empty, so this is belt and braces.
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- 1. The Reposts tab read function.
-- ------------------------------------------------------------
drop function if exists profile_posts(uuid, boolean, timestamptz, integer, bigint);
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
  parent_excerpt       text
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

-- ------------------------------------------------------------
-- 2. The 40-character tag cap: data first, then the constraint.
-- ------------------------------------------------------------
delete from tags where char_length(tag) > 40;

alter table tags drop constraint if exists tags_tag_check;
alter table tags add constraint tags_tag_check
  check (char_length(tag) between 1 and 40);

-- create_post, replaced in full (same signature, so grants persist):
-- only the hashtag loop changes.
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

  -- Hashtags (design §2, amended by the Owner 2026-10: the cap is 40):
  -- '#' at a word boundary, then letters, numbers, and underscores with
  -- at least one letter, at most 40 characters. A longer token is not a
  -- hashtag at all — nothing is indexed and the client renders it as
  -- muted, inert text (the same treatment as an unresolved mention).
  -- The post itself always succeeds. 30 distinct tags indexed per post,
  -- as before. The folded length is re-checked so a rare NFC expansion
  -- can never trip the tags length constraint and fail the post.
  for v_tag in
    select distinct internal.fold_tag(m[1])
    from regexp_matches(p_body, '(?:^|[^[:alnum:]_])#([[:alnum:]_]+)', 'g') m
    where char_length(m[1]) <= 40
      and char_length(internal.fold_tag(m[1])) between 1 and 40
      and m[1] ~ '[[:alpha:]]'
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
-- 3. EXECUTE lockdown for the new profile_posts signature (the 0025
--    pattern; the old signature was dropped above).
-- ------------------------------------------------------------
revoke execute on function profile_posts(uuid, boolean, boolean, timestamptz, integer, bigint) from public, anon, service_role;
grant  execute on function profile_posts(uuid, boolean, boolean, timestamptz, integer, bigint) to authenticated;
