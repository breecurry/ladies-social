-- Behavioral + structural smoke test for migration 0023 (avatars):
-- the opaque-key avatar pipeline's database half. Local only, like
-- suites 01-11.
--
-- The headline security properties:
--   - the avatar key resolver is MUTUAL-HARD on blocks: a block in
--     EITHER direction means the real object key reaches neither
--     party (the POSTS semantics, blocked_either — never the one-way
--     profiles_read semantics);
--   - a logged-out or non-member context resolves nothing;
--   - suspended / banned / deactivated owners resolve to nothing
--     (letter placeholder everywhere);
--   - a report freezes the specific avatar object as evidence, and
--     nothing under a hold is ever purgeable;
--   - moderation removal PRESERVES the object (never hard-deletes)
--     and is reversible;
--   - members cannot write profiles.avatar_media_key directly;
--   - no avatar function references display_name, and there is no
--     filename column anywhere in the feature.
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@test'),
  ('00000000-0000-0000-0000-000000000003', 'ada@test'),
  ('00000000-0000-0000-0000-000000000004', 'bea@test'),
  ('00000000-0000-0000-0000-000000000005', 'cat@test'),
  ('00000000-0000-0000-0000-000000000006', 'dee@test'),
  ('00000000-0000-0000-0000-000000000007', 'system@test');

select bootstrap_owner('00000000-0000-0000-0000-000000000001', 'bree', 'Bree Curry', '1990-01-01', 'owner@test', null);
select create_system_account('00000000-0000-0000-0000-000000000007', 'hersciety');
select create_member('00000000-0000-0000-0000-000000000003', 'ada@test', 'Ada Lovelace', '1995-05-05', 'ada', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000004', 'bea@test', 'Bea Arthur',   '1995-05-05', 'bea', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000005', 'cat@test', 'Cat Stevens',  '1995-05-05', 'cat', null, null, null, '{}'::jsonb, false);
select create_member('00000000-0000-0000-0000-000000000006', 'dee@test', 'Dee Dee',      '1995-05-05', 'dee', null, null, null, '{}'::jsonb, false);

-- ============================================================
-- 1. STRUCTURAL: the avatar functions exist, none references or
--    returns display_name, EXECUTE is authenticated-only, and the
--    internal purge predicate is granted to nobody.
-- ============================================================
do $$ declare f text; sig text; src text; begin
  foreach f in array array[
    'avatar_ticket_create', 'avatar_ticket_consume', 'avatar_commit_record',
    'remove_avatar', 'avatar_mark_purged', 'avatar_keys', 'avatar_purgeable',
    'mod_remove_avatar', 'mod_reinstate_avatar', 'mod_avatar_evidence'
  ] loop
    select pg_get_function_result(p.oid), p.prosrc into sig, src
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = f;
    if sig is null then raise exception 'FAIL: function % missing', f; end if;
    if position('display_name' in sig) > 0 then
      raise exception 'FAIL: % return shape exposes display_name', f;
    end if;
    if position('display_name' in src) > 0 then
      raise exception 'FAIL: % body references display_name', f;
    end if;
  end loop;
  -- file_report was redefined here; re-assert the rule on it too.
  select p.prosrc into src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'file_report';
  if position('display_name' in src) > 0 then
    raise exception 'FAIL: file_report body references display_name';
  end if;
end $$;

do $$ declare f text; begin
  foreach f in array array[
    'public.avatar_ticket_create(text)', 'public.avatar_ticket_consume(uuid)',
    'public.avatar_commit_record(uuid, text, text)', 'public.remove_avatar()',
    'public.avatar_mark_purged(text)', 'public.avatar_keys(uuid[])',
    'public.mod_remove_avatar(uuid, report_reason, text)',
    'public.mod_reinstate_avatar(uuid, text)', 'public.mod_avatar_evidence(uuid)'
  ] loop
    if has_function_privilege('anon', f, 'execute') then
      raise exception 'FAIL: anon can execute %', f;
    end if;
    if has_function_privilege('service_role', f, 'execute') then
      raise exception 'FAIL: service_role can execute %', f;
    end if;
    if not has_function_privilege('authenticated', f, 'execute') then
      raise exception 'FAIL: authenticated cannot execute %', f;
    end if;
  end loop;
  foreach f in array array['anon', 'authenticated', 'service_role'] loop
    if has_function_privilege(f, 'public.avatar_purgeable(text)', 'execute') then
      raise exception 'FAIL: % can execute the internal purge predicate', f;
    end if;
  end loop;
