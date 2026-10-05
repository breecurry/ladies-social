-- Behavioral smoke test for migration 0026 (the profile Reposts tab
-- and the 40-character hashtag cap). Local only, like suites 01-14.
--
-- Headline properties:
--   - a hashtag of exactly 40 characters is live and indexed; 41 is
--     not a hashtag at all (nothing indexed, nothing truncated), and
--     the post itself still succeeds;
--   - the tags table refuses rows longer than 40 outright;
--   - profile_posts(p_reposts => true) returns ONLY the member's
--     reposts, newest repost first, and keeps every visibility wall:
--     a viewer-author block, a reposter-author block, and a suspended
--     original author all hide the row, exactly as in the Posts tab;
--   - the Posts and Replies tabs behave exactly as before;
--   - EXECUTE on the new signature is authenticated-only.
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000007', 'system@test'),
  ('00000000-0000-0000-0000-000000000031', 'eve@test'),
  ('00000000-0000-0000-0000-000000000032', 'fay@test'),
  ('00000000-0000-0000-0000-000000000033', 'gia@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_system_account('00000000-0000-0000-0000-000000000007', 'hersciety');
select create_member('00000000-0000-0000-0000-000000000031', 'eve@test', 'Eve One',  '1995-05-05', 'eve', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000032', 'fay@test', 'Fay Two',  '1995-05-05', 'fay', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000033', 'gia@test', 'Gia Three','1995-05-05', 'gia', null, null, null, '{}'::jsonb, false);

-- ============================================================
-- 1. The 40-character cap in create_post.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000031', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000031","aal":"aal1","session_id":"se"}', false);
do $$ declare v bigint; begin
  -- 40 characters: a real tag. 41: inert — the post still succeeds.
  v := create_post('edge #' || repeat('x', 40) || ' and #' || repeat('y', 41));
  perform set_config('t.post_cap', v::text, false);
end $$;
reset role;
do $$ begin
  if not exists (select 1 from post_tags pt join tags t on t.id = pt.tag_id
                 where pt.post_id = current_setting('t.post_cap')::bigint
                   and t.tag = repeat('x', 40)) then
    raise exception 'FAIL: a 40-character tag was not indexed';
  end if;
  if exists (select 1 from post_tags pt join tags t on t.id = pt.tag_id
             where pt.post_id = current_setting('t.post_cap')::bigint
               and t.tag like repeat('y', 40) || '%') then
    raise exception 'FAIL: a 41-character token was indexed (truncated or whole)';
  end if;
  if (select count(*) from post_tags
      where post_id = current_setting('t.post_cap')::bigint) <> 1 then
    raise exception 'FAIL: expected exactly one indexed tag on the cap post';
  end if;
end $$;

-- The table itself refuses an over-long tag.
do $$ begin
  begin
    insert into tags (tag) values (repeat('z', 41));
    raise exception 'FAIL: tags accepted a 41-character row';
  exception when check_violation then
    null; -- expected
  end;
end $$;

-- ============================================================
-- 2. The Reposts tab: only reposts, every wall intact.
-- ============================================================
-- fay posts; eve posts her own and reposts fay's.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000032', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000032","aal":"aal1","session_id":"sf"}', false);
do $$ declare v bigint; begin
  v := create_post('fay''s original post');
  perform set_config('t.post_fay', v::text, false);
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000031', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000031","aal":"aal1","session_id":"se"}', false);
do $$ declare v bigint; begin
  v := create_post('eve''s own post');
  perform set_config('t.post_eve', v::text, false);
end $$;
insert into reshares (user_id, post_id)
  values ('00000000-0000-0000-0000-000000000031', current_setting('t.post_fay')::bigint);

-- Reposts tab = exactly the one repost, marked, by the original author.
do $$ declare n integer; row record; begin
  select count(*) into n from profile_posts(
    p_user => '00000000-0000-0000-0000-000000000031', p_reposts => true);
  if n <> 1 then
    raise exception 'FAIL: the Reposts tab returned % rows (expected 1)', n;
  end if;
  select * into row from profile_posts(
    p_user => '00000000-0000-0000-0000-000000000031', p_reposts => true);
  if not row.is_reshare or row.author_handle <> 'fay'
     or row.id <> current_setting('t.post_fay')::bigint then
    raise exception 'FAIL: the Reposts tab row is not the marked repost of fay''s post';
  end if;
