-- ============================================================
-- 0006 — Admission: applications, vouch requests, review queue.
--
-- ENUMERATION SAFETY (hard requirement): nothing in this schema or in
-- the functions over it ever tells an APPLICANT whether the handle she
-- named resolved to a member. Applications in 'awaiting_vouch' and
-- 'queued' are indistinguishable to the applicant (my_application_status
-- collapses them, 0008), and applicants have NO read access to
-- vouch_requests or to their own application row.
-- ============================================================
set search_path = public, extensions;

create table admission_applications (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null unique references profiles (user_id) on delete cascade,
  status          admission_status not null,
  -- Did the applicant fill in "Who invited you?" (her own input — safe to
  -- store; it says nothing about whether the handle resolved).
  inviter_named   boolean not null default false,
  -- A real member confirmed she knows this applicant but holds no
  -- auto_admit privilege -> stays queued at RAISED priority.
  vouch_confirmed boolean not null default false,
  -- Automated triage. Review is never based on appearance, photographs,
  -- or gender; these are bot/abuse signals only.
  triage_bucket   triage_bucket not null default 'clean',
  triage_signals  jsonb not null default '{}'::jsonb,
  triage_score    numeric(5, 3),
  info_request    text,   -- reviewer's request-more-info message to the applicant
  info_response   text,   -- the applicant's reply
  decided_at      timestamptz,
  decided_by      uuid references profiles (user_id),
  decision_note   text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
-- Queue ordering: clean to the top, flagged to the bottom; a confirmed
-- vouch raises priority within the bucket; oldest first after that.
-- 'auto_rejected' rows are excluded by RLS from every queue, including
-- the Owner's (locked requirement).
create index idx_admission_queue
  on admission_applications (triage_bucket, vouch_confirmed desc, created_at)
  where status in ('queued', 'info_requested');

create table vouch_requests (
  id                uuid primary key default gen_random_uuid(),
  application_id    uuid not null references admission_applications (id) on delete cascade,
  applicant_user_id uuid not null references profiles (user_id) on delete cascade,
  voucher_user_id   uuid not null references profiles (user_id) on delete cascade,
  status            vouch_request_status not null default 'pending',
  created_at        timestamptz not null default now(),
  deadline          timestamptz not null,
  responded_at      timestamptz
);
-- One live request per application; the daily per-member cap is enforced
-- in create_application (0008) against this index.
create unique index uq_vouch_request_active on vouch_requests (application_id)
  where status = 'pending';
create index idx_vouch_requests_voucher on vouch_requests (voucher_user_id, status, created_at desc);
create index idx_vouch_requests_deadline on vouch_requests (deadline) where status = 'pending';

create or replace function touch_admission_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger trg_admission_touch
  before update on admission_applications
  for each row execute function touch_admission_updated_at();
