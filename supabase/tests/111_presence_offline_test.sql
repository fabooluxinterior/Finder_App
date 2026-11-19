\set ON_ERROR_STOP 1
-- 01 and 02 are connected; 03 is a stranger.
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,3) i;
insert into public.profile_dob (user_id, dob) select id, date '2000-01-15' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, avatar_urls)
  select id, 'User '||right(id::text,2), 25, 'Kochi', '', array[gen_random_uuid()::text] from auth.users;
insert into public.swipes_and_requests (sender_id, receiver_id, action) values
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'follow_requested');
update public.swipes_and_requests set action = 'accepted', responded_at = now();
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000'||u, 'aal', 'aal1')::text, false); $$;
grant execute on all functions in schema pg_temp to authenticated;
set role authenticated;

select pg_temp.as_user('02');
select public.presence_ping();
select pg_temp.as_user('01');
select pg_temp.expect((select online from public.peer_presence_v2('00000000-0000-0000-0000-000000000002')), 'active person is online');
-- 02 closes the app / locks the phone
select pg_temp.as_user('02');
select public.presence_offline();
select pg_temp.as_user('01');
select pg_temp.expect((select not online from public.peer_presence_v2('00000000-0000-0000-0000-000000000002')), 'offline at once after leaving');
select pg_temp.expect((select last_active_at > now() - interval '1 minute' from public.peer_presence_v2('00000000-0000-0000-0000-000000000002')), 'last seen is when they left');
-- back again
select pg_temp.as_user('02');
select public.presence_ping();
select pg_temp.as_user('01');
select pg_temp.expect((select online from public.peer_presence_v2('00000000-0000-0000-0000-000000000002')), 'online again after returning');
-- an old app's touch keeps working and brings them online
select pg_temp.as_user('02');
select public.presence_offline();
reset role;
update public.user_presence set last_active_at = now() - interval '5 minutes', offline_at = now() - interval '6 minutes' where user_id = '00000000-0000-0000-0000-000000000002';
set role authenticated;
select pg_temp.as_user('02');
select public.touch_presence();
select pg_temp.as_user('01');
select pg_temp.expect((select online from public.peer_presence_v2('00000000-0000-0000-0000-000000000002')), 'old touch_presence still marks online');
-- idle too long = not online
reset role;
update public.user_presence set last_active_at = now() - interval '5 minutes', offline_at = null where user_id = '00000000-0000-0000-0000-000000000002';
set role authenticated;
select pg_temp.as_user('01');
select pg_temp.expect((select not online from public.peer_presence_v2('00000000-0000-0000-0000-000000000002')), 'no activity for minutes: not online');
-- strangers see nothing
select pg_temp.as_user('03');
select pg_temp.expect((select count(*) = 0 from public.peer_presence_v2('00000000-0000-0000-0000-000000000002')), 'a stranger sees no presence');
do $$ begin perform 1 from public.user_presence; raise exception 'CHECK FAILED: user_presence readable'; exception when insufficient_privilege then null; end $$;
