-- ============================================================
-- 0007 — E2E-readiness placeholders (deliberately empty in Phase 1).
--
-- These two tables are created now, unpopulated, per the locked
-- E2E-readiness decision #3: when end-to-end encrypted DMs ship in a
-- later phase they are populated by the device-registration flow — no
-- migration, no rewrite. They are NOT dead code; do not remove them.
-- ============================================================
set search_path = public, extensions;

create table user_devices (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references profiles (user_id) on delete cascade,
  device_name       text,
  identity_key_pub  bytea,
  signed_prekey_pub bytea,
  signed_prekey_sig bytea,
  created_at        timestamptz not null default now(),
  revoked_at        timestamptz
);
create index idx_user_devices_user on user_devices (user_id) where revoked_at is null;

create table one_time_prekeys (
  id          bigint generated always as identity primary key,
  device_id   uuid not null references user_devices (id) on delete cascade,
  prekey_pub  bytea not null,
  consumed_at timestamptz
);
create index idx_prekeys_device on one_time_prekeys (device_id) where consumed_at is null;
