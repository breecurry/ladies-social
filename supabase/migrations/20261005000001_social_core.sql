-- ============================================================
-- 0013 — Social core (Phase 2A): follows, blocks, mutes, hide,
-- posts (text only) with threaded replies, likes, reports,
-- notifications.
--
-- Forward-only and idempotent: safe against the live database where
-- 0001-0012 are applied, and safe to re-run.
--
-- 🚨 IDENTITY RULE, MADE STRUCTURAL HERE: profiles.display_name is
-- the member's verified legal name and is opt-in. NO function in this
-- migration ever SELECTs display_name. Every feed, thread, search,
-- list and notification function returns the author's @handle only,
-- so no UI code path reading these functions can leak a legal name.
-- The profile page is the single sanctioned display_name surface and
-- it reads the profiles table directly under RLS (where display_name
-- is NULL unless the member opted in — trigger-enforced since 0002).
--
-- 🚨 REPORT REASONS ARE CONDUCT-ONLY. There is deliberately no
-- 'male_account' value: gender is never a reportable offense here.
--
-- Deliberately ABSENT (additive later, with their features):
--   - reshares/quotes: no quoted_post_id, no reshare_count, no
--     'reshare'/'quote' notif_type values.
--   - 'message' report_subject and DM notif types (Phase 4).
--   - post_media (Phase 3, gated on NCMEC + PhotoDNA registration).
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- 1. Enums (guarded for idempotency)
-- ------------------------------------------------------------
do $$ begin
  if not exists (select 1 from pg_type where typname = 'post_visibility') then
    create type post_visibility as enum
      ('visible', 'pending_scan', 'removed_moderation', 'removed_author');
  end if;
  if not exists (select 1 from pg_type where typname = 'reply_control') then
    create type reply_control as enum ('everyone', 'followed', 'mentioned');
  end if;
  if not exists (select 1 from pg_type where typname = 'report_subject') then
    create type report_subject as enum ('post', 'user'); -- 'message' arrives with DMs
  end if;
  if not exists (select 1 from pg_type where typname = 'report_reason') then
    -- Conduct-based only. NO identity-based reason exists or may be added.
    create type report_reason as enum
      ('harassment', 'hate', 'violence_threat', 'doxxing', 'csam', 'ncii',
       'spam', 'impersonation', 'self_harm', 'other');
  end if;
  if not exists (select 1 from pg_type where typname = 'report_status') then
    create type report_status as enum
      ('open', 'in_review', 'actioned', 'dismissed', 'escalated');
  end if;
  if not exists (select 1 from pg_type where typname = 'report_routing') then
    create type report_routing as enum ('standard', 'admin_only', 'owner_conflict');
  end if;
  if not exists (select 1 from pg_type where typname = 'notif_type') then
    create type notif_type as enum ('follow', 'like', 'reply', 'mention', 'system');
  end if;
end $$;

