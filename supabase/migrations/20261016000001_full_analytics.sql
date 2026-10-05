-- ============================================================
-- 0023 — Full analytics (the owner's decision, in her own words):
-- "EVERY GODDAMN THING STARTS AT ZERO. it goes up by one when it
-- increases by one, it goes down by one when it decreases by one.
-- I want FULL analytics."
--
-- This migration removes every metric restriction that migration
-- 20261014000001 shipped — the k=5 small-N suppression and the
-- "refused metrics" prohibition — because neither was ever the
-- owner's decision. Every number the Owner sees is now the literal
-- number, and the previously-absent metrics (DAU/WAU/MAU and
-- stickiness, sessions and time-on-site, presence and precise
-- last-seen, per-member leaderboards, streaks, virality, retention)
-- are computed and returned.
--
-- Forward-only and idempotent: safe against the live database where
-- 0001-0022 are applied, and safe to re-run (guarded DDL; the
-- tracked-since rows keep their original timestamps on a re-run).
--
-- WHAT IS DELIBERATELY UNCHANGED — these are privacy rules, not
-- metric restrictions:
--   • No function here SELECTs or references profiles.display_name.
--     Members are identified by @handle everywhere. The audited AAL2
--     identity reveal (owner_reveal_identity) remains the only path
--     to a legal name.
--   • Everything is Owner-only at the DATA layer: owner_metrics()
--     raises for a non-Owner caller. Hiding the UI is not the gate.
--   • Every new table has row-level security enabled. The
--     zero-tables-without-RLS invariant holds.
--   • SECURITY DEFINER functions pin search_path; EXECUTE is
--     authenticated-only (anon and service_role hold nothing).
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- 1. COLLECTION: sessions and presence. A member's client sends a
--    cheap heartbeat while she is active; a session is a run of
--    heartbeats with no gap longer than 30 minutes. Duration is
--    derived (last_seen_at - started_at). This is the data behind
--    session count, time-on-site, who-is-online, and precise
--    per-member last-seen.
-- ------------------------------------------------------------
create table if not exists member_sessions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references profiles (user_id) on delete cascade,
  started_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index if not exists idx_member_sessions_user_seen on member_sessions (user_id, last_seen_at desc);
create index if not exists idx_member_sessions_seen on member_sessions (last_seen_at desc);

alter table member_sessions enable row level security;

-- A member may read her own sessions (her data, her transparency).
-- All writes go through session_heartbeat(); there is no direct
-- INSERT/UPDATE/DELETE privilege for any app role.
drop policy if exists member_sessions_read_own on member_sessions;
create policy member_sessions_read_own on member_sessions
  for select to authenticated using (user_id = auth.uid());

revoke all on member_sessions from public, anon, authenticated, service_role;
grant select on member_sessions to authenticated; -- RLS scopes to own rows

-- The heartbeat. Called by the signed-in client roughly once a
-- minute while the tab is visible. Extends the open session or
-- starts a new one.
create or replace function session_heartbeat()
returns void
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  v_uid     uuid := auth.uid();
  v_session uuid;
begin
  if v_uid is null then
    raise exception 'Not signed in.';
  end if;
  if not exists (select 1 from profiles pr where pr.user_id = v_uid and not pr.is_system) then
    raise exception 'No such member.';
  end if;

  select ms.id into v_session
  from member_sessions ms
  where ms.user_id = v_uid
    and ms.last_seen_at >= now() - interval '30 minutes'
  order by ms.last_seen_at desc
  limit 1;

  if v_session is null then
    insert into member_sessions (user_id) values (v_uid);
  else
    update member_sessions set last_seen_at = now() where id = v_session;
  end if;
end $$;

revoke execute on function session_heartbeat() from public, anon, service_role;
grant execute on function session_heartbeat() to authenticated;

-- ------------------------------------------------------------
-- 2. COLLECTION: departures. "It goes down by one when it decreases
--    by one" requires recording when an account leaves. The schema
--    had no departure timestamps, so net change was not computable.
--    Now: profiles carries deactivated_at / banned_at / deleted_at
--    (non-null exactly while the account is in that state), and
--    every status transition is appended to account_status_events,
--    the ledger that makes net change over any range a real number.
--    No backfill — past events were never recorded and are not
--    fabricated; the tracked-since timestamp labels the series
--    honestly.
-- ------------------------------------------------------------
alter table profiles add column if not exists deactivated_at timestamptz;
alter table profiles add column if not exists banned_at      timestamptz;
alter table profiles add column if not exists deleted_at     timestamptz;

create table if not exists account_status_events (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references profiles (user_id) on delete cascade,
  from_status account_status not null,
  to_status   account_status not null,
  occurred_at timestamptz not null default now()
);
create index if not exists idx_account_status_events_time on account_status_events (occurred_at desc);
create index if not exists idx_account_status_events_user on account_status_events (user_id);

alter table account_status_events enable row level security;
-- No policies: no app role reads or writes this ledger directly.
-- The trigger below writes it; owner_metrics() reads it.
revoke all on account_status_events from public, anon, authenticated, service_role;

create or replace function stamp_status_change() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if new.status is distinct from old.status then
    insert into account_status_events (user_id, from_status, to_status)
      values (new.user_id, old.status, new.status);
    if new.status = 'deactivated' then new.deactivated_at := now(); end if;
    if new.status = 'banned'      then new.banned_at      := now(); end if;
    if new.status = 'deleted'     then new.deleted_at     := now(); end if;
    if old.status = 'deactivated' and new.status <> 'deactivated' then new.deactivated_at := null; end if;
    if old.status = 'banned'      and new.status <> 'banned'      then new.banned_at      := null; end if;
    if old.status = 'deleted'     and new.status <> 'deleted'     then new.deleted_at     := null; end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_profiles_status_events on profiles;
create trigger trg_profiles_status_events
  before update of status on profiles
  for each row execute function stamp_status_change();

-- ------------------------------------------------------------
-- 3. When collection began, recorded once and preserved across
--    re-runs, so the dashboard can label the sessions and
--    departures series honestly instead of implying history that
--    was never collected.
-- ------------------------------------------------------------
create table if not exists analytics_collection (
  series        text primary key,
  tracked_since timestamptz not null default now()
);
alter table analytics_collection enable row level security;
-- No policies: read via owner_metrics() only.
revoke all on analytics_collection from public, anon, authenticated, service_role;

insert into analytics_collection (series) values ('sessions'), ('departures')
on conflict (series) do nothing;

-- ------------------------------------------------------------
-- 4. Internal helper: distinct members with any authentic activity
--    (post, like, follow, login, session heartbeat) since a moment.
--    EXECUTE granted to no app role; called only from inside
--    owner_metrics(). Powers DAU / WAU / MAU and active members.
-- ------------------------------------------------------------
create or replace function owner_active_since(p_since timestamptz)
returns bigint language sql stable as $$
  select count(distinct u.uid)
  from (
    select p.author_id as uid from posts p
     where p.created_at >= p_since and p.deleted_at is null
    union
    select f.follower_id from follows f where f.created_at >= p_since
    union
    select l.user_id from likes l where l.created_at >= p_since
    union
    select up.user_id from user_private up where up.last_login_at >= p_since
    union
    select ms.user_id from member_sessions ms where ms.last_seen_at >= p_since
  ) u
  join profiles pr on pr.user_id = u.uid
  where not pr.is_system and pr.status not in ('deleted', 'banned')
$$;

revoke execute on function owner_active_since(timestamptz) from public, anon, authenticated, service_role;

-- ------------------------------------------------------------
-- 5. owner_metrics(), superseding the 0022 version. One read, the
--    whole picture, every number literal. No suppression, no
--    withheld percentages, no floors: 1 means 1, 0 means 0.
--    Ranges: 'today' | '7d' | '30d' | 'all'. Raises for non-Owners.
-- ------------------------------------------------------------
create or replace function owner_metrics(p_range text default '30d')
returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_now        timestamptz := now();
  v_start      timestamptz;
  v_prev_start timestamptz;
  v_bucket     text; -- date_trunc unit for series
  v_total           bigint;
  v_deactivated     bigint;
  v_breakdown       jsonb;
  v_signups         bigint;
  v_signups_prev    bigint;
  v_signup_series   jsonb;
  v_departed        bigint;
  v_returned        bigint;
  v_dep_since       timestamptz;
  v_active          bigint;
  v_posts           bigint;
  v_posts_prev      bigint;
  v_post_series     jsonb;
  v_filed           bigint;
  v_filed_prev      bigint;
  v_resolved        bigint;
  v_median_hours    numeric;
  v_actions         bigint;
  v_action_breakdown jsonb;
  v_dau             bigint;
  v_wau             bigint;
  v_mau             bigint;
  v_sess_count      bigint;
  v_sess_total_min  numeric;
  v_sess_avg_min    numeric;
  v_sess_median_min numeric;
  v_sess_since      timestamptz;
  v_online          bigint;
  v_online_list     jsonb;
  v_last_seen       jsonb;
  v_top_posters     jsonb;
  v_likes_given     jsonb;
  v_likes_received  jsonb;
  v_by_sessions     jsonb;
  v_follower_growth jsonb;
  v_streaks         jsonb;
  v_longest_streak  bigint;
  v_likes_in_range  bigint;
  v_follows_in_range bigint;
  v_avg_depth       numeric;
  v_max_depth       integer;
  v_retention       jsonb := '{}'::jsonb;
  v_n               integer;
  v_eligible        bigint;
  v_came_back       bigint;
begin
  if not is_owner() then
    raise exception 'Only the Owner may read the metrics.';
  end if;

  case coalesce(p_range, '30d')
    when 'today' then v_start := date_trunc('day', v_now);                  v_bucket := 'hour';
    when '7d'    then v_start := v_now - interval '7 days';                 v_bucket := 'day';
    when '30d'   then v_start := v_now - interval '30 days';                v_bucket := 'day';
    when 'all'   then v_start := null;                                      v_bucket := 'week';
    else raise exception 'Unknown range %', p_range;
  end case;
  v_prev_start := case when v_start is null then null
                       else v_start - (v_now - v_start) end;

  -- Total members: headline excludes system, deleted, banned;
  -- deactivated counted, surfaced as a sub-figure. The status
  -- breakdown is exact at every count.
  select count(*) filter (where status not in ('deleted', 'banned')),
         count(*) filter (where status = 'deactivated')
    into v_total, v_deactivated
  from profiles where not is_system;
  v_deactivated := coalesce(v_deactivated, 0);

  select coalesce(jsonb_agg(jsonb_build_object('label', s.status, 'count', s.n)
         order by s.status), '[]'::jsonb)
    into v_breakdown
  from (
    select st.status::text, count(pr.user_id) as n
    from unnest(array['active','restricted','suspended','banned','deactivated']) as st(status)
    left join profiles pr on pr.status::text = st.status and not pr.is_system
    group by st.status
  ) s;

  -- Signups over time.
  select count(*) into v_signups from profiles
   where not is_system and (v_start is null or created_at >= v_start);
  if v_prev_start is not null then
    select count(*) into v_signups_prev from profiles
     where not is_system
       and created_at >= v_prev_start and created_at < v_start;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('t', t.d, 'v', t.n) order by t.d), '[]'::jsonb)
    into v_signup_series
  from (
    select to_char(date_trunc(v_bucket, created_at), 'YYYY-MM-DD"T"HH24:MI') as d, count(*) as n
    from profiles
    where not is_system and (v_start is null or created_at >= v_start)
    group by 1
  ) t;

  -- Net change: +1 when a member arrives, -1 when one leaves (banned
  -- or deleted — the headline's own definition), +1 when one is
  -- reinstated. Departures are real recorded events from
  -- account_status_events; collection starts at the tracked-since
  -- moment and no history is fabricated.
  select count(*) filter (where e.to_status   in ('banned','deleted')
                            and e.from_status not in ('banned','deleted')),
         count(*) filter (where e.from_status in ('banned','deleted')
                            and e.to_status   not in ('banned','deleted'))
    into v_departed, v_returned
  from account_status_events e
  join profiles pr on pr.user_id = e.user_id
  where not pr.is_system
    and (v_start is null or e.occurred_at >= v_start);
  select ac.tracked_since into v_dep_since from analytics_collection ac where ac.series = 'departures';

  -- Active members: distinct members with an authentic action in the
  -- last 30 days (posted, followed, liked, logged in, or had a live
  -- session).
  v_active := owner_active_since(v_now - interval '30 days');

  -- DAU / WAU / MAU: distinct active members over the standard fixed
  -- windows, plus the DAU/MAU stickiness ratio.
  v_dau := owner_active_since(v_now - interval '1 day');
  v_wau := owner_active_since(v_now - interval '7 days');
  v_mau := owner_active_since(v_now - interval '30 days');

  -- Posts (member-visible content, not removed/deleted items).
  select count(*) into v_posts from posts
   where deleted_at is null and visibility = 'visible'
     and (v_start is null or created_at >= v_start);
  if v_prev_start is not null then
    select count(*) into v_posts_prev from posts
     where deleted_at is null and visibility = 'visible'
       and created_at >= v_prev_start and created_at < v_start;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('t', t.d, 'v', t.n) order by t.d), '[]'::jsonb)
    into v_post_series
  from (
    select to_char(date_trunc(v_bucket, created_at), 'YYYY-MM-DD"T"HH24:MI') as d, count(*) as n
    from posts
    where deleted_at is null and visibility = 'visible'
      and (v_start is null or created_at >= v_start)
    group by 1
  ) t;

  -- Reports filed and resolved; median time to resolution.
  select count(*) into v_filed from reports
   where v_start is null or created_at >= v_start;
  if v_prev_start is not null then
    select count(*) into v_filed_prev from reports
     where created_at >= v_prev_start and created_at < v_start;
  end if;
  select count(*),
         round(extract(epoch from percentile_cont(0.5) within group
                       (order by (resolved_at - created_at))) / 3600.0, 1)
    into v_resolved, v_median_hours
  from reports
  where resolved_at is not null
    and status in ('actioned', 'dismissed')
    and (v_start is null or resolved_at >= v_start);

  -- Enforcement actions, breakdown exact at every count.
  select count(*) into v_actions from moderation_actions
   where v_start is null or created_at >= v_start;
  select coalesce(jsonb_agg(jsonb_build_object('label', a.action, 'count', a.n)
         order by a.n desc, a.action), '[]'::jsonb)
    into v_action_breakdown
  from (
    select ma.action::text, count(*) as n
    from moderation_actions ma
    where v_start is null or ma.created_at >= v_start
    group by ma.action
  ) a;

  -- Sessions and time-on-site, from the heartbeat collection.
  select count(*),
         round(coalesce(sum(extract(epoch from (ms.last_seen_at - ms.started_at))), 0) / 60.0, 1),
         round(coalesce(avg(extract(epoch from (ms.last_seen_at - ms.started_at))), 0) / 60.0, 1),
         round(coalesce((percentile_cont(0.5) within group
               (order by extract(epoch from (ms.last_seen_at - ms.started_at))))::numeric, 0) / 60.0, 1)
    into v_sess_count, v_sess_total_min, v_sess_avg_min, v_sess_median_min
  from member_sessions ms
  join profiles pr on pr.user_id = ms.user_id
  where not pr.is_system
    and (v_start is null or ms.started_at >= v_start);
  select ac.tracked_since into v_sess_since from analytics_collection ac where ac.series = 'sessions';

  -- Presence: who is online right now (heartbeat within 5 minutes),
  -- and precise per-member last-seen (latest heartbeat, falling back
  -- to last login where no session exists yet).
  select count(distinct ms.user_id) into v_online
  from member_sessions ms
  join profiles pr on pr.user_id = ms.user_id
  where not pr.is_system and ms.last_seen_at >= v_now - interval '5 minutes';

  select coalesce(jsonb_agg(jsonb_build_object('handle', o.handle, 'last_seen', o.seen)
         order by o.seen desc), '[]'::jsonb)
    into v_online_list
  from (
    select pr.handle::text as handle, max(ms.last_seen_at) as seen
    from member_sessions ms
    join profiles pr on pr.user_id = ms.user_id
    where not pr.is_system and ms.last_seen_at >= v_now - interval '5 minutes'
    group by pr.handle
  ) o;

  select coalesce(jsonb_agg(jsonb_build_object('handle', ls.handle, 'last_seen', ls.seen)
         order by ls.seen desc), '[]'::jsonb)
    into v_last_seen
  from (
    select pr.handle::text as handle,
           greatest(
             coalesce((select max(ms.last_seen_at) from member_sessions ms where ms.user_id = pr.user_id), '-infinity'),
             coalesce(up.last_login_at, '-infinity')
           ) as seen
    from profiles pr
    left join user_private up on up.user_id = pr.user_id
    where not pr.is_system and pr.status <> 'deleted'
    order by 2 desc
    limit 100
  ) ls
  where ls.seen > '-infinity';

  -- Per-member leaderboards (range-scoped, top 10, @handle only).
  select coalesce(jsonb_agg(jsonb_build_object('handle', t.handle, 'value', t.n)
         order by t.n desc, t.handle), '[]'::jsonb)
    into v_top_posters
  from (
    select pr.handle::text as handle, count(*) as n
    from posts p join profiles pr on pr.user_id = p.author_id
    where p.deleted_at is null and not pr.is_system and pr.status <> 'deleted'
      and (v_start is null or p.created_at >= v_start)
    group by pr.handle order by count(*) desc, pr.handle limit 10
  ) t;

  select coalesce(jsonb_agg(jsonb_build_object('handle', t.handle, 'value', t.n)
         order by t.n desc, t.handle), '[]'::jsonb)
    into v_likes_given
  from (
    select pr.handle::text as handle, count(*) as n
    from likes l join profiles pr on pr.user_id = l.user_id
    where not pr.is_system and pr.status <> 'deleted'
      and (v_start is null or l.created_at >= v_start)
    group by pr.handle order by count(*) desc, pr.handle limit 10
  ) t;

  select coalesce(jsonb_agg(jsonb_build_object('handle', t.handle, 'value', t.n)
         order by t.n desc, t.handle), '[]'::jsonb)
    into v_likes_received
  from (
    select pr.handle::text as handle, count(*) as n
    from likes l
    join posts p on p.id = l.post_id
    join profiles pr on pr.user_id = p.author_id
    where not pr.is_system and pr.status <> 'deleted'
      and (v_start is null or l.created_at >= v_start)
    group by pr.handle order by count(*) desc, pr.handle limit 10
  ) t;

  select coalesce(jsonb_agg(jsonb_build_object('handle', t.handle, 'value', t.n)
         order by t.n desc, t.handle), '[]'::jsonb)
    into v_by_sessions
  from (
    select pr.handle::text as handle, count(*) as n
    from member_sessions ms join profiles pr on pr.user_id = ms.user_id
    where not pr.is_system and pr.status <> 'deleted'
      and (v_start is null or ms.started_at >= v_start)
    group by pr.handle order by count(*) desc, pr.handle limit 10
  ) t;

  select coalesce(jsonb_agg(jsonb_build_object('handle', t.handle, 'value', t.n)
         order by t.n desc, t.handle), '[]'::jsonb)
    into v_follower_growth
  from (
    select pr.handle::text as handle, count(*) as n
    from follows f join profiles pr on pr.user_id = f.followee_id
    where not pr.is_system and pr.status <> 'deleted'
      and (v_start is null or f.created_at >= v_start)
    group by pr.handle order by count(*) desc, pr.handle limit 10
  ) t;

  -- Consecutive-day streaks per member: distinct days with any
  -- activity, counted back without a gap from the member's most
  -- recent active day, provided that day is today or yesterday.
  select coalesce(jsonb_agg(jsonb_build_object('handle', s.handle, 'value', s.streak)
         order by s.streak desc, s.handle), '[]'::jsonb),
         coalesce(max(s.streak), 0)
    into v_streaks, v_longest_streak
  from (
    with activity_days as (
      select distinct uid, d from (
        select p.author_id as uid, (p.created_at at time zone 'UTC')::date as d
          from posts p where p.deleted_at is null
        union all
        select l.user_id, (l.created_at at time zone 'UTC')::date from likes l
        union all
        select f.follower_id, (f.created_at at time zone 'UTC')::date from follows f
        union all
        select ms.user_id, (ms.started_at at time zone 'UTC')::date from member_sessions ms
        union all
        select ms.user_id, (ms.last_seen_at at time zone 'UTC')::date from member_sessions ms
        union all
        select up.user_id, (up.last_login_at at time zone 'UTC')::date
          from user_private up where up.last_login_at is not null
      ) raw
    ), ranked as (
      select uid, d,
             row_number() over (partition by uid order by d desc) as rn,
             max(d) over (partition by uid) as md
      from activity_days
    )
    select pr.handle::text as handle, count(*) as streak
    from ranked r
    join profiles pr on pr.user_id = r.uid
    where not pr.is_system and pr.status not in ('deleted', 'banned')
      and r.md >= (v_now at time zone 'UTC')::date - 1
      and r.d = r.md - (r.rn - 1)::integer
    group by pr.handle
    order by count(*) desc, pr.handle
    limit 10
  ) s;

  -- Virality / reach.
  select count(*) into v_likes_in_range from likes
   where v_start is null or created_at >= v_start;
  select count(*) into v_follows_in_range from follows
   where v_start is null or created_at >= v_start;
  select round(coalesce(avg(depth) filter (where depth > 0), 0), 2),
         coalesce(max(depth), 0)
    into v_avg_depth, v_max_depth
  from posts
  where deleted_at is null
    and (v_start is null or created_at >= v_start);

  -- Retention: of each signup cohort old enough to measure, the
  -- share that acted again at or after 1 / 7 / 30 days. Rates are
  -- real percentages whatever the base.
  foreach v_n in array array[1, 7, 30] loop
    select count(*),
           count(*) filter (where exists (
             select 1 from posts p
              where p.author_id = pr.user_id and p.deleted_at is null
                and p.created_at >= pr.created_at + make_interval(days => v_n)
             union all
             select 1 from likes l
              where l.user_id = pr.user_id
                and l.created_at >= pr.created_at + make_interval(days => v_n)
             union all
             select 1 from follows f
              where f.follower_id = pr.user_id
                and f.created_at >= pr.created_at + make_interval(days => v_n)
             union all
             select 1 from member_sessions ms
              where ms.user_id = pr.user_id
                and ms.last_seen_at >= pr.created_at + make_interval(days => v_n)
             union all
             select 1 from user_private up
              where up.user_id = pr.user_id and up.last_login_at is not null
                and up.last_login_at >= pr.created_at + make_interval(days => v_n)
           ))
      into v_eligible, v_came_back
    from profiles pr
    where not pr.is_system
      and pr.created_at <= v_now - make_interval(days => v_n);
    v_retention := v_retention || jsonb_build_object(
      'd' || v_n::text,
      jsonb_build_object(
        'eligible', coalesce(v_eligible, 0),
        'returned', coalesce(v_came_back, 0),
        'rate', case when coalesce(v_eligible, 0) = 0 then null
                     else round(v_came_back * 100.0 / v_eligible, 1) end));
  end loop;

  return jsonb_build_object(
    'range', coalesce(p_range, '30d'),
    'total_members', jsonb_build_object(
      'value', coalesce(v_total, 0),
      'deactivated', v_deactivated,
      'joined_in_range', coalesce(v_signups, 0),
      'departed_in_range', coalesce(v_departed, 0),
      'returned_in_range', coalesce(v_returned, 0),
      'net_change', coalesce(v_signups, 0) - coalesce(v_departed, 0) + coalesce(v_returned, 0),
      'departures_tracked_since', v_dep_since,
      'breakdown', v_breakdown),
    'signups', jsonb_build_object(
      'value', coalesce(v_signups, 0),
      'previous', v_signups_prev,
      'series', v_signup_series),
    'active_members', jsonb_build_object(
      'value', coalesce(v_active, 0),
      'window_days', 30,
      'total', coalesce(v_total, 0)),
    'posts', jsonb_build_object(
      'value', coalesce(v_posts, 0),
      'previous', v_posts_prev,
      'series', v_post_series),
    'reports_filed', jsonb_build_object(
      'value', coalesce(v_filed, 0),
      'previous', v_filed_prev),
    'reports_resolved', jsonb_build_object(
      'value', coalesce(v_resolved, 0),
      'filed', coalesce(v_filed, 0),
      'median_hours', v_median_hours),
    'enforcement_actions', jsonb_build_object(
      'value', coalesce(v_actions, 0),
      'breakdown', v_action_breakdown),
    'engagement', jsonb_build_object(
      'dau', coalesce(v_dau, 0),
      'wau', coalesce(v_wau, 0),
      'mau', coalesce(v_mau, 0),
      'stickiness', case when coalesce(v_mau, 0) = 0 then null
                         else round(v_dau * 100.0 / v_mau, 1) end),
    'sessions', jsonb_build_object(
      'count', coalesce(v_sess_count, 0),
      'total_minutes', coalesce(v_sess_total_min, 0),
      'average_minutes', coalesce(v_sess_avg_min, 0),
      'median_minutes', coalesce(v_sess_median_min, 0),
      'tracked_since', v_sess_since),
    'presence', jsonb_build_object(
      'online_now', coalesce(v_online, 0),
      'online', v_online_list,
      'last_seen', v_last_seen),
    'leaderboards', jsonb_build_object(
      'top_posters', v_top_posters,
      'likes_given', v_likes_given,
      'likes_received', v_likes_received,
      'by_sessions', v_by_sessions,
      'follower_growth', v_follower_growth),
    'streaks', jsonb_build_object(
      'longest_current', coalesce(v_longest_streak, 0),
      'members', v_streaks),
    'virality', jsonb_build_object(
      'posts_per_member', case when coalesce(v_total, 0) = 0 then null
                               else round(coalesce(v_posts, 0)::numeric / v_total, 2) end,
      'likes_per_post', case when coalesce(v_posts, 0) = 0 then null
                             else round(v_likes_in_range::numeric / v_posts, 2) end,
      'avg_reply_depth', coalesce(v_avg_depth, 0),
      'max_reply_depth', coalesce(v_max_depth, 0),
      'likes_in_range', coalesce(v_likes_in_range, 0),
      'follows_in_range', coalesce(v_follows_in_range, 0)),
    'retention', v_retention);
end $$;

revoke execute on function owner_metrics(text) from public, anon, service_role;
grant execute on function owner_metrics(text) to authenticated;
