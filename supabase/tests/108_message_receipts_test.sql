\set ON_ERROR_STOP 1
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,3) i;
insert into public.profile_dob (user_id, dob) select id, date '1998-01-01' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, gender) select id, 'User '||right(id::text,2), 25, 'Kochi', '', 'man' from auth.users;
insert into public.swipes_and_requests (sender_id, receiver_id, action) values ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','follow_requested');
update public.swipes_and_requests set action = 'accepted';
insert into public.messages (id, sender_id, receiver_id, client_msg_id, kind) values
  ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', gen_random_uuid(), 0),
  ('aaaaaaaa-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', gen_random_uuid(), 0);
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000'||u, 'aal', 'aal1')::text, false); $$;
grant execute on all functions in schema pg_temp to authenticated;
set role authenticated;

select pg_temp.as_user('01');
select pg_temp.expect((select delivered_at is null and read_at is null from public.messages where id = 'aaaaaaaa-0000-4000-8000-000000000001'), 'a new message is only sent');
select pg_temp.expect((select public.mark_delivered(array['aaaaaaaa-0000-4000-8000-000000000001']::uuid[])) = 0, 'the sender cannot mark their own message delivered');

select pg_temp.as_user('03');
select pg_temp.expect((select public.mark_delivered(array['aaaaaaaa-0000-4000-8000-000000000001']::uuid[])) = 0, 'a stranger cannot mark it delivered');

select pg_temp.as_user('02');
select pg_temp.expect((select public.mark_delivered(array['aaaaaaaa-0000-4000-8000-000000000001']::uuid[])) = 1, 'the receiver marks it delivered');
select pg_temp.expect((select public.mark_delivered(array['aaaaaaaa-0000-4000-8000-000000000001']::uuid[])) = 0, 'the first delivery time is kept');
update public.messages set is_read = true where receiver_id = auth.uid() and id = 'aaaaaaaa-0000-4000-8000-000000000001';
select pg_temp.expect((select read_at is not null and delivered_at is not null and delivered_at <= read_at from public.messages where id = 'aaaaaaaa-0000-4000-8000-000000000001'), 'reading fills read_at (an older app only sets is_read)');
update public.messages set is_read = true where receiver_id = auth.uid() and id = 'aaaaaaaa-0000-4000-8000-000000000002';
select pg_temp.expect((select delivered_at is not null from public.messages where id = 'aaaaaaaa-0000-4000-8000-000000000002'), 'reading also implies delivered');
select public.mark_listened('aaaaaaaa-0000-4000-8000-000000000002');
select pg_temp.expect((select listened_at is not null from public.messages where id = 'aaaaaaaa-0000-4000-8000-000000000002'), 'listened time stored');

select pg_temp.as_user('01');
select pg_temp.expect((select read_at is not null and delivered_at is not null from public.messages where id = 'aaaaaaaa-0000-4000-8000-000000000001'), 'the sender can read the receipt times');
select pg_temp.expect((select count(*) from public.messages where delivered_at is not null) = 2, 'both receipts visible to the sender');
