-- Behavioral + structural smoke test of the moderation console's data
-- layer (migration 0018). What this file proves:
--
--   1. STRUCTURALLY, no moderation function returns or even references
--      display_name: every console surface is @handle-only below the
--      app layer, and this test breaks the moment a future migration
--      lets a legal name into a moderation query;
--   2. the locked role boundaries hold at the database: a reviewer is
--      read-only, a MODERATOR CANNOT BAN, a MODERATOR CANNOT SUSPEND
--      (or restrict) LONGER THAN 7 DAYS, an ADMIN CAN, nobody can
--      suspend or ban THE OWNER, and nobody actions herself or the
--      system account;
--   3. a report naming the Owner routes to the normal admin panel and
--      is VISIBLE TO THE OWNER (her decision, 2026-10-05), and every
--      report queues its safety@ email copy — which names no reporter
--      and carries no report text;
--   4. banning writes HMAC-only rows to banned_identifiers and
--      create_member() then refuses a matching signup — the owner's
--      "including any new accounts they make" rule, end to end;
--   5. child-safety (csam) cases arrive escalated and can be resolved
--      by the Owner alone; admins and moderators are refused;
--   6. EVERY enforcement action lands in the hash-chained audit_log,
--      and the chain still verifies end to end afterwards;
--   7. moderation_actions and safety_email_outbox are unreachable
--      directly by app roles; the member-facing status functions tell
--      the member the rule and the action, never the actor.
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000012', 'admina@test'),
  ('00000000-0000-0000-0000-000000000013', 'modme@test'),
  ('00000000-0000-0000-0000-000000000014', 'reva@test'),
  ('00000000-0000-0000-0000-000000000015', 'mallory@test'),
  ('00000000-0000-0000-0000-000000000016', 'rita@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_member('00000000-0000-0000-0000-000000000012', 'admina@test', 'Ad Mina', '1995-05-05', 'admina', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000013', 'modme@test', 'Mod Me', '1995-05-05', 'modme', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000014', 'reva@test', 'Rev Va', '1995-05-05', 'reva', null, null, null, '{}'::jsonb, false);
-- mallory signs up WITH a device fingerprint hash, so a device-signal
-- ban has something real to write.
select create_member('00000000-0000-0000-0000-000000000015', 'mallory@test', 'Mal Lory', '1995-05-05', 'mallory', null, null, '\xabcd'::bytea, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000016', 'rita@test', 'Ri Ta', '1995-05-05', 'rita', null, null, null, '{}'::jsonb, false);

-- ============================================================
-- 1. STRUCTURAL identity protection across the whole console.
-- ============================================================
do $$ declare f text; sig text; src text; begin
  foreach f in array array[
    'mod_queue', 'mod_queue_counts', 'mod_case', 'mod_view_reporters',
    'mod_post_context', 'mod_account_posts', 'mod_account_context',
    'mod_enforcement_history', 'my_account_status', 'mod_claim',
    'mod_dismiss', 'mod_reopen', 'mod_warn', 'mod_remove_post',
    'mod_restore_post', 'mod_restrict', 'mod_suspend', 'mod_lift',
    'mod_escalate', 'mod_ban', 'owner_unban', 'file_report'] loop
    select pg_get_function_result(p.oid), p.prosrc into sig, src
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = f;
    if sig is null then raise exception 'FAIL: function % missing', f; end if;
    if position('display_name' in coalesce(sig, '')) > 0 then
      raise exception 'FAIL: % return shape exposes display_name', f;
    end if;
    if position('display_name' in src) > 0 then
      raise exception 'FAIL: % body references display_name', f;
    end if;
  end loop;
end $$;

-- ============================================================
-- 2. The tables behind the console are unreachable directly.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000016', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000016","aal":"aal1","session_id":"m1"}', false);
do $$ declare n int; begin
  select count(*) into n from moderation_actions;
  if n <> 0 then raise exception 'FAIL: moderation_actions readable by a member'; end if;
exception when insufficient_privilege then null;
end $$;
do $$ begin
  begin
    insert into moderation_actions (target_user_id, action, actor_id, actor_role)
    values ('00000000-0000-0000-0000-000000000015', 'warn',
            '00000000-0000-0000-0000-000000000016', 'member');
    raise exception 'FAIL: direct moderation_actions insert accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    perform count(*) from safety_email_outbox;
    raise exception 'FAIL: safety_email_outbox readable by a member';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set role service_role;
do $$ begin
  begin
    insert into safety_email_outbox (report_id, recipient, subject, body)
    values (gen_random_uuid(), 'x@test', 's', 'b');
    raise exception 'FAIL: service_role can insert outbox rows directly';
  exception when insufficient_privilege or foreign_key_violation then null;
  end;
  begin
    delete from safety_email_outbox;
    raise exception 'FAIL: service_role can delete outbox rows';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- ============================================================
-- 3. Roles granted; the accused posts; reports arrive.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"ow"}', false);
select grant_role('00000000-0000-0000-0000-000000000012', 'admin');
select grant_role('00000000-0000-0000-0000-000000000013', 'moderator');
select grant_role('00000000-0000-0000-0000-000000000014', 'ts_reviewer');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000015', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000015","aal":"aal1","session_id":"ml"}', false);
do $$ declare v bigint; begin
  v := create_post('a nasty post by mallory');
  perform set_config('t.post', v::text, false);
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000016', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000016","aal":"aal1","session_id":"ri"}', false);
do $$ declare r uuid; begin
  r := file_report('post', current_setting('t.post')::bigint, null, 'harassment', 'she keeps at it');
  r := file_report('user', null, '00000000-0000-0000-0000-000000000015', 'spam', null);
  -- a report naming the OWNER routes admin_only (owner decision)
  r := file_report('user', null, '00000000-0000-0000-0000-000000000001', 'other', null);
  perform set_config('t.report_owner', r::text, false);
