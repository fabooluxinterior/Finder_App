\set ON_ERROR_STOP 1
-- Demo payments: server-controlled, time-limited, no self-granting, never downgrades a paid plan.
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,3) i;
insert into public.profile_dob (user_id, dob) select id, date '2000-01-15' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, avatar_urls)
  select id, 'User '||right(id::text,2), 25, 'Kochi', '', array[gen_random_uuid()::text] from auth.users;
-- 03 already has a paid plan that runs much longer than 30 days.
update public.profiles set is_premium = true, premium_expires_at = now() + interval '200 days' where id = '00000000-0000-0000-0000-000000000003';

create or replace function pg_temp.expect_fail(sql text, label text) returns text language plpgsql as $$
begin execute sql; raise exception 'EXPECTED FAILURE DID NOT HAPPEN: %', label;
exception when others then if sqlerrm like 'EXPECTED FAILURE%' then raise; end if; return 'ok (blocked): ' || label || ' -> ' || sqlerrm; end $$;
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000'||u, 'aal', 'aal1')::text, false); $$;
grant execute on all functions in schema pg_temp to authenticated;

set role authenticated;
select pg_temp.as_user('01');
-- no setting: live mode, activation refused
select pg_temp.expect(public.payments_mode() = 'live', 'no setting means live');
select pg_temp.expect_fail($$select public.demo_activate_fast_track()$$, 'activation refused while live');
select pg_temp.expect(not public.is_premium(auth.uid()), 'still free');

-- the app can't turn the mode on or grant itself access
select pg_temp.expect_fail($$insert into public.app_private_settings (key, value) values ('payments_demo_until', '2099-01-01')$$, 'no writing the setting');
select pg_temp.expect_fail($$update public.profiles set is_premium = true, premium_expires_at = now() + interval '1 year' where id = auth.uid()$$, 'no self-granting');

-- demo window open (server side only)
reset role;
insert into public.app_private_settings (key, value) values ('payments_demo_until', to_char(now() at time zone 'utc', 'YYYY-MM-DD'))
  on conflict (key) do update set value = excluded.value;
set role authenticated;
select pg_temp.as_user('01');
select pg_temp.expect(public.payments_mode() = 'demo', 'today is still inside the window');
select public.demo_activate_fast_track();
select pg_temp.expect((select premium_expires_at from public.profiles where id = auth.uid()) between now() + interval '29 days' and now() + interval '31 days', 'activates for 30 days');
select pg_temp.expect(public.is_premium(auth.uid()), 'now has Fast-Track');
select pg_temp.expect(public.has_fast_track(auth.uid()), 'and chat access');
select pg_temp.expect((select plan from public.my_access_status()) = 'fast_track', 'plan shows fast_track');
reset role;
select pg_temp.expect((select count(*) from public.security_events where user_id = '00000000-0000-0000-0000-000000000001' and kind = 'demo_fast_track_activated') = 1, 'logged');
set role authenticated;
select pg_temp.as_user('01');

-- a longer paid plan is never shortened
select pg_temp.as_user('03');
select public.demo_activate_fast_track();
select pg_temp.expect((select premium_expires_at from public.profiles where id = auth.uid()) > now() + interval '190 days', 'a paid 200-day plan is not shortened');

-- signed-out callers
select set_config('request.jwt.claim.sub', '', false), set_config('request.jwt.claims', '{}', false);
select pg_temp.expect_fail($$select public.demo_activate_fast_track()$$, 'not signed in');

-- the window closes by itself
reset role;
update public.app_private_settings set value = to_char((now() at time zone 'utc') - interval '1 day', 'YYYY-MM-DD') where key = 'payments_demo_until';
set role authenticated;
select pg_temp.as_user('02');
select pg_temp.expect(public.payments_mode() = 'live', 'yesterday means live again');
select pg_temp.expect_fail($$select public.demo_activate_fast_track()$$, 'refused after the date');

-- garbage setting never opens it
reset role;
update public.app_private_settings set value = 'soon' where key = 'payments_demo_until';
set role authenticated;
select pg_temp.as_user('02');
select pg_temp.expect(public.payments_mode() = 'live', 'an invalid setting stays live');
