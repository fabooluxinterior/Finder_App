\set ON_ERROR_STOP 1
-- Contact email (notifications only, not verified): collected once, private to its owner,
-- validated, never readable by other users or by direct table access, never blocks the account.
alter table auth.users add column if not exists email text;
alter table auth.users add column if not exists email_confirmed_at timestamptz;
insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-000000000001', null, null),                         -- phone only
  ('00000000-0000-0000-0000-000000000002', 'asha@example.com', now()),          -- has an auth email
  ('00000000-0000-0000-0000-000000000003', null, null);
insert into public.profile_dob (user_id, dob) select id, date '1998-01-01' from auth.users;
insert into public.profiles (id, full_name, age, city, occupation)
select id, 'User', 26, 'Kochi', 'Teacher' from auth.users;
update public.profiles set is_onboarded = true;
-- Same copy the migration runs for accounts that already existed.
insert into public.user_contacts (user_id, email)
select id, lower(btrim(email)) from auth.users where email is not null on conflict do nothing;

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
select pg_temp.expect(public.my_contact_email() is null, 'phone-only account has no contact email yet');
select pg_temp.expect((select show_prompt and level = 'optional' from public.my_profile_updates() where key = 'email'),
  'asked, optionally, never blocking');
select public.set_contact_email('  Asha.K@Example.COM ');
select pg_temp.expect(public.my_contact_email() = 'asha.k@example.com', 'stored trimmed and lowercased');
select pg_temp.expect(not exists (select 1 from public.my_profile_updates() where key = 'email'), 'no longer asked once stored');
select pg_temp.expect(public.my_support_email() = 'asha.k@example.com', 'support uses the contact email');
select public.set_contact_email('new@example.com');
select pg_temp.expect(public.my_contact_email() = 'new@example.com', 'can be changed');

select pg_temp.expect_fail($$select public.set_contact_email('not-an-email')$$, 'no @');
select pg_temp.expect_fail($$select public.set_contact_email('a@b')$$, 'no dot');
select pg_temp.expect_fail($$select public.set_contact_email('a b@x.com')$$, 'space');
select pg_temp.expect_fail($$select public.set_contact_email(repeat('a', 250) || '@x.com')$$, 'too long');
select pg_temp.expect_fail($$select public.set_contact_email(null)$$, 'null');
select pg_temp.expect_fail($$select * from public.user_contacts$$, 'no direct table read');
select pg_temp.expect_fail($$insert into public.user_contacts (user_id, email) values (auth.uid(), 'x@y.com')$$, 'no direct insert');
select pg_temp.expect_fail($$update public.user_contacts set email = 'x@y.com'$$, 'no direct update');

select pg_temp.as_user('02');
select pg_temp.expect(public.my_contact_email() = 'asha@example.com', 'existing email was copied, not asked again');
select pg_temp.expect(not exists (select 1 from public.my_profile_updates() where key = 'email'), 'not prompted');
select pg_temp.as_user('03');
select pg_temp.expect(public.my_contact_email() is null, 'nobody can read another person''s email');
select pg_temp.expect((select count(*) from public.profiles where occupation = 'Teacher') = 3, 'profiles untouched');
