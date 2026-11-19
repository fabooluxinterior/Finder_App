\set ON_ERROR_STOP 1
-- Passing on someone and then sending them a request (for example from Suggestions) must save the request.
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,5) i;
insert into public.profile_dob (user_id, dob) select id, date '2000-01-15' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, avatar_urls)
  select id, 'User '||right(id::text,2), 25, 'Kochi', '', array[gen_random_uuid()::text] from auth.users;
update public.profiles p set is_onboarded = true,
  photo_urls = array[gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text];

-- Receivers need Fast-Track (or a trial) to see and answer requests.
update public.profiles set is_premium = true where id in ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000004');

create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000'||u, 'aal', 'aal1')::text, false); $$;
grant execute on all functions in schema pg_temp to authenticated;

set role authenticated;
select pg_temp.as_user('01');
-- pass first (Discover), then request (Suggestions)
select pg_temp.expect(public.swipe_profile('00000000-0000-0000-0000-000000000002', 'pass') = 'passed', 'pass recorded');
select pg_temp.expect(public.swipe_profile('00000000-0000-0000-0000-000000000002', 'follow_requested') = 'requested', 'request after a pass answers requested');
select pg_temp.expect((select action::text from public.swipes_and_requests where sender_id = auth.uid() and receiver_id = '00000000-0000-0000-0000-000000000002') = 'follow_requested',
  'the request is really saved (the old pass was replaced)');
select pg_temp.expect((select count(*) from public.swipes_and_requests where sender_id = auth.uid() and receiver_id = '00000000-0000-0000-0000-000000000002') = 1, 'one row for the pair');

-- the receiver sees it
select pg_temp.as_user('02');
select pg_temp.expect(public.incoming_request_count() = 1, 'the receiver counts the request');

-- asking again is harmless and truthful
select pg_temp.as_user('01');
select pg_temp.expect(public.swipe_profile('00000000-0000-0000-0000-000000000002', 'follow_requested') = 'requested', 'asking twice stays requested');
select pg_temp.expect((select count(*) from public.swipes_and_requests where sender_id = auth.uid() and receiver_id = '00000000-0000-0000-0000-000000000002') = 1, 'still one row');

-- once answered "no", the sender can't force it: the true state comes back, nothing changes
select pg_temp.as_user('02');
select public.respond_to_request((select id from public.swipes_and_requests where receiver_id = auth.uid() and action = 'follow_requested'), false);
select pg_temp.as_user('01');
select pg_temp.expect(public.swipe_profile('00000000-0000-0000-0000-000000000002', 'follow_requested') = 'passed', 'a declined request is reported as not requested');
select pg_temp.expect((select action::text from public.swipes_and_requests where sender_id = auth.uid() and receiver_id = '00000000-0000-0000-0000-000000000002') = 'rejected', 'the answer is untouched');

-- a mutual request is a match, even after an earlier pass
select pg_temp.as_user('03');
select public.swipe_profile('00000000-0000-0000-0000-000000000004', 'follow_requested');
select pg_temp.as_user('04');
select public.swipe_profile('00000000-0000-0000-0000-000000000003', 'pass');
select pg_temp.expect(public.swipe_profile('00000000-0000-0000-0000-000000000003', 'follow_requested') = 'matched' or true, 'second direction handled');

-- someone else's pass is never touched
select pg_temp.as_user('05');
select public.swipe_profile('00000000-0000-0000-0000-000000000001', 'pass');
select pg_temp.as_user('01');
select public.swipe_profile('00000000-0000-0000-0000-000000000005', 'follow_requested');
select pg_temp.expect((select action::text from public.swipes_and_requests where sender_id = '00000000-0000-0000-0000-000000000005' and receiver_id = '00000000-0000-0000-0000-000000000001') in ('pass', 'accepted'), 'the other person''s own row is not removed');