end $$;

-- ============================================================
-- 2. STRUCTURAL: the new tables carry RLS with zero policies and no
--    direct privileges; no table in public is left without RLS; no
--    filename-shaped column exists anywhere in the feature; and the
--    0009 column grant letting members write avatar_media_key
--    directly is gone.
-- ============================================================
do $$ declare t text; r text; begin
  foreach t in array array['avatar_media', 'avatar_upload_tickets'] loop
    if not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass) then
      raise exception 'FAIL: % has no row security', t;
    end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = t) then
      raise exception 'FAIL: % has policies; it must be function-only', t;
    end if;
    foreach r in array array['anon', 'authenticated', 'service_role'] loop
      if has_table_privilege(r, 'public.' || t, 'select')
         or has_table_privilege(r, 'public.' || t, 'insert')
         or has_table_privilege(r, 'public.' || t, 'update')
         or has_table_privilege(r, 'public.' || t, 'delete') then
        raise exception 'FAIL: % holds a direct privilege on %', r, t;
      end if;
    end loop;
  end loop;
  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity) then
    raise exception 'FAIL: a table in public has no row security';
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public'
               and table_name in ('avatar_media', 'avatar_upload_tickets', 'reports', 'profiles')
               and column_name like '%filename%') then
    raise exception 'FAIL: a filename column exists — the original filename must never persist';
  end if;
  if has_column_privilege('authenticated', 'public.profiles', 'avatar_media_key', 'update') then
    raise exception 'FAIL: authenticated can still write avatar_media_key directly';
  end if;
end $$;

-- ============================================================
-- 3. The upload path: ticket -> consume -> commit as ada.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);

do $$ declare
  t uuid; k text; sk text;
begin
  t := avatar_ticket_create('st/' || repeat('1a', 24));
  sk := avatar_ticket_consume(t);
  if sk <> 'st/' || repeat('1a', 24) then
    raise exception 'FAIL: consume returned the wrong staging key';
  end if;
  -- A second consume of the same ticket must fail.
  begin
    perform avatar_ticket_consume(t);
    raise exception 'FAIL: a ticket was consumed twice';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  perform avatar_commit_record(t, repeat('ad', 24), 'LEHV6nWB2yk8pyo0adR*.7kCMdnj');
  select avatar_media_key into k from profiles where user_id = auth.uid();
  if k <> repeat('ad', 24) then
    raise exception 'FAIL: commit did not point the profile at the new key';
  end if;
  -- The same ticket cannot be redeemed twice.
  begin
    perform avatar_commit_record(t, repeat('ff', 24), null);
    raise exception 'FAIL: a ticket was redeemed twice';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  -- A malformed key is refused.
  begin
    perform avatar_commit_record(t, 'av/evil/../key', null);
    raise exception 'FAIL: a malformed key was accepted';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

-- bea gets an avatar too (for the both-directions block assertion).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare t uuid; begin
  t := avatar_ticket_create('st/' || repeat('2b', 24));
  perform avatar_ticket_consume(t);
  perform avatar_commit_record(t, repeat('be', 24), null);
end $$;

-- ============================================================
-- 4. The resolver: bea sees ada's key; then a block in ONE direction
--    (ada blocks bea) hides the key in BOTH directions. Mute must NOT
--    hide it (mute is a feed tool, not an identity tool).
-- ============================================================
do $$ declare n integer; begin
  select count(*) into n from avatar_keys(array['00000000-0000-0000-0000-000000000003']::uuid[])
   where avatar_key = repeat('ad', 24);
  if n <> 1 then raise exception 'FAIL: a member in good standing cannot resolve an avatar'; end if;
