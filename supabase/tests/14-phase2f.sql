-- Behavioral + structural smoke test for migration 0025 (Phase 2F:
-- hashtags, at-mentions, reposts and quote-posts). Local only, like
-- suites 01-13.
--
-- Headline properties:
--   - hashtags parse with word boundaries, fold case-insensitively,
--     refuse pure numbers, truncate at 64 chars, index at most 30 per
--     post, and the new tables are function-only (RLS on, no direct
--     app-role reads);
--   - the "Who can mention you" policy (default Everyone) gates both
--     the participant row and the notification, and at most 10
--     mention notifications fire per post;
--   - a repost maintains the counter, notifies the author (pref- and
--     block-gated), refuses self-reposts and blocked authors, and
--     vanishes from feeds when any block wall appears, including
--     between the reposter and the original author;
--   - a quote-post is a first-class post that notifies the quoted
--     author and degrades its embedded card to an unavailable stub
--     when the original goes away — the quoting member's own words
--     always survive;
--   - trending counts DISTINCT PEOPLE, never raw post volume;
--   - tag suppression is two audited tiers: de-trend (moderator+) and
--     block (admin+);
--   - the structural legal-name rule holds on every new function.
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000007', 'system@test'),
  ('00000000-0000-0000-0000-000000000021', 'ada@test'),
  ('00000000-0000-0000-0000-000000000022', 'bea@test'),
  ('00000000-0000-0000-0000-000000000023', 'cat@test'),
  ('00000000-0000-0000-0000-000000000024', 'dee@test'),
  ('00000000-0000-0000-0000-000000000025', 'modp2f@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_system_account('00000000-0000-0000-0000-000000000007', 'hersciety');
select create_member('00000000-0000-0000-0000-000000000021', 'ada@test', 'Ada Lovelace', '1995-05-05', 'ada', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000022', 'bea@test', 'Bea Arthur',   '1995-05-05', 'bea', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000023', 'cat@test', 'Cat Stevens',  '1995-05-05', 'cat', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000024', 'dee@test', 'Dee Dee',      '1995-05-05', 'dee', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000025', 'modp2f@test', 'Mod Person', '1995-05-05', 'modp2f', null, null, null, '{}'::jsonb, false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"ow"}', false);
select grant_role('00000000-0000-0000-0000-000000000025', 'moderator');
reset role;

-- ============================================================
-- 1. STRUCTURAL: every new/rebuilt function exists, none references
--    display_name, and EXECUTE is authenticated-only.
-- ============================================================
do $$ declare f text; sig text; src text; begin
  foreach f in array array[
    'create_post', 'feed_following', 'profile_posts', 'get_thread',
    'feed_discover', 'get_tag', 'feed_hashtag', 'search_tags',
    'get_trending_tags', 'compute_trending_tags', 'mod_tag_lookup',
    'mod_detrend_tag', 'mod_block_tag', 'mod_reinstate_tag'
  ] loop
    select pg_get_function_result(p.oid), p.prosrc into sig, src
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = f
      limit 1;
    if sig is null then raise exception 'FAIL: function % missing', f; end if;
    if position('display_name' in coalesce(sig, '')) > 0
       or position('display_name' in coalesce(src, '')) > 0 then
      raise exception 'FAIL: % touches display_name', f;
    end if;
  end loop;
end $$;

do $$ declare f text; begin
  foreach f in array array[
    'public.create_post(text, bigint, reply_control, bigint)',
    'public.feed_hashtag(text, timestamptz, integer, bigint)',
    'public.search_tags(text, integer)',
    'public.get_trending_tags(integer)',
    'public.get_tag(text)'
  ] loop
    if has_function_privilege('anon', f, 'execute') then
      raise exception 'FAIL: anon can execute %', f;
    end if;
    if has_function_privilege('service_role', f, 'execute') then
      raise exception 'FAIL: service_role can execute %', f;
    end if;
    if not has_function_privilege('authenticated', f, 'execute') then
      raise exception 'FAIL: authenticated cannot execute %', f;
    end if;
  end loop;
  -- The internal helpers and the compute job are not app-callable.
  if has_function_privilege('authenticated', 'internal.blocked_pair(uuid, uuid)', 'execute') then
    raise exception 'FAIL: authenticated can execute internal.blocked_pair';
  end if;
  if has_function_privilege('authenticated', 'public.compute_trending_tags()', 'execute') then
    raise exception 'FAIL: authenticated can execute compute_trending_tags';
  end if;
  -- The replaced 3-argument create_post is gone (no ambiguous overload).
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'create_post'
               and p.pronargs = 3) then
    raise exception 'FAIL: the old create_post(text, bigint, reply_control) survives';
  end if;
