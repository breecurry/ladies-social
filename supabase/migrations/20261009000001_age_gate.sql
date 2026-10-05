-- ============================================================
-- 0017 — The age gate: 14-day device soft block + data minimisation.
--
-- Implements the storage side of spec §17 (docs/design-phase2-social-
-- core.md) and the decided age-assurance mechanism (docs/decisions/
-- age-assurance.md): self-attestation at signup, under-18 rejected,
-- and a 14-day, time-limited soft block on the device that failed.
--
-- WHAT A BLOCK RECORD MAY CONTAIN — THIS IS THE HARD CONSTRAINT
-- (§17.3/§17.4): a hashed device fingerprint, a timestamp, an expiry,
-- and a short human-readable reference code. NOTHING ELSE. No email,
-- no name, no date of birth, no IP. The moment a visitor self-declares
-- under 13 the platform has actual knowledge under COPPA; the gate
-- therefore takes in a date and gives back a yes, a no, or a wait —
-- it never takes in a person. A future migration must not add columns
-- to this table that identify anyone.
--
-- DATA MINIMISATION (the second half of this migration):
-- user_private.dob is DROPPED. The 18+ check still runs — in the
-- signup route, and in create_member()/bootstrap_owner(), which keep
-- their p_dob parameter for validation — but the raw date of birth is
-- no longer retained anywhere. user_private.age_attested_at (0002)
-- remains as the derived record: this account passed the 18+ gate at
-- that moment. Retaining the raw date added nothing the platform uses,
-- and Tennessee Public Chapter 899 — the statute the decision record
-- exists for — prohibits retaining the personally identifying
-- information used to verify age. Members here are hiding from
-- specific people; a birthdate is doxxing material.
--
-- The soft block is deliberately NOT permanent: shared family devices
-- and simple typos must not lock real adults out forever, and a
-- determined minor just opens another browser, so permanence buys
-- nothing and costs real people. The reference code is how a person
-- identifies her own device to support (nobody can read her own
-- fingerprint hash); support clears exactly that one block. The unlock
-- is friction relief, not a security boundary — unlocking only lets a
-- device type a date again.
--
-- Forward-only and idempotent: safe against the live database
-- (0001-0016 applied) and safe to re-run.
-- ============================================================
set search_path = public, extensions;

-- ------------------------------------------------------------
-- 1. The block table. RLS enabled with NO policies and every app-role
--    privilege revoked: invisible and immutable to anon/authenticated/
--    service_role alike. The SECURITY DEFINER functions below are the
--    only path in or out.
-- ------------------------------------------------------------
create table if not exists age_gate_blocks (
  id               bigint generated always as identity primary key,
  -- HMAC(pepper, client fingerprint) — never the raw value. NULL when
  -- the failing device produced no fingerprint (the cookie still
  -- carries the block for that device).
  fingerprint_hash bytea,
  -- Short human-readable code, e.g. "4F2A". Unambiguous alphabet
  -- (no 0/O, 1/I/L). Displayed on the blocked screen, quoted to
  -- support, looked up by the Owner. Grows past 4 chars only if the
  -- active-block space ever gets crowded.
  reference_code   text not null unique
                     check (reference_code ~ '^[2-9A-HJKMNP-Z]{4,8}$'),
  created_at       timestamptz not null default now(),
  expires_at       timestamptz not null
);
create index if not exists idx_age_gate_blocks_fingerprint
  on age_gate_blocks (fingerprint_hash) where fingerprint_hash is not null;

alter table age_gate_blocks enable row level security;
revoke all on age_gate_blocks from anon, authenticated, service_role;

-- ------------------------------------------------------------
-- 2. Recording a block. Called by the signup/age-gate API routes
--    (service_role) when a date of birth under 18 is submitted.
--    Idempotent per device: a device with an active block keeps its
--    existing code and expiry (returning to the form and failing again
--    does not restart the clock — 14 days means 14 days). Expired rows
--    are pruned opportunistically so nothing lingers past its use.
-- ------------------------------------------------------------
create or replace function record_age_gate_block(p_fingerprint_hash bytea)
returns table (reference_code text, expires_at timestamptz)
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  v_code    text;
  v_expires timestamptz;
  v_len     int := 4;
  v_tries   int := 0;
  v_i       int;
begin
  delete from age_gate_blocks b where b.expires_at <= now();

  if p_fingerprint_hash is not null then
    select b.reference_code, b.expires_at into v_code, v_expires
    from age_gate_blocks b
    where b.fingerprint_hash = p_fingerprint_hash and b.expires_at > now()
    order by b.expires_at desc
    limit 1;
    if found then
      return query select v_code, v_expires;
      return;
    end if;
  end if;

  loop
    v_code := '';
    for v_i in 1..v_len loop
      v_code := v_code
        || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;
    begin
      insert into age_gate_blocks (fingerprint_hash, reference_code, expires_at)
      values (p_fingerprint_hash, v_code, now() + interval '14 days')
      returning age_gate_blocks.expires_at into v_expires;
      exit;
    exception when unique_violation then
      v_tries := v_tries + 1;
      if v_tries >= 5 then
        v_len := least(v_len + 1, 8);
        v_tries := 0;
      end if;
    end;
  end loop;

  -- Audited by code only — the audit trail must hold no more about the
  -- turned-away visitor than the block row itself does.
  perform append_audit('age_gate.block', 'age_gate_block', v_code);
  return query select v_code, v_expires;
end $$;

revoke execute on function record_age_gate_block(bytea) from public, anon, authenticated;
grant execute on function record_age_gate_block(bytea) to service_role;

