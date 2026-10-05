-- Hardening regressions for migration 0014 (Grove-Code, 2026-10-06):
-- direct coverage for the audit/QA fixes that 02/03/04 do not already
-- assert — the follows_read block filter (P1-2), report rate limiting
-- and duplicate guarding (P2-1), the get_thread root block guard
-- (P2-2), the maximum reply depth (P2-4), parent-excerpt visibility
-- (P2-6) — plus structural EXECUTE-privilege guards (P1-3, P2-8) so a
-- future migration cannot quietly reopen the holes.
\set ON_ERROR_STOP on
set search_path = public, extensions;
begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000003', 'ada@test'),
  ('00000000-0000-0000-0000-000000000004', 'bea@test'),
  ('00000000-0000-0000-0000-000000000005', 'cat@test'),
  ('00000000-0000-0000-0000-000000000007', 'system@test'),
  ('00000000-0000-0000-0000-000000000008', 'eve@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_system_account('00000000-0000-0000-0000-000000000007', 'unitedfeminist');
select create_member('00000000-0000-0000-0000-000000000003', 'ada@test', 'Ada Lovelace', '1995-05-05', 'ada', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000004', 'bea@test', 'Bea Arthur',   '1995-05-05', 'bea', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000005', 'cat@test', 'Cat Stevens',  '1995-05-05', 'cat', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000008', 'eve@test', 'Eve Evangelista', '1995-05-05', 'eve', null, null, null, '{}'::jsonb, false);

-- Fixture: eve follows ada AND cat (pre-block), then ada blocks cat.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000008', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000008","aal":"aal1","session_id":"se"}', false);
insert into follows (follower_id, followee_id) values
  ('00000000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-000000000003'),
  ('00000000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-000000000005');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
insert into blocks (blocker_id, blocked_id) values
  ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000005');
reset role;

-- ============================================================
-- 1. P1-2: the follows table itself filters blocks. This was the worst
--    finding of the whole pass — list_followers()/list_following()
--    filtered correctly, but a direct PostgREST-style read of follows
--    let a blocked member enumerate her blocker's entire social graph.
-- ============================================================
-- cat (blocked by ada) reads follows directly, filtered on ada: nothing.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ declare n int; begin
  select count(*) into n from follows
    where followee_id = '00000000-0000-0000-0000-000000000003';
  if n <> 0 then
    raise exception 'FAIL (P1-2): blocked member enumerated her blocker''s follower list (% rows)', n;
  end if;
  select count(*) into n from follows
    where follower_id = '00000000-0000-0000-0000-000000000003';
  if n <> 0 then
    raise exception 'FAIL (P1-2): blocked member enumerated who her blocker follows (% rows)', n;
  end if;
end $$;
-- ...while an uninvolved member (bea) still sees the same rows: the
-- follow graph is member-visible (spec §7.2), just never across a block.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare n int; begin
  select count(*) into n from follows
    where followee_id = '00000000-0000-0000-0000-000000000003';
  if n <> 1 then
    raise exception 'FAIL: block filter over-hides — uninvolved member sees % follower rows, expected 1', n;
  end if;
end $$;
-- The blocker's side is filtered too: rows touching the person ada
-- blocked are gone from HER view of the graph (expected 0014 side
-- effect: pre-block follows disappear from both parties'' lists).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ declare n int; begin
  select count(*) into n from follows
    where followee_id = '00000000-0000-0000-0000-000000000005'
       or follower_id = '00000000-0000-0000-0000-000000000005';
  if n <> 0 then
    raise exception 'FAIL (P1-2): rows across a block remain visible to the blocker (% rows)', n;
  end if;
end $$;
reset role;

-- ============================================================
-- 2. P2-1: duplicate guard — one report per (reporter, accused,
--    reason) per 24h; a different reason still files.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare rid uuid; begin
  rid := file_report('user', null, '00000000-0000-0000-0000-000000000005', 'harassment', 'first');
  begin
    perform file_report('user', null, '00000000-0000-0000-0000-000000000005', 'harassment', 'again');
    raise exception 'FAIL (P2-1): duplicate (reporter, accused, reason) report accepted within 24h';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  -- a different reason about the same account is NOT a duplicate
  rid := file_report('user', null, '00000000-0000-0000-0000-000000000005', 'spam', null);
end $$;
reset role;

-- ============================================================
-- 3. P2-1: hourly cap — the 11th report inside an hour is refused,
--    calmly. (eve files 10 distinct (accused, reason) pairs first.)
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000008', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000008","aal":"aal1","session_id":"se"}', false);
do $$
declare
  accused uuid[] := array['00000000-0000-0000-0000-000000000003',
                          '00000000-0000-0000-0000-000000000004',
                          '00000000-0000-0000-0000-000000000005']::uuid[];
  reasons report_reason[] := array['harassment','hate','spam','impersonation']::report_reason[];
  filed int := 0;
  a uuid; r report_reason;
