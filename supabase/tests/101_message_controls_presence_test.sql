\set ON_ERROR_STOP 1
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,4) i;
insert into public.profile_dob (user_id, dob) select id, date '2000-01-15' from auth.users;
insert into public.profiles (id, full_name, age, city, bio) select id, 'U'||right(id::text,2), 25, 'Kochi', '' from auth.users;
-- 01 <-> 02 connected, 03 stranger, 04 blocked by 01
insert into public.swipes_and_requests (sender_id, receiver_id, action) values
  ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','follow_requested'),
  ('00000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000001','follow_requested');
update public.swipes_and_requests set action = 'accepted';
update public.profiles set is_premium = true where id in ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002');
create or replace function pg_temp.k(seed text, n int default 43) returns text language sql as $$ select left(rpad(encode(sha256(seed::bytea),'base64'), n, 'A'), n) $$;
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.expect_fail(sql text, label text) returns text language plpgsql as $$
begin execute sql; raise exception 'EXPECTED FAILURE DID NOT HAPPEN: %', label;
exception when others then if sqlerrm like 'EXPECTED FAILURE%' then raise; end if; return 'ok (blocked): ' || label; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000'||u, 'aal', 'aal1')::text, false); $$;
grant execute on all functions in schema pg_temp to authenticated;
create temp table ids (a uuid, b uuid);
grant all on ids to authenticated;

set role authenticated;
select pg_temp.as_user('01');
insert into ids (a) select public.register_device(pg_temp.k('a-c'), pg_temp.k('a-e'), 'Pixel', 'android');
select pg_temp.as_user('02');
update ids set b = public.register_device(pg_temp.k('b-c'), pg_temp.k('b-e'), 'Pixel', 'android');

-- an edit is stored as a hidden, already-read message of kind 1
select pg_temp.as_user('01');
select pg_temp.expect(public.send_message_control('00000000-0000-0000-0000-000000000002', gen_random_uuid(), (select a from ids),
  jsonb_build_array(jsonb_build_object('device_id',(select b from ids),'type',0,'ciphertext','X')), 1::smallint) is not null, 'edit control message is stored');
select pg_temp.expect((select kind = 1 and is_read from public.messages order by created_at desc limit 1), 'it is kind 1 and born read');
select pg_temp.expect_fail($$select public.send_message_control('00000000-0000-0000-0000-000000000002', gen_random_uuid(), (select a from ids),
  jsonb_build_array(jsonb_build_object('device_id',(select b from ids),'type',0,'ciphertext','X')), 0::smallint)$$, 'kind 0 is not accepted by the control function');
select pg_temp.expect_fail($$select public.send_message_control('00000000-0000-0000-0000-000000000003', gen_random_uuid(), (select a from ids),
  jsonb_build_array(jsonb_build_object('device_id',(select b from ids),'type',0,'ciphertext','X')), 2::smallint)$$, 'no control message to a stranger');
select pg_temp.expect((select count(*) from public.messages where kind = 0) = 0, 'normal messages untouched');

-- presence
select pg_temp.as_user('02');
select public.touch_presence();
select pg_temp.as_user('01');
select pg_temp.expect(public.peer_presence('00000000-0000-0000-0000-000000000002') is not null, 'a connected person sees last active');
select pg_temp.as_user('03');
select pg_temp.expect(public.peer_presence('00000000-0000-0000-0000-000000000002') is null, 'a stranger sees nothing');
select pg_temp.as_user('04');
select public.touch_presence();
select pg_temp.as_user('01');
select pg_temp.expect(public.peer_presence('00000000-0000-0000-0000-000000000004') is not null, 'connected before blocking');
select public.block_user('00000000-0000-0000-0000-000000000004');
select pg_temp.expect(public.peer_presence('00000000-0000-0000-0000-000000000004') is null, 'a blocked person is hidden');
select pg_temp.expect_fail($$select * from public.user_presence$$, 'table is not readable directly');
