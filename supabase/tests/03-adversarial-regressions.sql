-- Adversarial regression suite, written independently by Grove-Test (QA),
-- NOT by the author of migration 0013. Confirms behaviors the author
-- claimed but that 01-smoke/02-social-smoke did not directly exercise.
-- Everything in THIS file is expected to PASS today — it hardens the
-- suite against regressions in properties that already hold. Confirmed
-- VULNERABILITIES found during this adversarial pass live in
-- 04-known-vulnerabilities.sql instead, because they currently fail and
-- must not be silently masked by folding them in here.
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000003', 'ada@test'),
  ('00000000-0000-0000-0000-000000000004', 'bea@test'),
  ('00000000-0000-0000-0000-000000000005', 'cat@test'),
  ('00000000-0000-0000-0000-000000000007', 'system@test'),
  ('00000000-0000-0000-0000-000000000008', 'eve@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_system_account('00000000-0000-0000-0000-000000000007', 'herciety');
select create_member('00000000-0000-0000-0000-000000000003', 'ada@test', 'Ada Lovelace', '1995-05-05', 'ada', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000004', 'bea@test', 'Bea Arthur',   '1995-05-05', 'bea', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000005', 'cat@test', 'Cat Stevens',  '1995-05-05', 'cat', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000008', 'eve@test', 'Eve Evangelista', '1995-05-05', 'eve', null, null, null, '{}'::jsonb, false);

-- ============================================================
-- 1. Impersonation: a member cannot write a social-graph row with
--    someone ELSE's id in the "owner" column of the row, on every
--    table that allows own-row direct writes.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ begin
  begin
    insert into follows (follower_id, followee_id)
    values ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000005');
    raise exception 'FAIL: bea made ada follow cat (impersonation)';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into mutes (muter_id, muted_id)
    values ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000005');
    raise exception 'FAIL: bea muted on ada''s behalf';
  exception when others then if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    insert into blocks (blocker_id, blocked_id)
    values ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000005');
    raise exception 'FAIL: bea blocked on ada''s behalf';
  exception when others then if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    insert into hidden_accounts (hider_id, hidden_id)
    values ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000005');
    raise exception 'FAIL: bea hid an account on ada''s behalf';
  exception when others then if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    insert into notifications (user_id, actor_id, type)
    values ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001', 'follow');
    raise exception 'FAIL: bea forged a notification to herself';
  exception when others then if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    insert into post_mentions (post_id, mentioned_user_id) values (1, '00000000-0000-0000-0000-000000000004');
    raise exception 'FAIL: bea wrote post_mentions directly';
  exception when others then if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
reset role;

-- ============================================================
-- 2. Cross-member writes to notifications.read_at and profiles.display_name
--    affect zero rows: the column grant is real, but RLS still scopes it
--    to the caller's own row. (01-smoke only proves the TRIGGER rejects a
--    fabricated name under the subject's OWN session; this proves a
--    DIFFERENT member's session cannot move the needle on someone else's
--    row at all, which is the more realistic attack shape.)
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare n int; begin
  update notifications set read_at = now() where user_id = '00000000-0000-0000-0000-000000000003';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: bea marked ada''s notification read (% rows)', n; end if;
  update profiles set display_name = 'Totally Fake Name' where user_id = '00000000-0000-0000-0000-000000000003';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: bea changed ada''s display_name cross-session (% rows)', n; end if;
end $$;
reset role;
do $$ declare d text; begin
  select display_name into d from profiles where user_id = '00000000-0000-0000-0000-000000000003';
  if d is not null and d = 'Totally Fake Name' then
    raise exception 'FAIL: cross-member display_name write landed';
  end if;
end $$;

-- ============================================================
-- 3. hidden_accounts / mutes are undiscoverable BY THE TARGET, even
--    though real rows exist against her (RLS scopes select to the
--    initiator's own rows only, not the target's).
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
insert into hidden_accounts (hider_id, hidden_id) values
  ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000003');
insert into mutes (muter_id, muted_id) values
  ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000003');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ declare n int; begin
  select count(*) into n from hidden_accounts where hidden_id = '00000000-0000-0000-0000-000000000003';
  if n <> 0 then raise exception 'FAIL: ada can see % row(s) of being hidden by someone', n; end if;
  select count(*) into n from mutes where muted_id = '00000000-0000-0000-0000-000000000003';
  if n <> 0 then raise exception 'FAIL: ada can see % row(s) of being muted by someone', n; end if;
end $$;
reset role;

-- ============================================================
-- 4. Shared-thread block isolation, BOTH directions: when two blocked
--    members both reply to a third party's post, each one's own reply
--    renders normally to her, and the other's tombstones — proven for
--    BOTH sides of the block, not just one (02-social-smoke only
--    checked the blocked member's view).
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
insert into blocks (blocker_id, blocked_id) values
  ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000005');
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000008', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000008","aal":"aal1","session_id":"se"}', false);
do $$ declare v bigint; begin
  v := create_post('Eve shared root for mutual-block thread test.');
  perform set_config('t.root', v::text, false);
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ declare v bigint; begin
  v := create_post('ada reply on the shared thread', current_setting('t.root')::bigint);
  perform set_config('t.ada_reply', v::text, false);
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ declare v bigint; begin
  v := create_post('cat reply on the shared thread', current_setting('t.root')::bigint);
  perform set_config('t.cat_reply', v::text, false);
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ declare r record; begin
  select * into r from get_thread(current_setting('t.root')::bigint) where id = current_setting('t.cat_reply')::bigint;
  if not r.unavailable or r.author_handle <> '' then
    raise exception 'FAIL: ada can see cat''s reply in a thread they both posted to';
  end if;
  select * into r from get_thread(current_setting('t.root')::bigint) where id = current_setting('t.ada_reply')::bigint;
  if r.unavailable or r.author_handle <> 'ada' then
    raise exception 'FAIL: ada''s own reply is wrongly hidden from herself';
  end if;
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ declare r record; begin
  select * into r from get_thread(current_setting('t.root')::bigint) where id = current_setting('t.ada_reply')::bigint;
  if not r.unavailable or r.author_handle <> '' then
    raise exception 'FAIL: cat can see ada''s reply in a thread they both posted to';
  end if;
  select * into r from get_thread(current_setting('t.root')::bigint) where id = current_setting('t.cat_reply')::bigint;
  if r.unavailable or r.author_handle <> 'cat' then
    raise exception 'FAIL: cat''s own reply is wrongly hidden from herself';
  end if;
  -- Nested reply directly onto the blocked party's reply, two levels
  -- deep inside a thread they do not otherwise share, is also refused.
  begin
    perform create_post('replying straight onto ada''s nested reply', current_setting('t.ada_reply')::bigint);
    raise exception 'FAIL: cat replied onto ada''s nested reply despite the mutual block';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
reset role;

-- ============================================================
-- 5. Mentions never cross a block, and repeated mentions of the same
--    handle in one post dedupe to a single row/notification.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ declare v bigint; begin
  v := create_post('shout out to @ada even across our block');
  perform set_config('t.mention_post', v::text, false);
end $$;
reset role;
do $$ declare n int; begin
  select count(*) into n from post_mentions where post_id = current_setting('t.mention_post')::bigint;
  if n <> 0 then raise exception 'FAIL: a mention crossed a mutual block'; end if;
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000008', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000008","aal":"aal1","session_id":"se"}', false);
do $$ declare v bigint; begin
  v := create_post('@bea @bea @bea repeated mentions of the same handle only once please');
  perform set_config('t.repeat_post', v::text, false);
end $$;
reset role;
do $$ declare n int; begin
  select count(*) into n from post_mentions where post_id = current_setting('t.repeat_post')::bigint;
  if n <> 1 then raise exception 'FAIL: repeated @bea mentions produced % rows, expected 1', n; end if;
  select count(*) into n from notifications where post_id = current_setting('t.repeat_post')::bigint and type = 'mention';
  if n <> 1 then raise exception 'FAIL: repeated @bea mentions produced % notifications, expected 1', n; end if;
end $$;

-- ============================================================
-- 6. file_report refuses a self-report.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ begin
  begin
    perform file_report('user', null, '00000000-0000-0000-0000-000000000004', 'other', null);
    raise exception 'FAIL: self-report accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
reset role;

rollback;
\echo ALL ADVERSARIAL REGRESSION TESTS PASSED
