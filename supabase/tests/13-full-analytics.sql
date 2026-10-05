-- Behavioral + structural smoke test for migration 0023 (full
-- analytics): the owner's decision that every number is the literal
-- number, plus the two new collection mechanisms — member sessions
-- (heartbeat) and departure timestamps / the account-status ledger.
--
-- The security properties that still hold, asserted here:
--   1. OWNER-ONLY AT THE DATA LAYER: owner_metrics() raises for a
--      non-Owner; the internal helper is callable by no app role.
--   2. NO LEGAL NAME, STRUCTURALLY: none of the new functions
--      references profiles.display_name; every per-member figure is
--      keyed to @handle.
--   3. RLS EVERYWHERE: the new tables have RLS enabled; a member can
--      read only her own sessions, nobody writes any of them
--      directly, and the status ledger is reachable only through the
--      trigger and owner_metrics().
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000003', 'ada@test'),
  ('00000000-0000-0000-0000-000000000004', 'bea@test'),
  ('00000000-0000-0000-0000-000000000005', 'cat@test'),
  ('00000000-0000-0000-0000-000000000007', 'system@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_system_account('00000000-0000-0000-0000-000000000007', 'hersciety');
select create_member('00000000-0000-0000-0000-000000000003', 'ada@test', 'Ada Lovelace', '1995-05-05', 'ada', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000004', 'bea@test', 'Bea Arthur',   '1995-05-05', 'bea', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000005', 'cat@test', 'Cat Stevens',  '1995-05-05', 'cat', null, null, null, '{}'::jsonb, false);

-- ============================================================
-- 1. STRUCTURAL: the new functions exist, none references
--    display_name, and the EXECUTE posture is right: the heartbeat is
--    for every signed-in member, the active-count helper for no app
--    role at all.
-- ============================================================
do $$ declare f text; src text; begin
  foreach f in array array['owner_metrics', 'owner_active_since',
                           'session_heartbeat', 'stamp_status_change'] loop
    select p.prosrc into src
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = f;
    if src is null then raise exception 'FAIL: function % missing', f; end if;
    if position('display_name' in src) > 0 then
      raise exception 'FAIL: % body references display_name', f;
    end if;
  end loop;
  if has_function_privilege('anon', 'public.session_heartbeat()', 'execute')
     or has_function_privilege('service_role', 'public.session_heartbeat()', 'execute') then
    raise exception 'FAIL: heartbeat must be authenticated-only';
  end if;
  if not has_function_privilege('authenticated', 'public.session_heartbeat()', 'execute') then
    raise exception 'FAIL: a signed-in member must be able to heartbeat';
  end if;
  foreach f in array array['anon', 'authenticated', 'service_role'] loop
    if has_function_privilege(f, 'public.owner_active_since(timestamptz)', 'execute') then
      raise exception 'FAIL: % can execute the internal active-count helper', f;
    end if;
  end loop;
end $$;

-- The new tables exist with RLS enabled; no app role can write any of
-- them directly; the ledger and the tracked-since table are not even
-- readable directly.
do $$ declare t text; r text; priv text; begin
  foreach t in array array['member_sessions', 'account_status_events', 'analytics_collection'] loop
    if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                   where n.nspname = 'public' and c.relname = t and c.relrowsecurity) then
      raise exception 'FAIL: % is missing row-level security', t;
    end if;
    foreach r in array array['anon', 'authenticated', 'service_role'] loop
      foreach priv in array array['insert', 'update', 'delete'] loop
        if has_table_privilege(r, 'public.' || t, priv) then
          raise exception 'FAIL: % holds % on %', r, priv, t;
        end if;
      end loop;
    end loop;
  end loop;
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    if has_table_privilege(r, 'public.account_status_events', 'select')
       or has_table_privilege(r, 'public.analytics_collection', 'select') then
      raise exception 'FAIL: % can read a metrics-internal table directly', r;
    end if;
  end loop;
end $$;

-- profiles gained the departure timestamps.
do $$ begin
  if (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name = 'profiles'
        and column_name in ('deactivated_at', 'banned_at', 'deleted_at')) <> 3 then
    raise exception 'FAIL: profiles is missing a departure timestamp column';
  end if;
end $$;