begin
  foreach a in array accused loop
    foreach r in array reasons loop
      exit when filed >= 10;
      perform file_report('user', null, a, r, null);
      filed := filed + 1;
    end loop;
    exit when filed >= 10;
  end loop;
  if filed <> 10 then
    raise exception 'FAIL: fixture only filed % reports', filed;
  end if;
  begin
    perform file_report('user', null, '00000000-0000-0000-0000-000000000001', 'other', null);
    raise exception 'FAIL (P2-1): 11th report within an hour was accepted (no rate limit)';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    if position('hour' in sqlerrm) = 0 then
      raise exception 'FAIL (P2-1): 11th report refused with the wrong error: %', sqlerrm;
    end if;
  end;
end $$;
reset role;

-- ============================================================
-- 4. P2-2: get_thread returns NOTHING — not a tombstone — when the
--    ROOT post's author is blocked either way, so the app 404s exactly
--    as it does for an id that never existed. Tombstones for blocked
--    authors WITHIN someone else's thread still work (no over-hiding).
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ declare v bigint; begin
  v := create_post('ada''s root post, invisible to cat as a whole thread');
  perform set_config('t.ada_root', v::text, false);
end $$;
-- cat (blocked): zero rows, indistinguishable from a nonexistent id
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ declare n int; begin
  select count(*) into n from get_thread(current_setting('t.ada_root')::bigint);
  if n <> 0 then
    raise exception 'FAIL (P2-2): get_thread returned % row(s) for a blocked author''s root post', n;
  end if;
end $$;
-- bea (uninvolved): the thread is there
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare n int; begin
  select count(*) into n from get_thread(current_setting('t.ada_root')::bigint);
  if n < 1 then raise exception 'FAIL: root guard over-hides an unblocked thread'; end if;
end $$;
-- and inside EVE's thread, ada's reply still tombstones for cat
-- rather than vanishing (structure preserved, content hidden).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000008', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000008","aal":"aal1","session_id":"se"}', false);
do $$ declare v bigint; begin
  v := create_post('eve root shared by ada and cat');
  perform set_config('t.eve_root', v::text, false);
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ declare v bigint; begin
  v := create_post('ada reply inside eve''s thread', current_setting('t.eve_root')::bigint);
  perform set_config('t.ada_reply', v::text, false);
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ declare r record; begin
  select * into r from get_thread(current_setting('t.eve_root')::bigint)
    where id = current_setting('t.ada_reply')::bigint;
  if not found then
    raise exception 'FAIL (P2-2): root guard wrongly removed an in-thread tombstone';
  end if;
  if not r.unavailable or r.author_handle <> '' or r.body <> '' then
    raise exception 'FAIL: in-thread tombstone regressed';
  end if;
end $$;
reset role;

-- ============================================================
-- 5. P2-4: reply depth caps at 30. Reply #30 (depth 30) lands; a reply
--    onto it (depth 31) is refused with a human-readable message.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000008', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000008","aal":"aal1","session_id":"se"}', false);
do $$ declare parent bigint; i int; d smallint; begin
  parent := create_post('depth-cap chain root');
  for i in 1..30 loop
    parent := create_post('chain reply depth ' || i, parent);
  end loop;
  select depth into d from posts where id = parent;
  if d <> 30 then raise exception 'FAIL: chain fixture reached depth %, expected 30', d; end if;
  begin
    perform create_post('one too deep', parent);
    raise exception 'FAIL (P2-4): reply beyond depth 30 was accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;
