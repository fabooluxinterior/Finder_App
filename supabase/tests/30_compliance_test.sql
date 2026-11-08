\set ON_ERROR_STOP 1
-- Users: A(01) adult with DOB, B(02) adult, C(03) staff (MFA), N(04) new user without DOB, L(05) legacy user (no DOB)
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,5) i;
insert into public.profile_dob (user_id, dob) values
  ('00000000-0000-0000-0000-000000000001', date '1999-05-20'),
  ('00000000-0000-0000-0000-000000000002', date '2001-02-02'),
  ('00000000-0000-0000-0000-000000000003', date '1990-01-01');
insert into public.profiles (id, full_name, age, city, bio, avatar_urls) values
  ('00000000-0000-0000-0000-000000000001', 'Asha', 99, 'Kochi', '', '{aaaaaaaa-0000-0000-0000-000000000001}'),
  ('00000000-0000-0000-0000-000000000002', 'Bala', 99, 'Kochi', '', '{aaaaaaaa-0000-0000-0000-000000000002}'),
  ('00000000-0000-0000-0000-000000000003', 'Staff', 99, 'Kochi', '', '{}');
-- Legacy profile created before DOBs existed (trigger bypassed as superuser).
alter table public.profiles disable trigger profiles_age_from_dob;
insert into public.profiles (id, full_name, age, city, bio, avatar_urls) values ('00000000-0000-0000-0000-000000000005', 'Legacy', 30, 'Kochi', '', '{aaaaaaaa-0000-0000-0000-000000000005}');
alter table public.profiles enable trigger profiles_age_from_dob;
select 'age computed from DOB, not client value (expect not 99):', age from public.profiles where id = '00000000-0000-0000-0000-000000000001';
insert into public.profile_private (id, interests, gallery_urls) values ('00000000-0000-0000-0000-000000000001', '{music}', '{bbbbbbbb-0000-0000-0000-000000000001}');
insert into auth.mfa_factors (user_id, status) values ('00000000-0000-0000-0000-000000000003', 'verified');
insert into public.staff_roles (user_id, role) values ('00000000-0000-0000-0000-000000000003', 'moderator');
insert into public.media_objects (id, owner_id, kind, status, storage_path, wrapped_dek, kek_id, nonce, sha256, width, height, bytes) values
 ('aaaaaaaa-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','primary','approved','p','w','v1','n','s',800,800,1),
 ('bbbbbbbb-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','gallery','approved','p','w','v1','n','s',800,800,1),
 ('cccccccc-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','selfie','approved','p','w','v1','n','s',800,800,1);

create or replace function pg_temp.expect_fail(sql text, label text) returns text language plpgsql as $$
begin execute sql; raise exception 'EXPECTED FAILURE DID NOT HAPPEN: %', label;
exception when others then if sqlerrm like 'EXPECTED FAILURE%' then raise; end if; return 'ok (blocked): ' || label || ' -> ' || sqlerrm; end $$;
create or replace function pg_temp.as_user(u text, aal text default 'aal1') returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', u, 'aal', aal)::text, false); $$;
grant execute on all functions in schema pg_temp to authenticated;

-- ---------------------------------------------------------------- media access
select 'stranger sees gallery (open profiles):', public.can_view_media('00000000-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000001');
select 'stranger sees selfie (expect f):', public.can_view_media('00000000-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000001');
select 'owner sees own selfie:', public.can_view_media('00000000-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001');

set role authenticated;

-- ---------------------------------------------------------------- consent
select pg_temp.as_user('01');
select 'A consent before (expect null):', coalesce(public.accepted_policy_version(), 'null');
select pg_temp.expect_fail($$insert into public.user_consents (user_id, policy_type, policy_version) values (auth.uid(), 'terms', '2026-11-10')$$, 'direct consent insert');
select pg_temp.expect_fail($$select public.record_consent('latest')$$, 'malformed policy version');
select public.record_consent('2026-11-10');
select 'A consent after:', public.accepted_policy_version();
select public.record_consent('2027-01-01');
select 'A consent after re-consent:', public.accepted_policy_version();
select 'A sees own consent rows (expect 8):', count(*) from public.user_consents;
select pg_temp.as_user('02');
select 'B sees A consents (expect 0):', count(*) from public.user_consents;

-- ---------------------------------------------------------------- open profiles, no contact info
select 'B sees A interests + gallery (open profiles):', interests, gallery_urls from public.profile_private where id = '00000000-0000-0000-0000-000000000001';
select pg_temp.as_user('01');
select pg_temp.expect_fail($$update public.profiles set full_name = 'Asha @asha.k' where id = auth.uid()$$, 'handle in name');
select pg_temp.expect_fail($$update public.profiles set city = 'MG Road 682016' where id = auth.uid()$$, 'street address as city');
select pg_temp.expect_fail($$update public.profile_private set interests = '{"insta: asha_k"}' where id = auth.uid()$$, 'handle in interests');
select pg_temp.expect_fail($$update public.profile_private set interests = '{"98470 12345"}' where id = auth.uid()$$, 'phone in interests');
select pg_temp.expect_fail($$update public.profiles set is_verified = true where id = auth.uid()$$, 'self-verify');
select pg_temp.expect_fail($$update public.profiles set age = 18 where id = auth.uid()$$, 'edit age directly');
select pg_temp.expect_fail($$update public.profiles set hidden_pending_review = false where id = auth.uid()$$, 'unhide self');
select pg_temp.as_user('02');
select public.block_user('00000000-0000-0000-0000-000000000001');
select 'after block, B sees A private profile (expect 0):', count(*) from public.profile_private where id = '00000000-0000-0000-0000-000000000001';
reset role; delete from public.blocks; set role authenticated;