-- ============================================================
-- 2. THE HEARTBEAT: a member's first heartbeat opens a session, a
--    repeat within the 30-minute gap extends the SAME session, one
--    after the gap opens a new one. Sessions are readable by their
--    own member only.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);

select session_heartbeat();
select session_heartbeat();

do $$ begin
  if (select count(*) from member_sessions) <> 1 then
    raise exception 'FAIL: two heartbeats within the gap must be one session';
  end if;
end $$;

-- A direct write is refused even for the session's own member.
do $$ begin
  begin
    insert into member_sessions (user_id) values ('00000000-0000-0000-0000-000000000003');
    raise exception 'FAIL: a member wrote member_sessions directly';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

-- Age the open session past the gap; the next heartbeat opens a new one.
reset role;
update member_sessions set started_at = started_at - interval '2 hours',
                           last_seen_at = last_seen_at - interval '100 minutes';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
select session_heartbeat();

do $$ begin
  if (select count(*) from member_sessions) <> 2 then
    raise exception 'FAIL: a heartbeat after the gap must open a new session';
  end if;
end $$;

-- Bea sees none of ada's sessions (RLS scopes to own rows).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ begin
  if (select count(*) from member_sessions) <> 0 then
    raise exception 'FAIL: a member can read another member''s sessions';
  end if;
end $$;

-- ============================================================
-- 3. DEPARTURES: a status change stamps the matching timestamp and
--    appends to the ledger; a reversal clears the stamp and appends
--    the return. Net change is real arithmetic: up one when one
--    arrives, down one when one leaves.
-- ============================================================
reset role;
update profiles set status = 'banned' where handle = 'bea';
update profiles set status = 'deactivated' where handle = 'cat';

do $$ begin
  if (select banned_at from profiles where handle = 'bea') is null then
    raise exception 'FAIL: banning must stamp banned_at';
  end if;
  if (select deactivated_at from profiles where handle = 'cat') is null then
    raise exception 'FAIL: deactivating must stamp deactivated_at';
  end if;
  if not exists (select 1 from account_status_events e
                 join profiles pr on pr.user_id = e.user_id
                 where pr.handle = 'bea' and e.from_status = 'active' and e.to_status = 'banned') then
    raise exception 'FAIL: the ban is not in the status ledger';
  end if;
end $$;

-- Reinstate bea: the stamp clears, the return lands in the ledger.
update profiles set status = 'active' where handle = 'bea';
do $$ begin
  if (select banned_at from profiles where handle = 'bea') is not null then
    raise exception 'FAIL: reinstating must clear banned_at';
  end if;
  if not exists (select 1 from account_status_events e
                 join profiles pr on pr.user_id = e.user_id
                 where pr.handle = 'bea' and e.from_status = 'banned' and e.to_status = 'active') then
    raise exception 'FAIL: the reinstatement is not in the status ledger';
  end if;
end $$;

-- Ban her again so the range holds one standing departure, then read
-- the arithmetic as the Owner: 4 joined, 1 departed, 1 returned.
update profiles set status = 'banned' where handle = 'bea';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal1","session_id":"so"}', false);

do $$ declare m jsonb; tm jsonb; begin
  m := owner_metrics('30d');
  tm := m -> 'total_members';
  if (tm ->> 'joined_in_range')::int <> 4 then
    raise exception 'FAIL: joined_in_range should be 4, got %', tm ->> 'joined_in_range';
  end if;
  if (tm ->> 'departed_in_range')::int <> 2 then
    raise exception 'FAIL: departed_in_range should be 2 (two bans), got %', tm ->> 'departed_in_range';
  end if;
  if (tm ->> 'returned_in_range')::int <> 1 then
    raise exception 'FAIL: returned_in_range should be 1, got %', tm ->> 'returned_in_range';
  end if;
  if (tm ->> 'net_change')::int <> 3 then
    raise exception 'FAIL: net change must be 4 - 2 + 1 = 3, got %', tm ->> 'net_change';
  end if;
  if (tm ->> 'departures_tracked_since') is null then
    raise exception 'FAIL: the departures series must carry its tracked-since label';
  end if;
  -- The breakdown is literal at every N: 1 banned reads as exactly 1.
  if (select (x ->> 'count')::int from jsonb_array_elements(tm -> 'breakdown') x
      where x ->> 'label' = 'banned') <> 1 then
    raise exception 'FAIL: 1 must read as 1 in the breakdown';
  end if;
  if (select (x ->> 'count')::int from jsonb_array_elements(tm -> 'breakdown') x
      where x ->> 'label' = 'deactivated') <> 1 then
    raise exception 'FAIL: 1 deactivated must read as 1';
  end if;
