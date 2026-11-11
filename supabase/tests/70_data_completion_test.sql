\set ON_ERROR_STOP 1
-- Profile updates introduced after launch: only users missing a detail are
-- asked, saving completes it, dismiss/remind work, nothing else is touched,
-- and admin RPCs are staff-only.
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,4) i;
insert into public.profile_dob (user_id, dob) select id, date '1998-01-01' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, gender, occupation, interest_tags)
select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid, 'User '||i, 26, 'Kochi',
       'Rain, books and chai.', 'woman', case when i = 2 then 'Architect' else null end,
       '{Photography,Chai,Football,Poetry,Chess}'::text[]
  from generate_series(1,4) i;
update public.profiles set is_onboarded = true,
  photo_urls = array[gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text];
insert into public.staff_roles (user_id, role) values ('00000000-0000-0000-0000-000000000004', 'admin');

create or replace function pg_temp.expect_fail(sql text, label text) returns text language plpgsql as $$
begin execute sql; raise exception 'EXPECTED FAILURE DID NOT HAPPEN: %', label;
exception when others then if sqlerrm like 'EXPECTED FAILURE%' then raise; end if; return 'ok (blocked): ' || label || ' -> ' || sqlerrm; end $$;
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.as_user(u text, aal text default 'aal1') returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000'||u, 'aal', aal)::text, false); $$;
grant execute on all functions in schema pg_temp to authenticated;

create temporary table before_profiles as select * from public.profiles;
grant select on before_profiles to authenticated;

set role authenticated;

-- ------------------------------------------------------------ who is asked
select pg_temp.as_user('01');
select pg_temp.expect((select count(*) from public.my_profile_updates() where key = 'occupation' and show_prompt) = 1,
  'user without a profession is asked');
select pg_temp.as_user('02');
select pg_temp.expect(not exists (select 1 from public.my_profile_updates()), 'user with a profession is never asked');

-- ------------------------------------------------------------ prompt frequency
select pg_temp.as_user('01');
select public.mark_profile_update_seen('occupation');
select pg_temp.expect((select not show_prompt from public.my_profile_updates() where key = 'occupation'),
  'not shown again right after being shown');
select pg_temp.expect_fail($$select public.mark_profile_update_seen('nonexistent')$$, 'unknown key');

-- ------------------------------------------------------------ privileges
select pg_temp.expect_fail($$insert into public.user_requirement_status (user_id, key, completed_at) values (auth.uid(), 'occupation', now())$$, 'client writes its own status');
select pg_temp.expect_fail($$insert into public.profile_requirements (key, label, description, introduced_by) values ('evil', 'Evil', 'Evil field', 'x')$$, 'client registers a requirement');
select pg_temp.expect_fail($$select * from public.data_snapshot()$$, 'client reads data snapshot');
select pg_temp.expect_fail($$select * from public.admin_requirement_stats()$$, 'non-staff reads stats');
select pg_temp.expect_fail($$select public.admin_remind_requirement('occupation')$$, 'non-staff sends reminder');
select pg_temp.expect_fail($$select public.admin_schema_status()$$, 'non-staff reads schema status');
select pg_temp.expect_fail($$select * from public.admin_integration_status()$$, 'non-staff reads integrations');
select pg_temp.expect_fail($$select * from public.schema_change_log$$, 'client reads change log directly');
select pg_temp.expect_fail($$select * from public.integration_status$$, 'client reads integration table');
select pg_temp.expect_fail($$select public.requirement_missing('occupation', '00000000-0000-0000-0000-000000000002')$$, 'client probes another user');
select pg_temp.expect_fail($$select public.service_record_integration('spotify', true, '{}', true, 'x', true)$$, 'client writes integration status');

-- ------------------------------------------------------------ admin reminder
select pg_temp.as_user('04');
select pg_temp.expect_fail($$select * from public.admin_requirement_stats()$$, 'admin without MFA');
select pg_temp.as_user('04', 'aal2');
select pg_temp.expect((select pending from public.admin_requirement_stats() where key = 'occupation') = 3,
  'stats: 3 onboarded users pending');
select pg_temp.expect((select completed from public.admin_requirement_stats() where key = 'occupation') = 1,
  'stats: 1 already complete');
select public.admin_remind_requirement('occupation');
select pg_temp.as_user('01');
select pg_temp.expect((select show_prompt from public.my_profile_updates() where key = 'occupation'),
  'reminder shows it again');

-- ------------------------------------------------------------ dismiss
select pg_temp.as_user('03');
select public.dismiss_profile_update('occupation');
select pg_temp.expect((select not show_prompt from public.my_profile_updates() where key = 'occupation'),
  'dismissed optional detail stays hidden');
select pg_temp.as_user('04', 'aal2');
select public.admin_remind_requirement('occupation');
select pg_temp.as_user('03');
select pg_temp.expect((select not show_prompt from public.my_profile_updates() where key = 'occupation'),
  'reminder respects a dismissal');

-- ------------------------------------------------------------ completing saves only that field
select pg_temp.as_user('01');
update public.profiles set occupation = 'Teacher' where id = auth.uid();
select pg_temp.expect(not exists (select 1 from public.my_profile_updates()), 'saving the profession completes it');
select pg_temp.expect((select completed_at is not null from public.user_requirement_status where key = 'occupation'),
  'completion recorded');
select pg_temp.expect((select count(*) from public.profiles p join before_profiles b using (id)
   where p.id = auth.uid() and (p.full_name, p.bio, p.city, p.photo_urls, p.interest_tags, p.gender, p.is_onboarded)
       is not distinct from (b.full_name, b.bio, b.city, b.photo_urls, b.interest_tags, b.gender, b.is_onboarded)) = 1,
  'nothing else on the profile changed');

-- ------------------------------------------------------------ feature gating (registered as 'feature')
reset role;
insert into public.profile_requirements (key, label, description, level, gated_feature, introduced_by)
values ('test_detail', 'Test detail', 'A detail one feature needs.', 'feature', 'test_feature', 'test');
create or replace function public.requirement_missing(p_key text, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case p_key
    when 'occupation' then coalesce(btrim(p.occupation), '') = ''
    when 'test_detail' then coalesce(btrim(p.education), '') = ''
    else false end
  from public.profiles p where p.id = p_user; $$;
set role authenticated;
select pg_temp.as_user('02');
select pg_temp.expect_fail($$select public.require_profile_details('test_feature')$$, 'gated feature waits for its detail');
select pg_temp.expect_fail($$select public.dismiss_profile_update('test_detail')$$, 'feature detail can''t be dismissed');
select public.require_profile_details('other_feature');
select 'ok: other features stay open';
update public.profiles set education = 'B.Arch' where id = auth.uid();
select public.require_profile_details('test_feature');
select 'ok: feature opens once the detail is saved';

-- ------------------------------------------------------------ staff views
select pg_temp.as_user('04', 'aal2');
select pg_temp.expect((select (public.admin_schema_status()->'change_log') @> '[{"migration_id":"20261114000000_data_completion"}]'),
  'change log lists this migration');
select pg_temp.expect((select count(*) from public.admin_data_snapshot() where table_name = 'profiles' and row_count = 4) = 1,
  'snapshot counts profiles');
reset role;
select public.service_record_integration('spotify', false, '{SPOTIFY_CLIENT_SECRET}', null, null, false);
set role authenticated;
select pg_temp.expect((select not configured and missing = '{SPOTIFY_CLIENT_SECRET}' from public.admin_integration_status() where service = 'spotify'),
  'integration status shows what is missing, no values');
