-- Confirmed vulnerabilities found during Grove-Test's adversarial pass on
-- migration 0013 (2026-10-05), NOT fixed here — per the QA mandate, this
-- role finds and reports, it never patches production code or the
-- migration under test. This file is a durable, runnable proof of each
-- finding for Grove-Code to fix and for a future QA pass to re-run.
--
-- UNLIKE 01/02/03, this file does NOT \set ON_ERROR_STOP and does NOT
-- raise exceptions on failure: every check below reports PASS/FAIL via
-- RAISE NOTICE and the file always completes, specifically so a FAIL
-- here is visible without crashing the whole local-verification run.
-- When Grove-Code fixes a finding, flip its assertion to a hard
-- `raise exception` (matching 01/02/03's style) so it gates the suite
-- like every other regression from then on.
--
-- STATUS AS OF 2026-10-05: findings 1-3 and 5 are OPEN (FAIL). Finding 4
-- (search underscore wildcard) is OPEN (FAIL) but cosmetic/low severity.
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

-- ada blocks cat (two OTHER accounts, from bea's point of view below)
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
insert into blocks (blocker_id, blocked_id) values
  ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000005');
reset role;

-- ============================================================
-- FINDING 1 (MAJOR / P1): blocked_either(uuid, uuid) is directly
-- callable via RPC by ANY authenticated member with TWO ARBITRARY
-- third-party ids and answers whether ANY block exists between them —
-- not scoped to the caller at all. A member who is party to neither
-- block can map the block graph between other members.
-- File: supabase/migrations/20261005000001_social_core.sql:124-131
-- (definition), :1001 (grant execute ... to authenticated).
-- Reachable from the browser: supabase/config.toml exposes the
-- `public` schema to PostgREST, and this function sits in `public`
-- with EXECUTE granted to `authenticated`.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare leaked boolean; begin
  -- bea is not ada, not cat, and party to no block whatsoever
  select blocked_either('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000005')
    into leaked;
  if leaked then
    raise notice 'FAIL (FINDING 1, OPEN): an uninvolved member learned, via a direct RPC call, that two OTHER members have a block between them. blocked_either(uuid,uuid) must not be callable with arguments that do not include auth.uid(), or must not be granted to authenticated at all.';
  else
    raise notice 'PASS (FINDING 1 FIXED): blocked_either no longer leaks third-party block state.';
  end if;
end $$;
reset role;

-- ============================================================
-- FINDING 2 (MAJOR / P1): blocked_by(uuid) is directly callable via
-- RPC and lets the CALLER learn, for ANY target she names, whether
-- that target has blocked her — the exact fact the migration's own
-- header comment says must stay hidden ("the other person is never
-- told"). A stalker who knows (or looks up via search_people) his
-- target's user_id can ask the platform point-blank whether she has
-- blocked him.
-- File: supabase/migrations/20261005000001_social_core.sql:136-142
-- (definition), :1002 (grant execute ... to authenticated).
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ declare learned boolean; begin
  -- cat IS the blocked party here; she asks point-blank "does ada block me?"
  select blocked_by('00000000-0000-0000-0000-000000000003') into learned;
  if learned then
    raise notice 'FAIL (FINDING 2, OPEN): the blocked member (cat) directly confirmed, via RPC, that ada has blocked her. This defeats "the other person is never told" by design.';
  else
    raise notice 'PASS (FINDING 2 FIXED): blocked_by no longer confirms block status to the blocked party.';
  end if;
end $$;
reset role;

-- ============================================================
-- FINDING 3 (MINOR-MODERATE / P2): notif_enabled(uuid, text) is
-- directly callable via RPC with an ARBITRARY target user id, leaking
-- another member's notification preference for a given type — data
-- that notification_prefs' own RLS (own-row-select-only) deliberately
-- does not expose to anyone else.
-- File: supabase/migrations/20261005000001_social_core.sql:265-270
-- (definition), :1003 (grant execute ... to authenticated).
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare leaked boolean; begin
  perform notif_enabled('00000000-0000-0000-0000-000000000003', 'like');
  leaked := true; -- reaching here at all means the call was not rejected
  raise notice 'FAIL (FINDING 3, OPEN): bea read ada''s notification_prefs via notif_enabled(uuid,text), bypassing notification_prefs'' own RLS entirely.';
exception when insufficient_privilege then
  raise notice 'PASS (FINDING 3 FIXED): notif_enabled no longer answers for an arbitrary target.';
end $$;
reset role;

-- ============================================================
-- FINDING 4 (MINOR / P2, correctness not identity): search_people()
-- does not escape '_' before building its LIKE pattern, so '_' in a
-- query acts as a SQL wildcard (matches any single character) rather
-- than a literal underscore. 'a_a' matches handle 'ada'.
-- File: supabase/migrations/20261005000001_social_core.sql:677-694.
-- ============================================================
set role authenticated;
-- bea: a searcher with no block relationship to ada, so the block
-- filter cannot mask the wildcard bug being tested here.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare n int; begin
  select count(*) into n from search_people('a_a', 10) where handle = 'ada';
  if n > 0 then
    raise notice 'FAIL (FINDING 4, OPEN): searching "a_a" (literal underscore intended) matched handle "ada" because "_" was passed unescaped into a LIKE pattern.';
  else
    raise notice 'PASS (FINDING 4 FIXED): underscore is treated as a literal character in search.';
  end if;
end $$;
reset role;

-- ============================================================
-- FINDING 5 (MINOR-MODERATE / P2): the mention regexp has no
-- preceding word-boundary / non-identifier-character check, so a
-- handle-shaped substring following ANY character — not just
-- whitespace or start-of-string — is parsed as a mention. An
-- email-like string such as "noreply@cat" notifies the real handle
-- "cat" even though no human reading the post would call that an
-- intentional @mention. Lets an author quietly spam-notify a target
-- while the post reads as ordinary text.
-- File: supabase/migrations/20261005000001_social_core.sql:390-412
-- (regexp '@([A-Za-z0-9_]{3,30})').
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000008', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000008","aal":"aal1","session_id":"se"}', false);
do $$ declare v bigint; n int; begin
  v := create_post('contact me at noreply@cat for questions, not a real mention');
  select count(*) into n from post_mentions where post_id = v;
  if n > 0 then
    raise notice 'FAIL (FINDING 5, OPEN): "noreply@cat" (plainly not an @mention to a human reader) created a real post_mentions row and notification for handle "cat".';
  else
    raise notice 'PASS (FINDING 5 FIXED): the mention parser now requires a boundary before "@".';
  end if;
end $$;
reset role;

-- ============================================================
-- FINDING 6 (MINOR, correctness): feed_following's cursor pagination
-- has no tiebreaker beyond created_at. Two posts sharing the exact
-- same created_at (demonstrated here by creating both inside one
-- transaction, where now() is fixed for the whole transaction) cause
-- the second page to silently SKIP the tied post that was not
-- returned on the first page, because the WHERE clause is a strict
-- "<". Not identity- or safety-relevant, but a real, demonstrated
-- correctness bug: a post can vanish from a viewer's paged feed.
-- File: supabase/migrations/20261005000001_social_core.sql:512-549.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000008', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000008","aal":"aal1","session_id":"se"}', false);
do $$ declare a bigint; b bigint; begin
  a := create_post('tie post A for pagination test');
  b := create_post('tie post B for pagination test');
  perform set_config('t.tiea', a::text, false);
  perform set_config('t.tieb', b::text, false);
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
insert into follows (follower_id, followee_id) values
  ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000008')
  on conflict do nothing;
do $$ declare cur timestamptz; seen_b boolean; begin
  select created_at into cur from feed_following(null, 1) where id = current_setting('t.tieb')::bigint
     or id = current_setting('t.tiea')::bigint
   order by id limit 1; -- whichever page-1 returns (id ordering not guaranteed, just need its cursor)
  select created_at into cur from feed_following(null, 1) limit 1;
  select exists (select 1 from feed_following(cur, 1) where id = current_setting('t.tieb')::bigint
                 or id = current_setting('t.tiea')::bigint) into seen_b;
  if not seen_b then
    raise notice 'FAIL (FINDING 6, OPEN): paging past a created_at tie skipped the other tied post entirely (cursor has no secondary tiebreaker such as id).';
  else
    raise notice 'PASS (FINDING 6 FIXED): tied posts no longer vanish across a page boundary.';
  end if;
end $$;
reset role;

rollback;
\echo DONE -- see NOTICE lines above for PASS/FAIL per finding
