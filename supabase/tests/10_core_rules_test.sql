\set ON_ERROR_STOP 1
-- fixtures (as superuser)
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,15) i;
insert into public.profiles (id, full_name, age, city, bio, avatar_urls)
  select id, 'User '||right(id::text,2), 25, case when right(id::text,2)::int % 2 = 0 then 'Kochi' else 'Kozhikode' end, '', array[gen_random_uuid()::text] from auth.users;
update public.profiles set is_premium = true where id = '00000000-0000-0000-0000-000000000003';
insert into public.profile_private (id, interests, gallery_urls) values ('00000000-0000-0000-0000-000000000001', '{music}', '{x/gallery/1.webp}');

create or replace function pg_temp.expect_fail(sql text, label text) returns text language plpgsql as $$
begin
  execute sql;
  raise exception 'EXPECTED FAILURE DID NOT HAPPEN: %', label;
exception when others then
  if sqlerrm like 'EXPECTED FAILURE%' then raise; end if;
  return 'ok (blocked): ' || label || ' -> ' || sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to authenticated;

set role authenticated;
-- A = 01 (free), B = 02 (free), C = 03 (premium), D = 04
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
select 'A->B', public.swipe_profile('00000000-0000-0000-0000-000000000002', 'follow_requested');
select pg_temp.expect_fail($$select public.send_message('00000000-0000-0000-0000-000000000002', gen_random_uuid(), gen_random_uuid(), '[]')$$, 'message before accept');
select pg_temp.expect_fail($$update public.profiles set is_premium = true where id = auth.uid()$$, 'self-grant premium');
select pg_temp.expect_fail($$select public.swipe_profile('00000000-0000-0000-0000-000000000005', 'follow_requested', 'hello')$$, 'free direct note');
select pg_temp.expect_fail($$update public.profiles set bio = 'ping me @someone' where id = auth.uid()$$, 'handle in bio');
select 'A updates B-row status (should touch 0 rows)'; update public.swipes_and_requests set action = 'accepted' where sender_id = auth.uid();
select 'A remaining', public.remaining_swipes();

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);
select 'B (free) sees pending rows (expect 0):', count(*) from public.swipes_and_requests where receiver_id = auth.uid() and action = 'follow_requested';
select 'B incoming count (expect 1):', public.incoming_request_count();
select 'B private of A before match (expect 0):', count(*) from public.profile_private where id = '00000000-0000-0000-0000-000000000001';
select 'B->A', public.swipe_profile('00000000-0000-0000-0000-000000000001', 'follow_requested');
select 'B private of A after match (expect 1):', count(*) from public.profile_private where id = '00000000-0000-0000-0000-000000000001';


insert into storage.objects (bucket_id, name) values ('voice_notes', '00000000-0000-0000-0000-000000000001_00000000-0000-0000-0000-000000000002/v.bin');
select 'B voice upload ok';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);

select 'A feed excludes B:', not exists (select 1 from public.get_feed(50) where id = '00000000-0000-0000-0000-000000000002');
select 'A sends 9 more requests', count(public.swipe_profile(id, 'follow_requested')) from (select id from public.profiles where id::text > '00000000-0000-0000-0000-000000000004' order by id limit 9) t;
select 'A remaining (expect 0):', public.remaining_swipes();
select pg_temp.expect_fail($$select public.swipe_profile('00000000-0000-0000-0000-000000000015', 'follow_requested')$$, '11th request (limit)');
select 'A pass still allowed', public.swipe_profile('00000000-0000-0000-0000-000000000015', 'pass');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
select 'C (premium) note', public.swipe_profile('00000000-0000-0000-0000-000000000004', 'follow_requested', 'Loved your bio!');
select pg_temp.expect_fail($$select public.swipe_profile('00000000-0000-0000-0000-000000000006', 'follow_requested', 'call 98470 12345')$$, 'phone in note');
select 'C sees messages A<->B (expect 0):', count(*) from public.messages;
select pg_temp.expect_fail($$insert into storage.objects (bucket_id, name) values ('voice_notes', '00000000-0000-0000-0000-000000000001_00000000-0000-0000-0000-000000000002/x.m4a')$$, 'outsider voice upload');
select 'C feed first rows (premium same-city boost):', string_agg(right(id::text,2)||':'||city, ', ') from (select * from public.get_feed(3)) f;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
select pg_temp.expect_fail($$select public.respond_to_request((select id from public.swipes_and_requests limit 1), true)$$, 'free user cannot see request id');
reset role;
update public.profiles set is_premium = true where id = '00000000-0000-0000-0000-000000000004';
set role authenticated;
select 'D (now premium) sees note:', direct_note from public.swipes_and_requests where receiver_id = auth.uid();
select public.respond_to_request((select id from public.swipes_and_requests where receiver_id = auth.uid()), true);
select 'D connected to C:', public.is_connected(auth.uid(), '00000000-0000-0000-0000-000000000003');
select pg_temp.expect_fail($$update public.swipes_and_requests set action = 'rejected' where receiver_id = auth.uid()$$, 'reverse accepted->rejected');
