-- ============================================================
-- 20261019000001 — Identity-reveal gate: AAL2 OR a fresh passkey.
--
-- WHY. Passkey sign-in is live, but a passkey session is aal1 — the
-- auth service does not raise the assurance level for passkeys. The
-- Owner prefers a passkey over an authenticator app, so the audited
-- identity reveal (owner_reveal_identity, 0022 §5) now accepts EITHER:
--
--   (a) aal2 — the existing TOTP step-up, unchanged; OR
--   (b) a FRESH passkey authentication: the JWT's `amr` claim holds an
--       entry whose method is 'passkey' and whose timestamp is within
--       5 MINUTES of now. Keep this window in step with
--       PASSKEY_FRESHNESS_SECONDS in src/lib/passkeys.ts.
--
-- HOW `amr` WORKS (the bug this comment exists to prevent):
--   * `amr` is an ARRAY OF OBJECTS — [{ "method": ..., "timestamp":
--     epoch-seconds }]. A containment test against the string
--     'passkey' silently never matches; read `method` per element.
--   * `timestamp` is the AUTHENTICATION time and SURVIVES token
--     refreshes, which is what makes the freshness check meaningful.
--     To refresh it the Owner re-runs the passkey ceremony (the
--     interface offers exactly that when the gate finds it stale).
--   * Everything is read server-side from auth.jwt(); the client
--     check in IdentityPanel is only the polite front of this gate.
--
-- SCOPE — deliberately narrow. ONLY owner_reveal_identity moves to the
-- combined gate. Every other AAL2 requirement is UNCHANGED and must
-- stay that way without an explicit Owner decision: grant_role /
-- revoke_role / grant_privilege / revoke_privilege (0005), owner_unban
-- (0018), and the RLS policies user_private_owner and audit_owner_read
-- (0009). A passkey therefore still cannot change roles or read the
-- raw audit log and private tables.
--
-- AUDIT. The identity.reveal entry is unchanged in shape and still
-- written BEFORE any data is returned; its detail now also records
-- which method satisfied the gate ('auth_method': 'aal2'|'passkey').
-- ============================================================
set search_path = public, extensions;

-- Which method, if any, currently satisfies the sensitive-action gate.
-- Returns 'aal2', 'passkey', or null. Fails closed: a missing or
-- malformed amr claim simply yields null.
create or replace function owner_sensitive_auth_method() returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_entry jsonb;
  v_ts    text;
begin
  if coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2' then
    return 'aal2';
  end if;
  if jsonb_typeof(auth.jwt() -> 'amr') = 'array' then
    for v_entry in select jsonb_array_elements(auth.jwt() -> 'amr') loop
      -- Objects of shape { method, timestamp }; never match the array
      -- against a bare string.
      if jsonb_typeof(v_entry) = 'object' and v_entry ->> 'method' = 'passkey' then
        v_ts := v_entry ->> 'timestamp';
        if v_ts ~ '^\d{1,12}$'
           and to_timestamp(v_ts::bigint) > now() - interval '5 minutes' then
          return 'passkey';
        end if;
      end if;
    end loop;
  end if;
  return null;
end $$;

-- Companion to require_owner_aal2() (0005) for the one action that
-- accepts a fresh passkey. Raises unless the caller is the Owner with
-- a satisfying method; returns the method so the caller can audit it.
create or replace function require_owner_sensitive_auth() returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_method text;
begin
  if not is_owner() then
    raise exception 'Only the Owner may perform this action.';
  end if;
  v_method := owner_sensitive_auth_method();
  if v_method is null then
    raise exception 'Fresh verification is required: step up with your authenticator app or confirm with your passkey.';
  end if;
  return v_method;
end $$;

-- The identity reveal (0022 §5), identical except for the gate and the
-- audit detail gaining auth_method. Owner-only, mandatory reason, and
-- the audit entry still precedes the read.
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
  v_method text;
begin
  v_method := require_owner_sensitive_auth();
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
                                          'reason', left(trim(p_reason), 500),
                                          'auth_method', v_method));

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

-- Internal helpers: callable only from within SECURITY DEFINER bodies,
-- like require_owner_aal2() (0009 pattern). owner_reveal_identity's
-- existing grants are preserved by CREATE OR REPLACE.
revoke execute on function owner_sensitive_auth_method() from public, anon, authenticated, service_role;
revoke execute on function require_owner_sensitive_auth() from public, anon, authenticated, service_role;
