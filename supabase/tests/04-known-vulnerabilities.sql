-- Regression suite for the six vulnerabilities found during Grove-Test's
-- adversarial pass on migration 0013 (2026-10-05). ALL SIX ARE FIXED by
-- migration 0014 (20261006000001_social_core_hardening.sql), so this
-- file is now a HARD-FAILING gate in the style of 01/02/03: every
-- assertion raises on failure and the file runs with ON_ERROR_STOP.
-- (Its first life was NOTICE-based, documenting the then-open findings;
-- per its own header it was converted the moment the fixes landed.)
--
-- The blind spot that let findings 1-3 through originally: the earlier
-- suites only exercised the helper functions in their intended internal
-- role, never as an UNINVOLVED THIRD PARTY with arbitrary arguments.
-- That calling pattern is exactly what this file now locks down.
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

-- ada blocks cat (two OTHER accounts, from bea's point of view below)
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
insert into blocks (blocker_id, blocked_id) values
  ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000005');
reset role;

-- ============================================================
-- FINDING 1 (was MAJOR/P1, FIXED in 0014): blocked_either(uuid, uuid)
-- must not answer an uninvolved member probing two OTHER members' ids.
-- Fixed twice over: public.blocked_either lost EXECUTE for app roles
-- (only SECURITY DEFINER internals call it now), and the RLS-facing
-- twin internal.blocked_either — which `authenticated` must be able to
-- execute for the policies to work, but which PostgREST does not
-- expose (config.toml exposes `public` only) — carries a caller-
-- scoping guard that raises unless auth.uid() is one of the parties.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ begin
  -- bea is not ada, not cat, and party to no block whatsoever
  begin
    perform blocked_either('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000005');
    raise exception 'FAIL (FINDING 1 REGRESSED): public.blocked_either answered an uninvolved third party.';
  exception when insufficient_privilege then null;
  end;
  begin
    perform internal.blocked_either('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000005');
    raise exception 'FAIL (FINDING 1 REGRESSED): internal.blocked_either answered an uninvolved third party.';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
-- The caller-scoped path still works for a PARTY to the block: ada may
-- see her own block state (she holds the blocks row under RLS anyway).
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ begin
  if not internal.blocked_either('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000005') then
    raise exception 'FAIL: caller-scoped blocked_either broke the legitimate party path';
  end if;
end $$;
reset role;

-- ============================================================
-- FINDING 2 (was MAJOR/P1, FIXED in 0014): blocked_by(uuid) let the
-- CALLER ask point-blank "has she blocked me?" and get a straight
-- answer. public.blocked_by now has no app-role EXECUTE at all, so the
-- RPC path is dead. (profiles_read uses internal.blocked_by, which
-- PostgREST does not expose; the only residual signal a blocked member
-- gets is the profile/posts becoming unavailable, which is
-- indistinguishable from a deleted account.)
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ begin
  -- cat IS the blocked party here; she asks point-blank "does ada block me?"
  begin
    perform blocked_by('00000000-0000-0000-0000-000000000003');
    raise exception 'FAIL (FINDING 2 REGRESSED): blocked_by confirmed block status to the blocked party.';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
-- Structural guards: a future migration must not quietly re-grant the
-- public helpers to app roles, and the policies' internal twins must
-- stay executable by authenticated (RLS checks EXECUTE on the QUERYING
-- role) — exactly the configuration 0014 established.
do $$ begin
  if has_function_privilege('authenticated', 'public.blocked_either(uuid,uuid)', 'execute') then
    raise exception 'FAIL: authenticated regained EXECUTE on public.blocked_either';
  end if;
  if has_function_privilege('authenticated', 'public.blocked_by(uuid)', 'execute') then
    raise exception 'FAIL: authenticated regained EXECUTE on public.blocked_by';
  end if;
  if not has_function_privilege('authenticated', 'internal.blocked_either(uuid,uuid)', 'execute')
     or not has_function_privilege('authenticated', 'internal.blocked_by(uuid)', 'execute') then
    raise exception 'FAIL: authenticated lost EXECUTE on the internal RLS helpers (policies would break)';
  end if;
end $$;

-- ============================================================
-- FINDING 3 (was MINOR-MODERATE/P2, FIXED in 0014): notif_enabled no
-- longer answers an arbitrary caller about another member's
-- notification preferences — EXECUTE revoked from all app roles; it is
-- only called inside SECURITY DEFINER functions.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ begin
  begin
    perform notif_enabled('00000000-0000-0000-0000-000000000003', 'like');
    raise exception 'FAIL (FINDING 3 REGRESSED): bea read ada''s notification_prefs via notif_enabled.';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- ============================================================
-- FINDING 4 (was MINOR/P2, FIXED in 0014): '_' in a search query is a
-- literal underscore, not a LIKE wildcard. 'a_a' must NOT match 'ada',
-- and ordinary search must still work.
-- ============================================================
set role authenticated;
-- bea: a searcher with no block relationship to ada, so the block
-- filter cannot mask the wildcard bug being tested here.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare n int; begin
  select count(*) into n from search_people('a_a', 10) where handle = 'ada';
  if n > 0 then
    raise exception 'FAIL (FINDING 4 REGRESSED): "a_a" matched handle "ada" (unescaped LIKE wildcard).';
  end if;
  select count(*) into n from search_people('ada', 10) where handle = 'ada';
  if n <> 1 then
    raise exception 'FAIL: escaping broke ordinary search (searching "ada" found % rows)', n;
  end if;
end $$;
reset role;

-- ============================================================
-- FINDING 5 (was MINOR-MODERATE/P2, FIXED in 0014): the mention parser
-- requires a word boundary before '@'. "noreply@cat" is an email-shaped
-- string, not a mention; "@cat" at start of text, after whitespace, or
-- after punctuation still mentions.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000008', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000008","aal":"aal1","session_id":"se"}', false);
do $$ declare v bigint; n int; begin
  v := create_post('contact me at noreply@cat for questions, not a real mention');
  select count(*) into n from post_mentions where post_id = v;
  if n > 0 then
    raise exception 'FAIL (FINDING 5 REGRESSED): "noreply@cat" created a real mention/notification for @cat.';
  end if;
  v := create_post('@cat starts this one, and (@cat) sits after punctuation');
  select count(*) into n from post_mentions
    where post_id = v and mentioned_user_id = '00000000-0000-0000-0000-000000000005';
  if n <> 1 then
    raise exception 'FAIL: boundary rule broke real mentions (% rows, expected 1 deduped)', n;
  end if;
