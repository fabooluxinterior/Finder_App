\set ON_ERROR_STOP 1
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,3) i;
insert into public.profile_dob (user_id, dob) select id, date '1998-01-01' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, gender) select id, 'User '||right(id::text,2), 25, 'Kochi', '', 'man' from auth.users;
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

-- Messages: an old one (before the setting), a fresh one, and an expired one sent after the setting.
insert into public.messages (sender_id, receiver_id, client_msg_id, kind, created_at) values
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', gen_random_uuid(), 0, now() - interval '40 days');
set role authenticated;
select pg_temp.as_user('01');
select pg_temp.expect((select count(*) from public.get_disappearing('00000000-0000-0000-0000-000000000002')) = 0, 'off by default');
select pg_temp.expect_fail($$select public.set_disappearing('00000000-0000-0000-0000-000000000002', 3600)$$, 'only the three durations (and off)');
select pg_temp.expect_fail($$select public.set_disappearing('00000000-0000-0000-0000-000000000003', 86400)$$, 'not with someone you are not connected to');
select public.set_disappearing('00000000-0000-0000-0000-000000000002', 86400);
select pg_temp.as_user('02');
select pg_temp.expect((select seconds = 86400 and set_by = '00000000-0000-0000-0000-000000000001' from public.get_disappearing('00000000-0000-0000-0000-000000000001')), 'the other person sees it and who set it');
select pg_temp.expect((select count(*) from public.get_disappearing('00000000-0000-0000-0000-000000000003')) = 0, 'no setting with a stranger');
reset role;
-- sent after the setting, now older than 24 h; and a recent one
insert into public.messages (sender_id, receiver_id, client_msg_id, kind, created_at) values
  ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', gen_random_uuid(), 0, now() + interval '1 second'),
  ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', gen_random_uuid(), 0, now());
update public.chat_disappearing set set_at = now() - interval '3 days';
insert into public.messages (sender_id, receiver_id, client_msg_id, kind, created_at) values
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', gen_random_uuid(), 0, now() - interval '2 days');
set role authenticated;
select pg_temp.as_user('01');
select pg_temp.expect((select public.purge_expired_messages('00000000-0000-0000-0000-000000000002')) = 1, 'only the expired message sent after turning it on is removed');
select pg_temp.expect((select public.purge_expired_messages('00000000-0000-0000-0000-000000000002')) = 0, 'nothing more to remove');
reset role;
select pg_temp.expect((select count(*) from public.messages) = 3, 'the 40-day-old message from before the setting and the recent ones remain');
set role authenticated;
select pg_temp.as_user('03');
select pg_temp.expect((select public.purge_expired_messages('00000000-0000-0000-0000-000000000001')) = 0, 'a stranger cannot purge another chat');
select pg_temp.as_user('02');
select public.set_disappearing('00000000-0000-0000-0000-000000000001', 0);
select pg_temp.expect((select seconds from public.get_disappearing('00000000-0000-0000-0000-000000000001')) = 0, 'either person can turn it off');