-- ---------------------------------------------------------------- DOB
select pg_temp.as_user('04');
select 'new user has DOB (expect f):', public.has_dob();
select pg_temp.expect_fail($$insert into public.profiles (id, full_name, age, city, bio) values (auth.uid(), 'New', 25, 'Kochi', '')$$, 'profile without DOB');
select pg_temp.expect_fail($$select public.set_dob((current_date - interval '17 years')::date)$$, 'under-18 DOB');
select pg_temp.expect_fail($$select public.set_dob((current_date + 1))$$, 'future DOB');
select pg_temp.expect_fail($$insert into public.profile_dob (user_id, dob) values (auth.uid(), '1990-01-01')$$, 'direct DOB insert');
select 'set adult DOB, age:', public.set_dob((current_date - interval '25 years' - interval '3 days')::date);
insert into public.profiles (id, full_name, age, city, bio) values (auth.uid(), 'New', 60, 'Kochi', '');
select 'new profile age from DOB (expect 25):', age from public.profiles where id = auth.uid();
select pg_temp.expect_fail($$select public.set_dob('1990-01-01')$$, 'change DOB via RPC');
select pg_temp.expect_fail($$update public.profile_dob set dob = '1990-01-01' where user_id = auth.uid()$$, 'change DOB directly');
select 'DOB visible to owner:', count(*) from public.profile_dob;
reset role;
select pg_temp.expect_fail($$update public.profile_dob set dob = '1980-01-01'$$, 'superuser/service changes DOB');
set role authenticated;
select pg_temp.as_user('01');
select 'A sees other users DOB (expect 1 = own only):', count(*) from public.profile_dob;
select pg_temp.as_user('05');
select 'legacy user has DOB (expect f):', public.has_dob();
select 'legacy keeps age until DOB set:', age from public.profiles where id = auth.uid();
select public.set_dob((current_date - interval '31 years')::date);
select 'legacy age now from DOB (expect 31):', age from public.profiles where id = auth.uid();

-- ---------------------------------------------------------------- verification
select pg_temp.as_user('01');
select 'A starts verification, pose given:', length(pose) > 10 from public.start_verification();
select pg_temp.expect_fail($$insert into public.verification_requests (user_id, pose) values (auth.uid(), 'x')$$, 'direct request insert');
select pg_temp.expect_fail($$select public.attach_verification_selfie(auth.uid(), (select id from public.verification_requests limit 1), 'cccccccc-0000-0000-0000-000000000001')$$, 'client attaches selfie');
select pg_temp.expect_fail($$select media_id from public.verification_requests$$, 'client reads selfie media id');
reset role;
select public.attach_verification_selfie('00000000-0000-0000-0000-000000000001', (select id from public.verification_requests where status = 'awaiting_photo'), 'cccccccc-0000-0000-0000-000000000001');
set role authenticated;
select pg_temp.as_user('01');
select 'A status:', public.my_verification_status();
select pg_temp.expect_fail($$select * from public.start_verification()$$, 'second request while pending');
select pg_temp.expect_fail($$select * from public.mod_verification_queue()$$, 'non-staff reads queue');
select pg_temp.expect_fail($$select public.mod_review_verification((select id from public.verification_requests limit 1), true)$$, 'non-staff approves self');
select pg_temp.as_user('03');
select pg_temp.expect_fail($$select * from public.mod_verification_queue()$$, 'staff without MFA session');
select pg_temp.as_user('03', 'aal2');
select 'queue row (pose, selfie, profile photo):', pose is not null, selfie_media, profile_media from public.mod_verification_queue();
select public.mod_review_verification((select request_id from public.mod_verification_queue() limit 1), true);
select pg_temp.as_user('01');
select 'A verified:', is_verified, public.my_verification_status() from public.profiles where id = auth.uid();
select pg_temp.as_user('02');
select 'B feed shows A verified:', is_verified from public.get_feed(10) where id = '00000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------- under-18 auto-hide
select 'B feed has A before report (expect 1):', count(*) from public.get_feed(10) where id = '00000000-0000-0000-0000-000000000001';
select 'B reports A as appearing under 18', public.submit_report('00000000-0000-0000-0000-000000000001', 'underage', null, null, false) is not null;
select pg_temp.as_user('05');
select 'L feed has A after report (expect 0):', count(*) from public.get_feed(10) where id = '00000000-0000-0000-0000-000000000001';
select pg_temp.as_user('03', 'aal2');
select public.mod_resolve_report((select id from public.mod_list_reports() limit 1), 'dismissed', 'Adult, verified ID');
select pg_temp.as_user('05');
select 'L feed has A after dismissal (expect 1):', count(*) from public.get_feed(10) where id = '00000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------- selfie retention
reset role;
update public.verification_requests set reviewed_at = now() - interval '31 days';
select public.run_retention();
select 'selfie after 30 days:', status from public.media_objects where id = 'cccccccc-0000-0000-0000-000000000001';
select 'request media cleared:', media_id is null from public.verification_requests;
select 'A still verified after purge:', is_verified from public.profiles where id = '00000000-0000-0000-0000-000000000001';
