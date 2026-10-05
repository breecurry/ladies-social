-- ============================================================
-- 0023 — Profile pictures / avatars (Phase 2E).
-- Spec: docs/design-phase2e-profile-pictures.md (safety model in its
-- section 2 is the load-bearing part; this migration implements it).
--
-- Forward-only and idempotent: safe against the live database where
-- 0001-0022 are applied, and safe to re-run.
--
-- GUARANTEE CARRIED FORWARD FROM EVERY PRIOR MIGRATION: nothing in
-- this migration SELECTs or references profiles.display_name. The
-- avatar is identity imagery and the @handle is the only identity it
-- is ever paired with. Suite 12 asserts this structurally.
--
-- SCANNING (owner decision 2026-10-09, supersedes the design doc's
-- section 13 recommendation): the ONLY scanning layer is Cloudflare's
-- zone-level CSAM Scanning Tool, already enabled on the media zone by
-- the owner. It operates on Cloudflare's cache, out of band. There is
-- deliberately NO upload-time scan step, no scanning vendor, and no
-- scan-status machinery here. What remains in-band is the half the
-- law cares about when out-of-band detection fires: REMOVAL PRESERVES,
-- NEVER HARD-DELETES. A report hold or a moderation removal pins the
-- stored object (moderation-records window: 2 years; a csam-reason
-- report additionally sets legal_hold, the >=1-year preservation
-- anchor, cleared only by the Owner's existing escalation path).
--
-- THE BLOCK RULE (verified against 0014, do not weaken): profiles_read
-- filters ONE direction only (internal.blocked_by: "has this profile's
-- owner blocked me?"), while posts/follows/likes filter BOTH
-- directions (blocked_either). Avatars are mutual-hard by design-doc
-- section 2.6: the resolver below gates on blocked_either(auth.uid(),
-- owner) — the POSTS semantics — so the real object key never reaches
-- a blocked client in EITHER direction. A UI placeholder fallback is
-- not the control; this function is.
--
-- KEYS ARE OPAQUE: 48 hex chars of server CSPRNG output. No user id,
-- no handle, no counter, no timestamp, no filename — there is no
-- filename column anywhere and none may ever be added (design doc
-- section 2.2). A new upload mints a NEW key; nothing overwrites.
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- 1. Enum + tables.
-- ------------------------------------------------------------
do $$ begin
  if not exists (select 1 from pg_type where typname = 'avatar_removal') then
    create type avatar_removal as enum ('self', 'moderation');
  end if;
end $$;

-- One row per uploaded avatar object, forever (rows are never deleted;
-- only the storage objects are purged, and only when no hold applies).
-- RLS is enabled with ZERO policies and every direct privilege
-- revoked: the SECURITY DEFINER functions below are the only path.
create table if not exists avatar_media (
  key           text primary key check (key ~ '^[a-f0-9]{48}$'),
  owner_id      uuid not null references profiles (user_id),
  blurhash      text check (blurhash is null or char_length(blurhash) between 6 and 64),
  created_at    timestamptz not null default now(),
  superseded_at timestamptz,            -- replaced by a newer upload
  removed_at    timestamptz,
  removed_kind  avatar_removal,
  removed_rule  report_reason,          -- set on moderation removals
  purged_at     timestamptz,            -- storage objects deleted
  legal_hold    boolean not null default false,
  check (removed_at is null or removed_kind is not null)
);
create index if not exists idx_avatar_media_owner on avatar_media (owner_id, created_at desc);

alter table avatar_media enable row level security;
revoke all on avatar_media from anon, authenticated, service_role;

-- Upload tickets bind every staging upload and every commit to an
-- authenticated member and carry the rate limit. No filename, no
-- content type, no client-supplied anything beyond existence.
create table if not exists avatar_upload_tickets (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles (user_id),
  staging_key text not null check (staging_key ~ '^st/[a-f0-9]{48}$'),
  created_at  timestamptz not null default now(),
  consumed_at timestamptz,              -- staging object fetched for processing
  redeemed_at timestamptz               -- avatar_media row recorded
);
create index if not exists idx_avatar_tickets_user on avatar_upload_tickets (user_id, created_at desc);

alter table avatar_upload_tickets enable row level security;
revoke all on avatar_upload_tickets from anon, authenticated, service_role;

-- reports: the frozen-at-filing-time evidence reference (design doc
-- section 9). The FK means a referenced avatar_media row can never
-- disappear from under a report.
alter table reports add column if not exists
  reported_avatar_key text references avatar_media (key);
create index if not exists idx_reports_avatar_key
  on reports (reported_avatar_key) where reported_avatar_key is not null;

-- ------------------------------------------------------------
-- 2. Close the direct-write path. 0009 granted column-level UPDATE on
--    avatar_media_key so a member could write any string straight into
--    her profile row via PostgREST — bypassing the pipeline, the key
--    mint, and the evidence trail. From now on the column moves only
--    inside the functions below.
-- ------------------------------------------------------------
revoke update (avatar_media_key) on profiles from authenticated;

-- ------------------------------------------------------------
-- 3. Internal predicate: may this key's storage objects be purged?
--    Never granted; called only from the functions below. The answer
--    is NO whenever any evidence or retention duty touches the key:
--      - it is still somebody's current avatar;
--      - legal hold (csam-reason report; Owner path clears it);
--      - a report in a holding status references it (open, in_review,
--        escalated, actioned — 'actioned' means a confirmed violation,
--        which is exactly the evidence case; only 'dismissed' releases);
--      - it was removed by moderation (2-year moderation-records
--        window; pruning after that window is a deliberate later task,
--        never an automatic side effect here).
-- ------------------------------------------------------------
create or replace function avatar_purgeable(p_key text) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (
    select 1 from avatar_media am
    where am.key = p_key
      and am.purged_at is null
      and not am.legal_hold
      and (am.removed_kind is null or am.removed_kind <> 'moderation')
      and not exists (select 1 from profiles pr where pr.avatar_media_key = am.key)
      and not exists (select 1 from reports r
                      where r.reported_avatar_key = am.key
                        and r.status in ('open', 'in_review', 'escalated', 'actioned'))
  )
$$;
revoke execute on function avatar_purgeable(text) from public, anon, authenticated, service_role;

-- ------------------------------------------------------------
-- 4. The upload path: ticket -> consume -> record.
-- ------------------------------------------------------------

-- Mint an upload ticket. Active members only (restricted is
-- read-but-not-post, and publishing a new avatar is publishing).
-- 12 tickets/hour bounds abuse the same way file_report's cap does.
create or replace function avatar_ticket_create(p_staging_key text) returns uuid
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me uuid := auth.uid();
  v_id uuid;
begin
  if v_me is null then
    raise exception 'Not signed in.';
  end if;
  if not exists (select 1 from profiles where user_id = v_me and status = 'active') then
    raise exception 'Your account cannot change its photo right now.';
  end if;
  if p_staging_key is null or p_staging_key !~ '^st/[a-f0-9]{48}$' then
    raise exception 'Invalid upload.';
  end if;
  if (select count(*) from avatar_upload_tickets t
      where t.user_id = v_me and t.created_at > now() - interval '1 hour') >= 12 then
    raise exception 'You have tried several uploads in the last hour. Please wait a little while and try again.';
  end if;
  insert into avatar_upload_tickets (user_id, staging_key)
  values (v_me, p_staging_key)
  returning id into v_id;
  return v_id;
end $$;

-- Consume: the server is about to fetch the staging object and
-- process it. One consume per ticket, tickets expire after an hour.
create or replace function avatar_ticket_consume(p_ticket uuid) returns text
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me  uuid := auth.uid();
  v_key text;
begin
  if v_me is null then
    raise exception 'Not signed in.';
  end if;
  update avatar_upload_tickets t
     set consumed_at = now()
   where t.id = p_ticket
     and t.user_id = v_me
     and t.consumed_at is null
     and t.created_at > now() - interval '1 hour'
  returning t.staging_key into v_key;
  if v_key is null then
    raise exception 'That upload has expired. Please try again.';
  end if;
  return v_key;
end $$;

-- Record a processed avatar: insert the row, supersede the previous
-- one, swap the profile pointer. Returns the OLD key and whether its
-- storage objects may be purged (the route deletes from storage only
-- when the database says so — the database owns every retention
-- decision). The new key is minted by the server route (CSPRNG);
-- a hand-called rpc with an invented key only ever breaks the
-- caller's own avatar (the object does not exist; the letter
-- placeholder renders), it can never reference another member's
-- object because the key is a primary key and theirs is taken.
create or replace function avatar_commit_record(
  p_ticket uuid, p_key text, p_blurhash text default null
) returns table (old_key text, old_purgeable boolean)
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me  uuid := auth.uid();
  v_old text;
begin
  if v_me is null then
    raise exception 'Not signed in.';
  end if;
  if not exists (select 1 from profiles where user_id = v_me and status = 'active') then
    raise exception 'Your account cannot change its photo right now.';
  end if;
  if p_key is null or p_key !~ '^[a-f0-9]{48}$' then
    raise exception 'Invalid upload.';
  end if;
  if p_blurhash is not null and char_length(p_blurhash) not between 6 and 64 then
    raise exception 'Invalid upload.';
  end if;
  update avatar_upload_tickets t
     set redeemed_at = now()
   where t.id = p_ticket
     and t.user_id = v_me
     and t.consumed_at is not null
     and t.redeemed_at is null
     and t.created_at > now() - interval '1 hour';
  if not found then
    raise exception 'That upload has expired. Please try again.';
  end if;

  select pr.avatar_media_key into v_old from profiles pr where pr.user_id = v_me;

  insert into avatar_media (key, owner_id, blurhash) values (p_key, v_me, p_blurhash);

  if v_old is not null then
    update avatar_media set superseded_at = now()
     where key = v_old and superseded_at is null;
  end if;

  update profiles set avatar_media_key = p_key where user_id = v_me;

  return query select v_old, case when v_old is null then false
                                  else avatar_purgeable(v_old) end;
end $$;

-- Self-removal (design doc section 2.7): routine, not enforcement.
-- The clean, unreported object is purgeable; anything under a hold
-- is preserved out of the member's reach.
create or replace function remove_avatar()
returns table (old_key text, old_purgeable boolean)
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me  uuid := auth.uid();
  v_old text;
begin
  if v_me is null then
    raise exception 'Not signed in.';
  end if;
  if not exists (select 1 from profiles where user_id = v_me and status in ('active', 'restricted')) then
    raise exception 'Your account cannot change its photo right now.';
  end if;
  select pr.avatar_media_key into v_old from profiles pr where pr.user_id = v_me;
  if v_old is null then
    raise exception 'You have no profile photo to remove.';
  end if;
  update profiles set avatar_media_key = null where user_id = v_me;
  update avatar_media
     set removed_at = now(), removed_kind = 'self'
   where key = v_old and removed_at is null;
  return query select v_old, avatar_purgeable(v_old);
end $$;

-- Bookkeeping after the route has deleted the storage objects. The
-- purgeability predicate is re-checked here so the mark can never
-- outrun a hold that landed between the delete decision and this call.
create or replace function avatar_mark_purged(p_key text) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'Not signed in.';
  end if;
  if not exists (select 1 from avatar_media where key = p_key and owner_id = v_me) then
    raise exception 'That upload is unavailable.';
  end if;
  if not avatar_purgeable(p_key) then
    raise exception 'That image is retained.';
  end if;
  update avatar_media set purged_at = now() where key = p_key;
end $$;

-- ------------------------------------------------------------
-- 5. THE RESOLVER — the only way an avatar key reaches a client.
--    Mutual-hard block (blocked_either, both directions), account
--    standing (only active/restricted owners show a photo; suspended,
--    banned, deactivated and deleted all fall back to the letter
--    placeholder), removed/purged objects never resolve, and the
--    viewer must herself be a member in good standing. Logged-out
--    visitors cannot reach this function at all (EXECUTE is
--    authenticated-only and anon holds nothing).
--    blocked_either is called bare (the 0014 caller-scope guard is
--    satisfied: auth.uid() is always one of the two parties here).
-- ------------------------------------------------------------
create or replace function avatar_keys(p_users uuid[])
returns table (user_id uuid, avatar_key text, blurhash text)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if p_users is null or cardinality(p_users) = 0 then
    return;
  end if;
  if cardinality(p_users) > 200 then
    raise exception 'Too many accounts requested.';
  end if;
  return query
    select pr.user_id, am.key, am.blurhash
    from profiles pr
    join avatar_media am on am.key = pr.avatar_media_key
    where pr.user_id = any (p_users)
      and exists (select 1 from profiles me
                  where me.user_id = auth.uid()
                    and me.status in ('active', 'restricted'))
      and pr.status in ('active', 'restricted')
      and am.removed_at is null
      and am.purged_at is null
      and not blocked_either(auth.uid(), pr.user_id);
end $$;

-- ------------------------------------------------------------
-- 6. Evidence freeze: file_report() captures the accused's CURRENT
--    avatar key at filing time, so a later swap or self-removal can
--    never erase what was reported. Same signature as 0018 (grants
--    preserved); the two additions are marked AVATAR FREEZE below.
--    A csam-reason report also sets legal_hold on the frozen object
--    (the >=1-year preservation anchor; only the Owner's existing
--    escalation path goes near it afterwards).
-- ------------------------------------------------------------
create or replace function file_report(
  p_subject report_subject,
  p_post    bigint default null,
  p_user    uuid default null,
  p_reason  report_reason default 'other',
  p_details text default null
) returns uuid
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_me      uuid := auth.uid();
  v_accused uuid;
  v_handle  text;
  v_avatar  text;
  v_routing report_routing := 'standard';
  v_status  report_status := 'open';
  v_id      uuid;
begin
  if v_me is null then
    raise exception 'Not signed in.';
  end if;
  if not exists (select 1 from profiles where user_id = v_me and status in ('active', 'restricted')) then
    raise exception 'Your account cannot file reports right now.';
  end if;
  if p_details is not null and char_length(p_details) > 2000 then
    raise exception 'Details are limited to 2000 characters.';
  end if;

  if p_subject = 'post' then
    if p_post is null then raise exception 'No post given.'; end if;
    select author_id into v_accused from posts where id = p_post;
    if v_accused is null then raise exception 'That post is unavailable.'; end if;
  else
    if p_user is null then raise exception 'No account given.'; end if;
    select user_id into v_accused from profiles where user_id = p_user;
    if v_accused is null then raise exception 'That account is unavailable.'; end if;
  end if;
  if v_accused = v_me then
    raise exception 'You cannot report yourself.';
  end if;

  -- P2-1a (0014): duplicate guard. One report per (reporter, accused,
  -- reason) per 24 hours; the first one already covers the queue.
  if exists (select 1 from reports r
             where r.reporter_id = v_me
               and r.subject_user_id = v_accused
               and r.reason = p_reason
               and r.created_at > now() - interval '24 hours') then
    raise exception 'You have already reported this recently, and that report is with our team. There is no need to send it again.';
  end if;

  -- P2-1b (0014): hourly cap.
  if (select count(*) from reports r
      where r.reporter_id = v_me
        and r.created_at > now() - interval '1 hour') >= 10 then
    raise exception 'You have filed several reports in the last hour, and they are all safely with our team. Please wait a little while before filing another.';
  end if;

  -- OWNER OVERRIDE (0018): the accused being the Owner OR any staff
  -- member routes admin_only — the normal admin panel. There is no
  -- sealed lane. The reporter's flow stays identical either way.
  if exists (select 1 from role_assignments
             where user_id = v_accused
               and role in ('owner', 'admin', 'moderator', 'ts_reviewer')
               and revoked_at is null) then
    v_routing := 'admin_only';
  end if;

  -- Child-safety reports are never an ordinary queue item: Critical
  -- on arrival, resolvable by the Owner alone.
  if p_reason = 'csam' then
    v_status := 'escalated';
  end if;

  -- AVATAR FREEZE (0023): capture the accused's current avatar key so
  -- the reported image survives any later swap or removal as evidence.
  select pr.avatar_media_key into v_avatar from profiles pr where pr.user_id = v_accused;

  insert into reports (reporter_id, subject_type, subject_post_id, subject_user_id,
                       reason, details, routing, status, reported_avatar_key)
  values (v_me, p_subject,
          case when p_subject = 'post' then p_post end,
          v_accused, p_reason, nullif(btrim(coalesce(p_details, '')), ''), v_routing, v_status,
          v_avatar)
  returning id into v_id;

  -- AVATAR FREEZE (0023): a csam-reason report pins the object hard.
  if p_reason = 'csam' and v_avatar is not null then
    update avatar_media set legal_hold = true where key = v_avatar;
  end if;

  -- The second traceable copy (owner decision). Case reference and
  -- category only — no reporter, no details, no names.
  select pr.handle::text into v_handle from profiles pr where pr.user_id = v_accused;
  insert into safety_email_outbox (report_id, recipient, subject, body)
  values (
    v_id,
    'safety@unitedfeminist.com',
    'Hersciety report ' || left(v_id::text, 8) || ' — ' || p_reason::text,
    'A report was filed on Hersciety.' || E'\n\n'
      || 'Case reference: ' || v_id::text || E'\n'
      || 'Filed at: ' || to_char(now() at time zone 'utc', 'YYYY-MM-DD HH24:MI:SS') || ' UTC' || E'\n'
      || 'Reason: ' || p_reason::text || E'\n'
      || 'Subject: ' || case when p_subject = 'post' then 'a post by @' else 'the account @' end
      || coalesce(v_handle, 'unknown') || E'\n\n'
      || 'Full details are in the moderation console. This copy exists so every report '
      || 'is traceable in two places. It intentionally names no reporter and carries no '
      || 'report text.'
  );

  perform append_audit('report.filed', 'report', v_id::text,
                       jsonb_build_object('reason', p_reason));
  return v_id;
end $$;

-- ------------------------------------------------------------
-- 7. Moderation: remove (preserving) and reinstate, in the exact
--    shape of mod_remove_post / mod_restore_post from 0018.
-- ------------------------------------------------------------
create or replace function mod_remove_avatar(
  p_target uuid, p_rule report_reason, p_note text default null
) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_key     text;
  v_message text;
begin
  perform mod_assert_actionable(p_target, 1);
  perform mod_assert_not_csam(p_target, null);
  select pr.avatar_media_key into v_key from profiles pr where pr.user_id = p_target;
  if v_key is null then
    raise exception 'This account has no profile photo.';
  end if;
  -- Remove from public view, PRESERVE the object (never hard-delete:
  -- a moderation removal is an evidence event; design doc section 11).
  update profiles set avatar_media_key = null where user_id = p_target;
  update avatar_media
     set removed_at = now(), removed_kind = 'moderation', removed_rule = p_rule
   where key = v_key;
  v_message := 'Your profile photo was removed for breaking our rule on ' || p_rule::text
    || '. You can choose a new photo that follows the guidelines.'
    || ' You can appeal within 30 days at appeals@unitedfeminist.com.';
  perform mod_resolve_case(p_target, null, 'actioned', p_note);
  perform mod_record_action(p_target, null, 'remove_content', p_rule, null, v_message, p_note, null);
  perform mod_notify(p_target, v_message, null);
end $$;

-- Reinstate a wrongly removed avatar. Re-points the profile only when
-- the member has not already set a new photo in the meantime.
create or replace function mod_reinstate_avatar(p_target uuid, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_key     text;
  v_current text;
begin
  if mod_actor_tier() < 1 then
    raise exception 'You do not have permission to take this action.';
  end if;
  select am.key into v_key from avatar_media am
   where am.owner_id = p_target
     and am.removed_kind = 'moderation'
     and am.removed_at is not null
     and am.purged_at is null
     and not am.legal_hold
   order by am.removed_at desc limit 1;
  if v_key is null then
    raise exception 'This account has no removed profile photo to reinstate.';
  end if;
  update avatar_media
     set removed_at = null, removed_kind = null, removed_rule = null,
         superseded_at = null
   where key = v_key;
  select pr.avatar_media_key into v_current from profiles pr where pr.user_id = p_target;
  if v_current is null then
    update profiles set avatar_media_key = v_key where user_id = p_target;
  else
    -- The member moved on to a new photo; the reinstated object simply
    -- stops being "removed by moderation" and becomes superseded.
    update avatar_media set superseded_at = now() where key = v_key;
  end if;
  perform mod_record_action(p_target, null, 'restore_content', null, null, null, p_note, null);
  perform mod_notify(p_target, 'Your profile photo that was removed has been reinstated.', null);
end $$;

-- The reported-image panel (design doc section 10): staff see the
-- frozen keys for a case, NEVER anything csam-flagged — a csam-reason
-- report's image is never rendered in the console; it lives behind the
-- Owner's existing escalation path. Keys whose objects were purged are
-- excluded (nothing to render). Reviewer tier and up, read-only.
create or replace function mod_avatar_evidence(p_target uuid)
returns table (
  avatar_key  text,
  blurhash    text,
  reason      report_reason,
  reported_at timestamptz,
  is_current  boolean,
  removed     boolean
)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if mod_actor_tier() < 0 then
    raise exception 'You do not have permission to view this.';
  end if;
  return query
    select distinct on (am.key)
      am.key, am.blurhash, r.reason, r.created_at,
      exists (select 1 from profiles pr
              where pr.user_id = p_target and pr.avatar_media_key = am.key),
      am.removed_at is not null
    from reports r
    join avatar_media am on am.key = r.reported_avatar_key
    where r.subject_user_id = p_target
      and am.purged_at is null
      and not am.legal_hold
      and r.reason <> 'csam'
      and not exists (select 1 from reports rc
                      where rc.reported_avatar_key = am.key
                        and rc.reason = 'csam')
    order by am.key, r.created_at desc;
end $$;

-- ------------------------------------------------------------
-- 8. EXECUTE hygiene: everything revoked everywhere, then exactly the
--    member-session functions granted to authenticated. anon never
--    holds a thing (logged-out never resolves an avatar), and
--    service_role goes through none of these.
-- ------------------------------------------------------------
revoke execute on function avatar_ticket_create(text)              from public, anon, authenticated, service_role;
revoke execute on function avatar_ticket_consume(uuid)             from public, anon, authenticated, service_role;
revoke execute on function avatar_commit_record(uuid, text, text)  from public, anon, authenticated, service_role;
revoke execute on function remove_avatar()                         from public, anon, authenticated, service_role;
revoke execute on function avatar_mark_purged(text)                from public, anon, authenticated, service_role;
revoke execute on function avatar_keys(uuid[])                     from public, anon, authenticated, service_role;
revoke execute on function mod_remove_avatar(uuid, report_reason, text) from public, anon, authenticated, service_role;
revoke execute on function mod_reinstate_avatar(uuid, text)        from public, anon, authenticated, service_role;
revoke execute on function mod_avatar_evidence(uuid)               from public, anon, authenticated, service_role;

grant execute on function avatar_ticket_create(text)               to authenticated;
grant execute on function avatar_ticket_consume(uuid)              to authenticated;
grant execute on function avatar_commit_record(uuid, text, text)   to authenticated;
grant execute on function remove_avatar()                          to authenticated;
grant execute on function avatar_mark_purged(text)                 to authenticated;
grant execute on function avatar_keys(uuid[])                      to authenticated;
grant execute on function mod_remove_avatar(uuid, report_reason, text) to authenticated;
grant execute on function mod_reinstate_avatar(uuid, text)         to authenticated;
grant execute on function mod_avatar_evidence(uuid)                to authenticated;
