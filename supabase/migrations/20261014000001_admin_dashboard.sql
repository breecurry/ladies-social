-- ============================================================
-- 0022 — Admin dashboard and metrics (Phase 2D): the Owner's member
-- directory and the Insights metrics foundation
-- (docs/design-phase2d-admin-dashboard-and-metrics.md).
--
-- Forward-only and idempotent: safe against the live database where
-- 0001-0021 are applied, and safe to re-run. No new tables, so the
-- zero-tables-without-RLS invariant is untouched.
--
-- 🚨 OWNER-ONLY AT THE DATA LAYER (locked owner decision 2026-10-05).
-- Every function here is visible to the Owner role alone — not admins,
-- not moderators. The read functions filter on is_owner() so a
-- non-Owner caller gets ZERO ROWS; the action functions raise. Hiding
-- the UI is not the gate; this is. Widening visibility later is a
-- deliberate, logged capability, never a loosened default (spec §0.4).
--
-- 🚨 IDENTITY RULE, UNCHANGED AND STRUCTURAL: no function in this
-- migration SELECTs or references profiles.display_name. The directory
-- is precisely the surface where a legal name leaks by accident, so
-- the rule bites hardest here: every list row and glance view is
-- @handle-only (spec §0.2). The one identity read that exists at all,
-- owner_reveal_identity(), reads user_private (legal_name, contact,
-- IPs), requires the Owner at AAL2 plus a stated reason, and writes
-- the hash-chained audit log BEFORE returning a single byte. Identity
-- is a deliberate, logged, reasoned act, never a column.
--
-- 🚨 NO RAW ACTIVITY TIMESTAMP EVER REACHES A LIST (spec §3.4).
-- profiles has no last_active_at and must never gain one. The "last
-- active" signal derives server-side from user_private.last_login_at
-- and only the coarse BUCKET LABEL leaves these functions: 'Active
-- recently' / 'This month' / 'Earlier' / 'Dormant' / 'New, not yet
-- active'. A precise last-seen time is a stalker's metadata; the
-- precise value appears solely inside the AAL2-gated, audited
-- identity reveal, nowhere else.
--
-- NOTE (2026-10): this migration originally carried a "refused
-- metrics" prohibition and a k=5 small-N suppression rule. Neither was
-- ever the owner's decision — she asked for full, literal analytics —
-- and both are removed. Migration 20261016000001 supersedes
-- owner_metrics() below with the full-analytics version; the function
-- body here is kept byte-identical because this file is applied.
-- ============================================================
set search_path = public, extensions;

-- Guarded drops so a changed return shape can never break a re-run
-- (create-or-replace refuses a different row type). Grants are
-- re-issued at the bottom of this file, so drop+create is safe.
drop function if exists owner_activity_bucket(timestamptz);
drop function if exists owner_member_count();
drop function if exists owner_directory(text, account_status[], boolean, timestamptz, timestamptz, text[], timestamptz, uuid, integer);
drop function if exists owner_directory_count(text, account_status[], boolean, timestamptz, timestamptz, text[]);
drop function if exists owner_member_detail(citext);
drop function if exists owner_reveal_identity(uuid, text);
drop function if exists owner_directory_export(text, account_status[], boolean, timestamptz, timestamptz, text[]);
drop function if exists owner_metrics(text);

-- ------------------------------------------------------------
-- 1. The coarse activity bucket (spec §3.4). Internal helper: EXECUTE
--    is granted to no app role; it is only ever called from inside
--    the SECURITY DEFINER functions below. The five labels are the
--    complete vocabulary that may describe activity outside the
--    audited identity reveal.
-- ------------------------------------------------------------
create or replace function owner_activity_bucket(p_last_login timestamptz)
returns text language sql stable as $$
  select case
    when p_last_login is null                        then 'New, not yet active'
    when p_last_login >= now() - interval '7 days'   then 'Active recently'
    when p_last_login >= now() - interval '30 days'  then 'This month'
    when p_last_login >= now() - interval '180 days' then 'Earlier'
    else 'Dormant'
  end
