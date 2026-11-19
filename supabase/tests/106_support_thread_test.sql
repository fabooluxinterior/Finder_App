\set ON_ERROR_STOP 1
alter table auth.users add column if not exists email text;
insert into auth.users (id, email) select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid, 'u'||i||'@example.com' from generate_series(1,4) i;
insert into public.profile_dob (user_id, dob) select id, date '1998-01-01' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, gender) select id, 'User '||right(id::text,2), 25, 'Kochi', '', 'man' from auth.users;
insert into public.staff_roles (user_id, role) values ('00000000-0000-0000-0000-000000000003', 'moderator');
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.expect_fail(sql text, label text) returns text language plpgsql as $$
begin execute sql; raise exception 'EXPECTED FAILURE DID NOT HAPPEN: %', label;
exception when others then if sqlerrm like 'EXPECTED FAILURE%' then raise; end if; return 'ok (blocked): ' || label; end $$;
create or replace function pg_temp.as_user(u text, aal text default 'aal1') returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000'||u, 'aal', aal)::text, false); $$;
grant execute on all functions in schema pg_temp to authenticated;
set role authenticated;

select pg_temp.as_user('01');
create temporary table t1 as select * from public.submit_support_ticket('account', 'Account suspended', 'My account is suspended, please help');
grant select on t1 to authenticated;
select pg_temp.expect((select count(*) from public.my_ticket_thread((select id from t1))) = 1, 'thread starts with the first message');
select public.reply_to_ticket((select id from t1), 'Any update please?');
select pg_temp.expect((select count(*) from public.my_ticket_thread((select id from t1))) = 2, 'follow-up added');
select pg_temp.expect_fail($$select public.reply_to_ticket((select id from t1), '   ')$$, 'empty message refused');

select pg_temp.as_user('02');
select pg_temp.expect_fail($$select * from public.my_ticket_thread((select id from t1))$$, 'another user cannot read the thread');
select pg_temp.expect_fail($$select public.reply_to_ticket((select id from t1), 'hi')$$, 'another user cannot reply');
select pg_temp.expect_fail($$select * from public.mod_list_tickets_v2('open')$$, 'user cannot list tickets as staff');

select pg_temp.as_user('03', 'aal1');
select pg_temp.expect_fail($$select * from public.mod_list_tickets_v2('open')$$, 'staff without 2-step refused');
select pg_temp.as_user('03', 'aal2');
select pg_temp.expect((select user_name = 'User 01' and messages = 1 from public.mod_list_tickets_v2('open') where id = (select id from t1)), 'staff list shows the name and message count');
select pg_temp.expect((select count(*) from public.mod_ticket_thread((select id from t1))) = 2, 'staff read the thread');
select public.mod_reply_ticket((select id from t1), 'Hi, we are looking into it.');
select pg_temp.expect((select status from public.mod_list_tickets_v2('all') where id = (select id from t1)) = 'waiting_for_user', 'reply moves the ticket to waiting for the user');

select pg_temp.as_user('01');
select pg_temp.expect((select bool_or(from_staff) from public.my_ticket_thread((select id from t1))), 'the person sees the team reply');
select pg_temp.expect((select count(*) from public.user_notifications where kind = 'ticket_reply') = 1, 'the person is notified');
select public.reply_to_ticket((select id from t1), 'Thank you');
select pg_temp.as_user('03', 'aal2');
select pg_temp.expect((select status from public.mod_list_tickets_v2('all') where id = (select id from t1)) = 'in_progress', 'a reply from the person re-opens it');
