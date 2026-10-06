-- Independent QA pass (Grove-Test) — regression check for commit
-- 097c318 ("Correct false promise: suspended accounts are removed
-- from platform"). That commit corrected WORDING in
-- docs/community-guidelines.md and the in-app SuspendedScreen
-- (src/app/(member)/layout.tsx) to say a suspended/banned member's
-- profile and posts are removed from the platform. THIS FILE CHECKS
-- WHETHER THE CODE ACTUALLY DELIVERS THAT, across every public
-- surface: feeds, profile pages, reply trees, follower/following
-- lists, search, hashtag pages, and mention rendering. It also
-- characterises the already-known, already-queued expiry gap
-- (status_expires_at only clears on the member's own next sign-in).
--
-- ⚠️ THIS FILE IS EXPECTED TO FAIL ON THE CURRENT TREE, at the final
-- section. It reproduces a real, previously-undiscovered gap: the
-- suspended/banned member's PROFILE ROW ITSELF (handle, bio,
-- founding-member badge, join date, follower/following counts)
-- remains fully readable by any other active member — only her POSTS
-- are hidden. This directly contradicts the published promise. The
-- assertion encodes the PROMISE, not the current behaviour, and is
-- intentionally left red rather than weakened to match the bug — see
-- the QA report for the full writeup and severity. Everything BEFORE
-- that final section passes clean.
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000081', 'viewer81@test'),
  ('00000000-0000-0000-0000-000000000082', 'target82@test'),
  ('00000000-0000-0000-0000-000000000083', 'banned83@test'),
  ('00000000-0000-0000-0000-000000000084', 'replyauth84@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_member('00000000-0000-0000-0000-000000000081', 'viewer81@test', 'View Erson', '1995-05-05', 'viewer81', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000082', 'target82@test', 'Target Person', '1995-05-05', 'target82', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000083', 'banned83@test', 'Banned Person', '1995-05-05', 'banned83', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000084', 'replyauth84@test', 'Reply Author', '1995-05-05', 'replyauth84', null, null, null, '{}'::jsonb, false);

-- A post, a reply, a hashtag, a mention and a follow — all authored
-- by / involving the member who gets suspended below — so every
-- surface in the brief has something to hide.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000082', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000082","aal":"aal1","session_id":"t"}', false);
select set_config('t.root_post', (select create_post('A post with #qatag42 and @replyauth84 mentioned.')::text), false);
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000084', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000084","aal":"aal1","session_id":"r"}', false);
select set_config('t.reply_post', (select create_post('A reply from someone else.', current_setting('t.root_post')::bigint)::text), false);
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000081', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000081","aal":"aal1","session_id":"v"}', false);
insert into follows (follower_id, followee_id)
values ('00000000-0000-0000-0000-000000000081', '00000000-0000-0000-0000-000000000082');
reset role;

-- Suspend the target (7 days, Owner action).
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"ow"}', false);
select mod_suspend('00000000-0000-0000-0000-000000000082', 7, 'harassment', 'QA regression coverage for commit 097c318');
reset role;

-- An unrelated, uninvolved, active member views every surface as
-- herself, never as the suspended target.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000081', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000081","aal":"aal1","session_id":"v"}', false);

-- ============================================================
-- CLEAN: every READ-side surface checked here already hides her
-- content correctly. Verified first, before the one surface that
-- does not.
-- ============================================================
do $$ begin
  -- Her posts vanish from her own profile_posts (profile-page feed).
  if exists (select 1 from profile_posts('00000000-0000-0000-0000-000000000082'::uuid)) then
    raise exception 'FAIL: a suspended member''s own posts still appear in profile_posts';
  end if;

  -- The Following feed (the viewer follows her): her post is gone.
  if exists (select 1 from feed_following() where author_id = '00000000-0000-0000-0000-000000000082') then
    raise exception 'FAIL: a suspended member''s post survives in a follower''s Following feed';
  end if;

  -- The hashtag page: her #qatag42 post is gone.
  if exists (select 1 from feed_hashtag('qatag42') where author_id = '00000000-0000-0000-0000-000000000082') then
    raise exception 'FAIL: a suspended member''s post survives on its own hashtag page';
  end if;

  -- @handle search: she does not resolve.
  if exists (select 1 from search_people('target82', 10)) then
    raise exception 'FAIL: a suspended member is still findable by exact-handle search';
  end if;

  -- Her follower/following lists (list_followers/list_following of
  -- OTHER accounts) no longer surface her as an entry.
  if exists (select 1 from list_following('00000000-0000-0000-0000-000000000081'::uuid)
             where user_id = '00000000-0000-0000-0000-000000000082') then
    raise exception 'FAIL: a suspended member still appears in a follower''s following list';
  end if;

  -- The reply tree: her ROOT post tombstones (no body, no handle) —
  -- the thread is not simply empty (the viewer can still see the
  -- reply from the uninvolved third author), but her content is gone.
  if exists (select 1 from get_thread(current_setting('t.root_post')::bigint)
             where id = current_setting('t.root_post')::bigint
               and (author_handle <> '' or body <> '')) then
    raise exception 'FAIL: a suspended member''s root post did not tombstone in its own thread';
  end if;
