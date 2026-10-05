-- Behavioral + structural smoke test for migration 0021 (Discover):
-- feed_discover(), suggested_accounts(), and the Discoverability
-- opt-out (profiles.discoverable, default ON, owner decision
-- 2026-10-07). Local only, like suites 01-09.
--
-- The headline security property: a member who turns Discoverability
-- OFF never surfaces in anyone's Discover feed or suggested-accounts
-- module, while remaining reachable by exact @handle search — and the
-- structural legal-name rule extends to both new functions.
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
-- 1. STRUCTURAL: the Discover functions exist, neither returns nor
--    references display_name (the legal-name rule holds below the app
--    layer on the widest surface in the product), and EXECUTE is
--    authenticated-only.
-- ============================================================
do $$ declare f text; sig text; src text; begin
  foreach f in array array['feed_discover', 'suggested_accounts'] loop
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
end $$;

do $$ begin
  if has_function_privilege('anon', 'public.feed_discover(integer, integer)', 'execute') then
    raise exception 'FAIL: anon can execute feed_discover';
  end if;
  if has_function_privilege('service_role', 'public.feed_discover(integer, integer)', 'execute') then
    raise exception 'FAIL: service_role can execute feed_discover';
  end if;
  if not has_function_privilege('authenticated', 'public.feed_discover(integer, integer)', 'execute') then
    raise exception 'FAIL: authenticated cannot execute feed_discover';
  end if;
  if has_function_privilege('anon', 'public.suggested_accounts(integer)', 'execute') then
    raise exception 'FAIL: anon can execute suggested_accounts';
  end if;
  if has_function_privilege('service_role', 'public.suggested_accounts(integer)', 'execute') then
    raise exception 'FAIL: service_role can execute suggested_accounts';
  end if;
  if not has_function_privilege('authenticated', 'public.suggested_accounts(integer)', 'execute') then
    raise exception 'FAIL: authenticated cannot execute suggested_accounts';
  end if;
end $$;

-- ============================================================
-- 2. Discoverability defaults ON for every account (owner decision).
-- ============================================================
do $$ begin
  if exists (select 1 from profiles where not discoverable) then
    raise exception 'FAIL: a fresh account is not discoverable by default';
  end if;
end $$;

-- ============================================================
-- 3. Seed posts. Order matters for the hide-downrank assertion:
--    dee posts FIRST (oldest), then cat, then bea (newest), so with
--    no other signal bea outranks dee on freshness alone.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000006","aal":"aal1","session_id":"sd"}', false);
do $$ declare v bigint; begin
  v := create_post('First light, from dee.');
  perform set_config('t.post_dee', v::text, false);
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ declare v bigint; begin
  v := create_post('Hello from cat.');
  perform set_config('t.post_cat', v::text, false);
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare v bigint; begin
  v := create_post('Hello from bea.');
  perform set_config('t.post_bea', v::text, false);
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ declare v bigint; begin
  v := create_post('Hello from ada.');
  perform set_config('t.post_ada', v::text, false);
end $$;

-- ============================================================
-- 4. Cold start: a member with zero follows and zero likes gets a
--    populated feed of everyone else's posts — never her own.
--    Replies never appear (root posts only).
-- ============================================================
do $$ declare ids bigint[]; begin
  select coalesce(array_agg(id), '{}') into ids from feed_discover(50, 0);
  if not (current_setting('t.post_bea')::bigint = any(ids)
          and current_setting('t.post_cat')::bigint = any(ids)
          and current_setting('t.post_dee')::bigint = any(ids)) then
    raise exception 'FAIL: cold-start Discover is missing other members'' posts';
  end if;
  if current_setting('t.post_ada')::bigint = any(ids) then
    raise exception 'FAIL: Discover shows the viewer her own post';
  end if;
  if exists (select 1 from feed_discover(50, 0) fd where fd.viewer_follows) then
    raise exception 'FAIL: viewer_follows true with zero follows';
  end if;
end $$;

-- Offset pagination is deterministic: page 2 of size 1 is the second
-- row of page size 2.
do $$ declare a bigint; b bigint; begin
  select id into a from feed_discover(2, 0) offset 1;
  select id into b from feed_discover(1, 1);
  if a is distinct from b then
    raise exception 'FAIL: offset pagination is not deterministic (% vs %)', a, b;
  end if;
