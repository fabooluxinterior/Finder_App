\set ON_ERROR_STOP 1
-- 01 and 02 connected (long ago); 03 connected to 01 just now; 04 admin; 05 stranger.
alter table auth.users add column if not exists email text;
insert into auth.users (id, email) select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid, 'u'||i||'@example.com' from generate_series(1,5) i;
insert into public.profile_dob (user_id, dob) select id, date '1998-01-01' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, gender) select id, 'User '||right(id::text,2), 25, 'Kochi', '', 'man' from auth.users;
insert into public.staff_roles (user_id, role) values ('00000000-0000-0000-0000-000000000004', 'admin');
insert into public.swipes_and_requests (sender_id, receiver_id, action) values
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'follow_requested'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'follow_requested');
update public.swipes_and_requests set action = 'accepted', responded_at = now();
update public.swipes_and_requests set responded_at = now() - interval '5 days' where receiver_id = '00000000-0000-0000-0000-000000000002';
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.expect_fail(sql text, label text) returns text language plpgsql as $$
begin execute sql; raise exception 'EXPECTED FAILURE DID NOT HAPPEN: %', label;
exception when others then if sqlerrm like 'EXPECTED FAILURE%' then raise; end if; return 'ok (blocked): ' || label; end $$;
create or replace function pg_temp.as_user(u text, aal text default 'aal1') returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000'||u, 'aal', aal)::text, false); $$;
grant execute on all functions in schema pg_temp to authenticated;

-- verified notice
reset role;
update public.profiles set is_verified = true where id = '00000000-0000-0000-0000-000000000005';
select pg_temp.expect((select count(*) from public.user_notifications where user_id = '00000000-0000-0000-0000-000000000005' and kind = 'verification') = 1, 'verification creates one notification');
update public.profiles set is_verified = false where id = '00000000-0000-0000-0000-000000000005';
update public.profiles set is_verified = true where id = '00000000-0000-0000-0000-000000000005';
select pg_temp.expect((select count(*) from public.user_notifications where user_id = '00000000-0000-0000-0000-000000000005' and kind = 'verification') = 1, 'never duplicated');

set role authenticated;
select pg_temp.as_user('01');
select pg_temp.expect((select count(*) from public.fun_lines_list()) >= 10, 'fun lines are served');
select pg_temp.expect((select count(*) from public.fun_lines_list() where slot = 'call_locked' and text like '%{n}%') >= 1, 'call lock lines carry the days placeholder');
select pg_temp.expect(public.call_unlock_days() = 4, 'default 4 days');
select pg_temp.expect(public.connected_since('00000000-0000-0000-0000-000000000002') < now() - interval '4 days', 'old connection date');
select pg_temp.expect(public.connected_since('00000000-0000-0000-0000-000000000005') is null, 'stranger: no connection');
select pg_temp.expect(public.start_demo_call('00000000-0000-0000-0000-000000000002'), 'call opens after the waiting time');
select pg_temp.expect_fail($$select public.start_demo_call('00000000-0000-0000-0000-000000000003')$$, 'call refused before the waiting time');
select pg_temp.expect_fail($$select public.start_demo_call('00000000-0000-0000-0000-000000000005')$$, 'call refused to a stranger');
select pg_temp.expect_fail($$select public.admin_set_call_days(1)$$, 'only admins change the days');
select pg_temp.expect_fail($$select * from public.fun_lines$$, 'table is not readable directly');
select pg_temp.as_user('02');
select pg_temp.expect((select count(*) from public.user_notifications where user_id = '00000000-0000-0000-0000-000000000002' and kind = 'call') = 1, 'the other phone gets the incoming call notice');
-- admin
select pg_temp.as_user('04', 'aal2');
select public.admin_set_call_days(0);
select pg_temp.expect(public.call_unlock_days() = 0, 'admin changes the days');
select public.admin_fun_line_save(null, 'tip', 'Test line', true, 9);
select pg_temp.expect((select count(*) from public.admin_fun_lines() where text = 'Test line') = 1, 'admin adds a line');
select pg_temp.expect_fail($$select public.admin_fun_line_save(null, 'bogus', 'x', true, 0)$$, 'unknown slot refused');
-- job
reset role;
select pg_temp.expect(public.service_notify_call_unlock() >= 1, 'job runs');
select pg_temp.expect((select count(*) from public.user_notifications where kind = 'call' and title like 'Calling is open%') >= 2, 'both people told that calling opened');
select public.service_notify_call_unlock();
select pg_temp.expect((select count(*) from public.user_notifications where kind = 'call' and title like 'Calling is open%' and user_id = '00000000-0000-0000-0000-000000000002') = 1, 'only once per pair');
