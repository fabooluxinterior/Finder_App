\set ON_ERROR_STOP 1
-- 01 and 02 are connected; 03 is a stranger; 04 is blocked by 01 (also connected before).
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,4) i;
insert into public.profile_dob (user_id, dob) select id, date '2000-01-15' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, avatar_urls)
  select id, 'User '||right(id::text,2), 25, 'Kochi', '', array[gen_random_uuid()::text] from auth.users;
insert into public.swipes_and_requests (sender_id, receiver_id, action) values
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'follow_requested'),
  ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001', 'follow_requested');
update public.swipes_and_requests set action = 'accepted', responded_at = now();
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000'||u, 'aal', 'aal1')::text, false); $$;
grant execute on all functions in schema pg_temp to authenticated;

set role authenticated;
select pg_temp.as_user('01');
select pg_temp.expect(public.chat_topic_allowed('chat:00000000-0000-0000-0000-000000000001_00000000-0000-0000-0000-000000000002'), 'a member of a connected pair may use the channel');
select pg_temp.as_user('02');
select pg_temp.expect(public.chat_topic_allowed('chat:00000000-0000-0000-0000-000000000001_00000000-0000-0000-0000-000000000002'), 'and so may the other person');
select pg_temp.as_user('03');
select pg_temp.expect(not public.chat_topic_allowed('chat:00000000-0000-0000-0000-000000000001_00000000-0000-0000-0000-000000000002'), 'a stranger may not listen in');
select pg_temp.as_user('01');
select pg_temp.expect(not public.chat_topic_allowed('chat:00000000-0000-0000-0000-000000000001_00000000-0000-0000-0000-000000000003'), 'no channel with someone you are not connected to');
select pg_temp.expect(not public.chat_topic_allowed('chat:00000000-0000-0000-0000-000000000002_00000000-0000-0000-0000-000000000001'), 'only the canonical (sorted) name is accepted');
select pg_temp.expect(not public.chat_topic_allowed('chat:garbage'), 'malformed names are refused');
select pg_temp.expect(not public.chat_topic_allowed(null), 'null is refused');
-- blocked pairs are cut off
reset role;
insert into public.blocks (blocker_id, blocked_id) values ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004');
set role authenticated;
select pg_temp.as_user('01');
select pg_temp.expect(not public.chat_topic_allowed('chat:00000000-0000-0000-0000-000000000001_00000000-0000-0000-0000-000000000004'), 'a blocked pair has no channel');
-- signed out
select set_config('request.jwt.claim.sub', '', false), set_config('request.jwt.claims', '{}', false);
select pg_temp.expect(not public.chat_topic_allowed('chat:00000000-0000-0000-0000-000000000001_00000000-0000-0000-0000-000000000002'), 'signed-out callers are refused');