end $$;

-- ============================================================
-- 2. The new tables: RLS on; tags/post_tags/trending_tags are
--    function-only (no direct app-role privilege at all); reshares is
--    writable own-row only, with no UPDATE path.
-- ============================================================
do $$ declare t text; begin
  foreach t in array array['tags', 'post_tags', 'trending_tags', 'reshares'] loop
    if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                   where n.nspname = 'public' and c.relname = t and c.relrowsecurity) then
      raise exception 'FAIL: % has no row level security', t;
    end if;
  end loop;
  foreach t in array array['tags', 'post_tags', 'trending_tags'] loop
    if has_table_privilege('authenticated', 'public.' || t, 'select')
       or has_table_privilege('authenticated', 'public.' || t, 'insert')
       or has_table_privilege('anon', 'public.' || t, 'select') then
      raise exception 'FAIL: % is directly readable or writable by an app role', t;
    end if;
  end loop;
  if has_table_privilege('authenticated', 'public.reshares', 'update') then
    raise exception 'FAIL: reshares rows are updatable';
  end if;
  if has_table_privilege('anon', 'public.reshares', 'select') then
    raise exception 'FAIL: anon can read reshares';
  end if;
end $$;

-- mention_policy defaults to Everyone for every existing account
-- (owner decision 2026-10-09).
do $$ begin
  if exists (select 1 from profiles where mention_policy <> 'everyone') then
    raise exception 'FAIL: mention_policy default is not everyone';
  end if;
end $$;

-- ============================================================
-- 3. Hashtag parsing inside create_post.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000021","aal":"aal1","session_id":"sa"}', false);

do $$ declare v bigint; begin
  v := create_post('Loving #SelfCare and #selfcare and #SELFCARE today. '
                   || 'Not tags: example.com/page#section color#fff #2024 #___ '
                   || 'but #c3 is one, and #With_Under2 too.');
  perform set_config('t.post_tags1', v::text, false);
end $$;

reset role;
do $$ declare tags_found text[]; begin
  select coalesce(array_agg(t.tag order by t.tag), '{}') into tags_found
  from post_tags pt join tags t on t.id = pt.tag_id
  where pt.post_id = current_setting('t.post_tags1')::bigint;
  if tags_found <> array['c3', 'selfcare', 'with_under2'] then
    raise exception 'FAIL: parsed tags are % (expected c3, selfcare, with_under2)', tags_found;
  end if;
end $$;

-- 64-char truncation and the 30-distinct-tags cap.
set role authenticated;
do $$ declare v bigint; body text := ''; i integer; begin
  v := create_post('#' || repeat('a', 70));
  perform set_config('t.post_long', v::text, false);
  for i in 1..35 loop
    body := body || ' #tagnum' || i;
  end loop;
  v := create_post(body);
  perform set_config('t.post_stuffed', v::text, false);
end $$;
reset role;
do $$ declare n integer; begin
  if not exists (select 1 from post_tags pt join tags t on t.id = pt.tag_id
                 where pt.post_id = current_setting('t.post_long')::bigint
                   and t.tag = repeat('a', 64)) then
    raise exception 'FAIL: a 70-character tag was not truncated to 64';
  end if;
  select count(*) into n from post_tags
    where post_id = current_setting('t.post_stuffed')::bigint;
  if n <> 30 then
    raise exception 'FAIL: a 35-tag post indexed % tags (expected the 30 cap)', n;
  end if;
end $$;

-- ============================================================
-- 4. Mention policy and the notification cap.
-- ============================================================
-- Default (everyone): bea mentions ada -> participant row + ping.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000022', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000022","aal":"aal1","session_id":"sb"}', false);
do $$ declare v bigint; begin
  v := create_post('hello @ada from bea');
  perform set_config('t.post_mention1', v::text, false);
