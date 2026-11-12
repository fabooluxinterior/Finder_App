\set ON_ERROR_STOP 1
-- Push notifications: token registration, admin-only campaigns, audiences, in-app copy, no token leaks.
-- 01 free  02 Fast-Track  03 free, no phone match  04 admin (MFA)
alter table auth.users add column if not exists phone text;
insert into auth.users (id, phone) select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid, '9188774'||lpad(i::text,3,'0') from generate_series(1,4) i;
insert into public.profile_dob (user_id, dob) select id, date '1998-01-01' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, avatar_urls, is_onboarded)
  select id, 'User '||right(id::text,2), 26, 'Kochi', '', array[gen_random_uuid()::text], true from auth.users;
update public.profiles set is_premium = true, premium_expires_at = now() + interval '30 days' where id = '00000000-0000-0000-0000-000000000002';
insert into public.staff_roles (user_id, role) values ('00000000-0000-0000-0000-000000000004', 'admin');

create or replace function pg_temp.expect_fail(sql text, label text) returns text language plpgsql as $$
begin execute sql; raise exception 'EXPECTED FAILURE DID NOT HAPPEN: %', label;
exception when others then if sqlerrm like 'EXPECTED FAILURE%' then raise; end if; return 'ok (blocked): ' || label || ' -> ' || sqlerrm; end $$;
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.as_user(u text, aal text default 'aal1') returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000'||u, 'aal', aal)::text, false); $$;
grant execute on all functions in schema pg_temp to authenticated;

set role authenticated;
select pg_temp.as_user('01');
select public.register_push_token(repeat('a', 40), 'android');
select pg_temp.as_user('02');
select public.register_push_token(repeat('b', 40), 'android');
select pg_temp.expect_fail($$select public.register_push_token('short', 'android')$$, 'too-short token refused');
select pg_temp.expect_fail($$select * from public.push_devices$$, 'tokens are not readable by users');
select pg_temp.expect_fail($$select * from public.push_campaigns$$, 'campaigns are not readable by users');
select pg_temp.expect_fail($$select * from public.push_campaign_tokens(gen_random_uuid())$$, 'users cannot pull tokens');
select pg_temp.expect_fail($$select * from public.mod_push_prepare('Hi', 'Hello', 'all')$$, 'a normal user cannot send');

-- a token follows the person who signed in last; unregister only touches your own
select pg_temp.as_user('03');
select public.register_push_token(repeat('a', 40), 'android');
select public.unregister_push_token(repeat('b', 40));
reset role;
select pg_temp.expect((select user_id from public.push_devices where token = repeat('a', 40)) = '00000000-0000-0000-0000-000000000003', 'token moved to the latest user');
select pg_temp.expect((select count(*) from public.push_devices where token = repeat('b', 40)) = 1, 'someone else cannot remove my token');
set role authenticated;

-- a moderator-level session (no MFA) cannot send; admin with MFA can
select pg_temp.as_user('04', 'aal1');
select pg_temp.expect_fail($$select * from public.mod_push_prepare('Hi', 'Hello', 'all')$$, 'admin without two-step cannot send');
select pg_temp.as_user('04', 'aal2');
select pg_temp.expect_fail($$select * from public.mod_push_prepare('', 'Hello', 'all')$$, 'empty title refused');
select pg_temp.expect_fail($$select * from public.mod_push_prepare('Hi', repeat('x', 241), 'all')$$, 'long message refused');
select pg_temp.expect_fail($$select * from public.mod_push_prepare('Hi', 'Hello', 'everyone')$$, 'unknown audience refused');
select pg_temp.expect_fail($$select * from public.mod_push_prepare('Hi', 'Hello', 'user', '9000000000')$$, 'unknown number refused');

select pg_temp.expect((select recipients from public.mod_push_prepare('Free offer', 'Hello free users', 'free')) = 3, 'free audience = users without Fast-Track (incl. the admin account)');
select pg_temp.expect((select recipients from public.mod_push_prepare('Plan news', 'Hello plan users', 'plan')) = 1, 'plan audience = Fast-Track users');
select pg_temp.expect((select recipients from public.mod_push_prepare('Welcome', 'Hello all', 'all')) = 4, 'all audience');
select pg_temp.expect((select recipients from public.mod_push_prepare('Just you', 'Hello you', 'user', '+91 91887 74002')) = 1, 'one user by mobile number');
reset role;
select pg_temp.expect((select count(*) from public.user_notifications where kind = 'announcement') = 3 + 1 + 4 + 1, 'in-app copies created');
select pg_temp.expect((select count(*) from public.user_notifications where kind = 'announcement' and user_id = '00000000-0000-0000-0000-000000000002' and title = 'Just you') = 1, 'the single-user message reached only that user');
select pg_temp.expect((select count(*) from public.security_events where kind = 'push_campaign_sent') = 4, 'every send is logged');

-- service side: tokens of the audience only, paged, and users cannot reach it
select pg_temp.expect((select count(*) from public.push_campaign_tokens((select id from public.push_campaigns where title = 'Welcome'))) = 2, 'tokens for the all audience');
select pg_temp.expect((select count(*) from public.push_campaign_tokens((select id from public.push_campaigns where title = 'Plan news'))) = 1, 'tokens for the plan audience');
select pg_temp.expect((select count(*) from public.push_campaign_tokens((select id from public.push_campaigns where title = 'Welcome'), repeat('a', 40))) = 1, 'paging after a token');
select public.push_campaign_finish((select id from public.push_campaigns where title = 'Welcome'), 2, 0);
select pg_temp.expect((select delivered from public.push_campaigns where title = 'Welcome') = 2, 'results are saved');

set role authenticated;
select pg_temp.as_user('04', 'aal2');
select pg_temp.expect((select count(*) from public.mod_list_push_campaigns()) = 4, 'admin sees the log');
select pg_temp.as_user('01');
select pg_temp.expect_fail($$select * from public.mod_list_push_campaigns()$$, 'users cannot see the log');