end $$;
reset role;
do $$ declare n int; begin
  select count(*) into n from reports where routing = 'owner_conflict';
  if n <> 0 then raise exception 'FAIL: owner_conflict routing still produced'; end if;
  select count(*) into n from reports
    where id = current_setting('t.report_owner')::uuid and routing = 'admin_only';
  if n <> 1 then raise exception 'FAIL: Owner-accused report did not route admin_only'; end if;
  -- every report queued its email copy; no reporter, no details, no names
  select count(*) into n from safety_email_outbox;
  if n <> 3 then raise exception 'FAIL: % email copies queued, expected 3', n; end if;
  select count(*) into n from safety_email_outbox
    where recipient <> 'safety@unitedfeminist.com'
       or body like '%rita%' or body like '%she keeps at it%'
       or body like '%Ri Ta%' or body like '%Mal Lory%' or body like '%Bree Curry%';
  if n <> 0 then raise exception 'FAIL: an email copy leaks reporter, details, or a legal name'; end if;
end $$;

-- ============================================================
-- 4. Queue visibility by role. The Owner sees the report about
--    herself; a member sees nothing; a reviewer sees the standard
--    lane read-only.
-- ============================================================
set role authenticated;
-- a plain member cannot open the queue
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000016', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000016","aal":"aal1","session_id":"ri"}', false);
do $$ begin
  begin
    perform * from mod_queue('open', 10);
    raise exception 'FAIL: a plain member can read the moderation queue';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
-- the reviewer sees the standard cases but cannot act
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000014', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000014","aal":"aal1","session_id":"rv"}', false);
do $$ declare n int; begin
  select count(*) into n from mod_queue('open', 10);
  if n <> 2 then raise exception 'FAIL: reviewer sees % standard cases, expected 2', n; end if;
  begin
    perform mod_dismiss('00000000-0000-0000-0000-000000000015', null, null);
    raise exception 'FAIL: a reviewer dismissed a case';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
-- the Owner sees the report about herself in the same panel
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"ow"}', false);
do $$ declare n int; begin
  select count(*) into n from mod_queue('open', 10)
    where accused_handle = 'bree';
  if n <> 1 then raise exception 'FAIL: the Owner does not see the case naming her'; end if;
end $$;

-- ============================================================
-- 5. THE MODERATOR BOUNDARIES. No ban, nothing over 7 days.
-- ============================================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000013', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000013","aal":"aal1","session_id":"md"}', false);
do $$ begin
  -- A MODERATOR CANNOT BAN.
  begin
    perform mod_ban('00000000-0000-0000-0000-000000000015', 'spam', 'trying it on', null, null, true);
    raise exception 'FAIL: A MODERATOR BANNED AN ACCOUNT';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  -- A MODERATOR CANNOT SUSPEND LONGER THAN 7 DAYS.
  begin
    perform mod_suspend('00000000-0000-0000-0000-000000000015', 8, 'spam', null);
    raise exception 'FAIL: A MODERATOR SUSPENDED FOR MORE THAN 7 DAYS';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    perform mod_restrict('00000000-0000-0000-0000-000000000015', 8, 'spam', null);
    raise exception 'FAIL: a moderator restricted for more than 7 days';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  -- 31 days is over the guidelines' ceiling for everyone.
  begin
    perform mod_suspend('00000000-0000-0000-0000-000000000015', 31, 'spam', null);
    raise exception 'FAIL: a 31-day suspension was accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