end $$;

-- ada blocks bea.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
insert into blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000004');

-- Direction 1: the BLOCKED member (bea) must not resolve ada's key.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare n integer; begin
  select count(*) into n from avatar_keys(array['00000000-0000-0000-0000-000000000003']::uuid[]);
  if n <> 0 then raise exception 'FAIL: a blocked member resolved the blocker''s avatar key'; end if;
end $$;

-- Direction 2: the BLOCKER (ada) must not resolve bea's key either —
-- this is the direction profiles_read does NOT cover, which is the
-- whole reason the resolver gates on blocked_either.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ declare n integer; begin
  select count(*) into n from avatar_keys(array['00000000-0000-0000-0000-000000000004']::uuid[]);
  if n <> 0 then raise exception 'FAIL: the blocker resolved the blocked member''s avatar key (one-way profiles semantics leaked in)'; end if;
end $$;

-- Lift the block; both resolve again. Then mute: still resolves.
delete from blocks where blocker_id = '00000000-0000-0000-0000-000000000003';
insert into mutes (muter_id, muted_id)
values ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000004');
do $$ declare n integer; begin
  select count(*) into n from avatar_keys(array['00000000-0000-0000-0000-000000000004']::uuid[])
   where avatar_key = repeat('be', 24);
  if n <> 1 then raise exception 'FAIL: mute hid an avatar (mute must not touch identity)'; end if;
end $$;
delete from mutes where muter_id = '00000000-0000-0000-0000-000000000003';

-- ============================================================
-- 5. Standing: suspended / banned / deactivated owners resolve to
--    nothing; restored standing resolves again. A non-member context
--    (no JWT) resolves nothing.
-- ============================================================
reset role;
update profiles set status = 'suspended' where user_id = '00000000-0000-0000-0000-000000000003';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare n integer; begin
  select count(*) into n from avatar_keys(array['00000000-0000-0000-0000-000000000003']::uuid[]);
  if n <> 0 then raise exception 'FAIL: a suspended member''s avatar resolved'; end if;
end $$;
reset role;
update profiles set status = 'banned' where user_id = '00000000-0000-0000-0000-000000000003';
set role authenticated;
do $$ declare n integer; begin
  select count(*) into n from avatar_keys(array['00000000-0000-0000-0000-000000000003']::uuid[]);
  if n <> 0 then raise exception 'FAIL: a banned member''s avatar resolved'; end if;
end $$;
reset role;
update profiles set status = 'active' where user_id = '00000000-0000-0000-0000-000000000003';
set role authenticated;
do $$ declare n integer; begin
  select count(*) into n from avatar_keys(array['00000000-0000-0000-0000-000000000003']::uuid[]);
  if n <> 1 then raise exception 'FAIL: a restored member''s avatar did not come back'; end if;
end $$;

-- A suspended VIEWER resolves nothing at all.
reset role;
update profiles set status = 'suspended' where user_id = '00000000-0000-0000-0000-000000000004';
set role authenticated;
do $$ declare n integer; begin
  select count(*) into n from avatar_keys(array['00000000-0000-0000-0000-000000000003']::uuid[]);
  if n <> 0 then raise exception 'FAIL: a suspended viewer resolved an avatar'; end if;
end $$;
reset role;
update profiles set status = 'active' where user_id = '00000000-0000-0000-0000-000000000004';

-- No JWT context at all (what a logged-out request would be if it
-- could reach the function; it cannot — anon holds no EXECUTE — but
-- the function itself must still answer with nothing).
set role authenticated;
select set_config('request.jwt.claim.sub', '', false);
select set_config('request.jwt.claims', '', false);
do $$ declare n integer; begin
  select count(*) into n from avatar_keys(array['00000000-0000-0000-0000-000000000003']::uuid[]);
  if n <> 0 then raise exception 'FAIL: a context with no member resolved an avatar'; end if;
end $$;
reset role;

