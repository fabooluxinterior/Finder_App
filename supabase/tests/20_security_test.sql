\set ON_ERROR_STOP 1
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,6) i;
insert into public.profiles (id, full_name, age, city, bio) select id, 'U'||right(id::text,2), 25, 'Kochi', '' from auth.users;
-- A(01) <-> B(02) connected; C(03) stranger; D(04) has MFA; S(05) staff
insert into public.swipes_and_requests (sender_id, receiver_id, action) values ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','follow_requested');
update public.swipes_and_requests set action='accepted';
update public.profiles set is_premium = true where id in ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002');
insert into auth.mfa_factors (user_id, status) values ('00000000-0000-0000-0000-000000000004','verified'), ('00000000-0000-0000-0000-000000000005','verified');
insert into public.staff_roles (user_id, role) values ('00000000-0000-0000-0000-000000000005','admin');
insert into auth.sessions (user_id) values ('00000000-0000-0000-0000-000000000002');

create or replace function pg_temp.k(seed text, n int default 43) returns text language sql as $$ select left(rpad(encode(sha256(seed::bytea),'base64'), n, 'A'), n) $$;
create or replace function pg_temp.expect_fail(sql text, label text) returns text language plpgsql as $$
begin execute sql; raise exception 'EXPECTED FAILURE DID NOT HAPPEN: %', label;
exception when others then if sqlerrm like 'EXPECTED FAILURE%' then raise; end if; return 'ok (blocked): ' || label || ' -> ' || sqlerrm; end $$;
grant execute on all functions in schema pg_temp to authenticated;
create or replace function pg_temp.as_user(u text, aal text default 'aal1') returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', u, 'aal', aal)::text, false); $$;
grant execute on function pg_temp.as_user(text,text) to authenticated;

set role authenticated;
select pg_temp.as_user('01');
select 'A device', public.register_device(pg_temp.k('a-c'), pg_temp.k('a-e'), 'Pixel', 'android') is not null;
select pg_temp.as_user('02');
select 'B device', public.register_device(pg_temp.k('b-c'), pg_temp.k('b-e'), 'Phone', 'android') is not null;
select 'B uploads 2 otk + fallback ->', public.upload_one_time_keys((select id from public.devices where user_id = auth.uid()),
  jsonb_build_array(jsonb_build_object('key_id','k1','public_key',pg_temp.k('o1'),'signature',pg_temp.k('s1',86)),
                    jsonb_build_object('key_id','k2','public_key',pg_temp.k('o2'),'signature',pg_temp.k('s2',86)),
                    jsonb_build_object('key_id','f1','public_key',pg_temp.k('f1'),'signature',pg_temp.k('sf',86),'fallback',true)));
select pg_temp.as_user('03');
select 'C registers device', public.register_device(pg_temp.k('c-c'), pg_temp.k('c-e'), 'X', 'web') is not null;
select pg_temp.expect_fail($$select * from public.claim_device_keys('00000000-0000-0000-0000-000000000002')$$, 'stranger claims B keys');
select 'C sees B devices (expect 0):', count(*) from public.devices where user_id = '00000000-0000-0000-0000-000000000002';
select pg_temp.expect_fail($$insert into public.devices (user_id, curve25519, ed25519, platform) values (auth.uid(), 'x','y','web')$$, 'direct device insert');

select pg_temp.as_user('01');
select 'A claim 1:', key_id from public.claim_device_keys('00000000-0000-0000-0000-000000000002');
select 'A claim 2:', key_id from public.claim_device_keys('00000000-0000-0000-0000-000000000002');
select 'A claim 3 (fallback):', key_id from public.claim_device_keys('00000000-0000-0000-0000-000000000002');
select 'A sees B devices (expect 1):', count(*) from public.devices where user_id = '00000000-0000-0000-0000-000000000002';
create temp table ids as select (select id from public.devices where curve25519 = pg_temp.k('a-c')) a, (select id from public.devices where curve25519 = pg_temp.k('b-c')) b, (select id from public.devices where curve25519 = pg_temp.k('c-c')) c;
grant select on ids to authenticated;
select 'A sends', public.send_message('00000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', (select a from ids),
  jsonb_build_array(jsonb_build_object('device_id',(select b from ids),'type',0,'ciphertext','CIPHERTEXT'),
                    jsonb_build_object('device_id',(select a from ids),'type',1,'ciphertext','SELF'))) is not null;
select 'idempotent resend same id:', (select count(*) from public.messages) = 1 from (select public.send_message('00000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', (select a from ids), jsonb_build_array(jsonb_build_object('device_id',(select b from ids),'type',0,'ciphertext','X')))) t;
select pg_temp.expect_fail($$select public.send_message('00000000-0000-0000-0000-000000000002', gen_random_uuid(), (select a from ids), jsonb_build_array(jsonb_build_object('device_id',(select c from ids),'type',0,'ciphertext','leak')))$$, 'envelope to outsider device');
select pg_temp.expect_fail($$select public.send_message('00000000-0000-0000-0000-000000000002', gen_random_uuid(), (select b from ids), jsonb_build_array(jsonb_build_object('device_id',(select b from ids),'type',0,'ciphertext','x')))$$, 'spoof sender device');
select pg_temp.expect_fail($$insert into public.message_envelopes values (gen_random_uuid(), (select b from ids), 0, 'x')$$, 'direct envelope insert');
select pg_temp.expect_fail($$insert into public.messages (sender_id, receiver_id) values (auth.uid(), '00000000-0000-0000-0000-000000000002')$$, 'direct message insert');
select 'A sees own envelopes (self copy dropped, expect 0):', count(*) from public.message_envelopes;