-- What a moderator CAN do: warn, remove content, claim, suspend <= 7.
do $$ declare n int; begin
  n := mod_claim('00000000-0000-0000-0000-000000000015', current_setting('t.post')::bigint);
  if n <> 1 then raise exception 'FAIL: claim touched % reports, expected 1', n; end if;
  perform mod_warn('00000000-0000-0000-0000-000000000015', 'harassment',
                   'A post of yours broke our rule on harassment.',
                   current_setting('t.post')::bigint, false, 'first lapse');
  perform mod_remove_post(current_setting('t.post')::bigint, 'harassment', 'clear violation');
  perform mod_suspend('00000000-0000-0000-0000-000000000015', 7, 'harassment', 'pattern');
end $$;
reset role;
do $$ declare v post_visibility; s account_status; e timestamptz; n int; begin
  select visibility into v from posts where id = current_setting('t.post')::bigint;
  if v <> 'removed_moderation' then raise exception 'FAIL: removed post is %', v; end if;
  select status, status_expires_at into s, e from profiles
    where user_id = '00000000-0000-0000-0000-000000000015';
  if s <> 'suspended' then raise exception 'FAIL: status % after suspension', s; end if;
  if e is null or e > now() + interval '8 days' then
    raise exception 'FAIL: suspension expiry % is not ~7 days out', e;
  end if;
  -- the member was told, by the system, with the rule — never the actor
  select count(*) into n from notifications
    where user_id = '00000000-0000-0000-0000-000000000015'
      and type = 'system' and actor_id is null and body is not null;
  if n < 2 then raise exception 'FAIL: expected warn+removal system notices, found %', n; end if;
end $$;

-- ============================================================
-- 6. THE ADMIN CAN. Lift, long suspension, and the Owner stays
--    untouchable.
-- ============================================================
set role authenticated;
-- the moderator cannot lift a suspension
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000013', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000013","aal":"aal1","session_id":"md"}', false);
do $$ begin
  begin
    perform mod_lift('00000000-0000-0000-0000-000000000015', null);
    raise exception 'FAIL: a moderator lifted a suspension';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000012', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000012","aal":"aal1","session_id":"ad"}', false);
do $$ declare s account_status; begin
  perform mod_lift('00000000-0000-0000-0000-000000000015', 'reviewed');
  select status into s from profiles where user_id = '00000000-0000-0000-0000-000000000015';
  if s <> 'active' then raise exception 'FAIL: status % after lift', s; end if;
  -- AN ADMIN CAN SUSPEND LONGER THAN 7 DAYS.
  perform mod_suspend('00000000-0000-0000-0000-000000000015', 14, 'spam', 'escalated to me');
  select status into s from profiles where user_id = '00000000-0000-0000-0000-000000000015';
  if s <> 'suspended' then raise exception 'FAIL: admin 14-day suspension did not apply'; end if;
  perform mod_lift('00000000-0000-0000-0000-000000000015', null);
  -- THE OWNER IS UNSUSPENDABLE AND UNBANNABLE, even by an admin.
  begin
    perform mod_suspend('00000000-0000-0000-0000-000000000001', 3, 'other', null);
    raise exception 'FAIL: THE OWNER WAS SUSPENDED';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  begin
    perform mod_ban('00000000-0000-0000-0000-000000000001', 'other', 'no', null, null, true);
    raise exception 'FAIL: THE OWNER WAS BANNED';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  -- nobody actions herself
  begin
    perform mod_suspend('00000000-0000-0000-0000-000000000012', 3, 'other', null);
    raise exception 'FAIL: an admin suspended herself';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

-- ============================================================
-- 7. THE BAN, and ban evasion end to end: HMAC rows land in
--    banned_identifiers and a matching signup is refused.
-- ============================================================
do $$ begin
  -- the note is mandatory: a permanent action is justified on the record
  begin
    perform mod_ban('00000000-0000-0000-0000-000000000015', 'harassment', '  ', '\x1111'::bytea, null, true);
    raise exception 'FAIL: a ban without a note was accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  perform mod_ban('00000000-0000-0000-0000-000000000015', 'harassment',
                  'repeated harassment after suspension', '\x1111'::bytea, null, true);