end $$;

-- Mention rendering: a FRESH post made AFTER her suspension that
-- mentions her by handle must not resolve her into the mentions list
-- (internal.post_mentions_json filters mentioned_user's status).
select set_config('t.mention_post', (select create_post('Mentioning @target82 after her suspension.')::text), false);
do $$ begin
  if exists (
    select 1 from jsonb_array_elements(
      (select mentions from get_thread(current_setting('t.mention_post')::bigint)
        where id = current_setting('t.mention_post')::bigint)
    ) m
    where (m ->> 'handle') = 'target82'
  ) then
    raise exception 'FAIL: a post-suspension mention of a suspended member still resolved to her handle';
  end if;
end $$;
reset role;

-- ============================================================
-- THE KNOWN, ALREADY-QUEUED GAP: status_expires_at only clears on the
-- suspended member's OWN next sign-in (refresh_my_status(), self-only,
-- `where user_id = auth.uid()`). Confirmed here, not re-discovered:
-- once the clock in status_expires_at has passed, her content stays
-- hidden to EVERYONE else until she personally returns. Nothing else
-- in the schema — no cron, no trigger, no other member's read, no
-- Owner action — clears it. Run BEFORE the profile-row finding below,
-- so that finding is checked while she is unambiguously still
-- 'suspended', not yet restored.
-- ============================================================
update profiles set status_expires_at = now() - interval '1 hour'
 where user_id = '00000000-0000-0000-0000-000000000082';

-- The viewer reading the feed does NOT flip anyone else's status —
-- feed/profile reads never call refresh_my_status for another user,
-- and her content stays hidden despite the clock having run out.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000081', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000081","aal":"aal1","session_id":"v"}', false);
do $$ begin
  if exists (select 1 from profile_posts('00000000-0000-0000-0000-000000000082'::uuid)) then
    raise exception 'FAIL: content reappeared without anyone calling refresh_my_status — gap characterisation is stale, re-check';
  end if;
end $$;
reset role;

-- refresh_my_status() is self-only: another member calling it (even
-- the viewer, even the Owner) cannot clear a DIFFERENT member's expiry.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000081', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000081","aal":"aal1","session_id":"v"}', false);
select refresh_my_status();
reset role;
do $$ begin
  if (select status from profiles where user_id = '00000000-0000-0000-0000-000000000082') <> 'suspended' then
    raise exception 'FAIL: another member''s refresh_my_status() call flipped the suspended member''s status — should be impossible (self-only)';
  end if;
end $$;

-- Only the suspended member's OWN next sign-in (her own
-- refresh_my_status() call, exactly as the app runs on login/layout
-- load) clears it, and only then does her content reappear.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000082', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000082","aal":"aal1","session_id":"t"}', false);
select refresh_my_status();
reset role;
do $$ begin
  if (select status from profiles where user_id = '00000000-0000-0000-0000-000000000082') <> 'active' then
    raise exception 'FAIL: the suspended member''s own refresh_my_status() call did not clear her expired suspension';
  end if;
end $$;

-- ============================================================
-- THE FINDING: the profile ROW ITSELF (handle, bio, founding badge,
-- join date) is still fully readable — exactly what
-- src/app/(member)/u/[handle]/page.tsx does: a plain
-- `.from("profiles").select(...)` with NO status filter in the app
-- code, relying entirely on RLS. The `profiles_read` policy
-- (20261006000001_social_core_hardening.sql) excludes ONLY
-- status = 'deleted':
--     status <> 'deleted' and (user_id = auth.uid() or
--       (is_active_member() and not internal.blocked_by(...)))
-- 'suspended' and 'banned' are BOTH still readable under this policy.
-- She is re-suspended here (the gap section above restored her to
-- active) purely so this check runs against an unambiguous
-- 'suspended' row — the leak is identical for 'banned' (shown
-- separately via a direct psql probe in the QA report).
-- The assertion below encodes the PUBLISHED PROMISE (profile removed)
-- and will FAIL against the current schema — that failure IS the
-- finding, reported in full in the QA report, not silenced here.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"ow"}', false);
select mod_suspend('00000000-0000-0000-0000-000000000082', 7, 'harassment', 'QA re-suspend for the profile-row finding');
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000081', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000081","aal":"aal1","session_id":"v"}', false);
do $$ begin
  if exists (select 1 from profiles where user_id = '00000000-0000-0000-0000-000000000082') then
    raise exception 'FAIL (CONFIRMED PRODUCT BUG, not a test bug): a suspended member''s profile row (handle/bio/founding badge/join date) is still directly readable by an uninvolved member — contradicts the published Community Guidelines promise and the corrected SuspendedScreen copy from commit 097c318. Fix belongs in the profiles_read RLS policy (exclude suspended/banned, not only deleted) and/or the profile page (status-check before rendering), not in this test.';
  end if;
end $$;
reset role;
\echo IF YOU SEE THIS, THE PROFILE-VISIBILITY BUG HAS BEEN FIXED -- remove the FINDING comment above; this file then passes clean end to end.

rollback;
\echo ALL SUSPENSION-VISIBILITY REGRESSION CHECKS PASSED EXCEPT THE PROFILE-ROW FINDING (see report)

