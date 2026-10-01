-- ============================================================
-- 0008 — Admission flow functions (the two-lane gate).
--
-- All admission state transitions happen in SECURITY DEFINER functions
-- so application code never writes these tables directly. Every
-- decision lands in the audit log.
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- Triage signal helpers (called by the server before account creation).
-- ------------------------------------------------------------

-- Signups from the same subnet (/24 for IPv4, /56 for IPv6) in a window.
create or replace function count_signups_from_subnet(p_ip inet, p_window interval default interval '24 hours')
returns integer
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select count(*)::integer
  from signup_attempts s
  where s.created_at > now() - p_window
    and s.ip is not null
    and case
          when family(p_ip) = 4 and family(s.ip) = 4
            then network(set_masklen(s.ip, 24)) = network(set_masklen(p_ip, 24))
          when family(p_ip) = 6 and family(s.ip) = 6
            then network(set_masklen(s.ip, 56)) = network(set_masklen(p_ip, 56))
          else false
        end
$$;

create or replace function count_signup_attempts_from_ip(p_ip inet, p_window interval default interval '24 hours')
returns integer
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select count(*)::integer from signup_attempts
  where ip = p_ip and created_at > now() - p_window
$$;

create or replace function record_signup_attempt(p_ip inet, p_email_hash bytea) returns void
language sql security definer set search_path = public, extensions, pg_temp as $$
  insert into signup_attempts (ip, email_hash) values (p_ip, p_email_hash)
$$;

-- Device-fingerprint / email / phone hash match against banned accounts.
create or replace function identifier_is_banned(p_kind text, p_hash bytea) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (select 1 from banned_identifiers where kind = p_kind and value_hash = p_hash)
$$;