end $$;

-- Suggestions: everyone ada does not follow, minus herself and the
-- system account.
do $$ declare hs text[]; begin
  select coalesce(array_agg(sa.handle), '{}') into hs from suggested_accounts(20) sa;
  if not ('bea' = any(hs) and 'cat' = any(hs) and 'dee' = any(hs)) then
    raise exception 'FAIL: suggested_accounts is missing founding members (got %)', hs;
  end if;
  if 'ada' = any(hs) then
    raise exception 'FAIL: suggested_accounts suggests the viewer to herself';
  end if;
  if 'hersciety' = any(hs) then
    raise exception 'FAIL: suggested_accounts suggests the system account';
  end if;
end $$;

-- ============================================================
-- 5. THE OPT-OUT. cat turns Discoverability off (her own row only —
--    RLS keeps everyone else's row out of reach).
-- ============================================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);

-- She cannot flip anyone else's toggle: the update silently covers
-- zero rows under RLS.
update profiles set discoverable = false
  where user_id = '00000000-0000-0000-0000-000000000004';
do $$ begin
  if exists (select 1 from profiles
             where user_id = '00000000-0000-0000-0000-000000000004' and not discoverable) then
    raise exception 'FAIL: cat flipped bea''s discoverability';
  end if;
end $$;

-- Her own toggle works.
update profiles set discoverable = false
  where user_id = '00000000-0000-0000-0000-000000000005';
do $$ begin
  if not exists (select 1 from profiles
                 where user_id = '00000000-0000-0000-0000-000000000005' and not discoverable) then
    raise exception 'FAIL: cat could not turn her own discoverability off';
  end if;
end $$;

-- Opting out does not degrade HER view: cat still sees Discover.
do $$ declare ids bigint[]; begin
  select coalesce(array_agg(id), '{}') into ids from feed_discover(50, 0);
  if not (current_setting('t.post_bea')::bigint = any(ids)) then
    raise exception 'FAIL: opting out hid Discover from the opted-out member herself';
  end if;
end $$;

-- And now, as ada: cat has vanished from every Discover surface…
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ declare ids bigint[]; hs text[]; begin
  select coalesce(array_agg(id), '{}') into ids from feed_discover(50, 0);
  if current_setting('t.post_cat')::bigint = any(ids) then
    raise exception 'FAIL: an opted-out member''s post surfaced in Discover';
  end if;
  select coalesce(array_agg(sa.handle), '{}') into hs from suggested_accounts(20) sa;
  if 'cat' = any(hs) then
    raise exception 'FAIL: an opted-out member was suggested';
  end if;
end $$;

-- …but remains fully reachable by @handle search (the locked rule:
-- the toggle controls being SURFACED, not being findable by people
-- she gave her handle to).
do $$ begin
  if not exists (select 1 from search_people('cat') sp where sp.handle = 'cat') then
    raise exception 'FAIL: opting out of Discover broke @handle search';
  end if;
end $$;

-- ============================================================
-- 6. Hide ("show me less") SUPPRESSES but never hard-filters
--    (P2 spec §4.8: a tuning signal, not a wall) — and it does keep
--    the account out of suggestions.
-- ============================================================
insert into hidden_accounts (hider_id, hidden_id) values
  ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000004');
do $$ declare ids bigint[]; pos_bea int; pos_dee int; hs text[]; begin
  select coalesce(array_agg(id), '{}') into ids from feed_discover(50, 0);
  if not (current_setting('t.post_bea')::bigint = any(ids)) then
    raise exception 'FAIL: hide hard-filtered Discover (it must only down-rank)';
  end if;
  -- bea's post is NEWER than dee's, so freshness alone would rank it
  -- first; the hide suppression must push it below dee's.
  pos_bea := array_position(ids, current_setting('t.post_bea')::bigint);
  pos_dee := array_position(ids, current_setting('t.post_dee')::bigint);
  if pos_bea <= pos_dee then
    raise exception 'FAIL: a hidden account''s newer post still outranks (bea %, dee %)', pos_bea, pos_dee;
  end if;
  select coalesce(array_agg(sa.handle), '{}') into hs from suggested_accounts(20) sa;
  if 'bea' = any(hs) then
    raise exception 'FAIL: a hidden account was suggested';
  end if;
