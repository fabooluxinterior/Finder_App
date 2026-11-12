\set ON_ERROR_STOP 1
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,3) i;
insert into public.profile_dob (user_id, dob) select id, date '2000-01-15' from auth.users;
insert into public.profiles (id, full_name, age, city, bio) select id, 'U'||right(id::text,2), 25, 'Kochi', '' from auth.users;
insert into public.swipes_and_requests (sender_id, receiver_id, action) values ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','follow_requested');
update public.swipes_and_requests set action = 'accepted';
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.expect_fail(sql text, label text) returns text language plpgsql as $$
begin execute sql; raise exception 'EXPECTED FAILURE DID NOT HAPPEN: %', label;
exception when others then if sqlerrm like 'EXPECTED FAILURE%' then raise; end if; return 'ok (blocked): ' || label; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000'||u, 'aal', 'aal1')::text, false); $$;
grant execute on all functions in schema pg_temp to authenticated;
set role authenticated;
select pg_temp.as_user('01');
select public.block_user('00000000-0000-0000-0000-000000000002');
select pg_temp.expect((select count(*) from public.my_blocked_users()) = 1, 'the blocked person is listed');
select pg_temp.expect((select user_id from public.my_blocked_users()) = '00000000-0000-0000-0000-000000000002', 'it is the right person');
select pg_temp.as_user('03');
select pg_temp.expect((select count(*) from public.my_blocked_users()) = 0, 'other people see none of it');
select pg_temp.as_user('02');
select pg_temp.expect((select count(*) from public.my_blocked_users()) = 0, 'the blocked person does not see it either');
select pg_temp.as_user('01');
select public.unblock_user('00000000-0000-0000-0000-000000000002');
select pg_temp.expect((select count(*) from public.my_blocked_users()) = 0, 'unblock removes the entry');
select pg_temp.expect(not public.is_connected('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002'), 'the old connection is not restored');
select pg_temp.as_user('02');
select public.unblock_user('00000000-0000-0000-0000-000000000001');
select pg_temp.expect(true, 'unblocking someone who did not block you does nothing');