end $$;
reset role;
do $$ begin
  if not exists (select 1 from post_mentions
                 where post_id = current_setting('t.post_mention1')::bigint
                   and mentioned_user_id = '00000000-0000-0000-0000-000000000021') then
    raise exception 'FAIL: default-policy mention did not create a participant row';
  end if;
  if not exists (select 1 from notifications
                 where user_id = '00000000-0000-0000-0000-000000000021'
                   and type = 'mention'
                   and post_id = current_setting('t.post_mention1')::bigint) then
    raise exception 'FAIL: default-policy mention did not notify';
  end if;
end $$;

-- ada tightens to "People you follow": cat (whom ada does not follow)
-- can no longer reach her; dee (whom ada follows) still can.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000021","aal":"aal1","session_id":"sa"}', false);
update profiles set mention_policy = 'followed'
  where user_id = '00000000-0000-0000-0000-000000000021';
insert into follows (follower_id, followee_id) values
  ('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000024');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000023', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000023","aal":"aal1","session_id":"sc"}', false);
do $$ declare v bigint; begin
  v := create_post('hey @ada, from cat whom she does not follow');
  perform set_config('t.post_mention2', v::text, false);
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000024', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000024","aal":"aal1","session_id":"sd"}', false);
do $$ declare v bigint; begin
  v := create_post('hey @ada, from dee whom she follows');
  perform set_config('t.post_mention3', v::text, false);
end $$;
reset role;
do $$ begin
  if exists (select 1 from post_mentions
             where post_id = current_setting('t.post_mention2')::bigint) then
    raise exception 'FAIL: followed-policy let a non-followed account mention';
  end if;
  if exists (select 1 from notifications
             where post_id = current_setting('t.post_mention2')::bigint
               and type = 'mention') then
    raise exception 'FAIL: followed-policy let a non-followed mention notify';
  end if;
  if not exists (select 1 from post_mentions
                 where post_id = current_setting('t.post_mention3')::bigint
                   and mentioned_user_id = '00000000-0000-0000-0000-000000000021') then
    raise exception 'FAIL: followed-policy blocked a followed account''s mention';
  end if;
end $$;

-- "No one": nothing lands, from anyone.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000021","aal":"aal1","session_id":"sa"}', false);
update profiles set mention_policy = 'no_one'
  where user_id = '00000000-0000-0000-0000-000000000021';
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000024', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000024","aal":"aal1","session_id":"sd"}', false);
do $$ declare v bigint; begin
  v := create_post('once more @ada, from dee');
  perform set_config('t.post_mention4', v::text, false);
end $$;
reset role;
do $$ begin
  if exists (select 1 from post_mentions
             where post_id = current_setting('t.post_mention4')::bigint) then
    raise exception 'FAIL: no_one policy still created a participant row';
  end if;
end $$;
-- Restore ada to the default for the rest of the suite.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000021","aal":"aal1","session_id":"sa"}', false);
update profiles set mention_policy = 'everyone'
  where user_id = '00000000-0000-0000-0000-000000000021';
reset role;

-- The per-post cap: a post mentioning 12 people pings exactly 10.
do $$ declare i integer; u uuid; begin
  for i in 1..12 loop
    u := ('00000000-0000-0000-0000-0000000000' || lpad((40 + i)::text, 2, '0'))::uuid;
    insert into auth.users (id, email) values (u, 'cap' || i || '@test');
    perform create_member(u, ('cap' || i || '@test')::citext, 'Cap Member', '1995-05-05'::date,
                          ('capmember' || i)::citext, null::inet, null::bytea, null::bytea,
                          '{}'::jsonb, false);
  end loop;
end $$;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000022', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000022","aal":"aal1","session_id":"sb"}', false);
do $$ declare v bigint; body text := 'calling'; i integer; begin
  for i in 1..12 loop
    body := body || ' @capmember' || i;
  end loop;
  v := create_post(body);
  perform set_config('t.post_masscall', v::text, false);
