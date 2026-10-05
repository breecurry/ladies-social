-- ============================================================
-- 0018 — Moderation: the console's data layer. Reports become
-- actionable; the enforcement ladder (dismiss / warn / remove /
-- restrict / suspend / ban) exists as SECURITY DEFINER functions;
-- bans feed the ban-evasion blocklist; every report also queues a
-- tamper-evident email copy to safety@unitedfeminist.com.
--
-- Forward-only and idempotent: safe against the live database
-- (0001-0017 applied, real accounts present) and safe to re-run.
--
-- 🚨 OWNER DECISION, 2026-10-05, verbatim: "reports against me should
-- still go to the admin report panel. that panel should email safety@
-- every time a report is made so there are two copies completely
-- traceable." This OVERRULES the 'owner_conflict' total-invisibility
-- routing that 0013 shipped and the external-recipient design that
-- docs/design-phase2b-moderation-and-discover.md §7 recommended:
--   * file_report() no longer produces 'owner_conflict'. A report
--     naming the Owner routes 'admin_only' — the normal admin panel,
--     visible to admins and to the Owner herself.
--   * Existing owner_conflict rows are re-routed to admin_only below.
--     (The enum value itself stays: PostgreSQL cannot drop enum
--     values, and old rows must stay readable. Nothing writes it.)
--   * EVERY report inserts a row into safety_email_outbox, the
--     durable source for the second, externally-traceable copy.
--
-- 🚨 IDENTITY RULE (0013 header, upheld): no function in this
-- migration ever SELECTs display_name. Every moderation surface
-- identifies every member — reporter and accused alike — by @handle
-- only. Legal identity is reachable solely via the Owner's existing
-- AAL2 user_private access, which is deliberately NOT part of the
-- console's read functions.
--
-- 🚨 ROLE BOUNDARIES (locked owner decisions), enforced here, below
-- the app, so no UI bug can cross them:
--   * Ban is Admin-or-Owner only, permanent, and the Owner and the
--     system account can never be banned.
--   * Restrict and Suspend: Moderator up to 7 days; longer is
--     Admin-only; 30 days is the ceiling (the guidelines' band).
--   * T&S Reviewer is read-only everywhere.
--   * csam cases are Owner-only to resolve: anyone else's single
--     forward action is escalation (NCMEC filing and law-enforcement
--     contact are Owner powers).
--
-- RETENTION (owner-approved 2026-10-07): moderation records 2 years,
-- ban-evasion signals 2 years — pruned opportunistically in
-- mod_queue(). The audit log (7 years) is untouched.
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- 1. Enums (guarded) and columns (additive, guarded).
-- ------------------------------------------------------------
do $$ begin
  if not exists (select 1 from pg_type where typname = 'mod_action') then
    create type mod_action as enum
      ('dismiss', 'warn', 'remove_content', 'restore_content', 'restrict',
       'suspend', 'lift', 'ban', 'unban', 'escalate');
  end if;
end $$;

-- A member-facing message can ride on a 'system' notification (the
-- warn surface, the "your post was removed" notice). Additive and
-- nullable: every existing notification type leaves it NULL.
alter table notifications add column if not exists body text
  check (body is null or char_length(body) <= 500);

-- ------------------------------------------------------------
-- 2. moderation_actions — the enforcement history. One row per
--    action taken, forever keyed to the @handle-resolvable user id,
--    never to a name. `message` is what the member was told;
--    `note` is the internal staff rationale and never leaves staff
--    surfaces. RLS is enabled with ZERO policies and all direct
--    privileges revoked: the functions below are the only path.
-- ------------------------------------------------------------
create table if not exists moderation_actions (
  id              bigint generated always as identity primary key,
  target_user_id  uuid not null references profiles (user_id),
  post_id         bigint references posts (id),
  action          mod_action not null,
  rule            report_reason,
  duration_days   integer check (duration_days is null or duration_days between 1 and 30),
  message         text check (message is null or char_length(message) <= 1000),
  note            text check (note is null or char_length(note) <= 2000),
  actor_id        uuid not null references profiles (user_id),
  actor_role      text not null,
  created_at      timestamptz not null default now(),
  expires_at      timestamptz
);
create index if not exists idx_mod_actions_target
  on moderation_actions (target_user_id, created_at desc);

alter table moderation_actions enable row level security;
revoke all on moderation_actions from anon, authenticated, service_role;

-- ------------------------------------------------------------
-- 3. safety_email_outbox — the durable queue for the email copy of
--    every report ("two copies completely traceable"). Written only
--    inside file_report(); the server dispatcher (service_role) may
--    read rows and mark them sent, nothing more. The body carries a
--    case reference and minimal metadata — the reason category and
--    the accused @handle — NEVER the reporter, the free-text details,
--    or a legal name: email is the least secure channel, so it gets
--    the notification, not the contents.
-- ------------------------------------------------------------
create table if not exists safety_email_outbox (
  id         bigint generated always as identity primary key,
  report_id  uuid not null references reports (id) on delete cascade,
  recipient  text not null,
  subject    text not null,
  body       text not null,
  created_at timestamptz not null default now(),
  sent_at    timestamptz,
  attempts   integer not null default 0,
  last_error text
);
create index if not exists idx_safety_outbox_unsent
  on safety_email_outbox (created_at) where sent_at is null;

alter table safety_email_outbox enable row level security;
revoke all on safety_email_outbox from anon, authenticated;
-- The dispatcher needs select + the delivery-bookkeeping columns and
-- NOTHING else: rows are created only inside file_report() and are
-- never deleted by the app (retention pruning happens in mod_queue).
revoke all on safety_email_outbox from service_role;
grant select on safety_email_outbox to service_role;
grant update (sent_at, attempts, last_error) on safety_email_outbox to service_role;

-- ------------------------------------------------------------
-- 4. file_report() — same signature, three changes:
--    (a) OWNER OVERRIDE: a report naming the Owner routes
--        'admin_only' (normal admin panel, visible to her), never
--        'owner_conflict'.
--    (b) every report queues its safety@ email copy;
--    (c) csam auto-escalates on arrival (Critical lane; only the
--        Owner resolves it, per the roles matrix).
--    The duplicate guard and hourly cap from 0014 are preserved.
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

  -- OWNER OVERRIDE: the accused being the Owner OR any staff member
  -- routes admin_only — the normal admin panel. There is no sealed
  -- lane. The reporter's flow stays identical either way (§10.5).
  if exists (select 1 from role_assignments
             where user_id = v_accused
               and role in ('owner', 'admin', 'moderator', 'ts_reviewer')
               and revoked_at is null) then
    v_routing := 'admin_only';
  end if;

  -- Child-safety reports are never an ordinary queue item: Critical
  -- on arrival, resolvable by the Owner alone (mod functions below).
  if p_reason = 'csam' then
    v_status := 'escalated';
  end if;

  insert into reports (reporter_id, subject_type, subject_post_id, subject_user_id,
                       reason, details, routing, status)
  values (v_me, p_subject,
          case when p_subject = 'post' then p_post end,
          v_accused, p_reason, nullif(btrim(coalesce(p_details, '')), ''), v_routing, v_status)
  returning id into v_id;

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

-- Legacy sealed rows surface in the admin panel (idempotent; no-op
-- when none exist).
update reports set routing = 'admin_only' where routing = 'owner_conflict';

-- ------------------------------------------------------------
-- 5. Queue visibility: the RLS policy now matches the owner's
--    decision. Reviewers and up read the standard lane; admins and
--    the Owner read the staff lane — except that a non-Owner staff
--    member never reads a report about herself. The Owner reads
--    everything, reports about herself included (her decision).
--    'owner_conflict' is kept in the predicate only so any row that
--    somehow still carries it stays visible to admins rather than
--    vanishing.
-- ------------------------------------------------------------
drop policy if exists reports_queue on reports;
create policy reports_queue on reports for select
  using (
    (routing = 'standard' and is_reviewer_or_above())
    or (routing in ('admin_only', 'owner_conflict')
        and is_admin_or_owner()
        and (is_owner() or subject_user_id <> auth.uid()))
  );

-- ------------------------------------------------------------
-- 6. Shared internals for the enforcement functions.
-- ------------------------------------------------------------

-- The acting staff member's effective tier for the console:
-- 3 = owner, 2 = admin, 1 = moderator, 0 = reviewer, -1 = none.
create or replace function mod_actor_tier() returns integer
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce((
    select max(case role
                 when 'owner' then 3
                 when 'admin' then 2
                 when 'moderator' then 1
                 when 'ts_reviewer' then 0
               end)
    from role_assignments
    where user_id = auth.uid() and revoked_at is null), -1)
$$;

-- Guard rails every enforcement action shares. Raises on violation.
--   p_min_tier: 1 = moderator and up, 2 = admin and up.
create or replace function mod_assert_actionable(p_target uuid, p_min_tier integer)
returns void
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if mod_actor_tier() < p_min_tier then
    raise exception 'You do not have permission to take this action.';
  end if;
  if p_target is null or not exists (select 1 from profiles where user_id = p_target) then
    raise exception 'That account is unavailable.';
  end if;
  if p_target = auth.uid() then
    raise exception 'You cannot take moderation action on your own account.';
  end if;
  if exists (select 1 from profiles where user_id = p_target and is_system) then
    raise exception 'The system account cannot be actioned.';
  end if;
end $$;

-- csam cases are Owner-only to resolve. Everyone else escalates.
create or replace function mod_assert_not_csam(p_target uuid, p_post bigint)
returns void
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if is_owner() then
    return;
  end if;
  if exists (select 1 from reports r
             where r.subject_user_id = p_target
               and (p_post is null or r.subject_post_id = p_post)
               and r.reason = 'csam'
               and r.status in ('open', 'in_review', 'escalated')) then
    raise exception 'Child-safety cases can only be escalated to the Owner.';
  end if;
end $$;

-- Close out the open reports of one case (accused + optional post)
-- and record who resolved them. Internal helper, not granted.
create or replace function mod_resolve_case(
  p_target uuid, p_post bigint, p_status report_status, p_note text
) returns integer
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_count integer;
begin
  update reports r
     set status = p_status,
         resolved_at = now(),
         resolved_by = auth.uid(),
         resolution_note = nullif(btrim(coalesce(p_note, '')), '')
   where r.subject_user_id = p_target
     and (p_post is null or r.subject_post_id = p_post)
     and r.status in ('open', 'in_review', 'escalated');
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- One enforcement-history row + its audit entry. Internal helper.
create or replace function mod_record_action(
  p_target uuid, p_post bigint, p_action mod_action, p_rule report_reason,
  p_days integer, p_message text, p_note text, p_expires timestamptz
) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  insert into moderation_actions
    (target_user_id, post_id, action, rule, duration_days, message, note,
     actor_id, actor_role, expires_at)
  values
    (p_target, p_post, p_action, p_rule, p_days,
     nullif(btrim(coalesce(p_message, '')), ''),
     nullif(btrim(coalesce(p_note, '')), ''),
     auth.uid(), actor_role_name(auth.uid()), p_expires);
  perform append_audit('mod.' || p_action::text, 'user', p_target::text,
                       jsonb_build_object(
                         'rule', p_rule, 'days', p_days,
                         'post_id', p_post));
end $$;

-- A 'system' notification from the platform (actor NULL renders as
-- Hersciety). Internal helper.
create or replace function mod_notify(p_user uuid, p_body text, p_post bigint)
returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  insert into notifications (user_id, actor_id, type, post_id, body)
  values (p_user, null, 'system', p_post, left(p_body, 500));
end $$;

-- ------------------------------------------------------------
-- 7. The enforcement ladder.
-- ------------------------------------------------------------

-- Claim: mark a case in review and assign it to the caller, so two
-- moderators are not unknowingly actioning the same person.
create or replace function mod_claim(p_target uuid, p_post bigint default null)
returns integer
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_count integer;
begin
  if mod_actor_tier() < 1 then
    raise exception 'You do not have permission to take this action.';
  end if;
  update reports r
     set status = 'in_review', assigned_to = auth.uid()
   where r.subject_user_id = p_target
     and (p_post is null or r.subject_post_id = p_post)
     and r.status = 'open';
  get diagnostics v_count = row_count;
  if v_count > 0 then
    perform append_audit('mod.claim', 'user', p_target::text,
                         jsonb_build_object('post_id', p_post, 'reports', v_count));
  end if;
  return v_count;
end $$;

-- Dismiss (no action). Reversible: mod_reopen below.
create or replace function mod_dismiss(
  p_target uuid, p_post bigint default null, p_note text default null
) returns integer
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_count integer;
begin
  perform mod_assert_actionable(p_target, 1);
  perform mod_assert_not_csam(p_target, p_post);
  v_count := mod_resolve_case(p_target, p_post, 'dismissed', p_note);
  if v_count = 0 then
    raise exception 'No open reports to dismiss for this case.';
  end if;
  perform mod_record_action(p_target, p_post, 'dismiss', null, null, null, p_note, null);
  return v_count;
end $$;

-- Reopen a dismissed case (what makes dismiss honestly reversible).
create or replace function mod_reopen(p_target uuid, p_post bigint default null)
returns integer
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_count integer;
begin
  if mod_actor_tier() < 1 then
    raise exception 'You do not have permission to take this action.';
  end if;
  update reports r
     set status = 'open', resolved_at = null, resolved_by = null
   where r.subject_user_id = p_target
     and (p_post is null or r.subject_post_id = p_post)
     and r.status = 'dismissed';
  get diagnostics v_count = row_count;
  if v_count = 0 then
    raise exception 'No dismissed reports to reopen for this case.';
  end if;
  perform append_audit('mod.reopen', 'user', p_target::text,
                       jsonb_build_object('post_id', p_post, 'reports', v_count));
  return v_count;
end $$;

-- Warn: a recorded notice naming the rule, optionally also removing
-- the specific post. No functional restriction.
create or replace function mod_warn(
  p_target  uuid,
  p_rule    report_reason,
  p_message text,
  p_post    bigint default null,
  p_remove  boolean default false,
  p_note    text default null
) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  perform mod_assert_actionable(p_target, 1);
  perform mod_assert_not_csam(p_target, p_post);
  if nullif(btrim(coalesce(p_message, '')), '') is null then
    raise exception 'A warning needs a message to the member.';
  end if;
  if p_remove and p_post is not null then
    update posts set visibility = 'removed_moderation'
     where id = p_post and author_id = p_target and visibility = 'visible';
  end if;
  perform mod_resolve_case(p_target, p_post, 'actioned', p_note);
  perform mod_record_action(p_target, p_post, 'warn', p_rule, null, p_message, p_note, null);
  perform mod_notify(p_target, p_message, case when p_remove then null else p_post end);
end $$;

-- Remove content: the specific post leaves every public surface
-- (read paths already skip removed_moderation). Restorable.
create or replace function mod_remove_post(
  p_post bigint, p_rule report_reason, p_note text default null
) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_author uuid;
begin
  select author_id into v_author from posts
   where id = p_post and deleted_at is null;
  if v_author is null then
    raise exception 'That post is unavailable.';
  end if;
  perform mod_assert_actionable(v_author, 1);
  perform mod_assert_not_csam(v_author, p_post);
  update posts set visibility = 'removed_moderation'
   where id = p_post and visibility <> 'removed_moderation';
  perform mod_resolve_case(v_author, p_post, 'actioned', p_note);
  perform mod_record_action(v_author, p_post, 'remove_content', p_rule, null, null, p_note, null);
  perform mod_notify(v_author,
    'A post of yours was removed for breaking our rule on ' || p_rule::text
    || '. You can appeal within 30 days at appeals@unitedfeminist.com.', null);
end $$;

-- Restore a moderation-removed post (what makes removal reversible).
create or replace function mod_restore_post(p_post bigint, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_author uuid;
begin
  select author_id into v_author from posts
   where id = p_post and visibility = 'removed_moderation' and deleted_at is null;
  if v_author is null then
    raise exception 'That post is not removed by moderation.';
  end if;
  if mod_actor_tier() < 1 then
    raise exception 'You do not have permission to take this action.';
  end if;
  update posts set visibility = 'visible' where id = p_post;
  perform mod_record_action(v_author, p_post, 'restore_content', null, null, null, p_note, null);
  perform mod_notify(v_author, 'A post of yours that was removed has been restored.', p_post);
end $$;

-- Restrict: read-but-not-post, time-boxed. Moderator ≤ 7 days;
-- longer is Admin-only; 30 days is the ceiling.
create or replace function mod_restrict(
  p_target uuid, p_days integer, p_rule report_reason, p_note text default null
) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_until timestamptz;
begin
  perform mod_assert_actionable(p_target, 1);
  perform mod_assert_not_csam(p_target, null);
  if p_days is null or p_days < 1 or p_days > 30 then
    raise exception 'Restrictions run from 1 to 30 days.';
  end if;
  if p_days > 7 and mod_actor_tier() < 2 then
    raise exception 'Restrictions over 7 days are set by an admin.';
  end if;
  if exists (select 1 from profiles where user_id = p_target and status in ('suspended', 'banned')) then
    raise exception 'This account is already suspended or banned.';
  end if;
  v_until := now() + make_interval(days => p_days);
  update profiles set status = 'restricted', status_expires_at = v_until
   where user_id = p_target;
  perform mod_resolve_case(p_target, null, 'actioned', p_note);
  perform mod_record_action(p_target, null, 'restrict', p_rule, p_days, null, p_note, v_until);
  perform mod_notify(p_target,
    'Your account is limited until ' || to_char(v_until, 'DD Mon YYYY')
    || ' for breaking our rule on ' || p_rule::text
    || '. You can read, but you cannot post or reply. You can appeal at appeals@unitedfeminist.com.',
    null);
end $$;

-- Suspend: the account is out for a defined period. Moderator ≤ 7
-- days; longer is Admin-only; 30 days is the ceiling (the
-- guidelines' band). Permanent is NEVER a duration — permanent is
-- Ban, a different function with a different gate.
create or replace function mod_suspend(
  p_target uuid, p_days integer, p_rule report_reason, p_note text default null
) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_until timestamptz;
begin
  perform mod_assert_actionable(p_target, 1);
  perform mod_assert_not_csam(p_target, null);
  if exists (select 1 from role_assignments
             where user_id = p_target and role = 'owner' and revoked_at is null) then
    raise exception 'The Owner''s account cannot be suspended.';
  end if;
  if p_days is null or p_days < 1 or p_days > 30 then
    raise exception 'Suspensions run from 1 to 30 days.';
  end if;
  if p_days > 7 and mod_actor_tier() < 2 then
    raise exception 'Suspensions over 7 days are set by an admin.';
  end if;
  if exists (select 1 from profiles where user_id = p_target and status = 'banned') then
    raise exception 'This account is already banned.';
  end if;
  v_until := now() + make_interval(days => p_days);
  update profiles set status = 'suspended', status_expires_at = v_until
   where user_id = p_target;
  perform revoke_user_sessions(p_target);
  perform mod_resolve_case(p_target, null, 'actioned', p_note);
  perform mod_record_action(p_target, null, 'suspend', p_rule, p_days, null, p_note, v_until);
  perform mod_notify(p_target,
    'Your account is suspended until ' || to_char(v_until, 'DD Mon YYYY')
    || ' for breaking our rule on ' || p_rule::text
    || '. You can appeal at appeals@unitedfeminist.com.',
    null);
end $$;

-- Lift a restriction or suspension early. Moderators may lift a
-- restriction (which they can impose); suspensions are lifted by
-- admins and the Owner.
create or replace function mod_lift(p_target uuid, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_status account_status;
begin
  select status into v_status from profiles where user_id = p_target;
  if v_status is null or v_status not in ('restricted', 'suspended') then
    raise exception 'This account has no restriction or suspension to lift.';
  end if;
  perform mod_assert_actionable(p_target, case when v_status = 'suspended' then 2 else 1 end);
  update profiles set status = 'active', status_expires_at = null
   where user_id = p_target;
  perform mod_record_action(p_target, null, 'lift', null, null, null, p_note, null);
  perform mod_notify(p_target, 'Your account is active again. Welcome back.', null);
end $$;

-- Escalate: hand the case up with context. A moderator's path to a
-- longer suspension, and everyone's one forward action on csam.
create or replace function mod_escalate(
  p_target uuid, p_post bigint default null, p_note text default null
) returns integer
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_count integer;
begin
  if mod_actor_tier() < 0 then
    raise exception 'You do not have permission to take this action.';
  end if;
  update reports r
     set status = 'escalated',
         resolution_note = coalesce(nullif(btrim(coalesce(p_note, '')), ''), r.resolution_note)
   where r.subject_user_id = p_target
     and (p_post is null or r.subject_post_id = p_post)
     and r.status in ('open', 'in_review');
  get diagnostics v_count = row_count;
  if v_count = 0 then
    raise exception 'No open reports to escalate for this case.';
  end if;
  perform append_audit('mod.escalate', 'user', p_target::text,
                       jsonb_build_object('post_id', p_post, 'reports', v_count));
  return v_count;
end $$;

-- Ban, permanently. ADMIN AND OWNER ONLY. The Owner and the system
-- account are unbannable. Writes the chosen ban-evasion signals —
-- HMAC hashes only, computed server-side with the app pepper and
-- passed in; the raw identifiers never reach this function, the
-- client, or the audit log. The device hash is already stored hashed
-- in user_private and is read here directly.
create or replace function mod_ban(
  p_target     uuid,
  p_rule       report_reason,
  p_note       text,
  p_email_hash bytea default null,
  p_phone_hash bytea default null,
  p_ban_device boolean default true
) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_device bytea;
  v_kinds  text[] := '{}';
begin
  perform mod_assert_actionable(p_target, 2);
  perform mod_assert_not_csam(p_target, null);
  if exists (select 1 from role_assignments
             where user_id = p_target and role = 'owner' and revoked_at is null) then
    raise exception 'The Owner''s account cannot be banned.';
  end if;
  if nullif(btrim(coalesce(p_note, '')), '') is null then
    raise exception 'A permanent ban requires a note for the record.';
  end if;
  if exists (select 1 from profiles where user_id = p_target and status = 'banned') then
    raise exception 'This account is already banned.';
  end if;

  update profiles set status = 'banned', status_expires_at = null
   where user_id = p_target;
  perform revoke_user_sessions(p_target);

  if p_email_hash is not null then
    insert into banned_identifiers (kind, value_hash, source_user_id, reason)
    values ('email_hash', p_email_hash, p_target, p_rule::text)
    on conflict (kind, value_hash) do nothing;
    v_kinds := array_append(v_kinds, 'email_hash');
  end if;
  if p_phone_hash is not null then
    insert into banned_identifiers (kind, value_hash, source_user_id, reason)
    values ('phone_hash', p_phone_hash, p_target, p_rule::text)
    on conflict (kind, value_hash) do nothing;
    v_kinds := array_append(v_kinds, 'phone_hash');
  end if;
  if p_ban_device then
    select device_fingerprint_hash into v_device
      from user_private where user_id = p_target;
    if v_device is not null then
      insert into banned_identifiers (kind, value_hash, source_user_id, reason)
      values ('device_hash', v_device, p_target, p_rule::text)
      on conflict (kind, value_hash) do nothing;
      v_kinds := array_append(v_kinds, 'device_hash');
    end if;
  end if;

  perform mod_resolve_case(p_target, null, 'actioned', p_note);
  -- The audit entry records WHICH KINDS of signal were written,
  -- never the values.
  perform mod_record_action(p_target, null, 'ban', p_rule, null, null,
                            p_note || ' [evasion signals: '
                              || coalesce(array_to_string(v_kinds, ','), 'none') || ']',
                            null);
end $$;

-- Reversing a permanent ban is deliberately NOT a console action:
-- Owner-only, with MFA step-up, reached via the appeal and the audit
-- trail. Does not retract ban-evasion entries by itself (the Owner's
-- blocklist surface handles those separately, a later increment).
create or replace function owner_unban(p_target uuid, p_note text default null)
returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  perform require_owner_aal2();
  if not exists (select 1 from profiles where user_id = p_target and status = 'banned') then
    raise exception 'This account is not banned.';
  end if;
  update profiles set status = 'active', status_expires_at = null
   where user_id = p_target;
  perform mod_record_action(p_target, null, 'unban', null, null, null, p_note, null);
  perform mod_notify(p_target, 'Your account has been reopened following review.', null);
end $$;

-- ------------------------------------------------------------
-- 8. Console read functions. @handle only, by construction.
-- ------------------------------------------------------------

-- Which reports may the caller see? Mirrors the reports_queue policy
-- exactly, for use inside the DEFINER read functions (which bypass
-- RLS and must re-impose it).
create or replace function mod_report_visible(p_routing report_routing, p_accused uuid)
returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select (p_routing = 'standard' and is_reviewer_or_above())
      or (p_routing in ('admin_only', 'owner_conflict')
          and is_admin_or_owner()
          and (is_owner() or p_accused <> auth.uid()))
$$;

-- The queue, grouped into cases: one row per (accused, subject post).
-- p_state: 'open' | 'in_review' | 'escalated' | 'resolved'.
create or replace function mod_queue(
  p_state text default 'open',
  p_limit integer default 50
) returns table (
  accused_id      uuid,
  accused_handle  text,
  accused_status  account_status,
  subject_post_id bigint,
  top_reason      report_reason,
  report_count    bigint,
  reporter_count  bigint,
  newest_at       timestamptz,
  case_state      text,
  priority        text,
  assigned_handle text
)
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if mod_actor_tier() < 0 then
    raise exception 'You do not have permission to view the moderation queue.';
  end if;

  -- Opportunistic retention pruning (owner-approved): moderation
  -- records and ban-evasion signals both expire at 2 years. The
  -- audit log (7 years) is untouched.
  delete from safety_email_outbox o
   where o.created_at < now() - interval '2 years';
  delete from reports r
   where r.created_at < now() - interval '2 years'
     and r.status in ('actioned', 'dismissed');
  delete from moderation_actions a where a.created_at < now() - interval '2 years';
  delete from banned_identifiers b where b.created_at < now() - interval '2 years';

  return query
  with visible as (
    select r.* from reports r
    where mod_report_visible(r.routing, r.subject_user_id)
  ),
  grouped as (
    select
      r.subject_user_id,
      r.subject_post_id,
      count(*) as n_reports,
      count(distinct r.reporter_id) as n_reporters,
      max(r.created_at) as newest,
      -- Severity rank: csam > ncii > violence_threat > doxxing >
      -- self_harm > hate > the rest.
      (array_agg(r.reason order by case r.reason
          when 'csam' then 0 when 'ncii' then 1 when 'violence_threat' then 2
          when 'doxxing' then 3 when 'self_harm' then 4 when 'hate' then 5
          when 'harassment' then 6 when 'impersonation' then 7
          when 'spam' then 8 else 9 end))[1] as worst,
      case
        when bool_or(r.status = 'open') then 'open'
        when bool_or(r.status = 'in_review') then 'in_review'
        when bool_or(r.status = 'escalated') then 'escalated'
        else 'resolved'
      end as cstate,
      (array_agg(r.assigned_to) filter (where r.assigned_to is not null))[1] as assignee
    from visible r
    group by r.subject_user_id, r.subject_post_id
  )
  select
    g.subject_user_id,
    pr.handle::text,
    pr.status,
    g.subject_post_id,
    g.worst,
    g.n_reports,
    g.n_reporters,
    g.newest,
    g.cstate,
    case
      when g.worst in ('csam', 'ncii', 'violence_threat') then 'critical'
      when g.worst in ('doxxing', 'self_harm', 'hate') then 'high'
      else 'normal'
    end,
    (select apr.handle::text from profiles apr where apr.user_id = g.assignee)
  from grouped g
  join profiles pr on pr.user_id = g.subject_user_id
  where g.cstate = coalesce(nullif(p_state, ''), 'open')
  order by
    case when g.worst in ('csam', 'ncii', 'violence_threat') then 0
         when g.worst in ('doxxing', 'self_harm', 'hate') then 1
         else 2 end,
    g.newest desc
  limit least(greatest(coalesce(p_limit, 50), 1), 100);
end $$;

-- Queue shape without drama: open, critical-open, in-review counts.
create or replace function mod_queue_counts()
returns table (open_count bigint, critical_count bigint, in_review_count bigint)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if mod_actor_tier() < 0 then
    -- Members get zeros, not an error: the shell calls this only for
    -- staff, but a race on role revocation must not break the app.
    return query select 0::bigint, 0::bigint, 0::bigint;
    return;
  end if;
  return query
  with visible as (
    select r.* from reports r
    where mod_report_visible(r.routing, r.subject_user_id)
  )
  select
    count(*) filter (where v.status = 'open'),
    count(*) filter (where v.status in ('open', 'in_review', 'escalated')
                       and v.reason in ('csam', 'ncii', 'violence_threat')),
    count(*) filter (where v.status = 'in_review')
  from visible v;
end $$;

-- One case's reports. Reporter identity is deliberately ABSENT here;
-- revealing reporters is a separate, audited act (mod_view_reporters).
create or replace function mod_case(p_target uuid, p_post bigint default null)
returns table (
  report_id       uuid,
  reason          report_reason,
  details         text,
  status          report_status,
  created_at      timestamptz,
  assigned_handle text,
  resolution_note text
)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if mod_actor_tier() < 0 then
    raise exception 'You do not have permission to view this case.';
  end if;
  return query
  select r.id, r.reason, r.details, r.status, r.created_at,
         (select pr.handle::text from profiles pr where pr.user_id = r.assigned_to),
         case when mod_actor_tier() >= 1 then r.resolution_note end
  from reports r
  where r.subject_user_id = p_target
    and (p_post is null or r.subject_post_id = p_post)
    and mod_report_visible(r.routing, r.subject_user_id)
  order by r.created_at desc
  limit 200;
end $$;

-- Revealing who reported is an intentional, audited act (the power
-- to see who reports whom is itself loggable power). Returns each
-- report's reporter handle plus that reporter's 24-hour filing count
-- (the report-abuse tell).
create or replace function mod_view_reporters(p_target uuid, p_post bigint default null)
returns table (
  report_id        uuid,
  reporter_handle  text,
  reporter_reports_24h bigint
)
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if mod_actor_tier() < 0 then
    raise exception 'You do not have permission to view this case.';
  end if;
  perform append_audit('mod.viewed_reporters', 'user', p_target::text,
                       jsonb_build_object('post_id', p_post));
  return query
  select r.id, pr.handle::text,
         (select count(*) from reports r2
          where r2.reporter_id = r.reporter_id
            and r2.created_at > now() - interval '24 hours')
  from reports r
  join profiles pr on pr.user_id = r.reporter_id
  where r.subject_user_id = p_target
    and (p_post is null or r.subject_post_id = p_post)
    and mod_report_visible(r.routing, r.subject_user_id)
  order by r.created_at desc
  limit 200;
end $$;

-- A reported post in its thread context: the parent chain up to the
-- root and a small window of replies, read-only, handle-only.
-- Moderation-removed and author-removed content returns an empty body
-- with its visibility flag so the console stubs it rather than
-- re-surfacing what a colleague took down.
create or replace function mod_post_context(p_post bigint)
returns table (
  id             bigint,
  parent_post_id bigint,
  depth          smallint,
  author_handle  text,
  body           text,
  visibility     post_visibility,
  author_deleted boolean,
  created_at     timestamptz,
  is_subject     boolean
)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if mod_actor_tier() < 0 then
    raise exception 'You do not have permission to view this case.';
  end if;
  return query
  with recursive parents as (
    select p.* from posts p where p.id = p_post
    union all
    select pp.* from posts pp join parents c on pp.id = c.parent_post_id
  ),
  kids as (
    select p.* from posts p
    where p.parent_post_id = p_post
    order by p.created_at
    limit 10
  ),
  all_rows as (
    select * from parents
    union all
    select * from kids
  )
  select a.id, a.parent_post_id, a.depth,
         pr.handle::text,
         case when a.visibility = 'visible' and a.deleted_at is null then a.body else '' end,
         a.visibility,
         a.deleted_at is not null,
         a.created_at,
         a.id = p_post
  from all_rows a
  join profiles pr on pr.user_id = a.author_id
  order by a.depth, a.created_at;
end $$;

-- A reported account's recent posts (account-level cases).
create or replace function mod_account_posts(p_target uuid, p_limit integer default 20)
returns table (
  id         bigint,
  body       text,
  visibility post_visibility,
  is_reply   boolean,
  created_at timestamptz
)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if mod_actor_tier() < 0 then
    raise exception 'You do not have permission to view this case.';
  end if;
  return query
  select p.id,
         case when p.visibility = 'visible' and p.deleted_at is null then p.body else '' end,
         p.visibility,
         p.parent_post_id is not null,
         p.created_at
  from posts p
  where p.author_id = p_target and p.deleted_at is null
  order by p.created_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
end $$;

-- The account-context strip: age on platform, post count, current
-- status, and how often it has been actioned before. De-identified,
-- keyed to the handle.
create or replace function mod_account_context(p_target uuid)
returns table (
  handle            text,
  status            account_status,
  status_expires_at timestamptz,
  joined_at         timestamptz,
  post_count        bigint,
  prior_actions     bigint,
  is_staff          boolean
)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if mod_actor_tier() < 0 then
    raise exception 'You do not have permission to view this case.';
  end if;
  return query
  select pr.handle::text, pr.status, pr.status_expires_at, pr.created_at,
         (select count(*) from posts p where p.author_id = p_target and p.deleted_at is null),
         (select count(*) from moderation_actions a
          where a.target_user_id = p_target
            and a.action not in ('dismiss', 'restore_content', 'lift', 'unban')),
         exists (select 1 from role_assignments ra
                 where ra.user_id = p_target and ra.revoked_at is null)
  from profiles pr
  where pr.user_id = p_target;
end $$;

-- The enforcement trail on an account. Staff see the acting ROLE;
-- the acting staff member's handle is shown to admins and the Owner
-- only (accountability review), mirroring the design's stance that
-- moderators do not see each other's identities across cases.
create or replace function mod_enforcement_history(p_target uuid)
returns table (
  action       mod_action,
  rule         report_reason,
  duration_days integer,
  actor_role   text,
  actor_handle text,
  note         text,
  created_at   timestamptz,
  expires_at   timestamptz
)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if mod_actor_tier() < 0 then
    raise exception 'You do not have permission to view this case.';
  end if;
  return query
  select a.action, a.rule, a.duration_days, a.actor_role,
         case when is_admin_or_owner()
              then (select pr.handle::text from profiles pr where pr.user_id = a.actor_id) end,
         case when mod_actor_tier() >= 1 then a.note end,
         a.created_at, a.expires_at
  from moderation_actions a
  where a.target_user_id = p_target
  order by a.created_at desc, a.id desc
  limit 100;
end $$;

-- ------------------------------------------------------------
-- 9. Member-facing status: "what happened to me", with the rule and
--    the action, never the reporter and never the acting human.
-- ------------------------------------------------------------
create or replace function my_account_status()
returns table (
  status            account_status,
  status_expires_at timestamptz,
  last_action       mod_action,
  last_rule         report_reason,
  last_message      text,
  last_action_at    timestamptz
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select pr.status, pr.status_expires_at,
         a.action, a.rule, a.message, a.created_at
  from profiles pr
  left join lateral (
    select ma.action, ma.rule, ma.message, ma.created_at
    from moderation_actions ma
    where ma.target_user_id = pr.user_id
      and ma.action in ('warn', 'remove_content', 'restrict', 'suspend', 'ban')
    order by ma.created_at desc, ma.id desc
    limit 1
  ) a on true
  where pr.user_id = auth.uid()
$$;

-- Lazy expiry: a restriction or suspension whose clock has run out
-- flips back to active the next time the member arrives. Self-only.
create or replace function refresh_my_status() returns boolean
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_flipped boolean := false;
begin
  update profiles
     set status = 'active', status_expires_at = null
   where user_id = auth.uid()
     and status in ('restricted', 'suspended')
     and status_expires_at is not null
     and status_expires_at <= now();
  if found then
    v_flipped := true;
    perform append_audit('mod.status_expired', 'user', auth.uid()::text);
  end if;
  return v_flipped;
end $$;

-- ------------------------------------------------------------
-- 10. get_notifications: same shape plus the new body column, so the
--     warn/removal notices can carry their message. Signature
--     changes, so the old function is dropped and grants re-stated
--     (0014's pattern).
-- ------------------------------------------------------------
drop function if exists get_notifications(timestamptz, integer, bigint);
create or replace function get_notifications(
  p_before    timestamptz default null,
  p_limit     integer default 30,
  p_before_id bigint default null
) returns table (
  id           bigint,
  type         notif_type,
  actor_id     uuid,
  actor_handle text,
  post_id      bigint,
  post_excerpt text,
  body         text,
  created_at   timestamptz,
  read_at      timestamptz
)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select n.id, n.type, n.actor_id, coalesce(a.handle::text, ''), n.post_id,
         case when p.id is null or p.deleted_at is not null or p.visibility <> 'visible' then null
              else left(p.body, 120) end,
         n.body,
         n.created_at, n.read_at
  from notifications n
  left join profiles a on a.user_id = n.actor_id
  left join posts p on p.id = n.post_id
  where n.user_id = auth.uid()
    and (n.actor_id is null or (
          not blocked_either(auth.uid(), n.actor_id)
          and not exists (select 1 from mutes m
                          where m.muter_id = auth.uid() and m.muted_id = n.actor_id)))
    and (p_before is null
         or (p_before_id is null and n.created_at < p_before)
         or (p_before_id is not null and (n.created_at, n.id) < (p_before, p_before_id)))
  order by n.created_at desc, n.id desc
  limit least(greatest(coalesce(p_limit, 30), 1), 50)
$$;

-- ------------------------------------------------------------
-- 11. EXECUTE lockdown. Internal helpers get no app-role grants at
--     all; console functions go to authenticated (each re-checks the
--     caller's role inside, like grant_role does); nothing here is
--     for anon or service_role.
-- ------------------------------------------------------------
revoke execute on function mod_actor_tier()                                             from public, anon, authenticated, service_role;
revoke execute on function mod_assert_actionable(uuid, integer)                          from public, anon, authenticated, service_role;
revoke execute on function mod_assert_not_csam(uuid, bigint)                             from public, anon, authenticated, service_role;
revoke execute on function mod_resolve_case(uuid, bigint, report_status, text)           from public, anon, authenticated, service_role;
revoke execute on function mod_record_action(uuid, bigint, mod_action, report_reason, integer, text, text, timestamptz) from public, anon, authenticated, service_role;
revoke execute on function mod_notify(uuid, text, bigint)                                from public, anon, authenticated, service_role;
revoke execute on function mod_report_visible(report_routing, uuid)                      from public, anon, authenticated, service_role;

revoke execute on function mod_claim(uuid, bigint)                                       from public, anon, service_role;
revoke execute on function mod_dismiss(uuid, bigint, text)                               from public, anon, service_role;
revoke execute on function mod_reopen(uuid, bigint)                                      from public, anon, service_role;
revoke execute on function mod_warn(uuid, report_reason, text, bigint, boolean, text)    from public, anon, service_role;
revoke execute on function mod_remove_post(bigint, report_reason, text)                  from public, anon, service_role;
revoke execute on function mod_restore_post(bigint, text)                                from public, anon, service_role;
revoke execute on function mod_restrict(uuid, integer, report_reason, text)              from public, anon, service_role;
revoke execute on function mod_suspend(uuid, integer, report_reason, text)               from public, anon, service_role;
revoke execute on function mod_lift(uuid, text)                                          from public, anon, service_role;
revoke execute on function mod_escalate(uuid, bigint, text)                              from public, anon, service_role;
revoke execute on function mod_ban(uuid, report_reason, text, bytea, bytea, boolean)     from public, anon, service_role;
revoke execute on function owner_unban(uuid, text)                                       from public, anon, service_role;
revoke execute on function mod_queue(text, integer)                                      from public, anon, service_role;
revoke execute on function mod_queue_counts()                                            from public, anon, service_role;
revoke execute on function mod_case(uuid, bigint)                                        from public, anon, service_role;
revoke execute on function mod_view_reporters(uuid, bigint)                              from public, anon, service_role;
revoke execute on function mod_post_context(bigint)                                      from public, anon, service_role;
revoke execute on function mod_account_posts(uuid, integer)                              from public, anon, service_role;
revoke execute on function mod_account_context(uuid)                                     from public, anon, service_role;
revoke execute on function mod_enforcement_history(uuid)                                 from public, anon, service_role;
revoke execute on function my_account_status()                                           from public, anon, service_role;
revoke execute on function refresh_my_status()                                           from public, anon, service_role;
revoke execute on function get_notifications(timestamptz, integer, bigint)               from public, anon, service_role;

grant execute on function mod_claim(uuid, bigint)                                        to authenticated;
grant execute on function mod_dismiss(uuid, bigint, text)                                to authenticated;
grant execute on function mod_reopen(uuid, bigint)                                       to authenticated;
grant execute on function mod_warn(uuid, report_reason, text, bigint, boolean, text)     to authenticated;
grant execute on function mod_remove_post(bigint, report_reason, text)                   to authenticated;
grant execute on function mod_restore_post(bigint, text)                                 to authenticated;
grant execute on function mod_restrict(uuid, integer, report_reason, text)               to authenticated;
grant execute on function mod_suspend(uuid, integer, report_reason, text)                to authenticated;
grant execute on function mod_lift(uuid, text)                                           to authenticated;
grant execute on function mod_escalate(uuid, bigint, text)                               to authenticated;
grant execute on function mod_ban(uuid, report_reason, text, bytea, bytea, boolean)      to authenticated;
grant execute on function owner_unban(uuid, text)                                        to authenticated;
grant execute on function mod_queue(text, integer)                                       to authenticated;
grant execute on function mod_queue_counts()                                             to authenticated;
grant execute on function mod_case(uuid, bigint)                                         to authenticated;
grant execute on function mod_view_reporters(uuid, bigint)                               to authenticated;
grant execute on function mod_post_context(bigint)                                       to authenticated;
grant execute on function mod_account_posts(uuid, integer)                               to authenticated;
grant execute on function mod_account_context(uuid)                                      to authenticated;
grant execute on function mod_enforcement_history(uuid)                                  to authenticated;
grant execute on function my_account_status()                                            to authenticated;
grant execute on function refresh_my_status()                                            to authenticated;
grant execute on function get_notifications(timestamptz, integer, bigint)                to authenticated;
