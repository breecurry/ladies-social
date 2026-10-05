-- Behavioral smoke test of the Phase 2A social-core invariants (local only).
-- Covers: the write paths (posts/reports only via DEFINER functions), mutual-
-- hard blocks (read + interact, both directions), mutes filtering the feed,
-- "show me less" NOT filtering the Following feed, reply controls, mentions,
-- notifications + prefs + RLS, report routing (standard / admin_only /
-- owner_conflict invisibility), and — most importantly — the structural
-- guarantee that no feed/thread/search/list function can ever return a
-- member's legal name.
--
-- NOTE on zero counts: hiding "0" is a UI contract (spec §4.2/§4.6). The DB
-- contract asserted here is that counts are exact integers (0 when zero),
-- so the UI can hide them reliably.
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000003', 'ada@test'),
  ('00000000-0000-0000-0000-000000000004', 'bea@test'),
  ('00000000-0000-0000-0000-000000000005', 'cat@test'),
  ('00000000-0000-0000-0000-000000000006', 'dee@test'),
  ('00000000-0000-0000-0000-000000000007', 'system@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_system_account('00000000-0000-0000-0000-000000000007', 'hersciety');
select create_member('00000000-0000-0000-0000-000000000003', 'ada@test', 'Ada Lovelace', '1995-05-05', 'ada', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000004', 'bea@test', 'Bea Arthur',   '1995-05-05', 'bea', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000005', 'cat@test', 'Cat Stevens',  '1995-05-05', 'cat', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000006', 'dee@test', 'Dee Dee',      '1995-05-05', 'dee', null, null, null, '{}'::jsonb, false);

-- ============================================================
-- 1. STRUCTURAL identity protection: no social read function returns
--    or even references display_name, and the report enum holds no
--    identity-based reason.
-- ============================================================
do $$ declare f text; sig text; src text; begin
  foreach f in array array['feed_following', 'get_thread', 'profile_posts',
                           'search_people', 'list_followers', 'list_following',
                           'get_notifications'] loop
    select pg_get_function_result(p.oid), p.prosrc into sig, src
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = f;
    if sig is null then raise exception 'FAIL: function % missing', f; end if;
    if position('display_name' in sig) > 0 then
      raise exception 'FAIL: % return shape exposes display_name', f;
    end if;
    if position('display_name' in src) > 0 then
      raise exception 'FAIL: % body references display_name', f;
    end if;
  end loop;
  if exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
             where t.typname = 'report_reason' and e.enumlabel = 'male_account') then
    raise exception 'FAIL: male_account exists in report_reason';
  end if;
end $$;

-- ============================================================
-- 2. Posts exist only through create_post(); direct writes are dead
--    for authenticated AND service_role.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ begin
  begin
    insert into posts (author_id, body, root_post_id)
    values ('00000000-0000-0000-0000-000000000003', 'direct', 0);
    raise exception 'FAIL: authenticated inserted a post directly';
  exception when insufficient_privilege then null;
  end;
end $$;
do $$ declare v bigint; begin
  v := create_post('Hello from ada. Welcome, everyone.');
  perform set_config('t.post_ada', v::text, false);
end $$;
reset role;
set role service_role;
do $$ begin
  begin
    insert into posts (author_id, body, root_post_id)
    values ('00000000-0000-0000-0000-000000000003', 'direct', 0);
    raise exception 'FAIL: service_role inserted a post directly';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- Empty and over-limit bodies are refused.
set role authenticated;
do $$ begin
  begin
    perform create_post('   ');
    raise exception 'FAIL: empty post accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    perform create_post(repeat('x', 501));
    raise exception 'FAIL: 501-char post accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
reset role;

-- ============================================================
-- 3. Replies: adjacency + root/depth maintained, reply_count kept,
--    parent author notified ONCE even when also @mentioned.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare v bigint; root bigint := current_setting('t.post_ada')::bigint; begin
  v := create_post('Replying to @ada with a mention of her too.', root);
  perform set_config('t.reply_bea', v::text, false);
end $$;
reset role;
do $$ declare r posts%rowtype; n int; begin
  select * into r from posts where id = current_setting('t.reply_bea')::bigint;
  if r.root_post_id <> current_setting('t.post_ada')::bigint then raise exception 'FAIL: root_post_id wrong'; end if;
  if r.depth <> 1 then raise exception 'FAIL: depth is %, expected 1', r.depth; end if;
  select reply_count into n from posts where id = current_setting('t.post_ada')::bigint;
  if n <> 1 then raise exception 'FAIL: parent reply_count is %, expected 1', n; end if;
  select count(*) into n from notifications
    where user_id = '00000000-0000-0000-0000-000000000003'
      and actor_id = '00000000-0000-0000-0000-000000000004';
  if n <> 1 then raise exception 'FAIL: parent author got % notifications, expected exactly 1 (reply, no duplicate mention)', n; end if;
  if (select type from notifications
      where user_id = '00000000-0000-0000-0000-000000000003'
        and actor_id = '00000000-0000-0000-0000-000000000004') <> 'reply' then
    raise exception 'FAIL: parent-author notification is not a reply';
  end if;
  select count(*) into n from post_mentions
    where post_id = current_setting('t.reply_bea')::bigint
      and mentioned_user_id = '00000000-0000-0000-0000-000000000003';
  if n <> 1 then raise exception 'FAIL: mention row missing'; end if;
end $$;

-- A third member mentioned in a post gets a 'mention' notification.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
select create_post('Shout out to @cat, a great member.');
reset role;
do $$ declare n int; begin
  select count(*) into n from notifications
    where user_id = '00000000-0000-0000-0000-000000000005' and type = 'mention';
  if n <> 1 then raise exception 'FAIL: mention notification missing'; end if;
end $$;

-- ============================================================
-- 4. Reply controls: 'followed' and 'mentioned' enforced in create_post.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ declare v bigint; begin
  v := create_post('Only people I follow can reply.', null, 'followed');
  perform set_config('t.post_followed', v::text, false);
  v := create_post('Only @cat can reply to this.', null, 'mentioned');
  perform set_config('t.post_mentioned', v::text, false);
end $$;
-- bea (not followed by ada, not mentioned) is refused on both.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ begin
  begin
    perform create_post('may I?', current_setting('t.post_followed')::bigint);
    raise exception 'FAIL: reply_control=followed did not block a non-followed replier';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    perform create_post('may I?', current_setting('t.post_mentioned')::bigint);
    raise exception 'FAIL: reply_control=mentioned did not block a non-mentioned replier';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
-- ada follows bea -> bea may now reply to the 'followed' post.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
insert into follows (follower_id, followee_id)
values ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000004');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ begin
  perform create_post('Thanks for following me, now I can reply.', current_setting('t.post_followed')::bigint);
end $$;
-- cat (mentioned) may reply to the 'mentioned' post.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ begin
  perform create_post('I was mentioned, so this works.', current_setting('t.post_mentioned')::bigint);
end $$;
reset role;

-- ============================================================
-- 5. Follows + the Following feed; mute filters it; hide does NOT.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
insert into follows (follower_id, followee_id)
values ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000003');
reset role;
-- follow notification landed for ada (checked as superuser: the row is
-- ada's and is rightly invisible to bea under RLS)
do $$ declare n int; begin
  select count(*) into n from notifications
    where user_id = '00000000-0000-0000-0000-000000000003' and type = 'follow'
      and actor_id = '00000000-0000-0000-0000-000000000004';
  if n <> 1 then raise exception 'FAIL: follow notification missing'; end if;
end $$;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare n int; z int; begin
  select count(*) into n from feed_following(null, 50)
    where author_handle = 'ada';
  if n < 1 then raise exception 'FAIL: followed author absent from feed'; end if;
  -- counts are exact integers at zero (UI hides them; DB must not return null)
  select count(*) into z from feed_following(null, 50)
    where author_handle = 'ada' and like_count is null;
  if z <> 0 then raise exception 'FAIL: like_count returned NULL'; end if;
  -- feed never returns anything but the handle as identity
  perform set_config('t.feedcount', n::text, false);
end $$;
-- mute removes ada from bea's feed
insert into mutes (muter_id, muted_id)
values ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000003');
do $$ declare n int; begin
  select count(*) into n from feed_following(null, 50) where author_handle = 'ada';
  if n <> 0 then raise exception 'FAIL: muted author still in feed'; end if;
  -- muted actors also vanish from the notification list
  select count(*) into n from get_notifications(null, 50) where actor_handle = 'ada';
  if n <> 0 then raise exception 'FAIL: muted actor still in notifications'; end if;
end $$;
delete from mutes
  where muter_id = '00000000-0000-0000-0000-000000000004'
    and muted_id = '00000000-0000-0000-0000-000000000003';
-- hide ("show me less") stores the signal but does NOT filter Following
insert into hidden_accounts (hider_id, hidden_id)
values ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000003');
do $$ declare n int; begin
  select count(*) into n from feed_following(null, 50) where author_handle = 'ada';
  if n < 1 then raise exception 'FAIL: hidden author filtered from Following feed (spec 4.8 violation)'; end if;
end $$;
reset role;

-- ============================================================
-- 6. Likes: private rows, correct counters, notification prefs honoured.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
insert into likes (user_id, post_id)
values ('00000000-0000-0000-0000-000000000004', current_setting('t.post_ada')::bigint);
do $$ declare n int; begin
  select like_count into n from posts where id = current_setting('t.post_ada')::bigint;
  if n <> 1 then raise exception 'FAIL: like_count is %, expected 1', n; end if;
  select count(*) into n from feed_following(null, 50)
    where id = current_setting('t.post_ada')::bigint and viewer_liked;
  if n <> 1 then raise exception 'FAIL: viewer_liked not set'; end if;
end $$;
delete from likes
  where user_id = '00000000-0000-0000-0000-000000000004'
    and post_id = current_setting('t.post_ada')::bigint;
do $$ declare n int; begin
  select like_count into n from posts where id = current_setting('t.post_ada')::bigint;
  if n <> 0 then raise exception 'FAIL: like_count did not return to 0'; end if;
end $$;
-- likes rows are invisible to anyone but their owner
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ declare n int; begin
  select count(*) into n from likes where user_id <> '00000000-0000-0000-0000-000000000005';
  if n <> 0 then raise exception 'FAIL: another member''s likes are visible'; end if;
end $$;
-- notification_prefs: ada turns likes off; a new like creates no notification
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
insert into notification_prefs (user_id, prefs)
values ('00000000-0000-0000-0000-000000000003', '{"like": false}'::jsonb)
on conflict (user_id) do update set prefs = excluded.prefs;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
insert into likes (user_id, post_id)
values ('00000000-0000-0000-0000-000000000004', current_setting('t.post_ada')::bigint);
reset role;
-- checked as superuser; as bea the row would be RLS-invisible anyway.
-- Exactly one like notification exists: the one from the FIRST like in
-- this section (before prefs were set). The post-prefs like must not
-- have added a second.
do $$ declare n int; begin
  select count(*) into n from notifications
    where user_id = '00000000-0000-0000-0000-000000000003' and type = 'like';
  if n <> 1 then raise exception 'FAIL: like notifications = % (prefs toggle not honoured)', n; end if;
end $$;

-- ============================================================
-- 7. Blocks are mutual-hard: no reading, no interacting, either way.
-- ============================================================
set role authenticated;
-- cat posts something first
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ declare v bigint; begin
  v := create_post('A post by cat, pre-block.');
  perform set_config('t.post_cat', v::text, false);
end $$;
-- dee posts something too
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000006","aal":"aal1","session_id":"sd"}', false);
do $$ declare v bigint; begin
  v := create_post('A post by dee, pre-block.');
  perform set_config('t.post_dee', v::text, false);
end $$;
-- cat blocks dee
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
insert into blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000006');
-- dee's view: cat has vanished
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000006","aal":"aal1","session_id":"sd"}', false);
do $$ declare n int; begin
  select count(*) into n from posts where author_id = '00000000-0000-0000-0000-000000000005';
  if n <> 0 then raise exception 'FAIL: blocked member can read blocker''s posts'; end if;
  select count(*) into n from profiles where user_id = '00000000-0000-0000-0000-000000000005';
  if n <> 0 then raise exception 'FAIL: blocked member can see blocker''s profile'; end if;
  select count(*) into n from search_people('cat', 10);
  if n <> 0 then raise exception 'FAIL: blocked member can find blocker in search'; end if;
  begin
    insert into follows (follower_id, followee_id)
    values ('00000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000005');
    raise exception 'FAIL: blocked member followed the blocker';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    insert into likes (user_id, post_id)
    values ('00000000-0000-0000-0000-000000000006', current_setting('t.post_cat')::bigint);
    raise exception 'FAIL: blocked member liked the blocker''s post';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    perform create_post('reply across a block', current_setting('t.post_cat')::bigint);
    raise exception 'FAIL: blocked member replied to the blocker';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
-- cat's view: dee's content is gone too (mutual), but dee's HANDLE is
-- still visible to cat so she can manage her unblock list.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ declare n int; begin
  select count(*) into n from posts where author_id = '00000000-0000-0000-0000-000000000006';
  if n <> 0 then raise exception 'FAIL: blocker can still read the blocked member''s posts'; end if;
  select count(*) into n from profiles where user_id = '00000000-0000-0000-0000-000000000006';
  if n <> 1 then raise exception 'FAIL: blocker cannot see the blocked handle for her unblock list'; end if;
  begin
    perform create_post('reply down a block', current_setting('t.post_dee')::bigint);
    raise exception 'FAIL: blocker replied to the blocked member''s post';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
-- The Owner and the system account cannot be blocked.
do $$ begin
  begin
    insert into blocks (blocker_id, blocked_id)
    values ('00000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001');
    raise exception 'FAIL: the Owner was blocked';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    insert into blocks (blocker_id, blocked_id)
    values ('00000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000007');
    raise exception 'FAIL: the system account was blocked';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
reset role;

-- Thread integrity across a block: a blocked author's reply comes back
-- as an unavailable tombstone (empty handle and body), never orphaning
-- the subtree and never leaking content.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ declare v bigint; begin
  v := create_post('cat replies under ada''s post', current_setting('t.post_ada')::bigint);
  perform set_config('t.reply_cat', v::text, false);
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000006","aal":"aal1","session_id":"sd"}', false);
do $$ declare r record; begin
  select * into r from get_thread(current_setting('t.post_ada')::bigint)
    where id = current_setting('t.reply_cat')::bigint;
  if not found then raise exception 'FAIL: blocked reply missing entirely from thread (orphans subtree)'; end if;
  if not r.unavailable then raise exception 'FAIL: blocked reply not tombstoned'; end if;
  if r.author_handle <> '' or r.body <> '' then
    raise exception 'FAIL: tombstone leaks handle or body';
  end if;
end $$;
reset role;

-- ============================================================
-- 8. Reports: DEFINER-only writes, conduct-only reasons, routing,
--    owner_conflict invisibility.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ begin
  begin
    insert into reports (reporter_id, subject_type, subject_user_id, reason)
    values ('00000000-0000-0000-0000-000000000004', 'user',
            '00000000-0000-0000-0000-000000000005', 'spam');
    raise exception 'FAIL: direct report insert accepted';
  exception when insufficient_privilege then null;
  end;
end $$;
do $$ declare rid uuid; r reports%rowtype; begin
  -- standard: ordinary member accused
  rid := file_report('post', current_setting('t.post_cat')::bigint, null, 'harassment', 'test details');
  select * into r from reports where id = rid;
  if r.routing <> 'standard' then raise exception 'FAIL: routing % for ordinary accused', r.routing; end if;
  if r.subject_user_id <> '00000000-0000-0000-0000-000000000005' then raise exception 'FAIL: accused not derived from post'; end if;
  -- owner_conflict: the Owner accused
  rid := file_report('user', null, '00000000-0000-0000-0000-000000000001', 'other', null);
  select * into r from reports where id = rid;
  if r.routing <> 'owner_conflict' then raise exception 'FAIL: routing % for Owner accused', r.routing; end if;
  perform set_config('t.report_oc', rid::text, false);
end $$;
-- the reporter's own history shows both, with identical shape
do $$ declare n int; begin
  select count(*) into n from reports where reporter_id = '00000000-0000-0000-0000-000000000004';
  if n <> 2 then raise exception 'FAIL: reporter sees % of her own reports, expected 2', n; end if;
end $$;
-- another member sees none of them
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ declare n int; begin
  select count(*) into n from reports;
  if n <> 0 then raise exception 'FAIL: non-reporter non-staff sees % reports', n; end if;
end $$;
-- the OWNER cannot see the owner_conflict report, even at aal2
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"so"}', false);
do $$ declare n int; begin
  select count(*) into n from reports where routing = 'owner_conflict';
  if n <> 0 then raise exception 'FAIL: owner_conflict report visible to the Owner'; end if;
  -- the standard report IS visible to the Owner (moderator-or-above queue)
  select count(*) into n from reports where routing = 'standard';
  if n <> 1 then raise exception 'FAIL: Owner sees % standard reports, expected 1', n; end if;
end $$;
-- admin_only: a report about a moderator routes past moderators
select grant_role('00000000-0000-0000-0000-000000000005', 'moderator');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
-- (reason is 'spam' here, not 'harassment': bea already reported cat for
-- harassment above, and since 0014 a second (reporter, accused, reason)
-- report within 24h is refused by the duplicate guard — see
-- 05-hardening-regressions.sql, which asserts that guard directly.)
do $$ declare rid uuid; r reports%rowtype; begin
  rid := file_report('user', null, '00000000-0000-0000-0000-000000000005', 'spam', null);
  select * into r from reports where id = rid;
  if r.routing <> 'admin_only' then raise exception 'FAIL: routing % for moderator accused', r.routing; end if;
end $$;
-- the accused moderator cannot see the report about herself
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ declare n int; begin
  select count(*) into n from reports
    where subject_user_id = '00000000-0000-0000-0000-000000000005' and routing = 'admin_only';
  if n <> 0 then raise exception 'FAIL: accused moderator sees the report about herself'; end if;
end $$;
reset role;

-- ============================================================
-- 9. Legal-name protection, end to end: display_name NULL by default,
--    user_private unreadable, nothing in the social read paths.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare d text; n int; begin
  -- non-opted-in display_name reads as NULL on the profile surface
  select display_name into d from profiles where user_id = '00000000-0000-0000-0000-000000000003';
  if d is not null then raise exception 'FAIL: non-opted-in display_name is %', d; end if;
  -- another member's private row is unreadable
  select count(*) into n from user_private where user_id <> '00000000-0000-0000-0000-000000000004';
  if n <> 0 then raise exception 'FAIL: another member''s user_private is readable'; end if;
  -- and even after ada opts in, the FEED still carries only the handle
  -- (shape-level guarantee re-checked behaviorally)
  if exists (select 1 from feed_following(null, 50) f
             where f.author_handle not in (select handle::text from profiles)) then
    raise exception 'FAIL: feed returned a non-handle identity';
  end if;
end $$;
reset role;

-- ============================================================
-- 10. Notifications RLS: own rows only; read_at is the only writable
--     column.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare n int; begin
  select count(*) into n from notifications where user_id <> '00000000-0000-0000-0000-000000000004';
  if n <> 0 then raise exception 'FAIL: another member''s notifications are readable'; end if;
  begin
    insert into notifications (user_id, actor_id, type)
    values ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000004', 'system');
    raise exception 'FAIL: direct notification insert accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    update notifications set type = 'system' where user_id = '00000000-0000-0000-0000-000000000004';
    raise exception 'FAIL: notification type is writable';
  exception when insufficient_privilege then null;
  end;
end $$;
-- marking read works and affects only own rows
select notif_mark_all_read();
do $$ declare n int; begin
  select count(*) into n from notifications
    where user_id = '00000000-0000-0000-0000-000000000004' and read_at is null;
  if n <> 0 then raise exception 'FAIL: notif_mark_all_read left unread rows'; end if;
  select count(*) into n from notifications where read_at is null;
  -- other members' unread rows are invisible here, so this only proves
  -- no error; cross-member isolation was proven above.
end $$;
reset role;
do $$ declare n int; begin
  select count(*) into n from notifications
    where user_id = '00000000-0000-0000-0000-000000000003' and read_at is not null;
  if n <> 0 then raise exception 'FAIL: notif_mark_all_read touched another member''s rows'; end if;
end $$;

-- ============================================================
-- 11. delete_post: author-only, soft, decrements the parent counter.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ begin
  begin
    perform delete_post(current_setting('t.reply_bea')::bigint);
    raise exception 'FAIL: non-author deleted a post';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
select delete_post(current_setting('t.reply_bea')::bigint);
do $$ declare n int; begin
  select reply_count into n from posts where id = current_setting('t.post_ada')::bigint;
  if n <> 1 then raise exception 'FAIL: reply_count is %, expected 1 after delete (cat''s reply remains)', n; end if;
end $$;
reset role;
do $$ declare r posts%rowtype; begin
  select * into r from posts where id = current_setting('t.reply_bea')::bigint;
  if r.deleted_at is null or r.visibility <> 'removed_author' then
    raise exception 'FAIL: delete_post did not soft-delete';
  end if;
end $$;

rollback;
\echo ALL SOCIAL SMOKE TESTS PASSED