end $$;
reset role;
do $$ declare rows_n integer; notifs_n integer; begin
  select count(*) into rows_n from post_mentions
    where post_id = current_setting('t.post_masscall')::bigint;
  select count(*) into notifs_n from notifications
    where post_id = current_setting('t.post_masscall')::bigint and type = 'mention';
  if rows_n <> 12 then
    raise exception 'FAIL: mass-mention post has % participant rows (expected all 12)', rows_n;
  end if;
  if notifs_n <> 10 then
    raise exception 'FAIL: mass-mention post fired % pings (expected the 10 cap)', notifs_n;
  end if;
end $$;

-- ============================================================
-- 5. Plain reposts: counter, notification, refusals, feed walls.
-- ============================================================
-- cat reposts ada's tagged post; ada is notified; the count moves.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000023', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000023","aal":"aal1","session_id":"sc"}', false);
insert into reshares (user_id, post_id)
  values ('00000000-0000-0000-0000-000000000023', current_setting('t.post_tags1')::bigint);
reset role;
do $$ begin
  if (select reshare_count from posts where id = current_setting('t.post_tags1')::bigint) <> 1 then
    raise exception 'FAIL: reshare_count did not increment';
  end if;
  if not exists (select 1 from notifications
                 where user_id = '00000000-0000-0000-0000-000000000021'
                   and actor_id = '00000000-0000-0000-0000-000000000023'
                   and type = 'reshare') then
    raise exception 'FAIL: the author was not notified of the repost';
  end if;
end $$;

-- You cannot repost your own post.
set role authenticated;
do $$ begin
  begin
    insert into reshares (user_id, post_id)
      values ('00000000-0000-0000-0000-000000000023', current_setting('t.post_mention2')::bigint);
    raise exception 'FAIL: a member reposted her own post';
  exception when insufficient_privilege or check_violation then null;
  end;
end $$;

-- dee follows cat only; cat's repost carries ada's post into dee's
-- feed, attributed, exactly once.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000024', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000024","aal":"aal1","session_id":"sd"}', false);
insert into follows (follower_id, followee_id) values
  ('00000000-0000-0000-0000-000000000024', '00000000-0000-0000-0000-000000000023');
do $$ declare n integer; row record; begin
  select count(*) into n from feed_following(null, 50, null) ff
    where ff.id = current_setting('t.post_tags1')::bigint;
  if n <> 1 then
    raise exception 'FAIL: the reposted post appears % times in the follower feed (expected 1)', n;
  end if;
  select * into row from feed_following(null, 50, null) ff
    where ff.id = current_setting('t.post_tags1')::bigint;
  if row.reshared_by <> '["cat"]'::jsonb then
    raise exception 'FAIL: repost attribution is % (expected ["cat"])', row.reshared_by;
  end if;
  if row.viewer_follows then
    raise exception 'FAIL: viewer_follows is true for an unfollowed reposted author';
  end if;
end $$;

-- A block between the REPOSTER and the AUTHOR dissolves the repost
-- for everyone (design §17's fourth wall).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000021","aal":"aal1","session_id":"sa"}', false);
insert into blocks (blocker_id, blocked_id) values
  ('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000023');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000024', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000024","aal":"aal1","session_id":"sd"}', false);
do $$ begin
  if exists (select 1 from feed_following(null, 50, null) ff
             where ff.id = current_setting('t.post_tags1')::bigint) then
    raise exception 'FAIL: a repost survives a block between reposter and author';
  end if;
end $$;
-- And with the block up, bea cannot repost ada's post at all.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000023', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000023","aal":"aal1","session_id":"sc"}', false);
do $$ begin
  -- Undo the earlier repost first (plain statement, outside any
  -- exception scope so it is not rolled back by the refusal below)…
  delete from reshares where user_id = '00000000-0000-0000-0000-000000000023';
end $$;
do $$ begin
  -- …then the blocked insert must refuse.
  begin
    insert into reshares (user_id, post_id)
      values ('00000000-0000-0000-0000-000000000023', current_setting('t.post_long')::bigint);
    raise exception 'FAIL: a blocked member reposted across the block';
  exception when insufficient_privilege or check_violation then null;
  end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000021","aal":"aal1","session_id":"sa"}', false);
delete from blocks where blocker_id = '00000000-0000-0000-0000-000000000021';
reset role;

