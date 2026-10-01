-- ============================================================
-- 0004 — Immutable, hash-chained audit log.
--
-- Append-only BY CONSTRUCTION:
--   * No UPDATE or DELETE RLS policy exists at all.
--   * UPDATE/DELETE privileges are REVOKEd from every application
--     role INCLUDING service_role (0009), and belt-and-braces
--     triggers below reject them even if a privilege ever reappears.
--   * Rows are hash-chained: row_hash = SHA-256(fields || prev_hash),
--     so altering or removing any row breaks every subsequent hash —
--     verify_audit_chain() detects it.
-- Readable by the Owner only, with AAL2 step-up (policy in 0009).
-- ============================================================
set search_path = public, extensions;

create table audit_log (
  seq          bigint generated always as identity primary key,
  occurred_at  timestamptz not null default now(),
  actor_id     uuid,                 -- null = system/automated actor
  actor_role   text not null,        -- role AT THE TIME of the action
  action       text not null,        -- e.g. 'role.grant', 'admission.approve'
  target_type  text,
  target_id    text,
  before_state jsonb,
  after_state  jsonb,
  detail       jsonb not null default '{}'::jsonb,
  ip           inet,
  session_id   text,                 -- Supabase session id claim
  prev_hash    bytea not null,
  row_hash     bytea not null
);

create or replace function audit_hash_chain() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  last_hash bytea;
begin
  select row_hash into last_hash from audit_log order by seq desc limit 1;
  new.prev_hash := coalesce(last_hash, '\x00'::bytea);
  new.row_hash := extensions.digest(
    convert_to(
      coalesce(new.actor_id::text, '') || '|' ||
      new.actor_role                   || '|' ||
      new.action                       || '|' ||
      coalesce(new.target_type, '')    || '|' ||
      coalesce(new.target_id, '')      || '|' ||
      coalesce(new.before_state::text, '') || '|' ||
      coalesce(new.after_state::text, '')  || '|' ||
      new.detail::text                 || '|' ||
      coalesce(new.session_id, '')     || '|' ||
      new.occurred_at::text            || '|' ||
      encode(new.prev_hash, 'hex'),
      'UTF8'),
    'sha256');
  return new;
end $$;

create trigger trg_audit_chain
  before insert on audit_log
  for each row execute function audit_hash_chain();

-- Belt and braces: even a role that somehow regains the privilege
-- cannot update or delete (forbid_delete() defined in 0003).
create or replace function forbid_update() returns trigger
language plpgsql as $$
begin
  raise exception 'Rows in %.% are immutable.', tg_table_schema, tg_table_name;
end $$;

create trigger trg_audit_no_update before update on audit_log
  for each row execute function forbid_update();
create trigger trg_audit_no_delete before delete on audit_log
  for each row execute function forbid_delete();

-- The ONLY write path. Callable solely from within other SECURITY
-- DEFINER functions (EXECUTE is revoked from all app roles in 0009).
create or replace function append_audit(
  p_action      text,
  p_target_type text,
  p_target_id   text,
  p_detail      jsonb default '{}'::jsonb,
  p_before      jsonb default null,
  p_after       jsonb default null
) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  insert into audit_log (actor_id, actor_role, action, target_type, target_id,
                         before_state, after_state, detail, session_id)
  values (
    auth.uid(),
    case when auth.uid() is null then 'system' else actor_role_name(auth.uid()) end,
    p_action, p_target_type, p_target_id,
    p_before, p_after, coalesce(p_detail, '{}'::jsonb),
    nullif(coalesce(auth.jwt() ->> 'session_id', ''), '')
  );
end $$;

-- Owner-only chain verification: walks the whole chain and reports the
-- first sequence number at which it breaks, if any.
create or replace function verify_audit_chain()
returns table (ok boolean, checked_rows bigint, broken_at_seq bigint)
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  r          record;
  expect_prev bytea := '\x00'::bytea;
  computed   bytea;
  n          bigint := 0;
begin
  if not is_owner() then
    raise exception 'Only the Owner may verify the audit chain.';
  end if;
  for r in select * from audit_log order by seq loop
    n := n + 1;
    if r.prev_hash <> expect_prev then
      return query select false, n, r.seq; return;
    end if;
    computed := extensions.digest(
      convert_to(
        coalesce(r.actor_id::text, '') || '|' ||
        r.actor_role                   || '|' ||
        r.action                       || '|' ||
        coalesce(r.target_type, '')    || '|' ||
        coalesce(r.target_id, '')      || '|' ||
        coalesce(r.before_state::text, '') || '|' ||
        coalesce(r.after_state::text, '')  || '|' ||
        r.detail::text                 || '|' ||
        coalesce(r.session_id, '')     || '|' ||
        r.occurred_at::text            || '|' ||
        encode(r.prev_hash, 'hex'),
        'UTF8'),
      'sha256');
    if computed <> r.row_hash then
      return query select false, n, r.seq; return;
    end if;
    expect_prev := r.row_hash;
  end loop;
  return query select true, n, null::bigint;
end $$;