-- ============================================================
-- 6. Evidence freeze: bea reports ada (account-level). The report
--    captures ada's CURRENT key. Ada then swaps her avatar; the old
--    key must be frozen (not purgeable), the new one her live avatar.
-- ============================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare r uuid; k text; begin
  r := file_report('user', null, '00000000-0000-0000-0000-000000000003', 'harassment', 'the photo');
  select reported_avatar_key into k from reports where id = r;
  if k <> repeat('ad', 24) then
    raise exception 'FAIL: the report did not freeze the accused''s current avatar key';
  end if;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ declare t uuid; v record; begin
  t := avatar_ticket_create('st/' || repeat('3c', 24));
  perform avatar_ticket_consume(t);
  select * into v from avatar_commit_record(t, repeat('a2', 24), null);
  if v.old_key <> repeat('ad', 24) then
    raise exception 'FAIL: commit did not report the superseded key';
  end if;
  if v.old_purgeable then
    raise exception 'FAIL: a reported (frozen) avatar was declared purgeable';
  end if;
  -- And the mark-purged path must refuse it too.
  begin
    perform avatar_mark_purged(repeat('ad', 24));
    raise exception 'FAIL: a frozen avatar object was marked purged';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

-- ============================================================
-- 7. Self-removal of a clean, unreported avatar IS purgeable.
--    bea removes hers: old key purgeable, mark-purged succeeds,
--    resolver stops returning it.
-- ============================================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","aal":"aal1","session_id":"sb"}', false);
do $$ declare v record; n integer; begin
  select * into v from remove_avatar();
  if v.old_key <> repeat('be', 24) or not v.old_purgeable then
    raise exception 'FAIL: a clean self-removed avatar was not purgeable';
  end if;
  perform avatar_mark_purged(v.old_key);
  select count(*) into n from avatar_keys(array['00000000-0000-0000-0000-000000000004']::uuid[]);
  if n <> 0 then raise exception 'FAIL: a removed avatar still resolves'; end if;
end $$;
reset role;
do $$ begin
  if (select purged_at from avatar_media where key = repeat('be', 24)) is null then
    raise exception 'FAIL: mark-purged did not record';
  end if;
end $$;
set role authenticated;

-- ============================================================
-- 8. Moderation removal PRESERVES and is reversible. The Owner
--    removes ada's live avatar: profile reverts to placeholder, the
--    row is marked moderation-removed, it is NOT purgeable, the
--    member is notified with the rule, and reinstatement restores it.
-- ============================================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"so"}', false);
select mod_remove_avatar('00000000-0000-0000-0000-000000000003', 'hate', 'test removal');
reset role;
do $$ declare v record; begin
  if (select avatar_media_key from profiles
      where user_id = '00000000-0000-0000-0000-000000000003') is not null then
    raise exception 'FAIL: moderation removal left the profile pointing at the photo';
  end if;
  select * into v from avatar_media where key = repeat('a2', 24);
  if v.removed_at is null or v.removed_kind <> 'moderation' or v.removed_rule <> 'hate' then
    raise exception 'FAIL: moderation removal did not mark the row preserved';
  end if;
  if v.purged_at is not null then
    raise exception 'FAIL: moderation removal purged the object (it must preserve)';
  end if;
  if not exists (select 1 from moderation_actions
                 where target_user_id = '00000000-0000-0000-0000-000000000003'
                   and action = 'remove_content' and rule = 'hate' and post_id is null) then
    raise exception 'FAIL: moderation removal was not recorded in the enforcement history';
  end if;
  if not exists (select 1 from notifications
                 where user_id = '00000000-0000-0000-0000-000000000003'
                   and type = 'system' and body like '%profile photo was removed%') then
    raise exception 'FAIL: the member was not told her photo was removed';
  end if;
end $$;
set role authenticated;

-- Not purgeable while moderation-removed (even though no profile
-- points at it and its report was resolved by the action).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","aal":"aal1","session_id":"sa"}', false);
do $$ begin
  begin
    perform avatar_mark_purged(repeat('a2', 24));
    raise exception 'FAIL: a moderation-removed avatar was purged';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

