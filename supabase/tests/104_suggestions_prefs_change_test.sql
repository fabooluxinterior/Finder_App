\set ON_ERROR_STOP 1
-- Changing Discovery preferences takes effect at once, also for people already shown today.
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,3) i;
insert into public.profile_dob (user_id, dob) select id, date '1998-01-01' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, gender, interest_tags)
select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid, 'User '||i, 25, 'Kochi', '',
       case i when 1 then 'man' when 2 then 'woman' else 'man' end, '{Chai,Chess,Poetry,Baking,Yoga}'
  from generate_series(1,3) i;
update public.profiles set is_onboarded = true,
  photo_urls = array[gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text];
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false); $$;
grant execute on all functions in schema pg_temp to authenticated;
set role authenticated;
select pg_temp.as_user('01');
select pg_temp.expect((select count(*) from public.get_suggestions('main', 10, '{}')) = 2, 'everyone: a woman and a man are suggested');
update public.profiles set pref_genders = '{man}' where id = auth.uid();
select pg_temp.expect((select count(*) from public.get_suggestions('main', 10, '{}') where gender <> 'man') = 0, 'Men only: no women, even those shown earlier today');
select pg_temp.expect((select count(*) from public.get_suggestions('main', 10, '{}')) = 1, 'Men only: the man is still there');
update public.profiles set pref_genders = '{woman}' where id = auth.uid();
select pg_temp.expect((select count(*) from public.get_suggestions('main', 10, '{}') where gender <> 'woman') = 0, 'Women only: no men');
select pg_temp.expect((select count(*) from public.get_suggestions('main', 10, '{}')) = 1, 'Women only: the woman is there');
