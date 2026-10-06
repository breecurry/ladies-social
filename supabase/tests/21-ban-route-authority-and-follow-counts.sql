-- Regression coverage for the 2026-10 small-fix batch:
--
--   FIX 1 — a member could block a moderator and break that admin's
--   ban button. /api/mod/ban's typed-handle gate read profiles through
--   the CALLER'S RLS-scoped client; profiles_read honours
--   internal.blocked_by, so a target who had blocked the acting admin
--   vanished from that read and the route 404'd. The route now checks
--   the caller is admin/owner FIRST, then does the handle lookup with
--   the service client. This file pins the DATABASE facts that fix
--   rests on: (a) the user-scoped read really does return nothing for
--   a blocked admin (so the route MUST bypass it — if this assertion
--   ever fails, the policy changed and the route can be revisited);
--   (b) mod_ban() itself succeeds straight through a block; (c)
--   mod_ban() admits exactly admin and owner (tier >= 2), the same set
--   the route now gates on; (d) an ordinary member cannot read an
--   enforced profile — the enumeration the authority-first order
--   prevents at the route.
--
--   FIX 2 — profile follower/following counts disagreed with the
--   follower/following lists (raw `follows` rows vs the filtered
--   list_followers()/list_following()). profile_follow_counts()
--   (migration 20261025000001) must return numbers EQUAL to the row
--   counts of those lists for the same viewer, in every state:
--   untouched, suspended counterparty, banned counterparty,
--   counterparty-blocks-viewer, viewer<->owner block, and own-profile
--   view. Equality is asserted against the LISTS THEMSELVES, not just
--   hardcoded expectations, so the suite fails if the predicates ever
--   drift apart.
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000091', 'ada91@test'),
  ('00000000-0000-0000-0000-000000000092', 'mia92@test'),
  ('00000000-0000-0000-0000-000000000093', 'tess93@test'),
  ('00000000-0000-0000-0000-000000000094', 'paige94@test'),
  ('00000000-0000-0000-0000-000000000095', 'vera95@test'),
  ('00000000-0000-0000-0000-000000000096', 'sue96@test'),
  ('00000000-0000-0000-0000-000000000097', 'bia97@test'),
  ('00000000-0000-0000-0000-000000000098', 'belle98@test'),
  ('00000000-0000-0000-0000-000000000099', 'fran99@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_member('00000000-0000-0000-0000-000000000091', 'ada91@test',   'Ada Admin',   '1995-05-05', 'ada91',   null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000092', 'mia92@test',   'Mia Mod',     '1995-05-05', 'mia92',   null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000093', 'tess93@test',  'Tess Target', '1995-05-05', 'tess93',  null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000094', 'paige94@test', 'Paige Page',  '1995-05-05', 'paige94', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000095', 'vera95@test',  'Vera Viewer', '1995-05-05', 'vera95',  null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000096', 'sue96@test',   'Sue Susp',    '1995-05-05', 'sue96',   null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000097', 'bia97@test',   'Bia Banned',  '1995-05-05', 'bia97',   null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000098', 'belle98@test', 'Belle Block', '1995-05-05', 'belle98', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000099', 'fran99@test',  'Fran Follow', '1995-05-05', 'fran99',  null, null, null, '{}'::jsonb, false);

-- Roles: ada91 is admin, mia92 is moderator.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"ow"}', false);
select grant_role('00000000-0000-0000-0000-000000000091', 'admin');
select grant_role('00000000-0000-0000-0000-000000000092', 'moderator');
reset role;

-- ============================================================
-- 1. FIX 1 — the target blocks the admin, then gets banned anyway.
-- ============================================================

-- tess93 blocks the admin (admins and moderators ARE blockable;
-- only the Owner and the system account are protected).
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000093', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000093","aal":"aal1","session_id":"t"}', false);
insert into blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-000000000093', '00000000-0000-0000-0000-000000000091');
reset role;

