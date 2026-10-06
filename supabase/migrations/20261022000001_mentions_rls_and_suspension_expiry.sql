-- ============================================================
-- 20261022000001 — Two pre-launch audit fixes (P2-1, P2-2).
--
-- 1. post_mentions_read gains the block filter it always should have
--    had. Since 0013 the policy was `is_active_member()` alone, so a
--    blocked member could still read (post_id, mentioned_user_id)
--    rows for posts she is blocked from seeing — who was mentioned,
--    and which posts mention a given person. The post CONTENT was
--    protected by posts_read; this metadata was not, and for a member
--    who is being tracked by someone the metadata is itself
--    dangerous. The rewrite mirrors the established policy pattern
--    (likes_own_insert, reshares_own_insert): an EXISTS over the
--    posts primary key plus the explicit internal.blocked_either
--    check, with auth.uid() passed as a party so the caller-scope
--    guard (0014 P1-1) is satisfied. Evaluated as an app role the
--    EXISTS also runs under posts_read, so mentions of posts the
--    caller cannot see at all (deleted, moderation-hidden) stop
--    leaking too; the explicit block check is NOT redundant with
--    that — in a context that bypasses posts RLS (table owner) it is
--    the only filter.
--
-- 2. Suspensions now actually end. Until now a lapsed restriction or
--    suspension was cleared only by refresh_my_status() (0018), which
--    runs when THAT member next signs in. If she never comes back,
--    her account stays suspended — and her posts invisible to
--    everyone — forever. The published Community Guidelines promise
--    the opposite ("When the suspension ends … your account and all
--    of your content come back"), so this is now a correctness bug,
--    not tidiness. A pg_cron sweep clears lapsed statuses every five
--    minutes, mirroring refresh_my_status() EXACTLY: status →
--    'active', status_expires_at → null, one 'mod.status_expired'
--    audit row per member, and nothing else (the sign-in path sends
--    no notification, so neither does the sweep; append_audit records
--    the actor as 'system' when there is no session, which is the
--    truth). The sign-in path stays in place — belt and braces. The
--    profiles status trigger (trg_profiles_status_events, 0023)
--    fires identically on both paths, so the account_status_events
--    ledger sees sweep-cleared and sign-in-cleared lapses the same
--    way. Concurrent runs cannot double-process: under READ COMMITTED
--    the UPDATE re-checks its predicate after taking the row lock, so
--    whichever of the sweep and refresh_my_status() loses the race
--    matches zero rows and writes no audit entry.
--
-- Idempotent throughout: drop policy if exists / create or replace /
-- create extension if not exists / cron.schedule, which upserts by
-- job name. No existing RPC signature changes (sweep_expired_statuses
-- is new, and is not callable by any app role).
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- 1. post_mentions: invisible across a block, like the post itself.
-- ------------------------------------------------------------
drop policy if exists post_mentions_read on post_mentions;
create policy post_mentions_read on post_mentions for select
  using (
    is_active_member()
    and exists (select 1 from posts p
                where p.id = post_id
                  and not internal.blocked_either(auth.uid(), p.author_id))
  );

-- ------------------------------------------------------------
-- 2a. The sweep. Same predicate, same outcome, same audit action as
--     refresh_my_status() (0018) — only the trigger differs (clock,
--     not sign-in). Returns how many accounts it reopened, for
--     operational visibility when run by hand.
-- ------------------------------------------------------------
create or replace function sweep_expired_statuses() returns integer
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_user  uuid;
  v_count integer := 0;
begin
  for v_user in
    with flipped as (
      update profiles
         set status = 'active', status_expires_at = null
       where status in ('restricted', 'suspended')
         and status_expires_at is not null
         and status_expires_at <= now()
       returning user_id
    )
    select user_id from flipped
  loop
    perform append_audit('mod.status_expired', 'user', v_user::text);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- Scheduler-only: no app role may call it (Supabase's default
-- privileges would otherwise hand EXECUTE to all of them).
revoke execute on function sweep_expired_statuses()
  from public, anon, authenticated, service_role;

-- ------------------------------------------------------------
-- 2b. Install pg_cron where the platform offers it (hosted Supabase
--     does — 1.6.4 available, not yet installed on this project).
--     Guarded on pg_available_extensions so a local test stack
--     without the package still applies this file cleanly (0010's
--     pattern); the inner guard covers a stack that packages pg_cron
--     but has not preloaded it (shared_preload_libraries), where
--     CREATE EXTENSION itself refuses. On any stack where the
--     extension does not land, the sweep is simply not scheduled and
--     lapsed statuses clear on sign-in exactly as before this
--     migration — nothing breaks, the Guidelines promise just is not
--     kept there.
-- ------------------------------------------------------------
do $do$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    begin
      create extension if not exists pg_cron;
    exception when others then
      raise notice 'pg_cron could not be installed here (%); status sweep not scheduled.', sqlerrm;
    end;
  end if;
end
$do$;

-- ------------------------------------------------------------
-- 2c. Schedule the sweep. cron.schedule upserts by job name, so
--     re-running this file never creates a duplicate job. Five
--     minutes is ample: nothing is latency-critical about the end of
--     a suspension, and the sweep is one indexed-predicate UPDATE
--     that is almost always a no-op.
-- ------------------------------------------------------------
do $do$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'hersciety-status-expiry-sweep',
      '*/5 * * * *',
      $cron$ select public.sweep_expired_statuses(); $cron$
    );
  end if;
end
$do$;
