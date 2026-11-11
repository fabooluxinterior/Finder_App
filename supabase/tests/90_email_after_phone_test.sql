\set ON_ERROR_STOP 1
-- Email added after mobile sign-up: phone-only accounts are asked (optional, never blocked),
-- accounts with a confirmed email are not, and no address is exposed.
alter table auth.users add column if not exists email text;
alter table auth.users add column if not exists email_confirmed_at timestamptz;
insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-000000000001', null, null),                         -- phone only
  ('00000000-0000-0000-0000-000000000002', 'asha@example.com', now()),          -- confirmed
  ('00000000-0000-0000-0000-000000000003', 'pending@example.com', null);        -- not yet confirmed
insert into public.profile_dob (user_id, dob) select id, date '1998-01-01' from auth.users;
insert into public.profiles (id, full_name, age, city, occupation)
select id, 'User', 26, 'Kochi', 'Teacher' from auth.users;
update public.profiles set is_onboarded = true;

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
select pg_temp.expect(not public.my_email_status(), 'phone-only account has no email');
select pg_temp.expect((select show_prompt and level = 'optional' from public.my_profile_updates() where key = 'email'),
  'phone-only account is asked, optionally');
select pg_temp.as_user('02');
select pg_temp.expect(public.my_email_status(), 'confirmed email');
select pg_temp.expect(not exists (select 1 from public.my_profile_updates() where key = 'email'), 'confirmed email is never asked');
select pg_temp.as_user('03');
select pg_temp.expect(not public.my_email_status(), 'unconfirmed email does not count');
select pg_temp.expect_fail($$select public.has_confirmed_email('00000000-0000-0000-0000-000000000002')$$, 'client probes another account');

reset role;
update auth.users set email = 'new@example.com', email_confirmed_at = now() where id = '00000000-0000-0000-0000-000000000001';
set role authenticated;
select pg_temp.as_user('01');
select pg_temp.expect(not exists (select 1 from public.my_profile_updates() where key = 'email'), 'confirming the email completes it');
select pg_temp.expect((select is_onboarded and occupation = 'Teacher' from public.profiles where id = auth.uid()), 'profile untouched');