end $$;
delete from hidden_accounts
  where hider_id = '00000000-0000-0000-0000-000000000003';

-- ============================================================
-- 7. Mute removes the author from Discover entirely.
-- ============================================================
insert into mutes (muter_id, muted_id) values
  ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000004');
do $$ declare ids bigint[]; hs text[]; begin
  select coalesce(array_agg(id), '{}') into ids from feed_discover(50, 0);
  if current_setting('t.post_bea')::bigint = any(ids) then
    raise exception 'FAIL: a muted author surfaced in Discover';
  end if;
  select coalesce(array_agg(sa.handle), '{}') into hs from suggested_accounts(20) sa;
  if 'bea' = any(hs) then
    raise exception 'FAIL: a muted account was suggested';
  end if;
end $$;
delete from mutes
  where muter_id = '00000000-0000-0000-0000-000000000003';

-- ============================================================
-- 8. Blocks are mutual-hard in Discover, both directions.
-- ============================================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000006","aal":"aal1","session_id":"sd"}', false);
insert into blocks (blocker_id, blocked_id) values
  ('00000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000003');

-- dee (the blocker) never sees ada.
do $$ declare ids bigint[]; hs text[]; begin
  select coalesce(array_agg(id), '{}') into ids from feed_discover(50, 0);
  if current_setting('t.post_ada')::bigint = any(ids) then
    raise exception 'FAIL: blocker still sees the blocked member''s post in Discover';
  end if;
  select coalesce(array_agg(sa.handle), '{}') into hs from suggested_accounts(20) sa;
  if 'ada' = any(hs) then
    raise exception 'FAIL: blocker is offered the blocked member as a suggestion';
  end if;
end $$;

-- ada (the blocked) never sees dee — and is never told why.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ declare ids bigint[]; hs text[]; begin
  select coalesce(array_agg(id), '{}') into ids from feed_discover(50, 0);
  if current_setting('t.post_dee')::bigint = any(ids) then
    raise exception 'FAIL: blocked member still sees the blocker''s post in Discover';
  end if;
  select coalesce(array_agg(sa.handle), '{}') into hs from suggested_accounts(20) sa;
  if 'dee' = any(hs) then
    raise exception 'FAIL: blocked member is offered the blocker as a suggestion';
  end if;
end $$;

-- ============================================================
-- 9. Following an account flips viewer_follows on her Discover cards
--    (the card's Follow-pill signal) and retires her from suggestions.
-- ============================================================
insert into follows (follower_id, followee_id) values
  ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000004');
do $$ declare vf boolean; hs text[]; begin
  select fd.viewer_follows into vf from feed_discover(50, 0) fd
    where fd.id = current_setting('t.post_bea')::bigint;
  if vf is distinct from true then
    raise exception 'FAIL: viewer_follows is not true for a followed author';
  end if;
  select coalesce(array_agg(sa.handle), '{}') into hs from suggested_accounts(20) sa;
  if 'bea' = any(hs) then
    raise exception 'FAIL: an already-followed account was suggested';
  end if;
end $$;
reset role;

-- ============================================================
-- 10. Account status and post visibility hold in Discover exactly as
--     in every other read path: a suspended author's posts vanish,
--     a moderation-removed post vanishes.
-- ============================================================
update profiles set status = 'suspended'
  where user_id = '00000000-0000-0000-0000-000000000004';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ declare ids bigint[]; begin
  select coalesce(array_agg(id), '{}') into ids from feed_discover(50, 0);
  if current_setting('t.post_bea')::bigint = any(ids) then
    raise exception 'FAIL: a suspended author''s post surfaced in Discover';
  end if;
end $$;
reset role;
update profiles set status = 'active'
  where user_id = '00000000-0000-0000-0000-000000000004';

update posts set visibility = 'removed_moderation'
  where id = current_setting('t.post_bea')::bigint;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ declare ids bigint[]; begin
  select coalesce(array_agg(id), '{}') into ids from feed_discover(50, 0);
  if current_setting('t.post_bea')::bigint = any(ids) then
    raise exception 'FAIL: a moderation-removed post surfaced in Discover';
  end if;
end $$;
reset role;

rollback;
\echo ALL DISCOVER TESTS PASSED