-- Deleting a repost decrements the count.
do $$ begin
  if (select reshare_count from posts where id = current_setting('t.post_tags1')::bigint) <> 0 then
    raise exception 'FAIL: reshare_count did not decrement after undo';
  end if;
end $$;

-- profile_posts interleaves a repost, marked as one.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000023', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000023","aal":"aal1","session_id":"sc"}', false);
insert into reshares (user_id, post_id)
  values ('00000000-0000-0000-0000-000000000023', current_setting('t.post_mention1')::bigint);
do $$ declare row record; begin
  select * into row from profile_posts('00000000-0000-0000-0000-000000000023', false, null, 50, null) pp
    where pp.id = current_setting('t.post_mention1')::bigint;
  if row is null then
    raise exception 'FAIL: a repost does not appear in the reposter''s Posts tab';
  end if;
  if not row.is_reshare then
    raise exception 'FAIL: the profile repost row is not marked is_reshare';
  end if;
  if row.author_handle <> 'bea' then
    raise exception 'FAIL: the repost card does not carry the original author';
  end if;
end $$;

-- ============================================================
-- 6. Quote-posts: first-class, notified, and degrading honestly.
-- ============================================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000022', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000022","aal":"aal1","session_id":"sb"}', false);
do $$ declare v bigint; begin
  v := create_post('adding my own words to this', null, 'everyone',
                   current_setting('t.post_mention3')::bigint);
  perform set_config('t.post_quote', v::text, false);
end $$;
reset role;
do $$ begin
  if (select quoted_post_id from posts where id = current_setting('t.post_quote')::bigint)
     is distinct from current_setting('t.post_mention3')::bigint then
    raise exception 'FAIL: the quote post does not carry quoted_post_id';
  end if;
  if not exists (select 1 from notifications
                 where user_id = '00000000-0000-0000-0000-000000000024'
                   and actor_id = '00000000-0000-0000-0000-000000000022'
                   and type = 'quote'
                   and post_id = current_setting('t.post_quote')::bigint) then
    raise exception 'FAIL: the quoted author was not notified';
  end if;
end $$;

-- The embedded card resolves in the thread view…
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000023', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000023","aal":"aal1","session_id":"sc"}', false);
do $$ declare q jsonb; begin
  select gt.quoted into q from get_thread(current_setting('t.post_quote')::bigint) gt
    where gt.id = current_setting('t.post_quote')::bigint;
  if q is null or (q ->> 'unavailable')::boolean then
    raise exception 'FAIL: a live quoted post renders unavailable (%)', q;
  end if;
  if q ->> 'handle' <> 'dee' then
    raise exception 'FAIL: the quoted card carries the wrong author';
  end if;
end $$;

-- …and degrades to an unavailable stub when the original is deleted,
-- while the quote post itself (her own words) survives.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000024', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000024","aal":"aal1","session_id":"sd"}', false);
select delete_post(current_setting('t.post_mention3')::bigint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000023', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000023","aal":"aal1","session_id":"sc"}', false);
do $$ declare row record; begin
  select * into row from get_thread(current_setting('t.post_quote')::bigint) gt
    where gt.id = current_setting('t.post_quote')::bigint;
  if row is null or row.unavailable then
    raise exception 'FAIL: deleting the original destroyed the quoting member''s own post';
  end if;
  if not (row.quoted ->> 'unavailable')::boolean then
    raise exception 'FAIL: a deleted original still renders inside the quote';
  end if;
  if position('dee' in row.quoted::text) > 0 then
    raise exception 'FAIL: the unavailable stub leaks the deleted author';
  end if;
end $$;

-- A quote cannot also be a reply, and a blocked author cannot be quoted.
do $$ begin
  begin
    perform create_post('both at once', current_setting('t.post_mention1')::bigint,
                        'everyone', current_setting('t.post_mention1')::bigint);
    raise exception 'FAIL: a post was both a reply and a quote';
  exception when raise_exception then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000021","aal":"aal1","session_id":"sa"}', false);
insert into blocks (blocker_id, blocked_id) values
  ('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000022');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000022', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000022","aal":"aal1","session_id":"sb"}', false);
do $$ begin
  begin
    perform create_post('quoting across a block', null, 'everyone',
                        current_setting('t.post_tags1')::bigint);
    raise exception 'FAIL: a blocked member quoted across the block';
  exception when raise_exception then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000021","aal":"aal1","session_id":"sa"}', false);