end $$;
reset role;

-- ============================================================
-- FINDING 6 (was MINOR/P2, FIXED in 0014): pagination is deterministic
-- under created_at ties. Everything in this file shares one
-- transaction timestamp, so eve's three root posts (the finding-5 pair
-- above plus the two below) ALL tie on created_at — the worst case.
-- With the composite (created_at, id) cursor, paging one at a time
-- must walk every post exactly once, no skips, no repeats.
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
do $$
declare
  total   int;
  cur_ts  timestamptz;
  cur_id  bigint;
  page    record;
  walked  bigint[] := '{}';
  steps   int := 0;
begin
  select count(*) into total from feed_following(null, 50);
  if total < 4 then
    raise exception 'FAIL: expected at least 4 tied posts in the fixture feed, found %', total;
  end if;
  loop
    select id, created_at into page
      from feed_following(cur_ts, 1, cur_id) limit 1;
    exit when not found;
    if page.id = any (walked) then
      raise exception 'FAIL (FINDING 6 REGRESSED): post % repeated across page boundaries', page.id;
    end if;
    walked := walked || page.id;
    cur_ts := page.created_at;
    cur_id := page.id;
    steps := steps + 1;
    if steps > total + 5 then
      raise exception 'FAIL: pagination walk did not terminate';
    end if;
  end loop;
  if array_length(walked, 1) <> total then
    raise exception 'FAIL (FINDING 6 REGRESSED): one-at-a-time paging visited % of % posts (tied rows skipped)',
      array_length(walked, 1), total;
  end if;
  if not (current_setting('t.tiea')::bigint = any (walked))
     or not (current_setting('t.tieb')::bigint = any (walked)) then
    raise exception 'FAIL (FINDING 6 REGRESSED): a tied post vanished from the paged feed';
  end if;
end $$;
reset role;

rollback;
\echo ALL KNOWN-VULNERABILITY REGRESSION TESTS PASSED (findings 1-6 fixed and gated)