end $$;

-- ============================================================
-- 4. ENGAGEMENT, SESSIONS, PRESENCE: DAU/WAU/MAU count real activity,
--    stickiness is the real ratio, session minutes are the real
--    durations, and presence names who is online right now with a
--    precise last-seen — by @handle.
-- ============================================================
do $$ declare m jsonb; begin
  m := owner_metrics('30d');
  -- ada heartbeated moments ago: DAU = 1. Nobody else acted.
  if (m -> 'engagement' ->> 'dau')::int <> 1
     or (m -> 'engagement' ->> 'wau')::int <> 1
     or (m -> 'engagement' ->> 'mau')::int <> 1 then
    raise exception 'FAIL: DAU/WAU/MAU should all be 1, got %', m -> 'engagement';
  end if;
  if (m -> 'engagement' ->> 'stickiness')::numeric <> 100.0 then
    raise exception 'FAIL: stickiness should be the real 100.0, got %', m -> 'engagement' ->> 'stickiness';
  end if;
  if (m -> 'sessions' ->> 'count')::int <> 2 then
    raise exception 'FAIL: session count should be 2, got %', m -> 'sessions' ->> 'count';
  end if;
  if (m -> 'sessions' ->> 'tracked_since') is null then
    raise exception 'FAIL: the sessions series must carry its tracked-since label';
  end if;
  -- The first session ran 20 real minutes (aged by the rig above).
  if (m -> 'sessions' ->> 'total_minutes')::numeric < 20.0 then
    raise exception 'FAIL: time-on-site should include the 20-minute session, got %', m -> 'sessions' ->> 'total_minutes';
  end if;
  if (m -> 'presence' ->> 'online_now')::int <> 1 then
    raise exception 'FAIL: ada is online now, got %', m -> 'presence' ->> 'online_now';
  end if;
  if not exists (select 1 from jsonb_array_elements(m -> 'presence' -> 'online') x
                 where x ->> 'handle' = 'ada' and (x ->> 'last_seen') is not null) then
    raise exception 'FAIL: presence must name @ada with her precise last-seen';
  end if;
  if not exists (select 1 from jsonb_array_elements(m -> 'presence' -> 'last_seen') x
                 where x ->> 'handle' = 'ada') then
    raise exception 'FAIL: the last-seen list must carry @ada';
  end if;
end $$;

-- ============================================================
-- 5. LEADERBOARDS, STREAKS, VIRALITY: per-member figures, @handle
--    only, exact values. ada posts on three consecutive days and
--    likes bree's post; bree follows ada.
-- ============================================================
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
select create_post('day three', null, 'everyone');
select create_post('and a second today', null, 'everyone');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal1","session_id":"so"}', false);
select create_post('from the owner', null, 'everyone');

reset role;
-- Age ada's first post to two days ago and her second to yesterday,
-- making a three-day streak with today's heartbeat.
update posts set created_at = now() - interval '2 days'
 where body = 'day three';
update posts set created_at = now() - interval '1 day'
 where body = 'and a second today';

set role authenticated;
-- ada likes bree's post; bree follows ada.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
insert into likes (user_id, post_id)
  select '00000000-0000-0000-0000-000000000003', id from posts where body = 'from the owner';
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal1","session_id":"so"}', false);
insert into follows (follower_id, followee_id)
  values ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003');