create or replace function config_int(p_key text, p_default integer) returns integer
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce((select (value #>> '{}')::integer from app_config where key = p_key), p_default)
$$;

-- One-number-one-account is enforced at ADMISSION (not at signup, where a
-- duplicate-phone error would leak that the number belongs to an account).
create or replace function phone_in_use_by_member(p_user uuid) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (
    select 1
    from user_private mine
    join user_private other
      on other.phone_e164 = mine.phone_e164 and other.user_id <> mine.user_id
    join profiles p on p.user_id = other.user_id
    where mine.user_id = p_user
      and mine.phone_e164 is not null
      and p.trust_level <> 'pending_vouch'
      and p.status not in ('deleted', 'deactivated')
  )
$$;

-- ------------------------------------------------------------
-- create_application — the single entry point for signup.
--
-- Runs AFTER the auth user exists. Creates profile + private PII +
-- application, and — when the applicant named an inviter — resolves the
-- handle and creates a vouch request IF AND ONLY IF:
--   * the handle belongs to an admitted, active, non-system member, and
--   * that member is under her daily vouch-request cap (anti-fishing).
-- CRITICAL: the function's observable result is IDENTICAL whether or
-- not the handle resolved. It returns void, raises no handle-related
-- errors, and the caller responds with the same message and padded
-- timing either way. Membership is never confirmed or denied.
-- ------------------------------------------------------------
create or replace function create_application(
  p_user_id          uuid,
  p_email            citext,
  p_legal_name       text,
  p_dob              date,
  p_handle           citext,
  p_phone            text,
  p_inviter_handle   citext,   -- null/empty when the field was left blank
  p_signup_ip        inet,
  p_fingerprint_hash bytea,
  p_signals          jsonb,
  p_bucket           triage_bucket
) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_voucher   uuid;
  v_status    admission_status;
  v_named     boolean := p_inviter_handle is not null and btrim(p_inviter_handle::text) <> '';
  v_app_id    uuid;
  v_cap       integer := config_int('vouch_requests_per_member_per_day', 5);
  v_deadline  interval := make_interval(hours => config_int('vouch_deadline_hours', 48));
begin
  if p_dob > (current_date - interval '18 years') then
    raise exception 'Applicants must be 18 or older.';
  end if;

  insert into profiles (user_id, handle) values (p_user_id, p_handle);

  insert into user_private (user_id, legal_name, dob, email, phone_e164,
                            device_fingerprint_hash, signup_ip)
  values (p_user_id, p_legal_name, p_dob, p_email, nullif(p_phone, ''),
          p_fingerprint_hash, p_signup_ip);

  if p_bucket = 'auto_rejected' then
    -- Obvious automated abuse: parked silently; shown to nobody, ever.
    v_status := 'auto_rejected';
  else
    v_status := 'queued';
    if v_named then
      select p.user_id into v_voucher
      from profiles p
      where p.handle = p_inviter_handle
        and p.trust_level <> 'pending_vouch'
        and p.status = 'active'
        and not p.is_system
        and p.user_id <> p_user_id;

      if v_voucher is not null then
        -- Daily cap: nobody can be carpet-bombed with vouch requests to
        -- fish for a yes, and bulk probing yields nothing observable.
        if (select count(*) from vouch_requests
            where voucher_user_id = v_voucher
              and created_at > now() - interval '24 hours') < v_cap then
          v_status := 'awaiting_vouch';
        end if;
      end if;
    end if;
  end if;

  insert into admission_applications (user_id, status, inviter_named, triage_bucket, triage_signals, triage_score)
  values (p_user_id, v_status, v_named, p_bucket, coalesce(p_signals, '{}'::jsonb),
          nullif(p_signals ->> 'score', '')::numeric)
  returning id into v_app_id;

  if v_status = 'awaiting_vouch' then
    insert into vouch_requests (application_id, applicant_user_id, voucher_user_id, deadline)
    values (v_app_id, p_user_id, v_voucher, now() + v_deadline);
  end if;

  perform append_audit('admission.apply', 'application', v_app_id::text,
                       jsonb_build_object('bucket', p_bucket, 'inviter_named', v_named,
                                          'lane', case when v_status = 'awaiting_vouch' then 1 else 2 end));
end $$;

-- ------------------------------------------------------------
-- Internal: admit an applicant (shared by both lanes).
-- ------------------------------------------------------------
create or replace function admit_application(p_app_id uuid, p_new_status admission_status, p_voucher uuid)
returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_user uuid;
  v_old  admission_status;
begin
  select user_id, status into v_user, v_old from admission_applications where id = p_app_id for update;
  if v_user is null then
    raise exception 'Application not found.';
  end if;
  if phone_in_use_by_member(v_user) then
    raise exception 'phone_in_use';
  end if;
  update admission_applications
     set status = p_new_status, decided_at = now(), decided_by = auth.uid()
   where id = p_app_id;
  update profiles
     set trust_level = 'member', vouched_by = coalesce(p_voucher, vouched_by)
   where user_id = v_user;
  perform append_audit(
    case when p_new_status = 'admitted_vouched' then 'admission.admit_vouched'
         else 'admission.approve' end,
    'application', p_app_id::text, '{}'::jsonb,
    jsonb_build_object('status', v_old),
    jsonb_build_object('status', p_new_status));
end $$;

-- ------------------------------------------------------------
-- Vouching. ACCESS IS GRANTED ON CONFIRMATION, NOT ON SUBMISSION —
-- and only when the voucher holds the Owner-granted auto_admit
-- privilege (the Owner's own vouch counts as auto_admit). Any other
-- member's confirmed vouch moves the applicant to the review queue at
-- RAISED priority. Decline or 48h silence -> queue, never rejection.
-- ------------------------------------------------------------
create or replace function confirm_vouch(p_request uuid) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v vouch_requests%rowtype;
begin
  select * into v from vouch_requests where id = p_request for update;
  if v.id is null or v.voucher_user_id <> auth.uid() then
    raise exception 'Vouch request not found.';
  end if;
  if v.status <> 'pending' then
    raise exception 'This vouch request has already been resolved.';
  end if;
  if v.deadline < now() then
    update vouch_requests set status = 'lapsed', responded_at = now() where id = v.id;
    update admission_applications set status = 'queued'
      where id = v.application_id and status = 'awaiting_vouch';
    raise exception 'This vouch request has expired.';
  end if;

  update vouch_requests set status = 'confirmed', responded_at = now() where id = v.id;
  update profiles set vouched_by = v.voucher_user_id where user_id = v.applicant_user_id;

  if has_privilege(auth.uid(), 'auto_admit') or is_owner() then
    begin
      perform admit_application(v.application_id, 'admitted_vouched', v.voucher_user_id);
    exception when others then
      if sqlerrm = 'phone_in_use' then
        -- Cannot auto-admit over a phone collision; send to the queue
        -- flagged so a human sees why.
        update admission_applications
           set status = 'queued', vouch_confirmed = true,
               triage_bucket = 'flagged',
               triage_signals = triage_signals || '{"phone_in_use": true}'::jsonb
         where id = v.application_id;
        perform append_audit('admission.vouch_confirmed', 'application', v.application_id::text,
                             jsonb_build_object('auto_admit', false, 'phone_in_use', true));
      else
        raise;
      end if;
    end;
  else
    update admission_applications
       set status = 'queued', vouch_confirmed = true
     where id = v.application_id;
    perform append_audit('admission.vouch_confirmed', 'application', v.application_id::text,
                         jsonb_build_object('auto_admit', false));
  end if;
end $$;

create or replace function decline_vouch(p_request uuid) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v vouch_requests%rowtype;
begin
  select * into v from vouch_requests where id = p_request for update;
  if v.id is null or v.voucher_user_id <> auth.uid() then
    raise exception 'Vouch request not found.';
  end if;
  if v.status <> 'pending' then
    raise exception 'This vouch request has already been resolved.';
  end if;
  update vouch_requests set status = 'declined', responded_at = now() where id = v.id;
  -- NOT a rejection: the applicant simply continues in the review queue.
  update admission_applications set status = 'queued'
    where id = v.application_id and status = 'awaiting_vouch';
  perform append_audit('admission.vouch_declined', 'application', v.application_id::text);
end $$;

-- Scheduled (pg_cron / job drain): 48h of silence moves Lane 1 -> Lane 2.
create or replace function lapse_expired_vouch_requests() returns integer
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  n integer;
begin
  with lapsed as (
    update vouch_requests
       set status = 'lapsed', responded_at = now()
     where status = 'pending' and deadline < now()
     returning application_id
  )
  update admission_applications a
     set status = 'queued'
    from lapsed l
   where a.id = l.application_id and a.status = 'awaiting_vouch';
  get diagnostics n = row_count;
  if n > 0 then
    perform append_audit('admission.vouches_lapsed', 'batch', null,
                         jsonb_build_object('count', n));
  end if;
  return n;
end $$;

-- The voucher's view of her pending requests. The applicant's legal
-- name is disclosed to the NAMED voucher only — she cannot meaningfully
-- confirm she knows the applicant from a handle alone, and the
-- applicant explicitly named her.
create or replace function get_my_vouch_requests()
returns table (id uuid, applicant_handle citext, applicant_legal_name text,
               created_at timestamptz, deadline timestamptz)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select vr.id, p.handle, up.legal_name, vr.created_at, vr.deadline
  from vouch_requests vr
  join profiles p on p.user_id = vr.applicant_user_id
  join user_private up on up.user_id = vr.applicant_user_id
  where vr.voucher_user_id = auth.uid()
    and vr.status = 'pending'
    and vr.deadline > now()
  order by vr.deadline
$$;

-- ------------------------------------------------------------
-- The applicant's own view: a COLLAPSED status. 'awaiting_vouch',
-- 'queued' and 'auto_rejected' all read as 'pending' so the signup
-- flow never reveals whether a named handle resolved (enumeration
-- safety) nor that automated triage rejected a bot (no oracle).
-- ------------------------------------------------------------
create or replace function my_application_status()
returns table (status text, message text)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select case a.status
           when 'awaiting_vouch'    then 'pending'
           when 'queued'            then 'pending'
           when 'auto_rejected'     then 'pending'
           when 'info_requested'    then 'info_requested'
           when 'admitted_vouched'  then 'admitted'
           when 'admitted_reviewed' then 'admitted'
           when 'rejected'          then 'rejected'
         end,
         case when a.status = 'info_requested' then a.info_request else null end
  from admission_applications a
  where a.user_id = auth.uid()
$$;

create or replace function submit_info_response(p_text text) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_app uuid;
begin
  if p_text is null or btrim(p_text) = '' or char_length(p_text) > 2000 then
    raise exception 'Response must be between 1 and 2000 characters.';
  end if;
  update admission_applications
     set info_response = btrim(p_text), status = 'queued'
   where user_id = auth.uid() and status = 'info_requested'
  returning id into v_app;
  if v_app is null then
    raise exception 'No information request is open on your application.';
  end if;
  perform append_audit('admission.info_response', 'application', v_app::text);
end $$;

-- ------------------------------------------------------------
-- Reviewer actions: approve / reject / request more info.
-- Owner and Admin may act; Moderator and T&S Reviewer may only read
-- the queue (RLS, 0009). Every action is audit-logged with before/after.
-- Auto-rejected applications are unreachable here by RLS *and* by the
-- status guards below.
-- ------------------------------------------------------------
create or replace function review_approve(p_app uuid, p_note text default null) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_status admission_status;
begin
  if not is_admin_or_owner() then
    raise exception 'Only the Owner or an Admin may decide applications.';
  end if;
  select status into v_status from admission_applications where id = p_app for update;
  if v_status is null or v_status not in ('queued', 'info_requested', 'awaiting_vouch') then
    raise exception 'This application is not open for review.';
  end if;
  begin
    perform admit_application(p_app, 'admitted_reviewed', null);
  exception when others then
    if sqlerrm = 'phone_in_use' then
      raise exception 'Cannot approve: phone number already belongs to an admitted member.';
    end if;
    raise;
  end;
  if p_note is not null and btrim(p_note) <> '' then
    update admission_applications set decision_note = btrim(p_note) where id = p_app;
  end if;
  update vouch_requests set status = 'cancelled', responded_at = now()
   where application_id = p_app and status = 'pending';
end $$;

create or replace function review_reject(p_app uuid, p_note text default null) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_status admission_status;
  v_user   uuid;
begin
  if not is_admin_or_owner() then
    raise exception 'Only the Owner or an Admin may decide applications.';
  end if;
  select status, user_id into v_status, v_user
    from admission_applications where id = p_app for update;
  if v_status is null or v_status not in ('queued', 'info_requested', 'awaiting_vouch') then
    raise exception 'This application is not open for review.';
  end if;
  update admission_applications
     set status = 'rejected', decided_at = now(), decided_by = auth.uid(),
         decision_note = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_app;
  update profiles set status = 'deactivated' where user_id = v_user;
  update vouch_requests set status = 'cancelled', responded_at = now()
   where application_id = p_app and status = 'pending';
  perform revoke_user_sessions(v_user);
  perform append_audit('admission.reject', 'application', p_app::text, '{}'::jsonb,
                       jsonb_build_object('status', v_status),
                       jsonb_build_object('status', 'rejected'));
end $$;

create or replace function review_request_info(p_app uuid, p_message text) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_status admission_status;
begin
  if not is_admin_or_owner() then
    raise exception 'Only the Owner or an Admin may decide applications.';
  end if;
  if p_message is null or btrim(p_message) = '' or char_length(p_message) > 2000 then
    raise exception 'The request message must be between 1 and 2000 characters.';
  end if;
  select status into v_status from admission_applications where id = p_app for update;
  if v_status is null or v_status not in ('queued', 'awaiting_vouch') then
    raise exception 'This application is not open for an information request.';
  end if;
  update admission_applications
     set status = 'info_requested', info_request = btrim(p_message)
   where id = p_app;
  perform append_audit('admission.request_info', 'application', p_app::text, '{}'::jsonb,
                       jsonb_build_object('status', v_status),
                       jsonb_build_object('status', 'info_requested'));
end $$;

-- ------------------------------------------------------------
-- Per-member vouch statistics, Owner only. These INFORM the Owner's
-- auto_admit decisions; nothing is ever triggered automatically.
-- ------------------------------------------------------------
create or replace function owner_vouch_stats()
returns table (user_id uuid, handle citext,
               vouches_confirmed bigint, vouchees_admitted bigint,
               vouchees_in_good_standing bigint, vouchees_removed bigint,
               requests_pending bigint, has_auto_admit boolean)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select p.user_id, p.handle,
         count(*) filter (where vr.status = 'confirmed'),
         count(*) filter (where vr.status = 'confirmed'
                            and a.status in ('admitted_vouched', 'admitted_reviewed')),
         count(*) filter (where vr.status = 'confirmed'
                            and a.status in ('admitted_vouched', 'admitted_reviewed')
                            and ap.status in ('active', 'restricted')),
         count(*) filter (where vr.status = 'confirmed'
                            and a.status in ('admitted_vouched', 'admitted_reviewed')
                            and ap.status in ('suspended', 'banned')),
         count(*) filter (where vr.status = 'pending'),
         has_privilege(p.user_id, 'auto_admit')
  from vouch_requests vr
  join profiles p  on p.user_id  = vr.voucher_user_id
  join admission_applications a on a.id = vr.application_id
  join profiles ap on ap.user_id = vr.applicant_user_id
  where is_owner()
  group by p.user_id, p.handle
  order by count(*) filter (where vr.status = 'confirmed') desc
$$;

-- ------------------------------------------------------------
-- Opt-in public display of the verified legal name (collect ≠ display).
-- ------------------------------------------------------------
create or replace function set_display_name_visibility(p_show boolean) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if p_show then
    update profiles p
       set display_name = (select legal_name from user_private where user_id = auth.uid())
     where p.user_id = auth.uid();
  else
    update profiles set display_name = null where user_id = auth.uid();
  end if;
  if not found then
    raise exception 'No profile for the current user.';
  end if;
end $$;