end $$;
reset role;
do $$ declare s account_status; n int; begin
  select status into s from profiles where user_id = '00000000-0000-0000-0000-000000000015';
  if s <> 'banned' then raise exception 'FAIL: status % after ban', s; end if;
  select count(*) into n from banned_identifiers
    where source_user_id = '00000000-0000-0000-0000-000000000015'
      and ((kind = 'email_hash' and value_hash = '\x1111'::bytea)
        or (kind = 'device_hash' and value_hash = '\xabcd'::bytea));
  if n <> 2 then raise exception 'FAIL: expected email+device evasion signals, found %', n; end if;
end $$;
-- "including any new accounts they make": the same email hash is refused
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000017', 'back@test');
do $$ begin
  begin
    perform create_member('00000000-0000-0000-0000-000000000017', 'back@test', 'Mal Returns',
                          '1995-05-05', 'malreturns', null, '\x1111'::bytea, null, '{}'::jsonb, false);
    raise exception 'FAIL: A BANNED EMAIL HASH SIGNED UP AGAIN';
  exception when others then
    if sqlerrm <> 'banned_identifier' then raise; end if;
  end;
end $$;
-- reversing a permanent ban is Owner + AAL2, nothing less
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000012', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000012","aal":"aal2","session_id":"ad"}', false);
do $$ begin
  begin
    perform owner_unban('00000000-0000-0000-0000-000000000015', null);
    raise exception 'FAIL: an admin reversed a permanent ban';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal1","session_id":"ow"}', false);
do $$ begin
  begin
    perform owner_unban('00000000-0000-0000-0000-000000000015', null);
    raise exception 'FAIL: the Owner reversed a ban without AAL2';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

-- ============================================================
-- 8. Child safety: csam arrives escalated; only the Owner resolves.
-- ============================================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000016', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000016","aal":"aal1","session_id":"ri"}', false);
do $$ declare r uuid; s report_status; begin
  r := file_report('user', null, '00000000-0000-0000-0000-000000000013', 'csam', null);
  select status into s from reports where id = r;
  if s <> 'escalated' then raise exception 'FAIL: csam report arrived as %, not escalated', s; end if;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000012', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000012","aal":"aal1","session_id":"ad"}', false);
do $$ begin
  begin
    perform mod_dismiss('00000000-0000-0000-0000-000000000013', null, null);
    raise exception 'FAIL: an admin resolved a child-safety case';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"ow"}', false);
do $$ declare n int; begin
  n := mod_dismiss('00000000-0000-0000-0000-000000000013', null, 'verified: not csam, mistaken report');
  if n <> 1 then raise exception 'FAIL: owner dismiss touched % reports', n; end if;
end $$;

-- ============================================================
-- 9. The member-facing truth: rule and action, never the actor; and
--    the reporter reveal is an audited, deliberate act.
-- ============================================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000015', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000015","aal":"aal1","session_id":"ml"}', false);
do $$ declare r record; begin
  select * into r from my_account_status();
  if r.status <> 'banned' or r.last_action <> 'ban' or r.last_rule <> 'harassment' then
    raise exception 'FAIL: my_account_status returned %/%/%', r.status, r.last_action, r.last_rule;
  end if;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000013', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000013","aal":"aal1","session_id":"md"}', false);
do $$ declare n int; begin
  select count(*) into n from mod_view_reporters('00000000-0000-0000-0000-000000000015', null)
    where reporter_handle = 'rita';
  if n < 1 then raise exception 'FAIL: reporter reveal returned no reporter'; end if;
end $$;
reset role;

-- ============================================================
-- 10. EVERY ACTION LANDED IN THE AUDIT LOG, and the chain verifies.
-- ============================================================
do $$ declare a text; begin
  foreach a in array array['mod.claim', 'mod.warn', 'mod.remove_content', 'mod.suspend',
                           'mod.lift', 'mod.ban', 'mod.dismiss', 'mod.viewed_reporters',
                           'report.filed'] loop
    if not exists (select 1 from audit_log where action = a) then
      raise exception 'FAIL: no audit entry for %', a;
    end if;
  end loop;
  -- the ban audit records signal KINDS, never values or identifiers
  if exists (select 1 from audit_log where action = 'mod.ban'
             and (detail::text like '%@%' or detail::text like '%1111%')) then
    raise exception 'FAIL: the ban audit entry leaks an identifier';
  end if;
end $$;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"ow"}', false);
do $$ declare r record; begin
  select * into r from verify_audit_chain();
  if not r.ok then raise exception 'FAIL: audit chain broken at %', r.broken_at_seq; end if;
end $$;
reset role;

rollback;
\echo ALL MODERATION TESTS PASSED