reset role;

-- ============================================================
-- 6. P2-6: a moderation-removed parent contributes NO context to
--    profile_posts — neither its author's handle nor its text.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000008', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000008","aal":"aal1","session_id":"se"}', false);
do $$ declare v bigint; begin
  v := create_post('SENTINEL-PARENT-TEXT that moderation will remove');
  perform set_config('t.mod_parent', v::text, false);
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare v bigint; begin
  v := create_post('bea reply whose parent gets moderated away', current_setting('t.mod_parent')::bigint);
  perform set_config('t.mod_reply', v::text, false);
end $$;
-- before removal, the parent context is present (positive control)
do $$ declare r record; begin
  select * into r from profile_posts('00000000-0000-0000-0000-000000000004', true, null, 20)
    where id = current_setting('t.mod_reply')::bigint;
  if r.parent_excerpt not like '%SENTINEL-PARENT-TEXT%' then
    raise exception 'FAIL: fixture broken — visible parent produced no excerpt';
  end if;
end $$;
reset role;
-- moderation removes the parent (superuser stands in for the Phase 2B
-- moderation write path, which does not exist yet)
update posts set visibility = 'removed_moderation'
  where id = current_setting('t.mod_parent')::bigint;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ declare r record; begin
  select * into r from profile_posts('00000000-0000-0000-0000-000000000004', true, null, 20)
    where id = current_setting('t.mod_reply')::bigint;
  if not found then raise exception 'FAIL: reply itself vanished (only the parent was removed)'; end if;
  if r.parent_excerpt like '%SENTINEL%' or coalesce(r.parent_author_handle, '') = 'eve' then
    raise exception 'FAIL (P2-6): moderation-removed parent leaked into profile context (handle %, excerpt %)',
      r.parent_author_handle, r.parent_excerpt;
  end if;
end $$;
-- the paged DEFINER reads still run without error for a member who is
-- party to a block (the caller-scoping guard must never fire on
-- legitimate internal argument shapes)
do $$ declare n int; begin
  select count(*) into n from feed_following(null, 10);
  select count(*) into n from search_people('bea', 10);
  select count(*) into n from get_notifications(null, 10);
  select count(*) into n from list_followers('00000000-0000-0000-0000-000000000005', null, 10);
end $$;
reset role;

-- ============================================================
-- 7. Structural EXECUTE guards: P1-3 (notif_enabled), P2-8 (trigger
--    functions), and the new-signature paged functions (authenticated
--    only — anon and service_role have no business calling them).
-- ============================================================
do $$ declare f text; begin
  foreach f in array array[
    'public.notif_enabled(uuid,text)',
    'public.forbid_blocking_protected()',
    'public.set_post_thread_fields()',
    'public.on_like_change()',
    'public.on_follow_insert()'] loop
    if has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('anon', f, 'execute')
       or has_function_privilege('service_role', f, 'execute') then
      raise exception 'FAIL (P1-3/P2-8): % is executable by an app role', f;
    end if;
  end loop;
  foreach f in array array[
    'public.feed_following(timestamptz,integer,bigint)',
    'public.profile_posts(uuid,boolean,timestamptz,integer,bigint)',
    'public.list_followers(uuid,timestamptz,integer,uuid)',
    'public.list_following(uuid,timestamptz,integer,uuid)',
    'public.get_notifications(timestamptz,integer,bigint)'] loop
    if not has_function_privilege('authenticated', f, 'execute') then
      raise exception 'FAIL: % lost its authenticated grant', f;
    end if;
    if has_function_privilege('anon', f, 'execute')
       or has_function_privilege('service_role', f, 'execute') then
      raise exception 'FAIL: % is executable by anon or service_role', f;
    end if;
  end loop;
end $$;

rollback;
\echo ALL HARDENING REGRESSION TESTS PASSED