-- (a) The admin's USER-SCOPED profiles read returns NOTHING for the
-- member who blocked her — the exact RLS fact that broke the ban
-- route's typed-handle gate. If this ever starts returning a row, the
-- profiles_read policy changed and the route's service-client read
-- should be revisited.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000091', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000091","aal":"aal1","session_id":"a"}', false);
do $$ begin
  if exists (select 1 from profiles where user_id = '00000000-0000-0000-0000-000000000093') then
    raise exception 'FAIL: profiles_read now shows a member who blocked the reading admin — the ban route''s service-client handle gate rests on the opposite; re-examine both together';
  end if;
  -- The route's authority gate reads the caller's OWN role rows
  -- through her user-scoped client; that self-read must always work.
  if not exists (select 1 from role_assignments
                 where user_id = auth.uid() and role = 'admin' and revoked_at is null) then
    raise exception 'FAIL: an admin cannot read her own role_assignments row — the ban route''s authority gate would break';
  end if;
end $$;

-- (b) mod_ban() itself goes straight through the block: moderation
-- never consults blocks.
select mod_ban('00000000-0000-0000-0000-000000000093', 'harassment',
               'suite 21: banned by the admin she blocked', null, null, false);
reset role;

do $$ begin
  if not exists (select 1 from profiles
                 where user_id = '00000000-0000-0000-0000-000000000093' and status = 'banned') then
    raise exception 'FAIL: mod_ban by a blocked admin did not land';
  end if;
end $$;

-- (c) The tier boundary the route now mirrors: a MODERATOR (tier 1)
-- must be refused by mod_ban (tier >= 2: admin and owner only), and so
-- must a plain member. The route's admin/owner gate matches this set.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000092', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000092","aal":"aal1","session_id":"m"}', false);
do $$ begin
  begin
    perform mod_ban('00000000-0000-0000-0000-000000000099', 'spam', 'suite 21: moderator trying to ban', null, null, false);
    raise exception 'FAIL: a moderator (tier 1) was allowed to call mod_ban';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm !~ 'permission' then
      raise exception 'FAIL: wrong refusal for a moderator calling mod_ban: %', sqlerrm;
    end if;
  end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000095', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000095","aal":"aal1","session_id":"v"}', false);
do $$ begin
  begin
    perform mod_ban('00000000-0000-0000-0000-000000000099', 'spam', 'suite 21: member trying to ban', null, null, false);
    raise exception 'FAIL: a plain member was allowed to call mod_ban';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    if sqlerrm !~ 'permission' then
      raise exception 'FAIL: wrong refusal for a member calling mod_ban: %', sqlerrm;
    end if;
  end;
end $$;

-- (d) The enumeration the route's authority-first ordering prevents:
-- an ordinary member cannot see the banned profile at all, so a route
-- that did the service-client handle lookup BEFORE the authority check
-- would be handing out exactly this hidden mapping.
do $$ begin
  if exists (select 1 from profiles where user_id = '00000000-0000-0000-0000-000000000093') then
    raise exception 'FAIL: an ordinary member can read a banned member''s profile row';
  end if;
end $$;
reset role;

-- ============================================================
-- 2. FIX 2 — profile_follow_counts() must equal the lists, always.
--    paige94's followers: sue96, bia97, belle98, fran99.
--    paige94 follows: sue96, bia97, fran99.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000096', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000096","aal":"aal1","session_id":"s"}', false);
insert into follows (follower_id, followee_id)
values ('00000000-0000-0000-0000-000000000096', '00000000-0000-0000-0000-000000000094');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000097', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000097","aal":"aal1","session_id":"b"}', false);
insert into follows (follower_id, followee_id)
values ('00000000-0000-0000-0000-000000000097', '00000000-0000-0000-0000-000000000094');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000098', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000098","aal":"aal1","session_id":"e"}', false);
insert into follows (follower_id, followee_id)
values ('00000000-0000-0000-0000-000000000098', '00000000-0000-0000-0000-000000000094');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000099', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000099","aal":"aal1","session_id":"f"}', false);
insert into follows (follower_id, followee_id)
values ('00000000-0000-0000-0000-000000000099', '00000000-0000-0000-0000-000000000094');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000094', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000094","aal":"aal1","session_id":"p"}', false);
insert into follows (follower_id, followee_id) values
  ('00000000-0000-0000-0000-000000000094', '00000000-0000-0000-0000-000000000096'),
  ('00000000-0000-0000-0000-000000000094', '00000000-0000-0000-0000-000000000097'),
  ('00000000-0000-0000-0000-000000000094', '00000000-0000-0000-0000-000000000099');
reset role;