select pg_temp.as_user('03');
select 'C sees messages/envelopes (expect 0/0):', (select count(*) from public.messages), (select count(*) from public.message_envelopes);
select pg_temp.expect_fail($$select public.send_message('00000000-0000-0000-0000-000000000002', gen_random_uuid(), (select c from ids), jsonb_build_array(jsonb_build_object('device_id',(select b from ids),'type',0,'ciphertext','x')))$$, 'stranger sends to B');

select pg_temp.as_user('02');
select 'B envelope ciphertext:', ciphertext from public.message_envelopes;
select public.ack_envelopes((select b from ids), array(select id from public.messages));
select 'B envelopes after ack (expect 0):', count(*) from public.message_envelopes;
select pg_temp.expect_fail($$select public.revoke_session((select id from auth.sessions limit 1))$$, 'B reads auth.sessions directly');
select 'B sessions (expect 1):', count(*) from public.my_sessions();

select pg_temp.as_user('01');
select pg_temp.expect_fail($$select public.revoke_session('00000000-0000-0000-0000-00000000aaaa')$$, 'A revokes someone else session');
select public.block_user('00000000-0000-0000-0000-000000000002');
select 'after block: connected?', public.is_connected(auth.uid(), '00000000-0000-0000-0000-000000000002');
select 'after block: A sees messages (expect 0):', count(*) from public.messages;
select pg_temp.as_user('02');
select 'B sees A profile after block (expect 0):', count(*) from public.profiles where id = '00000000-0000-0000-0000-000000000001';
select pg_temp.expect_fail($$select * from public.claim_device_keys('00000000-0000-0000-0000-000000000001')$$, 'blocked user claims keys');
select pg_temp.expect_fail($$select public.swipe_profile('00000000-0000-0000-0000-000000000001', 'follow_requested')$$, 'blocked user re-requests');

-- MFA
select pg_temp.as_user('04');
select pg_temp.expect_fail($$select public.register_device(pg_temp.k('d-c'), pg_temp.k('d-e'), 'X', 'ios')$$, 'MFA user adds device on aal1');
select pg_temp.as_user('04', 'aal2');
select 'D adds device on aal2', public.register_device(pg_temp.k('d-c'), pg_temp.k('d-e'), 'X', 'ios') is not null;

-- Reports & staff
select pg_temp.as_user('03');
select 'C reports A with evidence', public.submit_report('00000000-0000-0000-0000-000000000001', 'harassment', 'abusive', '[{"text":"reported message"}]', true) is not null;
select 'C sees own report status:', status from public.reports;
select pg_temp.expect_fail($$select evidence from public.reports$$, 'reporter reads evidence column');
select pg_temp.expect_fail($$select * from public.mod_list_reports()$$, 'non-staff lists reports');
select pg_temp.expect_fail($$select public.admin_security_overview()$$, 'non-staff dashboard');
select pg_temp.as_user('05');
select pg_temp.expect_fail($$select * from public.mod_list_reports()$$, 'staff without MFA session');
select pg_temp.as_user('05', 'aal2');
select 'staff lists reports:', count(*) from public.mod_list_reports();
select pg_temp.expect_fail($$select * from public.mod_open_report((select id from public.mod_list_reports() limit 1), '')$$, 'open evidence without reason');
select 'staff opens evidence:', evidence from public.mod_open_report((select id from public.mod_list_reports() limit 1), 'Reviewing harassment report');
select 'dashboard keys:', (select string_agg(k, ',' order by k) from jsonb_object_keys(public.admin_security_overview()) k);
select pg_temp.expect_fail($$select * from public.access_audit_log$$, 'staff reads audit table directly');
reset role;
select 'audit rows:', count(*) from public.access_audit_log;
select pg_temp.expect_fail($$update public.access_audit_log set reason = 'x'$$, 'superuser edits audit log');
select pg_temp.expect_fail($$delete from public.access_audit_log$$, 'superuser deletes audit log');

-- Media authorisation (service-side function)
insert into public.media_objects (id, owner_id, kind, status, storage_path, wrapped_dek, kek_id, nonce, sha256, width, height, bytes) values
 ('aaaaaaaa-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000006','primary','approved','p','w','v1','n','s',800,800,1),
 ('aaaaaaaa-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000006','gallery','approved','p','w','v1','n','s',800,800,1),
 ('aaaaaaaa-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000006','primary','pending','p','w','v1','n','s',800,800,1);
select 'stranger: primary/gallery/pending =', public.can_view_media('00000000-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000001'),
  public.can_view_media('00000000-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000002'),
  public.can_view_media('00000000-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000003');
select 'owner sees pending:', public.can_view_media('00000000-0000-0000-0000-000000000006','aaaaaaaa-0000-0000-0000-000000000003');
set role authenticated;
select pg_temp.as_user('03');
select pg_temp.expect_fail($$select public.can_view_media(auth.uid(),'aaaaaaaa-0000-0000-0000-000000000001')$$, 'client calls can_view_media');
select pg_temp.expect_fail($$select wrapped_dek from public.media_objects$$, 'client reads wrapped keys');
select pg_temp.expect_fail($$select public.attach_media('aaaaaaaa-0000-0000-0000-000000000001')$$, 'client attaches media');
select pg_temp.expect_fail($$update public.profiles set avatar_urls = '{x}' where id = auth.uid()$$, 'client sets avatar ids');

-- Rate limit
select pg_temp.as_user('03');
select pg_temp.expect_fail($$select public.submit_report('00000000-0000-0000-0000-000000000006','spam_or_scam',null,null,false) from generate_series(1,11)$$, 'report flood (11/day)');