do $$ declare m jsonb; lb jsonb; begin
  m := owner_metrics('30d');
  lb := m -> 'leaderboards';
  -- Most posts: ada 2, bree 1 — exact, ordered, @handle-keyed.
  if (lb -> 'top_posters' -> 0 ->> 'handle') <> 'ada'
     or (lb -> 'top_posters' -> 0 ->> 'value')::int <> 2
     or (lb -> 'top_posters' -> 1 ->> 'handle') <> 'bree'
     or (lb -> 'top_posters' -> 1 ->> 'value')::int <> 1 then
    raise exception 'FAIL: top posters wrong: %', lb -> 'top_posters';
  end if;
  if (lb -> 'likes_given' -> 0 ->> 'handle') <> 'ada'
     or (lb -> 'likes_given' -> 0 ->> 'value')::int <> 1 then
    raise exception 'FAIL: likes given wrong: %', lb -> 'likes_given';
  end if;
  if (lb -> 'likes_received' -> 0 ->> 'handle') <> 'bree'
     or (lb -> 'likes_received' -> 0 ->> 'value')::int <> 1 then
    raise exception 'FAIL: likes received wrong: %', lb -> 'likes_received';
  end if;
  if (lb -> 'by_sessions' -> 0 ->> 'handle') <> 'ada'
     or (lb -> 'by_sessions' -> 0 ->> 'value')::int <> 2 then
    raise exception 'FAIL: sessions leaderboard wrong: %', lb -> 'by_sessions';
  end if;
  if (lb -> 'follower_growth' -> 0 ->> 'handle') <> 'ada'
     or (lb -> 'follower_growth' -> 0 ->> 'value')::int <> 1 then
    raise exception 'FAIL: follower growth wrong: %', lb -> 'follower_growth';
  end if;
  -- Streak: ada acted on three consecutive days.
  if (m -> 'streaks' ->> 'longest_current')::int <> 3 then
    raise exception 'FAIL: ada''s streak should be 3, got %', m -> 'streaks' ->> 'longest_current';
  end if;
  if not exists (select 1 from jsonb_array_elements(m -> 'streaks' -> 'members') x
                 where x ->> 'handle' = 'ada' and (x ->> 'value')::int = 3) then
    raise exception 'FAIL: the streak list must carry @ada at 3';
  end if;
  -- Virality: 3 posts, 1 like → likes per post 0.33; follows 1.
  if (m -> 'virality' ->> 'likes_per_post')::numeric <> 0.33 then
    raise exception 'FAIL: likes per post should be 0.33, got %', m -> 'virality' ->> 'likes_per_post';
  end if;
  if (m -> 'virality' ->> 'follows_in_range')::int <> 1 then
    raise exception 'FAIL: follows in range should be 1';
  end if;
  -- No per-member object anywhere carries anything but handle+value.
  if exists (
    select 1
    from jsonb_each(lb) boards(k, arr)
    cross join lateral jsonb_array_elements(boards.arr) entry
    cross join lateral jsonb_object_keys(entry) key
    where key not in ('handle', 'value')
  ) then
    raise exception 'FAIL: a leaderboard entry carries an unexpected field';
  end if;
end $$;

-- ============================================================
-- 6. RETENTION: real cohort shares at 1/7/30 days, real percentages
--    at any base. Backdate ada and bea ten days: ada came back (her
--    activity is today, 10 days after signup), bea never did → the
--    d1 and d7 rates are a real 50.0; nobody is 30 days old yet.
-- ============================================================
reset role;
update profiles set created_at = now() - interval '10 days'
 where handle in ('ada', 'bea');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal1","session_id":"so"}', false);

do $$ declare m jsonb; begin
  m := owner_metrics('30d');
  if (m -> 'retention' -> 'd7' ->> 'eligible')::int <> 2
     or (m -> 'retention' -> 'd7' ->> 'returned')::int <> 1
     or (m -> 'retention' -> 'd7' ->> 'rate')::numeric <> 50.0 then
    raise exception 'FAIL: 7-day retention should be 1 of 2 = 50.0, got %', m -> 'retention' -> 'd7';
  end if;
  if (m -> 'retention' -> 'd1' ->> 'rate')::numeric <> 50.0 then
    raise exception 'FAIL: 1-day retention should be the real 50.0, got %', m -> 'retention' -> 'd1';
  end if;
  if (m -> 'retention' -> 'd30' ->> 'eligible')::int <> 0 then
    raise exception 'FAIL: nobody is 30 days old; eligible must read 0';
  end if;
end $$;

-- ============================================================
-- 7. OWNER-ONLY HOLDS: a plain member still cannot read any of it,
--    and anon cannot heartbeat.
-- ============================================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal2","session_id":"sa"}', false);
do $$ begin
  begin
    perform owner_metrics('30d');
    raise exception 'FAIL: non-owner read the metrics';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

reset role;
rollback;
\echo 'FULL ANALYTICS SMOKE: ALL CHECKS PASSED'