-- The contract, checked as one reusable assertion: counts == lists,
-- for whoever the current session viewer is.
create function pg_temp.assert_counts_match_lists(p_user uuid, p_label text,
                                                  p_want_followers bigint, p_want_following bigint)
returns void language plpgsql as $$
declare
  v_fc bigint; v_gc bigint; v_fl bigint; v_gl bigint;
begin
  select follower_count, following_count into v_fc, v_gc from profile_follow_counts(p_user);
  select count(*) into v_fl from list_followers(p_user, null, 50);
  select count(*) into v_gl from list_following(p_user, null, 50);
  if v_fc is distinct from v_fl or v_gc is distinct from v_gl then
    raise exception 'FAIL (%): counts disagree with lists — counts (%, %), lists (%, %)',
      p_label, v_fc, v_gc, v_fl, v_gl;
  end if;
  if v_fc is distinct from p_want_followers or v_gc is distinct from p_want_following then
    raise exception 'FAIL (%): expected (%, %), got (%, %)',
      p_label, p_want_followers, p_want_following, v_fc, v_gc;
  end if;
end $$;

-- Untouched state, uninvolved viewer: 4 followers, 3 following.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000095', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000095","aal":"aal1","session_id":"v"}', false);
select pg_temp.assert_counts_match_lists('00000000-0000-0000-0000-000000000094', 'clean state', 4, 3);
reset role;

-- Enforcement and a block: sue96 suspended, bia97 banned,
-- belle98 blocks the viewer vera95.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"ow"}', false);
select mod_suspend('00000000-0000-0000-0000-000000000096', 7, 'spam', 'suite 21: suspended follower');
select mod_ban('00000000-0000-0000-0000-000000000097', 'spam', 'suite 21: banned follower', null, null, false);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000098', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000098","aal":"aal1","session_id":"e"}', false);
insert into blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-000000000098', '00000000-0000-0000-0000-000000000095');
reset role;

-- vera95 now sees 1 follower (fran99: sue96 suspended, bia97 banned,
-- belle98 blocked her) and 1 following (fran99) — and the counts still
-- equal the lists.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000095', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000095","aal":"aal1","session_id":"v"}', false);
select pg_temp.assert_counts_match_lists('00000000-0000-0000-0000-000000000094', 'after enforcement, uninvolved viewer', 1, 1);
reset role;

-- paige94 on her OWN profile: belle98's block of vera95 is not hers,
-- so belle98 counts for her; the suspended and banned followers do
-- not, exactly as her own lists already behave.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000094', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000094","aal":"aal1","session_id":"p"}', false);
select pg_temp.assert_counts_match_lists('00000000-0000-0000-0000-000000000094', 'own profile', 2, 1);
reset role;

-- A block between the VIEWER and the PROFILE OWNER empties the lists
-- entirely; the counts must go to zero with them, not keep reporting
-- numbers for a profile whose lists show nothing.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000095', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000095","aal":"aal1","session_id":"v"}', false);
insert into blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-000000000095', '00000000-0000-0000-0000-000000000094');
select pg_temp.assert_counts_match_lists('00000000-0000-0000-0000-000000000094', 'viewer blocked the owner', 0, 0);
reset role;

-- ============================================================
-- 3. Structure and grants: exactly ONE signature (a leftover second
--    signature makes PostgREST ambiguous — this project has been
--    bitten), EXECUTE for authenticated only.
-- ============================================================
do $$ begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'profile_follow_counts') <> 1 then
    raise exception 'FAIL: profile_follow_counts must have exactly one signature, found %',
      (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = 'profile_follow_counts');
  end if;
  if not has_function_privilege('authenticated', 'public.profile_follow_counts(uuid)', 'execute') then
    raise exception 'FAIL: authenticated lost EXECUTE on profile_follow_counts';
  end if;
  if has_function_privilege('anon', 'public.profile_follow_counts(uuid)', 'execute') then
    raise exception 'FAIL: anon can execute profile_follow_counts';
  end if;
  if has_function_privilege('service_role', 'public.profile_follow_counts(uuid)', 'execute') then
    raise exception 'FAIL: service_role can execute profile_follow_counts';
  end if;
end $$;

rollback;
\echo ALL BAN-ROUTE-AUTHORITY AND FOLLOW-COUNT TESTS PASSED
