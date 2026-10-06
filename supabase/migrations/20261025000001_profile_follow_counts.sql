-- ============================================================
-- 20261025000001 — profile_follow_counts(): follower/following COUNTS
-- that agree with the follower/following LISTS.
--
-- The profile page counted rows in `follows` directly, with no join to
-- profiles, so suspended / banned / deactivated counterparties — and
-- counterparties the viewer has blocked or been blocked by — were
-- still counted. The LISTS at /u/<handle>/followers and /following go
-- through list_followers() / list_following() (20261006000001), which
-- DO filter. A viewer therefore saw "12 followers" above a list of 10.
--
-- This function reuses the lists' predicate VERBATIM (minus
-- pagination): the caller must be an active member; the viewer and the
-- profile owner must not be blocked either way; each counted
-- counterparty must not be blocked either way with the viewer; and the
-- counterparty's profile must be 'active' or 'restricted'. Blocks ARE
-- therefore reflected in the count, deliberately: the number above the
-- list must equal the number of rows in the list, or the difference
-- becomes a side channel revealing exactly what the lists are designed
-- to hide (enforced accounts and block relationships). Suite 21 pins
-- counts == lists directly.
--
-- Forward-only, idempotent, safe to re-run. ONE SIGNATURE ONLY: the
-- function is dropped by its exact signature and recreated, then its
-- grants re-applied. Conventions mirror the neighbouring profile RPCs
-- (list_followers / list_following): SECURITY DEFINER, pinned
-- search_path, EXECUTE revoked from public/anon/service_role and
-- granted to authenticated only.
-- ============================================================
set search_path = public, extensions;

drop function if exists profile_follow_counts(uuid);
create function profile_follow_counts(p_user uuid)
returns table (follower_count bigint, following_count bigint)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select
    (select count(*)
       from follows f
       join profiles pr on pr.user_id = f.follower_id
      where exists (select 1 from profiles me
                    where me.user_id = auth.uid() and me.status in ('active', 'restricted'))
        and f.followee_id = p_user
        and not blocked_either(auth.uid(), p_user)
        and not blocked_either(auth.uid(), pr.user_id)
        and pr.status in ('active', 'restricted')) as follower_count,
    (select count(*)
       from follows f
       join profiles pr on pr.user_id = f.followee_id
      where exists (select 1 from profiles me
                    where me.user_id = auth.uid() and me.status in ('active', 'restricted'))
        and f.follower_id = p_user
        and not blocked_either(auth.uid(), p_user)
        and not blocked_either(auth.uid(), pr.user_id)
        and pr.status in ('active', 'restricted')) as following_count
$$;

comment on function profile_follow_counts(uuid) is
  'Follower/following counts for a profile, filtered with the exact predicate list_followers()/list_following() use, so the count above a list always equals the rows in it. Counts over raw follows would leak enforced and blocked accounts the lists hide.';

revoke execute on function profile_follow_counts(uuid) from public, anon, service_role;
grant execute on function profile_follow_counts(uuid) to authenticated;
