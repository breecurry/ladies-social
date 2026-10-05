-- ============================================================
-- 0014 — Social core hardening (Phase 2A security audit + QA fixes).
--
-- Forward-only and idempotent: safe against a live database where
-- 0001-0013 are applied, and safe to re-run. Migration 0013 is
-- immutable; every fix to its objects lands HERE by redefining them.
--
-- What this migration fixes (audit/QA finding ids in section comments):
--   P1-1  blocked_either()/blocked_by() were callable via RPC by any
--         member with arbitrary arguments (block-graph probing).
--   P1-2  follows_read had no block filter: a blocked member could
--         enumerate her blocker's follower/following lists by reading
--         the follows table directly.
--   P1-3  notif_enabled() was callable via RPC, leaking another
--         member's notification preferences.
--   P1-5  The mention parser had no word boundary before '@', so
--         "noreply@cat" silently notified the real handle "cat".
--   P2-1  file_report() had no rate limit and no duplicate guard
--         (mass-reporting weaponisation against a victim).
--   P2-2  get_thread() returned a tombstone for a blocked author's
--         ROOT post, confirming to a blocked person the post exists.
--   P2-3  Cursor pagination had no tiebreaker beyond created_at, so
--         timestamp ties were silently skipped across page boundaries.
--   P2-4  No maximum reply depth (recursive-CTE cost in get_thread).
--   P2-5  search_people() passed '_' unescaped into its LIKE pattern.
--   P2-6  profile_posts() parent excerpts checked deleted_at but not
--         visibility, so a moderation-removed post's text could
--         surface as parent context once moderation ships.
--   P2-8  The four trigger functions were the only functions in 0013
--         not REVOKEd from PUBLIC (hygiene; not exploitable).
--
-- 🥊 THE P1-1 DESIGN, BECAUSE IT IS SUBTLE:
-- PostgreSQL checks EXECUTE on a function referenced in an RLS policy
-- against the QUERYING role, even when the function is SECURITY
-- DEFINER (DEFINER changes what the body runs as, not who may invoke
-- it). So the grant to `authenticated` cannot simply be revoked while
-- the policies still reference public.blocked_either — but the grant
-- does not have to live on an RPC-reachable function either:
--   1. public.blocked_either gains a caller-scoping guard: unless the
--      call is server-context (auth.uid() is null — unreachable through
--      PostgREST, which always carries a sub claim for authenticated)
--      the caller must BE one of the two parties, or it raises. Every
--      0013 call site passes auth.uid() as a party (audited: see list
--      at the guard below), so nothing internal changes behaviour.
--   2. EXECUTE on public.blocked_either / public.blocked_by /
--      public.notif_enabled is revoked from all app roles. Their only
--      remaining callers are SECURITY DEFINER functions and triggers,
--      which execute as the migration owner and are unaffected.
--   3. The RLS policies that genuinely need a member-executable helper
--      now call copies in a new `internal` schema. PostgREST exposes
--      only `public` (and graphql_public) — see supabase/config.toml —
--      so internal.* satisfies the policy EXECUTE check while being
--      unreachable via supabase.rpc() from any client.
-- Net effect: a member can no longer ask the database whether a block
-- exists between two other people, nor "did she block me?" — the exact
-- fact the 0013 header promises stays hidden. The residual signal (her
-- profile and posts stop being visible) is indistinguishable from an
-- account that was deleted, which is the intended ambiguity.
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- 1. P1-1 — caller-scope the block helpers and move the RLS-facing
--    grants into a schema PostgREST does not expose.
-- ------------------------------------------------------------
create schema if not exists internal;
revoke all on schema internal from public;
grant usage on schema internal to authenticated;
comment on schema internal is
  'RLS helper functions executable by app roles but deliberately NOT '
  'exposed through PostgREST (config.toml exposes public only). Do not '
  'add this schema to the API-exposed schema list.';