$$;

revoke execute on function owner_activity_bucket(timestamptz) from public, anon, authenticated, service_role;

-- ------------------------------------------------------------
-- 2. The headline member count (spec §12.1, the owner's explicit
--    ask). Counts profiles EXCLUDING the system account (it is
--    infrastructure, not a member), EXCLUDING deleted accounts (a
--    deleted member asked to be gone; counting her dishonours the
--    request), and EXCLUDING banned accounts (available in the
--    metrics breakdown, not the headline). Deactivated accounts are
--    counted: a reversible step-away is still a member.
--    Non-Owner callers get zero — not an error, nothing.
-- ------------------------------------------------------------
create or replace function owner_member_count()
returns bigint
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select count(*)
  from profiles pr
  where is_owner()
    and not pr.is_system
    and pr.status not in ('deleted', 'banned')
$$;

-- ------------------------------------------------------------
-- 3. The directory read (spec §3, §4). Search-first: exact-and-prefix
--    @handle only (the locked people-search rule), filters for
--    status / staff role / join window / activity bucket, keyset
--    pagination on (created_at desc, user_id desc). Deleted accounts
--    and the system account never appear under any filter. Default
--    status view (null filter) is active+restricted+suspended —
--    "people who are here"; seeing banned or deactivated accounts is
--    a deliberate selection. The only identity in a row is @handle.
-- ------------------------------------------------------------
create or replace function owner_directory(
  p_query          text default null,
  p_statuses       account_status[] default null,
  p_staff_only     boolean default false,
  p_joined_after   timestamptz default null,
  p_joined_before  timestamptz default null,
  p_activity       text[] default null,
  p_before_created timestamptz default null,
  p_before_user    uuid default null,
  p_limit          integer default 50
) returns table (
  user_id           uuid,
  handle            text,
  founding          boolean,
  status            account_status,
  status_expires_at timestamptz,
  staff_role        text,
  joined_at         timestamptz,
  activity_bucket   text
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select pr.user_id,
         pr.handle::text,
         pr.founding_member,
         pr.status,
         pr.status_expires_at,
         (select ra.role::text from role_assignments ra
          where ra.user_id = pr.user_id and ra.revoked_at is null
          order by case ra.role when 'owner' then 0 when 'admin' then 1
                                when 'moderator' then 2 else 3 end
          limit 1),
         pr.created_at,
         owner_activity_bucket(up.last_login_at)
  from profiles pr
  left join user_private up on up.user_id = pr.user_id
  where is_owner()
    and not pr.is_system
    and pr.status <> 'deleted'
    and pr.status = any (coalesce(p_statuses,
          array['active', 'restricted', 'suspended']::account_status[]))
    -- Exact-and-prefix handle search only; '_' is literal in a handle,
    -- so escape it before it becomes a LIKE wildcard.
    and (p_query is null or trim(p_query) = ''
         or pr.handle::text like
            replace(replace(lower(trim(leading '@' from trim(p_query))), '\', '\\'), '_', '\_') || '%')
    and (not coalesce(p_staff_only, false)
         or exists (select 1 from role_assignments ra
                    where ra.user_id = pr.user_id and ra.revoked_at is null))
    and (p_joined_after  is null or pr.created_at >= p_joined_after)
    and (p_joined_before is null or pr.created_at <  p_joined_before)
    and (p_activity is null or cardinality(p_activity) = 0
         or owner_activity_bucket(up.last_login_at) = any (p_activity))
    and (p_before_created is null or p_before_user is null
         or (pr.created_at, pr.user_id) < (p_before_created, p_before_user))
  order by pr.created_at desc, pr.user_id desc
  limit least(greatest(coalesce(p_limit, 50), 1), 100)
$$;

-- The "[N] members match" count for the current filtered view (spec
-- §4.2), same filters, no cursor. Non-Owner: zero.
create or replace function owner_directory_count(
  p_query         text default null,
  p_statuses      account_status[] default null,
  p_staff_only    boolean default false,
  p_joined_after  timestamptz default null,
  p_joined_before timestamptz default null,
  p_activity      text[] default null
) returns bigint
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select count(*)
  from profiles pr
  left join user_private up on up.user_id = pr.user_id
  where is_owner()
    and not pr.is_system
    and pr.status <> 'deleted'
    and pr.status = any (coalesce(p_statuses,
          array['active', 'restricted', 'suspended']::account_status[]))
    and (p_query is null or trim(p_query) = ''
         or pr.handle::text like
            replace(replace(lower(trim(leading '@' from trim(p_query))), '\', '\\'), '_', '\_') || '%')
    and (not coalesce(p_staff_only, false)
         or exists (select 1 from role_assignments ra
                    where ra.user_id = pr.user_id and ra.revoked_at is null))
    and (p_joined_after  is null or pr.created_at >= p_joined_after)
    and (p_joined_before is null or pr.created_at <  p_joined_before)
    and (p_activity is null or cardinality(p_activity) = 0
         or owner_activity_bucket(up.last_login_at) = any (p_activity))
$$;

-- ------------------------------------------------------------
-- 4. The member-detail glance view (spec §6): the account-accounting
--    surface. Everything about the account's standing and shape,
--    NOTHING that identifies the person: handle, dates, status, role,
--    coarse bucket, and the same counts her public profile shows.
--    Enforcement history is NOT duplicated here — the client calls
--    the existing mod_enforcement_history(), the single source of
--    truth (spec §8). Non-Owner: zero rows.
-- ------------------------------------------------------------
create or replace function owner_member_detail(p_handle citext)
returns table (
  user_id           uuid,
  handle            text,
  founding          boolean,
  is_system         boolean,
  status            account_status,
  status_expires_at timestamptz,
  staff_role        text,
  joined_at         timestamptz,
  activity_bucket   text,
  post_count        bigint,
  follower_count    bigint,
  following_count   bigint
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select pr.user_id,
         pr.handle::text,
         pr.founding_member,
         pr.is_system,
         pr.status,
         pr.status_expires_at,
         (select ra.role::text from role_assignments ra
          where ra.user_id = pr.user_id and ra.revoked_at is null
          order by case ra.role when 'owner' then 0 when 'admin' then 1
                                when 'moderator' then 2 else 3 end
          limit 1),
         pr.created_at,
         owner_activity_bucket(up.last_login_at),
         (select count(*) from posts p
          where p.author_id = pr.user_id and p.deleted_at is null
            and p.visibility = 'visible'),
         (select count(*) from follows f where f.followee_id = pr.user_id),
         (select count(*) from follows f where f.follower_id = pr.user_id)
  from profiles pr
  left join user_private up on up.user_id = pr.user_id
  where is_owner()
    and pr.handle = p_handle
    and pr.status <> 'deleted'
$$;

-- ------------------------------------------------------------
-- 5. The identity reveal (spec §7): the one place the product shows
--    who a member really is. Owner-only AND AAL2 (require_owner_aal2,
--    the roles-manager gate), a mandatory stated reason, and an
--    audit_log entry written BEFORE the data is returned, so there is
--    no code path in which identity is read invisibly. Device signals
--    are returned as a COUNT, never raw hashes (P2B §6). IPs travel
--    as text. The precise last-login time is returned HERE and only
--    here — behind the step-up, the reason, and the log.
-- ------------------------------------------------------------
create or replace function owner_reveal_identity(p_user uuid, p_reason text)
returns table (
  handle              text,
  legal_name          text,
  email               text,
  phone               text,
  phone_verified_at   timestamptz,
  signup_ip           text,
  last_login_ip       text,
  last_login_at       timestamptz,
  device_signal_count integer
)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_handle text;
begin
  perform require_owner_aal2();
  if coalesce(char_length(trim(p_reason)), 0) < 3 then
    raise exception 'A stated reason is required to access identity details.';
  end if;
  select pr.handle::text into v_handle
  from profiles pr
  where pr.user_id = p_user and not pr.is_system;
  if v_handle is null then
    raise exception 'No such member.';
  end if;

  -- The record precedes the read, always.
  perform append_audit('identity.reveal', 'user', p_user::text,
                       jsonb_build_object('handle', v_handle,
                                          'reason', left(trim(p_reason), 500)));

  return query
  select v_handle,
         up.legal_name,
         up.email::text,
         up.phone_e164,
         up.phone_verified_at,
         host(up.signup_ip),
         host(up.last_login_ip),
         up.last_login_at,
         case when up.device_fingerprint_hash is null then 0 else 1 end
  from user_private up
  where up.user_id = p_user;
end $$;

-- ------------------------------------------------------------
-- 6. The export (spec §9.2): the directory's single bulk operation,
--    a deliberate, logged, identity-free READ of exactly the current
--    filtered view. Glance columns only — never a legal name, email,
--    phone, or IP; an export with identity would be a bulk
--    deanonymisation file. The audit entry records the filter set and
--    the row count, so a mass read is as accountable as an identity
--    reveal. Raises for non-Owners (it is an act, not a view).
-- ------------------------------------------------------------
create or replace function owner_directory_export(
  p_query         text default null,
  p_statuses      account_status[] default null,
  p_staff_only    boolean default false,
  p_joined_after  timestamptz default null,
  p_joined_before timestamptz default null,
  p_activity      text[] default null
) returns table (
  handle          text,
  founding        boolean,
  status          account_status,
  staff_role      text,
  joined_at       timestamptz,
  activity_bucket text
)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_count bigint;
begin
  if not is_owner() then
    raise exception 'Only the Owner may export the directory.';
  end if;

  select owner_directory_count(p_query, p_statuses, p_staff_only,
                               p_joined_after, p_joined_before, p_activity)
    into v_count;

  perform append_audit('directory.export', 'directory', null,
                       jsonb_build_object(
                         'rows', v_count,
                         'query', nullif(trim(coalesce(p_query, '')), ''),
                         'statuses', to_jsonb(coalesce(p_statuses, array['active','restricted','suspended']::account_status[])),
                         'staff_only', coalesce(p_staff_only, false),
                         'joined_after', p_joined_after,
                         'joined_before', p_joined_before,
                         'activity', to_jsonb(p_activity)));

  return query
  select d.handle, d.founding, d.status, d.staff_role, d.joined_at, d.activity_bucket
  from owner_directory(p_query, p_statuses, p_staff_only,
                       p_joined_after, p_joined_before, p_activity,
                       null, null, 100000) d;
end $$;

-- ------------------------------------------------------------
-- 7. owner_metrics(): the day-one metric set (spec §12), one read,
--    aggregates only, suppression applied before anything leaves the
--    database. Ranges: 'today' | '7d' | '30d' | 'all'. Comparison is
--    versus the previous equal period; 'all' has no comparison.
--    Series granularity follows range (hourly / daily / weekly).
--    Active members is deliberately a FIXED 30-day window whatever
--    the global range — a wide-window liveness reading, not a daily
--    engagement dial (spec §12.3). Raises for non-Owners.
-- ------------------------------------------------------------
create or replace function owner_metrics(p_range text default '30d')
returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  k            constant integer := 5; -- the small-N suppression floor (spec §16)
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

  -- 12.1 Total members: headline excludes system, deleted, banned;
  -- deactivated counted, surfaced as a sub-figure. The status
  -- breakdown is segmented, so it obeys the suppression floor.
  select count(*) filter (where status not in ('deleted', 'banned')),
         count(*) filter (where status = 'deactivated')
    into v_total, v_deactivated
  from profiles where not is_system;
  v_deactivated := coalesce(v_deactivated, 0);

  select coalesce(jsonb_agg(jsonb_build_object(
           'status', s.status,
           'count', case when s.n > 0 and s.n < k then null else s.n end,
           'suppressed', s.n > 0 and s.n < k)
         order by s.status), '[]'::jsonb)
    into v_breakdown
  from (
    select st.status::text, count(pr.user_id) as n
    from unnest(array['active','restricted','suspended','banned','deactivated']) as st(status)
    left join profiles pr on pr.status::text = st.status and not pr.is_system
    group by st.status
  ) s;

  -- 12.2 Signups over time.
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

  -- 12.3 Active members: fixed 30-day window, aggregate only. An
  -- authentic action = posted, followed, liked, or logged in. Never
  -- per-member, never daily.
  select count(distinct u.uid) into v_active
  from (
    select p.author_id as uid from posts p
     where p.created_at >= v_now - interval '30 days' and p.deleted_at is null
    union
    select f.follower_id from follows f where f.created_at >= v_now - interval '30 days'
    union
    select l.user_id from likes l where l.created_at >= v_now - interval '30 days'
    union
    select up.user_id from user_private up
     where up.last_login_at >= v_now - interval '30 days'
  ) u
  join profiles pr on pr.user_id = u.uid
  where not pr.is_system and pr.status not in ('deleted', 'banned');

  -- 12.4 Posts (member-visible content, not removed/deleted items).
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

  -- 12.5 / 12.6 Reports filed and resolved; median time to resolution
  -- — the question a safety-first founder actually asks: how fast do
  -- we protect people when they ask.
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

  -- 12.7 Enforcement actions, breakdown suppressed below the floor
  -- (at tiny N, "1 ban" identifies a person).
  select count(*) into v_actions from moderation_actions
   where v_start is null or created_at >= v_start;
  select coalesce(jsonb_agg(jsonb_build_object(
           'action', a.action,
           'count', case when a.n > 0 and a.n < k then null else a.n end,
           'suppressed', a.n > 0 and a.n < k)
         order by a.n desc nulls last, a.action), '[]'::jsonb)
    into v_action_breakdown
  from (
    select ma.action::text, count(*) as n
    from moderation_actions ma
    where v_start is null or ma.created_at >= v_start
    group by ma.action
  ) a;

  return jsonb_build_object(
    'range', coalesce(p_range, '30d'),
    'suppression_floor', k,
    'total_members', jsonb_build_object(
      'value', coalesce(v_total, 0),
      'deactivated', v_deactivated,
      'joined_in_range', v_signups,
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
      'breakdown', v_action_breakdown));
end $$;

-- ------------------------------------------------------------
-- 8. EXECUTE lockdown: authenticated only, same posture as every
--    other session function (the real gate is is_owner() /
--    require_owner_aal2() inside each body; this keeps anon and
--    service_role out entirely).
-- ------------------------------------------------------------
revoke execute on function owner_member_count()                                                                            from public, anon, service_role;
revoke execute on function owner_directory(text, account_status[], boolean, timestamptz, timestamptz, text[], timestamptz, uuid, integer) from public, anon, service_role;
revoke execute on function owner_directory_count(text, account_status[], boolean, timestamptz, timestamptz, text[])        from public, anon, service_role;
revoke execute on function owner_member_detail(citext)                                                                     from public, anon, service_role;
revoke execute on function owner_reveal_identity(uuid, text)                                                               from public, anon, service_role;
revoke execute on function owner_directory_export(text, account_status[], boolean, timestamptz, timestamptz, text[])       from public, anon, service_role;
revoke execute on function owner_metrics(text)                                                                             from public, anon, service_role;

grant execute on function owner_member_count()                                                                             to authenticated;
grant execute on function owner_directory(text, account_status[], boolean, timestamptz, timestamptz, text[], timestamptz, uuid, integer)  to authenticated;
grant execute on function owner_directory_count(text, account_status[], boolean, timestamptz, timestamptz, text[])         to authenticated;
grant execute on function owner_member_detail(citext)                                                                      to authenticated;
grant execute on function owner_reveal_identity(uuid, text)                                                                to authenticated;
grant execute on function owner_directory_export(text, account_status[], boolean, timestamptz, timestamptz, text[])        to authenticated;
grant execute on function owner_metrics(text)                                                                              to authenticated;