-- ------------------------------------------------------------
-- 2. Social graph tables
-- ------------------------------------------------------------
create table if not exists follows (
  follower_id uuid not null references profiles (user_id) on delete cascade,
  followee_id uuid not null references profiles (user_id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
create index if not exists idx_follows_followee on follows (followee_id);

create table if not exists blocks (
  blocker_id uuid not null references profiles (user_id) on delete cascade,
  blocked_id uuid not null references profiles (user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index if not exists idx_blocks_blocked on blocks (blocked_id);

create table if not exists mutes (
  muter_id   uuid not null references profiles (user_id) on delete cascade,
  muted_id   uuid not null references profiles (user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (muter_id, muted_id),
  check (muter_id <> muted_id)
);

-- "Show me less from @handle": the lightest negative signal. Stored
-- per account. Per spec §4.8 it does NOT filter the Following feed;
-- it tunes Discover (Phase 2B) and the Phase 5 ranked feed.
create table if not exists hidden_accounts (
  hider_id   uuid not null references profiles (user_id) on delete cascade,
  hidden_id  uuid not null references profiles (user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (hider_id, hidden_id),
  check (hider_id <> hidden_id)
);

-- The Owner's account and the system account cannot be blocked
-- (locked product decision; moderation never consults blocks anyway).
create or replace function forbid_blocking_protected() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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

drop trigger if exists trg_blocks_protected on blocks;
create trigger trg_blocks_protected before insert on blocks
  for each row execute function forbid_blocking_protected();

-- Blocks are MUTUAL-HARD: either direction severs all visibility and
-- interaction. SECURITY DEFINER so it is usable inside RLS policies
-- (a plain subquery on blocks would be filtered by blocks' own
-- own-row RLS and silently never match).
create or replace function blocked_either(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (
    select 1 from blocks
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a)
  )
$$;

-- One-directional check for profile visibility: has p_owner blocked
-- the current viewer? (The blocker herself still sees the blocked
-- account's handle, so she can manage her unblock list.)
create or replace function blocked_by(p_owner uuid) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (
    select 1 from blocks
    where blocker_id = p_owner and blocked_id = auth.uid()
  )
$$;

-- ------------------------------------------------------------
-- 3. Posts: adjacency list + denormalized root/depth.
--    Text only in Phase 2A. No quoted_post_id, no reshare_count —
--    reshares/quotes arrive additively with their feature.
-- ------------------------------------------------------------
create table if not exists posts (
  id             bigint generated always as identity primary key,
  author_id      uuid not null references profiles (user_id),
  parent_post_id bigint references posts (id),
  root_post_id   bigint not null,             -- = id for roots; set by trigger
  depth          smallint not null default 0, -- set by trigger
  body           text not null check (char_length(body) <= 500),
  reply_control  reply_control not null default 'everyone',
  like_count     integer not null default 0,
  reply_count    integer not null default 0,
  visibility     post_visibility not null default 'visible',
  created_at     timestamptz not null default now(),
  edited_at      timestamptz,
  deleted_at     timestamptz
);
create index if not exists idx_posts_author_time on posts (author_id, created_at desc)
  where deleted_at is null and parent_post_id is null;
create index if not exists idx_posts_author_replies on posts (author_id, created_at desc)
  where deleted_at is null and parent_post_id is not null;
create index if not exists idx_posts_thread on posts (root_post_id, created_at)
  where deleted_at is null;
create index if not exists idx_posts_parent on posts (parent_post_id);
create index if not exists idx_posts_recent on posts (created_at desc)
  where deleted_at is null and parent_post_id is null and visibility = 'visible';
create index if not exists idx_posts_fts on posts using gin (to_tsvector('english', body));

create or replace function set_post_thread_fields() returns trigger
language plpgsql as $$
declare
  v_root  bigint;
  v_depth smallint;
begin
  if new.parent_post_id is null then
    new.root_post_id := new.id; -- identity value exists before BEFORE-row triggers
    new.depth := 0;
  else
    select root_post_id, depth into v_root, v_depth
      from posts where id = new.parent_post_id;
    if v_root is null then
      raise exception 'Parent post not found.';
    end if;
    new.root_post_id := v_root;
    new.depth := v_depth + 1;
  end if;
  return new;
end $$;

drop trigger if exists trg_posts_thread on posts;
create trigger trg_posts_thread before insert on posts
  for each row execute function set_post_thread_fields();

-- @mentions, parsed at post time inside create_post(). Also the data
-- behind reply_control = 'mentioned'.
create table if not exists post_mentions (
  post_id           bigint not null references posts (id) on delete cascade,
  mentioned_user_id uuid not null references profiles (user_id) on delete cascade,
  primary key (post_id, mentioned_user_id)
);
create index if not exists idx_post_mentions_user on post_mentions (mentioned_user_id);

create table if not exists likes (
  user_id    uuid   not null references profiles (user_id) on delete cascade,
  post_id    bigint not null references posts (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);
create index if not exists idx_likes_post on likes (post_id);

-- ------------------------------------------------------------
-- 4. Reports. Written only via file_report(); routing is computed
--    server-side and never shown to the reporter (spec §10.5).
-- ------------------------------------------------------------
create table if not exists reports (
  id              uuid primary key default gen_random_uuid(),
  reporter_id     uuid not null references profiles (user_id),
  subject_type    report_subject not null,
  subject_post_id bigint references posts (id),
  subject_user_id uuid not null references profiles (user_id), -- the accused, always set
  reason          report_reason not null,
  details         text check (char_length(details) <= 2000),
  routing         report_routing not null default 'standard',
  status          report_status not null default 'open',
  assigned_to     uuid references profiles (user_id),
  created_at      timestamptz not null default now(),
  resolved_at     timestamptz,
  resolved_by     uuid references profiles (user_id),
  resolution_note text,
  check (subject_type <> 'post' or subject_post_id is not null)
);
create index if not exists idx_reports_queue on reports (status, routing, created_at);
create index if not exists idx_reports_accused on reports (subject_user_id, created_at desc);

-- ------------------------------------------------------------
-- 5. Notifications. Rows are created ONLY inside SECURITY DEFINER
--    functions and triggers; members read their own and may update
--    nothing but read_at.
-- ------------------------------------------------------------
create table if not exists notifications (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references profiles (user_id) on delete cascade,
  actor_id   uuid references profiles (user_id),
  type       notif_type not null,
  post_id    bigint references posts (id) on delete cascade,
  created_at timestamptz not null default now(),
  read_at    timestamptz
);
create index if not exists idx_notifications_user on notifications (user_id, created_at desc);
create index if not exists idx_notifications_unread on notifications (user_id) where read_at is null;

create table if not exists notification_prefs (
  user_id    uuid primary key references profiles (user_id) on delete cascade,
  prefs      jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- A per-type toggle. Missing key = enabled (sensible defaults: all on).
create or replace function notif_enabled(p_user uuid, p_type text) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(
    (select (prefs ->> p_type)::boolean from notification_prefs where user_id = p_user),
    true)
$$;

-- ------------------------------------------------------------
-- 6. Interaction triggers: like counters + like/follow notifications.
--    (Reply counters and reply/mention notifications live inside
--    create_post, the only write path for posts.)
-- ------------------------------------------------------------
create or replace function on_like_change() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_author uuid;
begin
  if tg_op = 'INSERT' then
    update posts set like_count = like_count + 1
      where id = new.post_id
      returning author_id into v_author;
    if v_author is not null
       and v_author <> new.user_id
       and not blocked_either(v_author, new.user_id)
       and not exists (select 1 from mutes where muter_id = v_author and muted_id = new.user_id)
       and notif_enabled(v_author, 'like') then
      insert into notifications (user_id, actor_id, type, post_id)
      values (v_author, new.user_id, 'like', new.post_id);
    end if;
    return new;
  end if;
  update posts set like_count = greatest(like_count - 1, 0) where id = old.post_id;
  return old;
end $$;

drop trigger if exists trg_likes_change on likes;
create trigger trg_likes_change after insert or delete on likes
  for each row execute function on_like_change();

create or replace function on_follow_insert() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not exists (select 1 from mutes where muter_id = new.followee_id and muted_id = new.follower_id)
     and notif_enabled(new.followee_id, 'follow') then
    insert into notifications (user_id, actor_id, type)
    values (new.followee_id, new.follower_id, 'follow');
  end if;
  return new;
end $$;

drop trigger if exists trg_follows_notify on follows;
create trigger trg_follows_notify after insert on follows
  for each row execute function on_follow_insert();

-- ------------------------------------------------------------
-- 7. Post write path: create_post / delete_post. Direct table writes
--    are REVOKEd from every app role below, so these functions are
--    the only way a post comes to exist or go away.
-- ------------------------------------------------------------
create or replace function create_post(
  p_body          text,
  p_parent        bigint default null,
  p_reply_control reply_control default 'everyone'
) returns bigint
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me             uuid := auth.uid();
  v_parent         posts%rowtype;
  v_parent_author  uuid; -- captured separately: plpgsql errors on field access
                         -- of a never-assigned record even behind short-circuit OR
  v_id             bigint;
  v_mention        uuid;
  v_handle         text;
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

  insert into posts (author_id, parent_post_id, body, reply_control)
  values (v_me, p_parent, p_body, p_reply_control)
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

  -- Mentions: @handle tokens resolved against real, unblocked accounts.
  for v_handle in
    select distinct lower(m[1])
    from regexp_matches(p_body, '@([A-Za-z0-9_]{3,30})', 'g') m
  loop
    select user_id into v_mention from profiles
      where handle = v_handle::citext
        and status in ('active', 'restricted')
        and user_id <> v_me;
    if v_mention is not null and not blocked_either(v_me, v_mention) then
      insert into post_mentions (post_id, mentioned_user_id)
      values (v_id, v_mention)
      on conflict do nothing;
      -- Do not double-notify the parent author (she already got 'reply').
      if (p_parent is null or v_mention <> v_parent_author)
         and not exists (select 1 from mutes where muter_id = v_mention and muted_id = v_me)
         and notif_enabled(v_mention, 'mention') then
        insert into notifications (user_id, actor_id, type, post_id)
        values (v_mention, v_me, 'mention', v_id);
      end if;
    end if;
    v_mention := null;
  end loop;

  return v_id;
end $$;

create or replace function delete_post(p_post bigint) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_parent bigint;
begin
  update posts
     set deleted_at = now(), visibility = 'removed_author'
   where id = p_post and author_id = auth.uid() and deleted_at is null
   returning parent_post_id into v_parent;
  if not found then
    raise exception 'That post is unavailable.';
  end if;
  if v_parent is not null then
    update posts set reply_count = greatest(reply_count - 1, 0) where id = v_parent;
  end if;
end $$;

-- ------------------------------------------------------------
-- 8. Reporting: file_report() computes routing server-side.
--    'standard'       -> moderator queue
--    'admin_only'     -> accused holds a staff role; admins/Owner only
--    'owner_conflict' -> accused IS the Owner; visible to NO ONE
--                        in-app, the Owner included (architecture
--                        §3.5: external escalation path). The flow
--                        and confirmation are identical for the
--                        reporter in all cases.
-- ------------------------------------------------------------
create or replace function file_report(
  p_subject report_subject,
  p_post    bigint default null,
  p_user    uuid default null,
  p_reason  report_reason default 'other',
  p_details text default null
) returns uuid
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me      uuid := auth.uid();
  v_accused uuid;
  v_routing report_routing := 'standard';
  v_id      uuid;
begin
  if v_me is null then
    raise exception 'Not signed in.';
  end if;
  if not exists (select 1 from profiles where user_id = v_me and status in ('active', 'restricted')) then
    raise exception 'Your account cannot file reports right now.';
  end if;
  if p_details is not null and char_length(p_details) > 2000 then
    raise exception 'Details are limited to 2000 characters.';
  end if;

  if p_subject = 'post' then
    if p_post is null then raise exception 'No post given.'; end if;
    select author_id into v_accused from posts where id = p_post;
    if v_accused is null then raise exception 'That post is unavailable.'; end if;
  else
    if p_user is null then raise exception 'No account given.'; end if;
    select user_id into v_accused from profiles where user_id = p_user;
    if v_accused is null then raise exception 'That account is unavailable.'; end if;
  end if;
  if v_accused = v_me then
    raise exception 'You cannot report yourself.';
  end if;

  if exists (select 1 from role_assignments
             where user_id = v_accused and role = 'owner' and revoked_at is null) then
    v_routing := 'owner_conflict';
  elsif exists (select 1 from role_assignments
                where user_id = v_accused and role in ('admin', 'moderator', 'ts_reviewer')
                  and revoked_at is null) then
    v_routing := 'admin_only';
  end if;

  insert into reports (reporter_id, subject_type, subject_post_id, subject_user_id,
                       reason, details, routing)
  values (v_me, p_subject,
          case when p_subject = 'post' then p_post end,
          v_accused, p_reason, nullif(btrim(coalesce(p_details, '')), ''), v_routing)
  returning id into v_id;

  -- Audited WITHOUT accused or routing: the audit log is Owner-readable
  -- and must not reveal that a report about the Owner exists (§3.5).
  perform append_audit('report.filed', 'report', v_id::text,
                       jsonb_build_object('reason', p_reason));
  return v_id;
end $$;

-- ------------------------------------------------------------
-- 9. Read functions. ALL of these are SECURITY DEFINER and return
--    the author's @handle ONLY — display_name is structurally absent
--    from every return shape (see the header rule).
-- ------------------------------------------------------------

-- Following feed: fan-out-on-read over follows ∪ self. Excludes muted
-- and blocked authors. "Show me less" (hidden_accounts) deliberately
-- does NOT filter this feed (spec §4.8: it is a Discover/ranking signal).
create or replace function feed_following(
  p_before timestamptz default null,
  p_limit  integer default 20
) returns table (
  id            bigint,
  author_id     uuid,
  author_handle text,
  author_founding boolean,
  body          text,
  reply_control reply_control,
  like_count    integer,
  reply_count   integer,
  viewer_liked  boolean,
  created_at    timestamptz
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select p.id, p.author_id, pr.handle::text, pr.founding_member,
         p.body, p.reply_control, p.like_count, p.reply_count,
         exists (select 1 from likes l where l.post_id = p.id and l.user_id = auth.uid()),
         p.created_at
  from posts p
  join profiles pr on pr.user_id = p.author_id
  where exists (select 1 from profiles me
                where me.user_id = auth.uid() and me.status in ('active', 'restricted'))
    and p.parent_post_id is null
    and p.deleted_at is null
    and p.visibility = 'visible'
    and pr.status in ('active', 'restricted')
    and (p.author_id = auth.uid() or exists (
          select 1 from follows f
          where f.follower_id = auth.uid() and f.followee_id = p.author_id))
    and not exists (select 1 from mutes m
                    where m.muter_id = auth.uid() and m.muted_id = p.author_id)
    and not blocked_either(auth.uid(), p.author_id)
    and (p_before is null or p.created_at < p_before)
  order by p.created_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

-- Whole subtree of a post (works for true roots and for re-rooted
-- focused views). Deleted posts, and posts whose author is blocked
-- either way or muted by the viewer, come back as tombstones
-- (unavailable = true, empty handle and body) so thread structure
-- never orphans a reply.
create or replace function get_thread(p_post bigint)
returns table (
  id             bigint,
  parent_post_id bigint,
  depth          smallint,
  author_id      uuid,
  author_handle  text,
  author_founding boolean,
  body           text,
  reply_control  reply_control,
  like_count     integer,
  reply_count    integer,
  viewer_liked   boolean,
  unavailable    boolean,
  created_at     timestamptz
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
         (not sh.hidden) and exists (select 1 from likes l
                                     where l.post_id = sh.id and l.user_id = auth.uid()),
         sh.hidden,
         sh.created_at
  from shaped sh
  where exists (select 1 from profiles me
                where me.user_id = auth.uid() and me.status in ('active', 'restricted'))
  order by sh.depth, sh.created_at
  limit 500
$$;

-- A member's posts or replies for the profile tabs. Replies carry a
-- one-line parent context (handle + excerpt), handle-only as always.
create or replace function profile_posts(
  p_user    uuid,
  p_replies boolean default false,
  p_before  timestamptz default null,
  p_limit   integer default 20
) returns table (
  id            bigint,
  author_id     uuid,
  author_handle text,
  author_founding boolean,
  body          text,
  reply_control reply_control,
  like_count    integer,
  reply_count   integer,
  viewer_liked  boolean,
  created_at    timestamptz,
  parent_author_handle text,
  parent_excerpt       text
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select p.id, p.author_id, pr.handle::text, pr.founding_member,
         p.body, p.reply_control, p.like_count, p.reply_count,
         exists (select 1 from likes l where l.post_id = p.id and l.user_id = auth.uid()),
         p.created_at,
         case when p.parent_post_id is null then null
              else coalesce((select ppr.handle::text
                             from posts pp join profiles ppr on ppr.user_id = pp.author_id
                             where pp.id = p.parent_post_id
                               and pp.deleted_at is null
                               and not blocked_either(auth.uid(), pp.author_id)), '') end,
         case when p.parent_post_id is null then null
              else coalesce((select left(pp.body, 120) from posts pp
                             where pp.id = p.parent_post_id
                               and pp.deleted_at is null
                               and not blocked_either(auth.uid(), pp.author_id)), '') end
  from posts p
  join profiles pr on pr.user_id = p.author_id
  where exists (select 1 from profiles me
                where me.user_id = auth.uid() and me.status in ('active', 'restricted'))
    and p.author_id = p_user
    and ((p_replies and p.parent_post_id is not null)
         or (not p_replies and p.parent_post_id is null))
    and p.deleted_at is null
    and p.visibility = 'visible'
    and pr.status in ('active', 'restricted')
    and not blocked_either(auth.uid(), p_user)
    and (p_before is null or p.created_at < p_before)
  order by p.created_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

-- People search: matches the @handle ONLY. It deliberately does not
-- match or return display_name (see the header rule); the profile
-- page is the one surface where an opted-in legal name may appear.
create or replace function search_people(
  p_query text,
  p_limit integer default 20
) returns table (
  user_id        uuid,
  handle         text,
  founding       boolean,
  bio            text,
  viewer_follows boolean
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with q as (
    select lower(regexp_replace(coalesce(p_query, ''), '[^A-Za-z0-9_]', '', 'g')) as term
  )
  select pr.user_id, pr.handle::text, pr.founding_member, pr.bio,
         exists (select 1 from follows f
                 where f.follower_id = auth.uid() and f.followee_id = pr.user_id)
  from profiles pr, q
  where exists (select 1 from profiles me
                where me.user_id = auth.uid() and me.status in ('active', 'restricted'))
    and q.term <> ''
    and pr.handle::text like '%' || q.term || '%'
    and pr.status in ('active', 'restricted')
    and not blocked_either(auth.uid(), pr.user_id)
  order by (pr.handle::text = q.term) desc,
           (pr.handle::text like q.term || '%') desc,
           pr.handle::text
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

-- Follower / following lists (profile sub-pages). Handle-only rows.
create or replace function list_followers(
  p_user   uuid,
  p_before timestamptz default null,
  p_limit  integer default 30
) returns table (
  user_id        uuid,
  handle         text,
  founding       boolean,
  bio            text,
  viewer_follows boolean,
  followed_at    timestamptz
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select pr.user_id, pr.handle::text, pr.founding_member, pr.bio,
         exists (select 1 from follows f2
                 where f2.follower_id = auth.uid() and f2.followee_id = pr.user_id),
         f.created_at
  from follows f
  join profiles pr on pr.user_id = f.follower_id
  where exists (select 1 from profiles me
                where me.user_id = auth.uid() and me.status in ('active', 'restricted'))
    and f.followee_id = p_user
    and not blocked_either(auth.uid(), p_user)
    and not blocked_either(auth.uid(), pr.user_id)
    and pr.status in ('active', 'restricted')
    and (p_before is null or f.created_at < p_before)
  order by f.created_at desc
  limit least(greatest(coalesce(p_limit, 30), 1), 50)
$$;

create or replace function list_following(
  p_user   uuid,
  p_before timestamptz default null,
  p_limit  integer default 30
) returns table (
  user_id        uuid,
  handle         text,
  founding       boolean,
  bio            text,
  viewer_follows boolean,
  followed_at    timestamptz
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select pr.user_id, pr.handle::text, pr.founding_member, pr.bio,
         exists (select 1 from follows f2
                 where f2.follower_id = auth.uid() and f2.followee_id = pr.user_id),
         f.created_at
  from follows f
  join profiles pr on pr.user_id = f.followee_id
  where exists (select 1 from profiles me
                where me.user_id = auth.uid() and me.status in ('active', 'restricted'))
    and f.follower_id = p_user
    and not blocked_either(auth.uid(), p_user)
    and not blocked_either(auth.uid(), pr.user_id)
    and pr.status in ('active', 'restricted')
    and (p_before is null or f.created_at < p_before)
  order by f.created_at desc
  limit least(greatest(coalesce(p_limit, 30), 1), 50)
$$;

-- Notifications list: actor handle only, plus a short post excerpt.
create or replace function get_notifications(
  p_before timestamptz default null,
  p_limit  integer default 30
) returns table (
  id           bigint,
  type         notif_type,
  actor_id     uuid,
  actor_handle text,
  post_id      bigint,
  post_excerpt text,
  created_at   timestamptz,
  read_at      timestamptz
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select n.id, n.type, n.actor_id, coalesce(a.handle::text, ''), n.post_id,
         case when p.id is null or p.deleted_at is not null then null
              else left(p.body, 120) end,
         n.created_at, n.read_at
  from notifications n
  left join profiles a on a.user_id = n.actor_id
  left join posts p on p.id = n.post_id
  where n.user_id = auth.uid()
    and (n.actor_id is null or (
          not blocked_either(auth.uid(), n.actor_id)
          and not exists (select 1 from mutes m
                          where m.muter_id = auth.uid() and m.muted_id = n.actor_id)))
    and (p_before is null or n.created_at < p_before)
  order by n.created_at desc
  limit least(greatest(coalesce(p_limit, 30), 1), 50)
$$;

create or replace function notif_mark_all_read() returns void
language sql security definer set search_path = public, extensions, pg_temp as $$
  update notifications set read_at = now()
  where user_id = auth.uid() and read_at is null
$$;

-- ------------------------------------------------------------
-- 10. RLS + privilege lockdown for every new table.
-- ------------------------------------------------------------
alter table follows            enable row level security;
alter table blocks             enable row level security;
alter table mutes              enable row level security;
alter table hidden_accounts    enable row level security;
alter table posts              enable row level security;
alter table post_mentions      enable row level security;
alter table likes              enable row level security;
alter table reports            enable row level security;
alter table notifications      enable row level security;
alter table notification_prefs enable row level security;

-- follows: lists are member-visible (spec §7.2); own-row writes only;
-- you cannot follow across a block or follow a non-member.
drop policy if exists follows_read on follows;
create policy follows_read on follows for select
  using (is_active_member());
drop policy if exists follows_insert on follows;
create policy follows_insert on follows for insert
  with check (
    follower_id = auth.uid()
    and is_active_member()
    and not blocked_either(auth.uid(), followee_id)
    and exists (select 1 from profiles t
                where t.user_id = followee_id and t.status in ('active', 'restricted'))
  );
drop policy if exists follows_delete on follows;
create policy follows_delete on follows for delete
  using (follower_id = auth.uid());
revoke all on follows from anon;
revoke update on follows from authenticated;
revoke all on follows from service_role;

-- blocks / mutes / hidden_accounts: strictly own-row, invisible to
-- everyone else (the other person is never told).
drop policy if exists blocks_own_read on blocks;
create policy blocks_own_read on blocks for select
  using (blocker_id = auth.uid());
drop policy if exists blocks_own_insert on blocks;
create policy blocks_own_insert on blocks for insert
  with check (blocker_id = auth.uid() and is_active_member());
drop policy if exists blocks_own_delete on blocks;
create policy blocks_own_delete on blocks for delete
  using (blocker_id = auth.uid());
revoke all on blocks from anon;
revoke update on blocks from authenticated;
revoke all on blocks from service_role;

drop policy if exists mutes_own_read on mutes;
create policy mutes_own_read on mutes for select
  using (muter_id = auth.uid());
drop policy if exists mutes_own_insert on mutes;
create policy mutes_own_insert on mutes for insert
  with check (muter_id = auth.uid() and is_active_member());
drop policy if exists mutes_own_delete on mutes;
create policy mutes_own_delete on mutes for delete
  using (muter_id = auth.uid());
revoke all on mutes from anon;
revoke update on mutes from authenticated;
revoke all on mutes from service_role;

drop policy if exists hidden_own_read on hidden_accounts;
create policy hidden_own_read on hidden_accounts for select
  using (hider_id = auth.uid());
drop policy if exists hidden_own_insert on hidden_accounts;
create policy hidden_own_insert on hidden_accounts for insert
  with check (hider_id = auth.uid() and is_active_member());
drop policy if exists hidden_own_delete on hidden_accounts;
create policy hidden_own_delete on hidden_accounts for delete
  using (hider_id = auth.uid());
revoke all on hidden_accounts from anon;
revoke update on hidden_accounts from authenticated;
revoke all on hidden_accounts from service_role;

-- posts: member-readable where visible and not across a block; ALL
-- writes only via create_post()/delete_post() (DEFINER).
drop policy if exists posts_read on posts;
create policy posts_read on posts for select
  using (
    is_active_member()
    and visibility = 'visible'
    and deleted_at is null
    and not blocked_either(auth.uid(), author_id)
  );
revoke all on posts from anon;
revoke insert, update, delete on posts from authenticated;
revoke insert, update, delete on posts from service_role;

-- post_mentions: readable by members (they render in post bodies
-- anyway); written only inside create_post().
drop policy if exists post_mentions_read on post_mentions;
create policy post_mentions_read on post_mentions for select
  using (is_active_member());
revoke all on post_mentions from anon;
revoke insert, update, delete on post_mentions from authenticated;
revoke insert, update, delete on post_mentions from service_role;

-- likes: PRIVATE. A member sees only her own likes (spec §7.3: likes
-- are not public); counts are denormalized onto posts. Own-row writes,
-- only onto posts she can actually see.
drop policy if exists likes_own_read on likes;
create policy likes_own_read on likes for select
  using (user_id = auth.uid());
drop policy if exists likes_own_insert on likes;
create policy likes_own_insert on likes for insert
  with check (
    user_id = auth.uid()
    and is_active_member()
    and exists (select 1 from posts p
                where p.id = post_id
                  and p.deleted_at is null
                  and p.visibility = 'visible'
                  and not blocked_either(auth.uid(), p.author_id))
  );
drop policy if exists likes_own_delete on likes;
create policy likes_own_delete on likes for delete
  using (user_id = auth.uid());
revoke all on likes from anon;
revoke update on likes from authenticated;
revoke all on likes from service_role;

-- reports: the reporter sees her own (report history, §8.2 Safety —
-- identical regardless of routing, so filing against the Owner is
-- indistinguishable from any other report). Queue visibility respects
-- routing; owner_conflict is visible to NO ONE in-app. Writes only
-- via file_report().
drop policy if exists reports_own on reports;
create policy reports_own on reports for select
  using (reporter_id = auth.uid());
drop policy if exists reports_queue on reports;
create policy reports_queue on reports for select
  using (
    (routing = 'standard' and is_moderator_or_above())
    or (routing = 'admin_only' and is_admin_or_owner() and subject_user_id <> auth.uid())
    -- owner_conflict: no in-app visibility, deliberately (§3.5).
  );
revoke all on reports from anon;
revoke insert, update, delete on reports from authenticated;
revoke insert, update, delete on reports from service_role;

-- notifications: read own; the ONLY writable column is read_at on
-- your own rows. Creation happens solely inside DEFINER functions.
drop policy if exists notif_own_read on notifications;
create policy notif_own_read on notifications for select
  using (user_id = auth.uid());
drop policy if exists notif_own_update on notifications;
create policy notif_own_update on notifications for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
revoke all on notifications from anon;
revoke insert, delete on notifications from authenticated;
revoke update on notifications from authenticated;
grant update (read_at) on notifications to authenticated;
revoke all on notifications from service_role;

-- notification_prefs: own row only.
drop policy if exists notif_prefs_own_read on notification_prefs;
create policy notif_prefs_own_read on notification_prefs for select
  using (user_id = auth.uid());
drop policy if exists notif_prefs_own_insert on notification_prefs;
create policy notif_prefs_own_insert on notification_prefs for insert
  with check (user_id = auth.uid());
drop policy if exists notif_prefs_own_update on notification_prefs;
create policy notif_prefs_own_update on notification_prefs for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
revoke all on notification_prefs from anon;
revoke delete on notification_prefs from authenticated;
revoke all on notification_prefs from service_role;

-- profiles_read, extended for blocks: the person a member blocked can
-- no longer see her profile at all. The BLOCKER still sees the blocked
-- account's handle (she needs it to manage her unblock list). Self and
-- the deleted-filter behave exactly as before (0012).
drop policy if exists profiles_read on profiles;
create policy profiles_read on profiles for select
  using (
    status <> 'deleted'
    and (
      user_id = auth.uid()
      or (is_active_member() and not blocked_by(profiles.user_id))
    )
  );

-- ------------------------------------------------------------
-- 11. Function EXECUTE lockdown: members call the social functions;
--     nothing here is server-only, and anon gets nothing.
-- ------------------------------------------------------------
revoke execute on function blocked_either(uuid, uuid)                           from public;
revoke execute on function blocked_by(uuid)                                     from public;
revoke execute on function notif_enabled(uuid, text)                            from public;
revoke execute on function create_post(text, bigint, reply_control)             from public;
revoke execute on function delete_post(bigint)                                  from public;
revoke execute on function file_report(report_subject, bigint, uuid, report_reason, text) from public;
revoke execute on function feed_following(timestamptz, integer)                 from public;
revoke execute on function get_thread(bigint)                                   from public;
revoke execute on function profile_posts(uuid, boolean, timestamptz, integer)   from public;
revoke execute on function search_people(text, integer)                         from public;
revoke execute on function list_followers(uuid, timestamptz, integer)           from public;
revoke execute on function list_following(uuid, timestamptz, integer)           from public;
revoke execute on function get_notifications(timestamptz, integer)              from public;
revoke execute on function notif_mark_all_read()                                from public;

grant execute on function blocked_either(uuid, uuid)                            to authenticated;
grant execute on function blocked_by(uuid)                                      to authenticated;
grant execute on function notif_enabled(uuid, text)                             to authenticated;
grant execute on function create_post(text, bigint, reply_control)              to authenticated;
grant execute on function delete_post(bigint)                                   to authenticated;
grant execute on function file_report(report_subject, bigint, uuid, report_reason, text) to authenticated;
grant execute on function feed_following(timestamptz, integer)                  to authenticated;
grant execute on function get_thread(bigint)                                    to authenticated;
grant execute on function profile_posts(uuid, boolean, timestamptz, integer)    to authenticated;
grant execute on function search_people(text, integer)                          to authenticated;
grant execute on function list_followers(uuid, timestamptz, integer)            to authenticated;
grant execute on function list_following(uuid, timestamptz, integer)            to authenticated;
grant execute on function get_notifications(timestamptz, integer)               to authenticated;
grant execute on function notif_mark_all_read()                                 to authenticated;