-- ------------------------------------------------------------
-- 3. Reading a block. Called by the API routes (service_role) to
--    decide whether a device meets the blocked screen instead of the
--    signup form: by fingerprint hash (submit-time check) or by the
--    reference code carried in the device cookie (page-load check).
--    Returns nothing when there is no active block.
-- ------------------------------------------------------------
create or replace function get_age_gate_block(p_fingerprint_hash bytea, p_code text)
returns table (reference_code text, expires_at timestamptz)
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  delete from age_gate_blocks b where b.expires_at <= now();
  return query
    select b.reference_code, b.expires_at
    from age_gate_blocks b
    where b.expires_at > now()
      and ((p_fingerprint_hash is not null and b.fingerprint_hash = p_fingerprint_hash)
        or (p_code is not null and b.reference_code = upper(btrim(p_code))))
    order by b.expires_at desc
    limit 1;
end $$;

revoke execute on function get_age_gate_block(bytea, text) from public, anon, authenticated;
grant execute on function get_age_gate_block(bytea, text) to service_role;

-- ------------------------------------------------------------
-- 4. Support lookup + unlock, Owner only (checked inside; EXECUTE is
--    granted to authenticated because the Owner calls these from her
--    own session). Pull, not push: nobody is notified of a block; the
--    Owner consults this only when someone emails support and quotes
--    her code. No AAL2 demand — deliberately. The unlock is friction
--    relief, not a security boundary: clearing a block only lets a
--    device type a date again, which a different browser could already
--    do. The lookup reveals nothing personal because nothing personal
--    exists to reveal.
-- ------------------------------------------------------------
create or replace function lookup_age_gate_block(p_code text)
returns table (reference_code text, created_at timestamptz, expires_at timestamptz)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if not is_owner() then
    raise exception 'Only the Owner may perform this action.';
  end if;
  return query
    select b.reference_code, b.created_at, b.expires_at
    from age_gate_blocks b
    where b.reference_code = upper(btrim(p_code));
end $$;

create or replace function clear_age_gate_block(p_code text)
returns boolean
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_code text;
begin
  if not is_owner() then
    raise exception 'Only the Owner may perform this action.';
  end if;
  delete from age_gate_blocks b
  where b.reference_code = upper(btrim(p_code))
  returning b.reference_code into v_code;
  if v_code is null then
    return false;
  end if;
  perform append_audit('age_gate.unblock', 'age_gate_block', v_code);
  return true;
end $$;

revoke execute on function lookup_age_gate_block(text) from public, anon;
revoke execute on function clear_age_gate_block(text) from public, anon;
grant execute on function lookup_age_gate_block(text) to authenticated;
grant execute on function clear_age_gate_block(text) to authenticated;

-- ------------------------------------------------------------
-- 5. Stop retaining the raw date of birth. Same signatures (callers
--    unchanged; the 18+ validation stays exactly where it was), same
--    SECURITY DEFINER + pinned search_path, same guards and audit
--    calls; existing EXECUTE grants are preserved by REPLACE. The only
--    change: dob is validated, never written.
-- ------------------------------------------------------------
create or replace function create_member(
  p_user_id          uuid,
  p_email            citext,
  p_legal_name       text,
  p_dob              date,
  p_handle           citext,
  p_signup_ip        inet,
  p_email_hash       bytea,
  p_fingerprint_hash bytea,
  p_signals          jsonb default '{}'::jsonb,
  p_flagged          boolean default false
) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if p_dob > (current_date - interval '18 years') then
    raise exception 'Members must be 18 or older.';
  end if;

  if (p_email_hash is not null and identifier_is_banned('email_hash', p_email_hash))
     or (p_fingerprint_hash is not null and identifier_is_banned('device_hash', p_fingerprint_hash)) then
    raise exception 'banned_identifier';
  end if;

  insert into profiles (user_id, handle, trust_level)
  values (p_user_id, p_handle, 'member');

  -- age_attested_at (default now()) is the retained record of passing
  -- the 18+ gate; the date of birth itself is not stored.
  insert into user_private (user_id, legal_name, email,
                            device_fingerprint_hash, signup_ip, signup_flags)
  values (p_user_id, p_legal_name, p_email,
          p_fingerprint_hash, p_signup_ip,
          case when p_flagged then coalesce(p_signals, '{}'::jsonb) end);

  perform append_audit('member.signup', 'user', p_user_id::text,
                       jsonb_build_object('flagged', p_flagged,
                                          'signals', coalesce(p_signals, '{}'::jsonb)));
end $$;

create or replace function bootstrap_owner(
  p_user       uuid,
  p_handle     citext,
  p_legal_name text,
  p_dob        date,
  p_email      citext,
  p_phone      text default null
) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if exists (select 1 from role_assignments where role = 'owner' and revoked_at is null) then
    raise exception 'An Owner already exists; the owner role cannot be granted again.';
  end if;
  if p_dob > (current_date - interval '18 years') then
    raise exception 'The Owner must be 18 or older.';
  end if;
  insert into profiles (user_id, handle, trust_level, status)
  values (p_user, p_handle, 'established', 'active');
  insert into user_private (user_id, legal_name, email, phone_e164)
  values (p_user, p_legal_name, p_email, nullif(p_phone, ''));
  perform set_config('uf.allow_owner_bootstrap', 'on', true); -- transaction-local
  insert into role_assignments (user_id, role, granted_by) values (p_user, 'owner', p_user);
  perform set_config('uf.allow_owner_bootstrap', '', true);
  perform append_audit('owner.bootstrap', 'user', p_user::text);
end $$;

-- The drop comes AFTER the functions stop referencing the column, so
-- a re-run (or a fresh apply) never has a window where a function
-- body names a column that does not exist.
alter table user_private drop column if exists dob;
