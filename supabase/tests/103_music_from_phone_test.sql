\set ON_ERROR_STOP 1
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,2) i;
insert into public.profile_dob (user_id, dob) select id, date '2000-01-15' from auth.users;
insert into public.profiles (id, full_name, age, city, bio) select id, 'U'||right(id::text,2), 25, 'Kochi', '' from auth.users;
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
select public.store_my_music(
  '[{"id":"4Z8W4fKeB5YxbusRsdQVPb","name":"Radiohead","image":"https://i.scdn.co/image/abc123","genres":["rock"]},
    {"id":"bad id","name":"Bad"},
    {"id":"1dfeR4HaWDbWqFHLkxsg1d","name":"Evil","image":"https://evil.example/x.png"}]',
  '[{"id":"11dFghVXANMlKmJXsNCbNl","name":"Song","artists":["A"],"image":"https://i.scdn.co/image/zzz"}]',
  '[{"id":"11dFghVXANMlKmJXsNCbNl","name":"Song","artists":["A"],"played_at":"2026-11-01T10:00:00Z"}]',
  'user-top-read user-read-recently-played');
select pg_temp.expect((select count(*) from public.my_music() m, jsonb_array_elements(m.artists)) = 2, 'invalid artist ids are dropped');
select pg_temp.expect((select (artists -> 1 ->> 'image') is null from public.my_music()), 'non-Spotify image urls are dropped');
select pg_temp.expect((select jsonb_array_length(top_tracks) = 1 and jsonb_array_length(recent_tracks) = 1 from public.my_music()), 'tracks saved');
select pg_temp.expect((select music_linked from public.profiles where id = '00000000-0000-0000-0000-000000000001'), 'profile shows Spotify linked');
-- recent = null keeps the stored list
select public.store_my_music('[]', '[]', null, '');
select pg_temp.expect((select jsonb_array_length(recent_tracks) = 1 from public.my_music()), 'null recent keeps stored recent');
select pg_temp.expect_fail($$select public.store_my_music('{"a":1}', '[]', null, '')$$, 'non-array rejected');
select pg_temp.as_user('02');
select pg_temp.expect((select count(*) from public.my_music()) = 0, 'other people have nothing stored');
select public.disconnect_music();
reset role;
select set_config('request.jwt.claims', '', false), set_config('request.jwt.claim.sub', '', false);
set role anon;
select pg_temp.expect_fail($$select public.store_my_music('[]','[]',null,'')$$, 'signed-out refused');
