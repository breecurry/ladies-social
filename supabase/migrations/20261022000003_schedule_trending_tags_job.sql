-- 20261022000003_schedule_trending_tags_job.sql
--
-- Schedules the trending-tags job that migration
-- `20261017000001_hashtags_mentions_reposts.sql` intended to create but
-- silently skipped.
--
-- WHY IT WAS SKIPPED
-- That migration wraps its `cron.schedule` call in
--     if exists (select 1 from pg_extension where extname = 'pg_cron') then
-- which is the right defensive shape, but `pg_cron` was NOT installed on this
-- project at the time, so the branch simply did not run and no job was ever
-- created. Nothing failed and nothing logged, which is exactly why it went
-- unnoticed: `compute_trending_tags()` has a read-through fallback, so
-- trending kept working, just computed on demand instead of precomputed.
--
-- `20261022000001` installed `pg_cron` (1.6.4) for the suspension-expiry
-- sweep, so the dependency now exists and the intended job can be created.
--
-- VERIFIED BEFORE WRITING THIS MIGRATION
--   * `public.compute_trending_tags()` EXISTS on live, zero arguments.
--   * `public.trending_tags` EXISTS on live.
--   * The sibling job from `20261001000010_jobs.sql`
--     (`uf-lapse-vouch-requests` -> `lapse_expired_vouch_requests()`) is
--     deliberately NOT revived here: that function no longer exists, because
--     the admission/vouch gate was deleted when registration became fully
--     open. Scheduling it would schedule a call to a missing function.
--     Its absence is correct, not an oversight.
--
-- The */15 schedule matches what 20261017000001 originally specified.
--
-- IDEMPOTENT: `cron.schedule` upserts by job name, so re-running leaves
-- exactly one job row. The extension guard keeps the file safe to run on a
-- database where pg_cron is unavailable.

set search_path = public, extensions;

do $do$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'hersciety-trending-tags',
      '*/15 * * * *',
      $cron$ select public.compute_trending_tags(); $cron$
    );
  else
    raise notice 'pg_cron not installed; trending-tags job not scheduled.';
  end if;
end
$do$;