end $$;

-- Posts tab unchanged: eve's own posts (the cap post from section 1
-- and this one) AND the interleaved repost.
do $$ declare n integer; r integer; begin
  select count(*), count(*) filter (where is_reshare) into n, r
    from profile_posts(p_user => '00000000-0000-0000-0000-000000000031');
  if n <> 3 or r <> 1 then
    raise exception 'FAIL: the Posts tab returned % rows / % reposts (expected 3 / 1)', n, r;
  end if;
end $$;

-- A viewer who blocks the ORIGINAL author does not see the repost row.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000033', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000033","aal":"aal1","session_id":"sg"}', false);
insert into blocks (blocker_id, blocked_id)
  values ('00000000-0000-0000-0000-000000000033', '00000000-0000-0000-0000-000000000032');
do $$ declare n integer; begin
  select count(*) into n from profile_posts(
    p_user => '00000000-0000-0000-0000-000000000031', p_reposts => true);
  if n <> 0 then
    raise exception 'FAIL: a viewer-author block did not hide the repost (% rows)', n;
  end if;
end $$;
delete from blocks where blocker_id = '00000000-0000-0000-0000-000000000033';

-- A block between REPOSTER and original author hides the row for everyone.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000032', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000032","aal":"aal1","session_id":"sf"}', false);
insert into blocks (blocker_id, blocked_id)
  values ('00000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-000000000031');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000033', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000033","aal":"aal1","session_id":"sg"}', false);
do $$ declare n integer; begin
  select count(*) into n from profile_posts(
    p_user => '00000000-0000-0000-0000-000000000031', p_reposts => true);
  if n <> 0 then
    raise exception 'FAIL: a reposter-author block did not hide the repost (% rows)', n;
  end if;
end $$;
reset role;
delete from blocks where blocker_id = '00000000-0000-0000-0000-000000000032';

-- A suspended original author vanishes from the Reposts tab.
update profiles set status = 'suspended'
  where user_id = '00000000-0000-0000-0000-000000000032';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000033', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000033","aal":"aal1","session_id":"sg"}', false);
do $$ declare n integer; begin
  select count(*) into n from profile_posts(
    p_user => '00000000-0000-0000-0000-000000000031', p_reposts => true);
  if n <> 0 then
    raise exception 'FAIL: a suspended author''s post survives in the Reposts tab (% rows)', n;
  end if;
end $$;
reset role;
update profiles set status = 'active'
  where user_id = '00000000-0000-0000-0000-000000000032';

-- Replies tab ignores reposts entirely; the nonsense combo is empty.
set role authenticated;
do $$ declare n integer; begin
  select count(*) into n from profile_posts(
    p_user => '00000000-0000-0000-0000-000000000031', p_replies => true, p_reposts => true);
  if n <> 0 then
    raise exception 'FAIL: p_replies + p_reposts returned % rows (expected 0)', n;
  end if;
end $$;
reset role;

-- ============================================================
-- 3. EXECUTE lockdown on the new signature.
-- ============================================================
do $$ begin
  if has_function_privilege('anon',
       'profile_posts(uuid, boolean, boolean, timestamptz, integer, bigint)', 'execute') then
    raise exception 'FAIL: anon can execute profile_posts';
  end if;
  if not has_function_privilege('authenticated',
       'profile_posts(uuid, boolean, boolean, timestamptz, integer, bigint)', 'execute') then
    raise exception 'FAIL: authenticated cannot execute profile_posts';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'profile_posts'
               and pg_get_function_identity_arguments(p.oid)
                   = 'p_user uuid, p_replies boolean, p_before timestamp with time zone, p_limit integer, p_before_id bigint') then
    raise exception 'FAIL: the old profile_posts signature survives (ambiguous overload for PostgREST)';
  end if;
end $$;

rollback;
\echo PASS: 15-reposts-tab-and-tag-cap (Reposts tab walls, 40-char hashtag cap)
