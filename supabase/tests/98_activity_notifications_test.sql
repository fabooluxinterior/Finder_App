\set ON_ERROR_STOP 1
-- 01 Fast-Track (receiver), 02 requester, 03 free receiver, 04 blocked requester, 05 hasn't opened suggestions.
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,5) i;
insert into public.profile_dob (user_id, dob) select id, date '2000-01-15' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, avatar_urls, is_onboarded)
  select id, case right(id::text,2) when '02' then 'Meera Nair' else 'User '||right(id::text,2) end, 25, 'Kochi', '', array[gen_random_uuid()::text], true from auth.users;
update public.profiles set photo_urls = array[gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text];
update public.profiles set is_premium = true, premium_expires_at = now() + interval '30 days' where id = '00000000-0000-0000-0000-000000000001';
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;

-- A request to a Fast-Track user names the sender.
insert into public.swipes_and_requests (sender_id, receiver_id, action) values ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'follow_requested');
select pg_temp.expect((select title from public.user_notifications where user_id = '00000000-0000-0000-0000-000000000001' and kind = 'request') = 'Meera sent you a request', 'receiver with Fast-Track sees the name');
-- A free user is never told who.
insert into public.swipes_and_requests (sender_id, receiver_id, action) values ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000003', 'follow_requested');
select pg_temp.expect((select title || body from public.user_notifications where user_id = '00000000-0000-0000-0000-000000000003' and kind = 'request') not like '%Meera%', 'free receiver is not told the name');
-- Accepting tells the requester.
update public.swipes_and_requests set action = 'accepted', responded_at = now() where sender_id = '00000000-0000-0000-0000-000000000002' and receiver_id = '00000000-0000-0000-0000-000000000001';
select pg_temp.expect((select title from public.user_notifications where user_id = '00000000-0000-0000-0000-000000000002' and kind = 'match') = 'You''re connected with User', 'requester hears about the connection');
-- A decline says nothing.
update public.swipes_and_requests set action = 'rejected', responded_at = now() where sender_id = '00000000-0000-0000-0000-000000000002' and receiver_id = '00000000-0000-0000-0000-000000000003';
select pg_temp.expect((select count(*) from public.user_notifications where user_id = '00000000-0000-0000-0000-000000000002') = 1, 'a decline creates no notice');
-- A blocked person's request is silent.
insert into public.blocks (blocker_id, blocked_id) values ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004');
do $$ begin
  insert into public.swipes_and_requests (sender_id, receiver_id, action) values ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001', 'follow_requested');
  raise exception 'EXPECTED FAILURE DID NOT HAPPEN: blocked request accepted';
exception when insufficient_privilege then null; end $$;
select pg_temp.expect((select count(*) from public.user_notifications where user_id = '00000000-0000-0000-0000-000000000001' and kind = 'request') = 1, 'blocked sender is refused and creates no notice');

-- Suggestion nudge: once, only for people who have not opened Suggestions today.
insert into public.recommendation_daily (user_id, day, shown) values ('00000000-0000-0000-0000-000000000001', current_date, 3);
select pg_temp.expect(public.service_suggestion_nudges() = 4, 'nudge goes to the four people who have not opened Suggestions');
select pg_temp.expect(public.service_suggestion_nudges() = 0, 'and only once a day');
select pg_temp.expect((select count(*) from public.user_notifications where kind = 'suggestions' and user_id = '00000000-0000-0000-0000-000000000001') = 0, 'not to someone who opened Suggestions today');

-- The push trigger never blocks writes, even with push configured but unreachable.
insert into public.app_private_settings (key, value) values ('push_webhook_url', 'http://127.0.0.1:9/none'), ('push_webhook_secret', 'x')
  on conflict (key) do update set value = excluded.value;
insert into public.user_notifications (user_id, kind, title, body) values ('00000000-0000-0000-0000-000000000001', 'announcement', 'Hi', 'There');
select pg_temp.expect((select count(*) from public.user_notifications where kind = 'announcement') = 1, 'announcements and unreachable push never block an insert');

set role authenticated;
do $$ begin perform public.service_suggestion_nudges(); raise exception 'EXPECTED FAILURE DID NOT HAPPEN';
exception when insufficient_privilege then null; end $$;
