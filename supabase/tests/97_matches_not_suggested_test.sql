\set ON_ERROR_STOP 1
-- 01 me, 02 requested me and I accepted (a match), 03 passed in Discovery, 04 untouched.
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,4) i;
insert into public.profile_dob (user_id, dob) select id, date '2000-01-15' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, avatar_urls, is_onboarded, gender, interest_tags)
  select id, 'User '||right(id::text,2), 25, 'Kochi', 'Rain and chai.', array[gen_random_uuid()::text], true,
         case when right(id::text,2) = '01' then 'woman' else 'man' end, '{Chai,Poetry,Chess,Cycling,Baking}'::text[]
    from auth.users;
update public.profiles set photo_urls = array[gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text];
update public.profiles set is_premium = true, premium_expires_at = now() + interval '30 days';
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000'||u, 'aal', 'aal1')::text, false); $$;
grant execute on all functions in schema pg_temp to authenticated;

set role authenticated;
-- 02 asks me; I accept.
select pg_temp.as_user('02');
select public.swipe_profile('00000000-0000-0000-0000-000000000001', 'follow_requested');
select pg_temp.as_user('01');
select public.respond_to_request((select id from public.swipes_and_requests where receiver_id = auth.uid() and action = 'follow_requested'), true);

-- Suggestions were shown earlier today (history), including the person I just matched with.
reset role;
insert into public.recommendation_history (user_id, target_id, section, score, reasons, shown_at)
values ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'main', 80, '[]', now());
set role authenticated;
select pg_temp.as_user('01');
select public.swipe_profile('00000000-0000-0000-0000-000000000003', 'pass');
create temp table _s as select id from public.get_suggestions('main', 10);
select pg_temp.expect(not exists (select 1 from _s where id = '00000000-0000-0000-0000-000000000002'), 'a match is not suggested again (shown-earlier list)');
select pg_temp.expect(not exists (select 1 from public.get_feed(50) where id = '00000000-0000-0000-0000-000000000002'), 'a match is not in Discovery');

-- Passed in Discovery: still suggestable, but not shown in Discovery again.
select pg_temp.expect(not exists (select 1 from public.get_feed(50) where id = '00000000-0000-0000-0000-000000000003'), 'a passed profile leaves Discovery');
select pg_temp.expect(exists (select 1 from _s where id = '00000000-0000-0000-0000-000000000003'), 'a passed profile can still appear in Suggestions');

-- Requesting someone I'm already connected with creates no second row.
select pg_temp.expect(public.swipe_profile('00000000-0000-0000-0000-000000000002', 'follow_requested') = 'matched', 'asking an existing connection answers matched');
select pg_temp.as_user('02');
select pg_temp.expect(public.swipe_profile('00000000-0000-0000-0000-000000000001', 'follow_requested') = 'matched', 'and from the other side too');
reset role;
select pg_temp.expect((select count(*) from public.swipes_and_requests
  where (sender_id, receiver_id) in (('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002'), ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001'))) = 1, 'exactly one row for the pair (no duplicate chat card)');
