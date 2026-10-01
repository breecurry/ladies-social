-- ============================================================
-- 0002 — Identity: public profiles + private PII, split hard.
--
-- THE REAL-NAME RULE (locked decision): the legal name is collected
-- and verified but NOT publicly displayed by default. It lives in
-- user_private (self + Owner RLS only). profiles.display_name is the
-- ONLY public name surface and may hold nothing (handle shows) or the
-- member's own verified legal name (opt-in) — enforced by trigger, so
-- no API bug can display anything else.
-- ============================================================
set search_path = public, extensions;

create table profiles (
  user_id          uuid primary key references auth.users (id) on delete restrict,
  handle           citext not null unique,
  -- Opt-in public name. NULL = show the @handle only (the default).
  display_name     text,
  bio              text check (char_length(bio) <= 300),
  avatar_media_key text, -- R2 key, served via Cloudflare (media ships Phase 3)
  trust_level      trust_level not null default 'pending_vouch',
  founding_member  boolean not null default false, -- badge only, zero privileges
  is_system        boolean not null default false, -- the "United Feminist" account
  status           account_status not null default 'active',
  status_expires_at timestamptz,
  -- Accountability chain: the member whose confirmed vouch covered this
  -- account, whether or not that vouch auto-admitted.
  vouched_by       uuid references profiles (user_id),
  search_indexable boolean not null default false, -- opt-IN to search engines
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  -- citext regex is case-insensitive; cast to text so the charset rule is exact
  constraint handle_format check ((handle::text) ~ '^[a-z0-9_]{3,30}$'),
  constraint display_name_length check (display_name is null or char_length(display_name) between 1 and 60)
);
create index idx_profiles_handle_trgm on profiles using gin (handle gin_trgm_ops);

-- Private PII. RLS: the subject and the Owner only. Admins and
-- moderators can NEVER read this table (roles matrix).
create table user_private (
  user_id                 uuid primary key references profiles (user_id) on delete cascade,
  legal_name              text not null check (char_length(legal_name) between 1 and 100),
  dob                     date not null check (dob > date '1900-01-01'),
  email                   citext not null, -- triage/review copy; auth.users is authoritative
  phone_e164              text check (phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  phone_verified_at       timestamptz,
  age_attested_at         timestamptz not null default now(), -- 18+ legal attestation
  device_fingerprint_hash bytea, -- HMAC(pepper, client fingerprint); never the raw value
  signup_ip               inet,
  last_login_ip           inet,
  last_login_at           timestamptz
);
-- NOTE: phone_e164 is deliberately NOT unique here. A duplicate phone at
-- signup must not error (error shape/timing would leak that the number
-- belongs to an account). It is recorded as a triage flag instead, and
-- one-number-one-account is enforced at ADMISSION time (0008).
create index idx_user_private_phone on user_private (phone_e164);

-- Ban-evasion blocklist: HMAC hashes only, never raw identifiers.
create table banned_identifiers (
  id             bigint generated always as identity primary key,
  kind           text not null check (kind in ('email_hash', 'phone_hash', 'device_hash')),
  value_hash     bytea not null,
  source_user_id uuid references profiles (user_id),
  reason         text,
  created_at     timestamptz not null default now(),
  unique (kind, value_hash)
);

-- Every signup attempt, successful or not — feeds the velocity and
-- IP-clustering triage signals and the per-IP rate limit.
create table signup_attempts (
  id         bigint generated always as identity primary key,
  ip         inet,
  email_hash bytea,
  created_at timestamptz not null default now()
);
create index idx_signup_attempts_time on signup_attempts (created_at desc);

-- Tunable knobs, readable only by server-side code and SECURITY DEFINER
-- functions. Changing a limit is an UPDATE, not a deploy.
create table app_config (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);
insert into app_config (key, value) values
  ('vouch_requests_per_member_per_day', '5'::jsonb),
  ('signup_attempts_per_ip_per_day',    '10'::jsonb),
  ('vouch_deadline_hours',              '48'::jsonb);

-- ------------------------------------------------------------
-- display_name may only ever be NULL or the member's own verified
-- legal name. Enforced below the app layer: even a compromised
-- endpoint cannot put a fabricated name on a public profile.
-- ------------------------------------------------------------
create or replace function enforce_display_name_is_legal_name() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if new.display_name is not null then
    if new.is_system then
      return new; -- the system account's display name is set at bootstrap
    end if;
    if not exists (
      select 1 from user_private up
      where up.user_id = new.user_id and up.legal_name = new.display_name
    ) then
      raise exception 'display_name must be empty or exactly the verified legal name';
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;

create trigger trg_profiles_display_name
  before insert or update on profiles
  for each row execute function enforce_display_name_is_legal_name();