delete from blocks where blocker_id = '00000000-0000-0000-0000-000000000021';
reset role;

-- ============================================================
-- 7. Tag surfaces: the page read, the search, and trending's
--    distinct-person arithmetic.
-- ============================================================
set role authenticated;
-- cat posts #zebra twice (one person); ada and bea each post #apple
-- (two people). Trending must put apple above zebra.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000023', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000023","aal":"aal1","session_id":"sc"}', false);
select create_post('first #zebra');
select create_post('second #zebra');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000021","aal":"aal1","session_id":"sa"}', false);
select create_post('an #apple a day');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000022', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000022","aal":"aal1","session_id":"sb"}', false);
select create_post('another #apple voice');

do $$ declare row record; begin
  select * into row from get_tag('#Apple');
  if row.tag <> 'apple' or row.status <> 'active' or row.post_count <> 2 then
    raise exception 'FAIL: get_tag(#Apple) returned %/%/%', row.tag, row.status, row.post_count;
  end if;
  select * into row from get_tag('#neverused');
  if row.post_count <> 0 or row.status <> 'active' then
    raise exception 'FAIL: an unused tag is not an honest empty active tag';
  end if;
end $$;

do $$ declare n integer; first_id bigint; begin
  select count(*) into n from feed_hashtag('apple', null, 50, null);
  if n <> 2 then
    raise exception 'FAIL: feed_hashtag(apple) returned % posts (expected 2)', n;
  end if;
  -- Newest first.
  select fh.id into first_id from feed_hashtag('apple', null, 50, null) fh limit 1;
  if (select p.author_id from posts p where p.id = first_id)
     <> '00000000-0000-0000-0000-000000000022' then
    raise exception 'FAIL: feed_hashtag is not newest-first';
  end if;
end $$;

-- A muted author's tagged posts disappear from the viewer's tag page.
do $$ declare n integer; begin
  insert into mutes (muter_id, muted_id) values
    ('00000000-0000-0000-0000-000000000022', '00000000-0000-0000-0000-000000000021');
  select count(*) into n from feed_hashtag('apple', null, 50, null);
  if n <> 1 then
    raise exception 'FAIL: a muted author still appears on the tag page';
  end if;
  delete from mutes where muter_id = '00000000-0000-0000-0000-000000000022';
end $$;

-- Tag search prefix-matches the canonical index.
do $$ declare found text[]; begin
  select coalesce(array_agg(st.tag order by st.tag), '{}') into found
    from search_tags('#ap') st;
  if found <> array['apple'] then
    raise exception 'FAIL: search_tags(#ap) found % (expected apple)', found;
  end if;
end $$;

-- Trending: distinct people, two beats one-posting-twice.
do $$ declare apple_people integer; zebra_people integer; apple_rank integer; zebra_rank integer; begin
  select tt.distinct_people into apple_people from get_trending_tags(20) tt where tt.tag = 'apple';
  select tt.distinct_people into zebra_people from get_trending_tags(20) tt where tt.tag = 'zebra';
  if apple_people <> 2 then
    raise exception 'FAIL: #apple counts % people (expected 2)', apple_people;
  end if;
  if zebra_people <> 1 then
    raise exception 'FAIL: #zebra counts % people (two posts, ONE person expected)', zebra_people;
  end if;
  select rank into apple_rank from (
    select tt.tag, row_number() over () as rank from get_trending_tags(20) tt) r
    where r.tag = 'apple';
  select rank into zebra_rank from (
    select tt.tag, row_number() over () as rank from get_trending_tags(20) tt) r
    where r.tag = 'zebra';
  if apple_rank > zebra_rank then
    raise exception 'FAIL: raw post volume outranked distinct people';
  end if;
end $$;

-- A repost of a tagged post counts the reposter as ONE participant.
reset role;
do $$ declare zp bigint; begin
  select p.id into zp from posts p
    join post_tags pt on pt.post_id = p.id
    join tags t on t.id = pt.tag_id
    where t.tag = 'zebra' order by p.id limit 1;
  perform set_config('t.post_zebra', zp::text, false);
