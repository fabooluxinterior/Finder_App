\set ON_ERROR_STOP 1
-- Re-registering the same phone any number of times never locks the user out of chat.
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,2) i;
insert into public.profile_dob (user_id, dob) select id, date '2000-01-15' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, avatar_urls)
  select id, 'User '||right(id::text,2), 25, 'Kochi', '', array[gen_random_uuid()::text] from auth.users;
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.expect_fail(sql text, label text) returns text language plpgsql as $$
begin execute sql; raise exception 'EXPECTED FAILURE DID NOT HAPPEN: %', label;
exception when others then if sqlerrm like 'EXPECTED FAILURE%' then raise; end if; return 'ok (blocked): ' || label; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000'||u, 'aal', 'aal1')::text, false); $$;
grant execute on all functions in schema pg_temp to authenticated;

set role authenticated;
select pg_temp.as_user('01');
select public.register_device(repeat('a', 43), repeat('b', 43), 'Pixel', 'android') as first_id \gset
select pg_temp.expect((select count(*) from (select public.register_device(repeat('a', 43), repeat('b', 43), 'Pixel', 'android') from generate_series(1, 20)) s) = 20, 'the same phone can re-register 20 times');
select pg_temp.expect(public.register_device(repeat('a', 43), repeat('b', 43), 'Pixel', 'android') = :'first_id'::uuid, 'always the same device id');

-- creating new devices is still limited (5 per hour, 5 devices)
select public.register_device(repeat('c', 43), repeat('d', 43), 'Two', 'android');
select public.register_device(repeat('e', 43), repeat('f', 43), 'Three', 'android');
select public.register_device(repeat('g', 43), repeat('h', 43), 'Four', 'android');
select public.register_device(repeat('i', 43), repeat('j', 43), 'Five', 'android');
select pg_temp.expect_fail($$select public.register_device(repeat('k', 43), repeat('l', 43), 'Six', 'android')$$, 'a sixth device is refused');
select pg_temp.expect(public.register_device(repeat('a', 43), repeat('b', 43), 'Pixel', 'android') = :'first_id'::uuid, 'the first phone still works at the limit');
