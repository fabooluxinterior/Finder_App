\set ON_ERROR_STOP 1
-- 01 sender, 02 receiver, 03 stranger.
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,3) i;
insert into public.profile_dob (user_id, dob) select id, date '1998-01-01' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, gender) select id, 'User '||right(id::text,2), 25, 'Kochi', '', 'man' from auth.users;
insert into public.swipes_and_requests (sender_id, receiver_id, action) values ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','follow_requested');
update public.swipes_and_requests set action = 'accepted';
insert into public.devices (id, user_id, curve25519, ed25519, platform) values
  ('d1000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000001', repeat('a', 43), repeat('b', 43), 'android'),
  ('d2000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000002', repeat('c', 43), repeat('d', 43), 'android'),
  ('d3000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000003', repeat('e', 43), repeat('f', 43), 'android');
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.expect_fail(sql text, label text) returns text language plpgsql as $$
begin execute sql; raise exception 'EXPECTED FAILURE DID NOT HAPPEN: %', label;
exception when others then if sqlerrm like 'EXPECTED FAILURE%' then raise; end if; return 'ok (blocked): ' || label; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000'||u, 'aal', 'aal1')::text, false); $$;
grant execute on all functions in schema pg_temp to authenticated;
-- The sender has chat access (Fast-Track).
update public.profiles set is_premium = true, premium_expires_at = now() + interval '30 days' where id = '00000000-0000-0000-0000-000000000001';

set role authenticated;
select pg_temp.as_user('01');
select pg_temp.expect_fail($$select public.schedule_message('00000000-0000-0000-0000-000000000002', gen_random_uuid(), 'd1000000-0000-4000-8000-000000000001', '[{"device_id":"d2000000-0000-4000-8000-000000000002","type":1,"ciphertext":"x"}]', now() - interval '1 minute')$$, 'a time in the past is refused');
select pg_temp.expect_fail($$select public.schedule_message('00000000-0000-0000-0000-000000000003', gen_random_uuid(), 'd1000000-0000-4000-8000-000000000001', '[{"device_id":"d3000000-0000-4000-8000-000000000003","type":1,"ciphertext":"x"}]', now() + interval '1 day')$$, 'only to someone you are connected to');
select pg_temp.expect_fail($$select public.schedule_message('00000000-0000-0000-0000-000000000002', gen_random_uuid(), 'd1000000-0000-4000-8000-000000000001', '[{"device_id":"d3000000-0000-4000-8000-000000000003","type":1,"ciphertext":"x"}]', now() + interval '1 day')$$, 'envelopes only for the two people''s devices');
select pg_temp.expect_fail($$select public.schedule_message('00000000-0000-0000-0000-000000000002', gen_random_uuid(), 'd2000000-0000-4000-8000-000000000002', '[{"device_id":"d2000000-0000-4000-8000-000000000002","type":1,"ciphertext":"x"}]', now() + interval '1 day')$$, 'not from someone else''s device');

create temporary table s1 as select public.schedule_message('00000000-0000-0000-0000-000000000002', '11111111-1111-4111-8111-111111111111',
  'd1000000-0000-4000-8000-000000000001', '[{"device_id":"d2000000-0000-4000-8000-000000000002","type":1,"ciphertext":"CIPHER-A"}]', now() + interval '2 minutes', 'Asia/Kolkata') as id;
grant select on s1 to authenticated;
select pg_temp.expect((select count(*) from public.my_scheduled_messages('00000000-0000-0000-0000-000000000002') where status = 'scheduled') = 1, 'it is waiting in the sender''s list');
select pg_temp.expect((select public.schedule_message('00000000-0000-0000-0000-000000000002', '11111111-1111-4111-8111-111111111111',
  'd1000000-0000-4000-8000-000000000001', '[{"device_id":"d2000000-0000-4000-8000-000000000002","type":1,"ciphertext":"CIPHER-A"}]', now() + interval '2 minutes') = (select id from s1)), 'the same request twice makes one row (idempotent)');
select pg_temp.expect((select count(*) from public.my_scheduled_messages()) = 1, 'still one');

-- Before its time nothing is delivered and the recipient sees nothing.
reset role;
select pg_temp.expect((select public.service_deliver_scheduled()) = 0, 'not delivered before its time');
select pg_temp.expect((select count(*) from public.messages) = 0 and (select count(*) from public.message_envelopes) = 0, 'no message exists yet');

-- Its time arrives (the job also works with nobody logged in).
update public.scheduled_messages set send_at = now() - interval '1 second', next_attempt_at = now() - interval '1 second';
select pg_temp.expect((select public.service_deliver_scheduled()) = 1, 'delivered when due');
select pg_temp.expect((select public.service_deliver_scheduled()) = 0, 'a second run does not send it again');
select pg_temp.expect((select count(*) from public.messages where client_msg_id = '11111111-1111-4111-8111-111111111111') = 1, 'exactly one message');
select pg_temp.expect((select ciphertext from public.message_envelopes) = 'CIPHER-A' and (select recipient_device_id from public.message_envelopes) = 'd2000000-0000-4000-8000-000000000002', 'the recipient gets the encrypted copy');
select pg_temp.expect((select status = 'sent' and message_id is not null and envelopes = '[]'::jsonb from public.scheduled_messages), 'marked sent, ciphertext released from the queue');

-- Cancel.
set role authenticated;
select pg_temp.as_user('01');
create temporary table s2 as select public.schedule_message('00000000-0000-0000-0000-000000000002', '22222222-2222-4222-8222-222222222222',
  'd1000000-0000-4000-8000-000000000001', '[{"device_id":"d2000000-0000-4000-8000-000000000002","type":1,"ciphertext":"CIPHER-B"}]', now() + interval '3 days') as id;
grant select on s2 to authenticated;
select pg_temp.as_user('02');
select pg_temp.expect(not public.cancel_scheduled_message((select id from s2)), 'the receiver cannot cancel it');
select pg_temp.expect((select count(*) from public.my_scheduled_messages()) = 0, 'and does not see it');
select pg_temp.as_user('01');
select pg_temp.expect(public.cancel_scheduled_message((select id from s2)), 'the sender can cancel it');
select pg_temp.expect(not public.cancel_scheduled_message((select id from s1)), 'a sent one cannot be cancelled');
reset role;
update public.scheduled_messages set send_at = now() - interval '1 second', next_attempt_at = now() - interval '1 second' where id = (select id from s2);
select pg_temp.expect((select public.service_deliver_scheduled()) = 0, 'a cancelled message is never delivered');

-- Failure: the sender lost chat access before the time came.
set role authenticated;
select pg_temp.as_user('01');
create temporary table s3 as select public.schedule_message('00000000-0000-0000-0000-000000000002', '33333333-3333-4333-8333-333333333333',
  'd1000000-0000-4000-8000-000000000001', '[{"device_id":"d2000000-0000-4000-8000-000000000002","type":1,"ciphertext":"CIPHER-C"}]', now() + interval '1 hour') as id;
grant select on s3 to authenticated;
reset role;
update public.profiles set is_premium = false, premium_expires_at = null where id = '00000000-0000-0000-0000-000000000001';
update public.scheduled_messages set send_at = now() - interval '1 second', next_attempt_at = now() - interval '1 second' where id = (select id from s3);
select pg_temp.expect((select public.service_deliver_scheduled()) = 0, 'not sent without chat access');
select pg_temp.expect((select status = 'failed' and last_error like '%Fast-Track%' from public.scheduled_messages where id = (select id from s3)), 'marked failed with the reason');
select pg_temp.expect((select count(*) from public.user_notifications where kind = 'scheduled_failed') = 1, 'the sender is told');