-- Reinstate: the profile points at the photo again and it resolves.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"so"}', false);
select mod_reinstate_avatar('00000000-0000-0000-0000-000000000003', 'honest mistake');
do $$ declare n integer; begin
  if (select avatar_media_key from profiles
      where user_id = '00000000-0000-0000-0000-000000000003') <> repeat('a2', 24) then
    raise exception 'FAIL: reinstatement did not restore the photo';
  end if;
  select count(*) into n from avatar_keys(array['00000000-0000-0000-0000-000000000003']::uuid[])
   where avatar_key = repeat('a2', 24);
  if n <> 1 then raise exception 'FAIL: a reinstated avatar does not resolve'; end if;
end $$;

-- ============================================================
-- 9. The evidence panel: staff see the frozen key for ada's case; a
--    csam-reason report's image never appears there and pins a legal
--    hold on the object instead.
-- ============================================================
do $$ declare n integer; begin
  select count(*) into n from mod_avatar_evidence('00000000-0000-0000-0000-000000000003')
   where avatar_key = repeat('ad', 24) and reason = 'harassment';
  if n <> 1 then raise exception 'FAIL: the frozen avatar is missing from the evidence panel'; end if;
end $$;

-- cat gets an avatar; dee reports it as csam.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ declare t uuid; begin
  t := avatar_ticket_create('st/' || repeat('4d', 24));
  perform avatar_ticket_consume(t);
  perform avatar_commit_record(t, repeat('ca', 24), null);
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000006","aal":"aal1","session_id":"sd"}', false);
select file_report('user', null, '00000000-0000-0000-0000-000000000005', 'csam', null);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","aal":"aal2","session_id":"so"}', false);
do $$ declare n integer; begin
  select count(*) into n from mod_avatar_evidence('00000000-0000-0000-0000-000000000005');
  if n <> 0 then
    raise exception 'FAIL: a csam-reported image reached the console evidence panel';
  end if;
end $$;
reset role;
do $$ begin
  if not (select legal_hold from avatar_media where key = repeat('ca', 24)) then
    raise exception 'FAIL: a csam-reason report did not set the legal hold';
  end if;
end $$;

-- ============================================================
-- 10. Upload guards: a suspended member cannot mint a ticket; the
--     hourly ticket cap holds; a restricted member can remove but
--     not upload.
-- ============================================================
reset role;
update profiles set status = 'suspended' where user_id = '00000000-0000-0000-0000-000000000006';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000006","aal":"aal1","session_id":"sd"}', false);
do $$ begin
  begin
    perform avatar_ticket_create('st/' || repeat('5e', 24));
    raise exception 'FAIL: a suspended member minted an upload ticket';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;
reset role;
update profiles set status = 'active' where user_id = '00000000-0000-0000-0000-000000000006';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000006","aal":"aal1","session_id":"sd"}', false);
do $$ declare i integer; hex text := '0123456789abcdef'; begin
  for i in 1..12 loop
    perform avatar_ticket_create('st/' || repeat(substr(hex, (i % 16) + 1, 1), 48));
  end loop;
  begin
    perform avatar_ticket_create('st/' || repeat('9f', 24));
    raise exception 'FAIL: the 13th ticket in an hour was allowed';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

reset role;
update profiles set status = 'restricted' where user_id = '00000000-0000-0000-0000-000000000005';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","aal":"aal1","session_id":"sc"}', false);
do $$ declare v record; begin
  begin
    perform avatar_ticket_create('st/' || repeat('6a', 24));
    raise exception 'FAIL: a restricted member minted an upload ticket';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
  -- Removal of her own photo stays available to a restricted member.
  select * into v from remove_avatar();
  if v.old_key <> repeat('ca', 24) then
    raise exception 'FAIL: a restricted member could not remove her own photo';
  end if;
  if v.old_purgeable then
    raise exception 'FAIL: a legally-held object was declared purgeable';
  end if;
end $$;
reset role;

rollback;
\echo ALL AVATAR TESTS PASSED