end $$;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000024', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000024","aal":"aal1","session_id":"sd"}', false);
insert into reshares (user_id, post_id)
  values ('00000000-0000-0000-0000-000000000024', current_setting('t.post_zebra')::bigint);
reset role;
select compute_trending_tags();
set role authenticated;
do $$ declare zebra_people integer; begin
  select tt.distinct_people into zebra_people from get_trending_tags(20) tt where tt.tag = 'zebra';
  if zebra_people <> 2 then
    raise exception 'FAIL: a repost did not count its reposter as a tag participant (%)', zebra_people;
  end if;
end $$;
reset role;

-- ============================================================
-- 8. Tag suppression: tiers, effects, audit.
-- ============================================================
set role authenticated;
-- A plain member cannot suppress anything.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000021","aal":"aal1","session_id":"sa"}', false);
do $$ begin
  begin
    perform mod_detrend_tag('apple');
    raise exception 'FAIL: a plain member de-trended a tag';
  exception when raise_exception then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

-- A moderator can de-trend but not block; de-trend removes the tag
-- from trending and search while its page stays readable.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000025', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000025","aal":"aal1","session_id":"sm"}', false);
select mod_detrend_tag('apple', 'coordinated spike');
do $$ declare n integer; begin
  if exists (select 1 from get_trending_tags(20) tt where tt.tag = 'apple') then
    raise exception 'FAIL: a de-trended tag still trends';
  end if;
  if exists (select 1 from search_tags('#ap') st where st.tag = 'apple') then
    raise exception 'FAIL: a de-trended tag is still suggested in search';
  end if;
  select count(*) into n from feed_hashtag('apple', null, 50, null);
  if n < 1 then
    raise exception 'FAIL: a de-trended tag''s page went dark (block-tier effect)';
  end if;
  begin
    perform mod_block_tag('apple');
    raise exception 'FAIL: a moderator blocked a tag (admin action)';
  exception when raise_exception then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

-- The Owner (admin tier and above) can block; the page goes dark; a
-- moderator cannot lift a block; the Owner can; everything audited.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"ow"}', false);
select mod_block_tag('apple', 'tag itself abusive (test)');
do $$ declare n integer; st tag_status; begin
  select count(*) into n from feed_hashtag('apple', null, 50, null);
  if n <> 0 then
    raise exception 'FAIL: a blocked tag still lists posts';
  end if;
  select gt.status into st from get_tag('apple') gt;
  if st <> 'blocked' then
    raise exception 'FAIL: get_tag does not report the blocked status';
  end if;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000025', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000025","aal":"aal1","session_id":"sm"}', false);
do $$ begin
  begin
    perform mod_reinstate_tag('apple');
    raise exception 'FAIL: a moderator lifted an admin block';
  exception when raise_exception then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"ow"}', false);
select mod_reinstate_tag('apple', 'lifted (test)');
reset role;
do $$ begin
  if (select status from tags where tag = 'apple') <> 'active' then
    raise exception 'FAIL: reinstate did not restore the tag';
  end if;
  if (select count(*) from audit_log
      where action in ('tag.detrend', 'tag.block', 'tag.reinstate')) < 3 then
    raise exception 'FAIL: tag suppression actions are not audited';
  end if;
end $$;

-- Staff lookup carries the brigade signal fields.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000025', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000025","aal":"aal1","session_id":"sm"}', false);
do $$ declare row record; begin
  select * into row from mod_tag_lookup('apple', 5);
  if row is null then
    raise exception 'FAIL: mod_tag_lookup finds nothing for apple';
  end if;
  if row.people_48h < 2 or row.new_account_share is null then
    raise exception 'FAIL: mod_tag_lookup signals are wrong (% / %)', row.people_48h, row.new_account_share;
  end if;
end $$;
-- A plain member gets nothing from the staff lookup.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000021","aal":"aal1","session_id":"sa"}', false);
do $$ begin
  if exists (select 1 from mod_tag_lookup('apple', 5)) then
    raise exception 'FAIL: a plain member can read the staff tag lookup';
  end if;
end $$;
reset role;

rollback;
\echo PASS: 14-phase2f (hashtags, mentions policy + cap, reposts, quotes, trending, tag suppression)