-- Caller-scoped mutual-block check. Truthful ONLY when the call is
-- server-context (auth.uid() is null) or the caller is one of the two
-- parties; any other combination raises. Audited call sites in 0013,
-- all of which pass auth.uid() as a party:
--   on_like_change (new.user_id = auth.uid(), enforced by likes RLS),
--   create_post x2 (v_me), feed_following, get_thread, profile_posts
--   x3, search_people, list_followers x2, list_following x2,
--   get_notifications, and the policies recreated in section 2 below
--   (follows_read/insert, posts_read, likes_own_insert), which pass
--   auth.uid() literally.
create or replace function blocked_either(a uuid, b uuid) returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if auth.uid() is not null
     and auth.uid() is distinct from a
     and auth.uid() is distinct from b then
    raise insufficient_privilege using
      message = 'Block status can only be checked for your own account.';
  end if;
  return exists (
    select 1 from blocks
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a)
  );
end $$;

-- public.blocked_by keeps its 0013 body (it only ever answers about
-- the caller's own relationship) but loses every app-role grant below;
-- the profiles_read policy now uses internal.blocked_by instead.

revoke execute on function blocked_either(uuid, uuid) from public, anon, authenticated, service_role;
revoke execute on function blocked_by(uuid)           from public, anon, authenticated, service_role;
-- P1-3: notif_enabled is only ever called from inside SECURITY DEFINER
-- functions, which do not need the caller to hold EXECUTE.
revoke execute on function notif_enabled(uuid, text)  from public, anon, authenticated, service_role;

-- The policy-facing twins. internal.blocked_either inherits the
-- caller-scoping guard by delegating to the public function (the
-- delegate call runs as the definer and passes its EXECUTE check).
create or replace function internal.blocked_either(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select public.blocked_either(a, b)
$$;

create or replace function internal.blocked_by(p_owner uuid) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (
    select 1 from blocks
    where blocker_id = p_owner and blocked_id = auth.uid()
  )
$$;

revoke execute on function internal.blocked_either(uuid, uuid) from public;
revoke execute on function internal.blocked_by(uuid)           from public;
grant  execute on function internal.blocked_either(uuid, uuid) to authenticated;
grant  execute on function internal.blocked_by(uuid)           to authenticated;

-- ------------------------------------------------------------
-- 2. Recreate every policy that references the helpers so the EXECUTE
--    check lands on internal.* (P1-1), and add the missing block
--    filter to follows_read (P1-2).
-- ------------------------------------------------------------

-- P1-2: follows rows are invisible across a block, in BOTH directions
-- and on BOTH sides of the relationship. Expected side effect: follows
-- created before a block disappear from the blocked viewer's lists
-- (and from follower/following counts as that viewer sees them).
drop policy if exists follows_read on follows;
create policy follows_read on follows for select
  using (
    is_active_member()
    and not internal.blocked_either(auth.uid(), follower_id)
    and not internal.blocked_either(auth.uid(), followee_id)
  );

drop policy if exists follows_insert on follows;
create policy follows_insert on follows for insert
  with check (
    follower_id = auth.uid()
    and is_active_member()
    and not internal.blocked_either(auth.uid(), followee_id)
    and exists (select 1 from profiles t
                where t.user_id = followee_id and t.status in ('active', 'restricted'))
  );

drop policy if exists posts_read on posts;
create policy posts_read on posts for select
  using (
    is_active_member()
    and visibility = 'visible'
    and deleted_at is null
    and not internal.blocked_either(auth.uid(), author_id)
  );

drop policy if exists likes_own_insert on likes;
create policy likes_own_insert on likes for insert
  with check (
    user_id = auth.uid()
    and is_active_member()
    and exists (select 1 from posts p
                where p.id = post_id
                  and p.deleted_at is null
                  and p.visibility = 'visible'
                  and not internal.blocked_either(auth.uid(), p.author_id))
  );

drop policy if exists profiles_read on profiles;
create policy profiles_read on profiles for select
  using (
    status <> 'deleted'
    and (
      user_id = auth.uid()
      or (is_active_member() and not internal.blocked_by(profiles.user_id))
    )
  );

-- ------------------------------------------------------------
-- 3. P2-8 — the four trigger functions, REVOKEd like the other
--    fourteen. Not exploitable (Postgres refuses to call trigger
--    functions directly) but consistency matters.
-- ------------------------------------------------------------
revoke execute on function forbid_blocking_protected() from public, anon, authenticated, service_role;
revoke execute on function set_post_thread_fields()    from public, anon, authenticated, service_role;
revoke execute on function on_like_change()            from public, anon, authenticated, service_role;
revoke execute on function on_follow_insert()          from public, anon, authenticated, service_role;

-- ------------------------------------------------------------
-- 4. P1-5 + P2-4 — create_post: mention word boundary, max reply depth.
--    Same signature, so CREATE OR REPLACE preserves the 0013 grants.
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
  -- P1-5: the '@' must sit at the start of the text or after a
  -- non-word character, so "noreply@cat" is an email-shaped string,
  -- not a mention of @cat. Repeats still dedupe to one row and one
  -- notification, and mentions still never cross a block.
  for v_handle in
    select distinct lower(m[1])
    from regexp_matches(p_body, '(?:^|[^A-Za-z0-9_])@([A-Za-z0-9_]{3,30})', 'g') m
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

-- ------------------------------------------------------------
-- 5. P2-1 — file_report: duplicate guard + hourly cap. Same signature,
--    grants preserved. Both messages are calm and non-accusatory: a
--    legitimate reporter in distress must never read blame into them.
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

  -- P2-1a: duplicate guard. One report per (reporter, accused, reason)
  -- per 24 hours; the first one already covers the queue.
  if exists (select 1 from reports r
             where r.reporter_id = v_me
               and r.subject_user_id = v_accused
               and r.reason = p_reason
               and r.created_at > now() - interval '24 hours') then
    raise exception 'You have already reported this recently, and that report is with our team. There is no need to send it again.';
  end if;

  -- P2-1b: hourly cap. Mass filing buries real reports; 10/hour is
  -- generous for genuine use and cheap for an abuser to hit.
  if (select count(*) from reports r
      where r.reporter_id = v_me
        and r.created_at > now() - interval '1 hour') >= 10 then
    raise exception 'You have filed several reports in the last hour, and they are all safely with our team. Please wait a little while before filing another.';
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
-- 6. P2-2 — get_thread: when the ROOT post's author is blocked either
--    way, return NOTHING, so the app's notFound() fires exactly as it
--    does for a nonexistent id. Tombstones for blocked authors WITHIN
--    an otherwise visible thread are correct and stay. Same signature.
-- ------------------------------------------------------------
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
    -- P2-2: a blocked person gets an empty result for the whole thread,
    -- never a page-rendering tombstone that confirms the post exists.
    and exists (select 1 from posts rp
                where rp.id = p_post
                  and not blocked_either(auth.uid(), rp.author_id))
  order by sh.depth, sh.created_at
  limit 500
$$;

-- ------------------------------------------------------------
-- 7. P2-3 (+ P2-6) — deterministic pagination for every paged read
--    function. The new cursor parameter is appended LAST so existing
--    positional calls keep their meaning; passing it is optional (the
--    old timestamp-only behaviour remains for callers that do not),
--    but the app now always sends it. Old signatures are DROPPED so
--    PostgREST never sees an ambiguous overload.
-- ------------------------------------------------------------
drop function if exists feed_following(timestamptz, integer);
create or replace function feed_following(
  p_before    timestamptz default null,
  p_limit     integer default 20,
  p_before_id bigint default null
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
    and (p_before is null
         or (p_before_id is null and p.created_at < p_before)
         or (p_before_id is not null and (p.created_at, p.id) < (p_before, p_before_id)))
  order by p.created_at desc, p.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

drop function if exists profile_posts(uuid, boolean, timestamptz, integer);
create or replace function profile_posts(
  p_user      uuid,
  p_replies   boolean default false,
  p_before    timestamptz default null,
  p_limit     integer default 20,
  p_before_id bigint default null
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
    and (p_before is null
         or (p_before_id is null and p.created_at < p_before)
         or (p_before_id is not null and (p.created_at, p.id) < (p_before, p_before_id)))
  order by p.created_at desc, p.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

drop function if exists list_followers(uuid, timestamptz, integer);
create or replace function list_followers(
  p_user        uuid,
  p_before      timestamptz default null,
  p_limit       integer default 30,
  p_before_user uuid default null
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
    and (p_before is null
         or (p_before_user is null and f.created_at < p_before)
         or (p_before_user is not null and (f.created_at, pr.user_id) < (p_before, p_before_user)))
  order by f.created_at desc, pr.user_id desc
  limit least(greatest(coalesce(p_limit, 30), 1), 50)
$$;

drop function if exists list_following(uuid, timestamptz, integer);
create or replace function list_following(
  p_user        uuid,
  p_before      timestamptz default null,
  p_limit       integer default 30,
  p_before_user uuid default null
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
    and (p_before is null
         or (p_before_user is null and f.created_at < p_before)
         or (p_before_user is not null and (f.created_at, pr.user_id) < (p_before, p_before_user)))
  order by f.created_at desc, pr.user_id desc
  limit least(greatest(coalesce(p_limit, 30), 1), 50)
$$;

drop function if exists get_notifications(timestamptz, integer);
create or replace function get_notifications(
  p_before    timestamptz default null,
  p_limit     integer default 30,
  p_before_id bigint default null
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
         -- Same reasoning as P2-6: no excerpt from a post that is no
         -- longer visible, whatever the reason it was removed.
         case when p.id is null or p.deleted_at is not null or p.visibility <> 'visible' then null
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
    and (p_before is null
         or (p_before_id is null and n.created_at < p_before)
         or (p_before_id is not null and (n.created_at, n.id) < (p_before, p_before_id)))
  order by n.created_at desc, n.id desc
  limit least(greatest(coalesce(p_limit, 30), 1), 50)
$$;

-- ------------------------------------------------------------
-- 8. P2-5 — search_people: LIKE metacharacters are escaped before the
--    pattern is built, so '_' matches a literal underscore. The strip
--    step already removes '%' and '\', but all three are escaped so
--    the code stays safe if the allowed character set ever widens.
--    Same signature, grants preserved.
-- ------------------------------------------------------------
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
    select term,
           replace(replace(replace(term, '\', '\\'), '%', '\%'), '_', '\_') as pat
    from (select lower(regexp_replace(coalesce(p_query, ''), '[^A-Za-z0-9_]', '', 'g')) as term) t
  )
  select pr.user_id, pr.handle::text, pr.founding_member, pr.bio,
         exists (select 1 from follows f
                 where f.follower_id = auth.uid() and f.followee_id = pr.user_id)
  from profiles pr, q
  where exists (select 1 from profiles me
                where me.user_id = auth.uid() and me.status in ('active', 'restricted'))
    and q.term <> ''
    and pr.handle::text like '%' || q.pat || '%' escape '\'
    and pr.status in ('active', 'restricted')
    and not blocked_either(auth.uid(), pr.user_id)
  order by (pr.handle::text = q.term) desc,
           (pr.handle::text like q.pat || '%' escape '\') desc,
           pr.handle::text
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

-- ------------------------------------------------------------
-- 9. EXECUTE lockdown for the functions recreated with NEW signatures
--    (dropping + recreating resets ACLs, and both the local shim and
--    hosted Supabase grant EXECUTE on new public functions to all app
--    roles by default). anon and service_role are revoked too: these
--    are member-session functions, nothing server-side calls them.
-- ------------------------------------------------------------
revoke execute on function feed_following(timestamptz, integer, bigint)                  from public, anon, service_role;
revoke execute on function profile_posts(uuid, boolean, timestamptz, integer, bigint)    from public, anon, service_role;
revoke execute on function list_followers(uuid, timestamptz, integer, uuid)              from public, anon, service_role;
revoke execute on function list_following(uuid, timestamptz, integer, uuid)              from public, anon, service_role;
revoke execute on function get_notifications(timestamptz, integer, bigint)               from public, anon, service_role;

grant execute on function feed_following(timestamptz, integer, bigint)                   to authenticated;
grant execute on function profile_posts(uuid, boolean, timestamptz, integer, bigint)     to authenticated;
grant execute on function list_followers(uuid, timestamptz, integer, uuid)               to authenticated;
grant execute on function list_following(uuid, timestamptz, integer, uuid)               to authenticated;
grant execute on function get_notifications(timestamptz, integer, bigint)                to authenticated;
