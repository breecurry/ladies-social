-- ============================================================
-- 0010 — Scheduled jobs.
--
-- pg_cron is available on hosted Supabase (enable under Database →
-- Extensions). The schedule below is applied only when the extension
-- is present, so this migration is safe on local stacks without it;
-- the /api/internal/jobs/drain endpoint (cron-secret protected) is the
-- equivalent external trigger for environments without pg_cron.
-- ============================================================
set search_path = public, extensions;

do $do$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'uf-lapse-vouch-requests',
      '*/15 * * * *',
      $cron$ select public.lapse_expired_vouch_requests(); $cron$
    );
  end if;
end
$do$;
