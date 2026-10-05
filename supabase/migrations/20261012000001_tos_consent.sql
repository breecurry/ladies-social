-- ============================================================
-- 0019 — Terms of Service consent: what was agreed, when, which text.
--
-- The signup form requires a separate "I agree to the Terms of
-- Service" checkbox — independent of the 18+ attestation, because the
-- two assertions are different in kind and bundled consent is weaker.
-- The server route refuses any signup without it (signupSchema), so
-- the checkbox cannot be skipped by POSTing to the API directly.
--
-- This migration adds the durable record of that agreement. On a
-- successful signup the route calls record_tos_consent() with a
-- version identifier DERIVED from the document itself — its
-- "Last updated" date plus a content hash, computed at request time by
-- src/lib/legal.ts. It is never a hand-bumped constant, so it cannot
-- silently go stale: if the Terms text changes, new consents
-- automatically carry a new identifier, and it stays possible to tell
-- exactly which text each member accepted. While the Terms page still
-- shows the interim "being finalised with counsel" notice, the
-- identifier carries an "interim:" prefix; the prefix disappears by
-- itself the moment the document's `published` flag flips.
--
-- The columns live on user_private: the same privacy posture as the
-- rest of the per-member private data (RLS self + Owner only, no
-- direct app-role write privilege — the SECURITY DEFINER function
-- below is the only write path, exactly like create_member).
--
-- PRE-EXISTING ACCOUNTS: both columns are nullable and the accounts
-- that predate this checkbox keep NULL — the truthful record that no
-- Terms consent was captured at their creation (the Terms were not yet
-- published and no checkbox existed). Nothing gates sign-in on these
-- columns; nobody is locked out and no re-consent interruption exists.
--
-- Forward-only and idempotent: safe against the live database
-- (0001-0018 applied, with live rows in user_private) and safe to
-- re-run.
-- ============================================================
set search_path = public, extensions;

alter table user_private
  add column if not exists tos_agreed_at timestamptz,
  add column if not exists tos_version   text
    constraint tos_version_length
    check (tos_version is null or char_length(tos_version) between 1 and 200);

comment on column user_private.tos_agreed_at is
  'When the member agreed to the Terms of Service at signup. NULL on accounts that predate the consent checkbox.';
comment on column user_private.tos_version is
  'Identifier of the exact Terms text agreed to, derived from the document (last-updated date + content hash) by src/lib/legal.ts — never hand-maintained.';

-- ------------------------------------------------------------
-- The only write path for the consent record. Called by the signup
-- route (service_role) immediately after create_member() succeeds.
-- Returns false when no such member exists (nothing to record);
-- raises on a missing version so a bug upstream cannot quietly write
-- an unattributable consent.
-- ------------------------------------------------------------
create or replace function record_tos_consent(p_user_id uuid, p_version text)
returns boolean
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if p_user_id is null then
    raise exception 'record_tos_consent: a member id is required';
  end if;
  if p_version is null or btrim(p_version) = '' then
    raise exception 'record_tos_consent: a document version is required';
  end if;

  update user_private
     set tos_agreed_at = now(),
         tos_version   = btrim(p_version)
   where user_id = p_user_id;
  if not found then
    return false;
  end if;

  perform append_audit('member.tos_consent', 'user', p_user_id::text,
                       jsonb_build_object('version', btrim(p_version)));
  return true;
end $$;

revoke execute on function record_tos_consent(uuid, text) from public, anon, authenticated;
grant execute on function record_tos_consent(uuid, text) to service_role;
