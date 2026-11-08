\set ON_ERROR_STOP 1
-- Profile builder: photos, prompts, completion score, onboarding, music, prompt replies.
-- Users: A(01) B(02) C(03, new user without a profile)
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,3) i;
insert into public.profile_dob (user_id, dob) select id, date '1998-03-03' from auth.users;
insert into public.profiles (id, full_name, age, city, bio) values
  ('00000000-0000-0000-0000-000000000001', 'Asha Menon', 99, 'Kochi', ''),
  ('00000000-0000-0000-0000-000000000002', 'Bala', 99, 'Kochi', '');
-- Six approved photos for A (as if processed), one for B.
insert into public.media_objects (id, owner_id, kind, status, storage_path, wrapped_dek, kek_id, nonce, sha256, width, height, bytes)
select ('aaaaaaaa-0000-0000-0000-00000000000'||i)::uuid, '00000000-0000-0000-0000-000000000001', 'photo', 'approved',
       'u1/a'||i||'.bin', 'w', 'v1', 'n', 's', 1080, 1350, 90000 from generate_series(1,7) i;
insert into public.media_objects (id, owner_id, kind, status, storage_path, wrapped_dek, kek_id, nonce, sha256, width, height, bytes) values
 ('bbbbbbbb-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','photo','approved','u2/b1.bin','w','v1','n','s',1080,1080,1);

create or replace function pg_temp.expect_fail(sql text, label text) returns text language plpgsql as $$
begin execute sql; raise exception 'EXPECTED FAILURE DID NOT HAPPEN: %', label;
exception when others then if sqlerrm like 'EXPECTED FAILURE%' then raise; end if; return 'ok (blocked): ' || label || ' -> ' || sqlerrm; end $$;
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false); $$;
grant execute on all functions in schema pg_temp to authenticated;

-- ---------------------------------------------------------------- completion score (pure)
select pg_temp.expect(public.profile_completion(0, null, null, '{}', 0, 0, '', 0, false) = 0, 'empty profile scores 0');
select pg_temp.expect(public.profile_completion(4, 'Designer', 'NIT Calicut',
  '{"intention":"long_term","activity":"often","drinking":"socially","smoking":"never","zodiac":"leo","culture":"malayali"}',
  2, 5, 'Twenty characters exactly!', 2, true) = 100, 'complete profile scores 100');
select pg_temp.expect(public.profile_completion(3, 'Designer', null, '{}', 0, 2, 'short', 1, false) = 39,
  '3 photos (22.5) + occupation (5) + 2 tags (6) + 1 prompt (5) = 38.5 -> 39 (half rounds up, same as Dart)');
select pg_temp.expect(public.profile_completion(6, null, null, '{}', 0, 9, '', 4, false) = 55, 'photos and tags and prompts are capped');

-- ---------------------------------------------------------------- service attaches photos into slots
select pg_temp.expect(cardinality(public.attach_media(('aaaaaaaa-0000-0000-0000-00000000000'||i)::uuid)) = 0, 'attach photo '||i)
  from generate_series(1,6) i;
select pg_temp.expect(cardinality(photo_urls) = 6 and avatar_urls[1] = photo_urls[1], 'six slots filled, primary synced')
  from public.profiles where id = '00000000-0000-0000-0000-000000000001';
select pg_temp.expect((select cardinality(gallery_urls) from public.profile_private where id = '00000000-0000-0000-0000-000000000001') = 5,
  'gallery mirrors slots 2-6');
select pg_temp.expect_fail($$select public.attach_media('aaaaaaaa-0000-0000-0000-000000000007')$$, '7th photo');
-- Replace slot 2 in place: old object becomes obsolete and its path is returned for deletion.
insert into public.media_objects (id, owner_id, kind, status, storage_path, wrapped_dek, kek_id, nonce, sha256, width, height, bytes, replaces) values
 ('aaaaaaaa-0000-0000-0000-000000000008','00000000-0000-0000-0000-000000000001','photo','approved','u1/a8.bin','w','v1','n','s',1080,1080,1,
  'aaaaaaaa-0000-0000-0000-000000000002');
select pg_temp.expect(public.attach_media('aaaaaaaa-0000-0000-0000-000000000008') = '{u1/a2.bin}', 'replace returns obsolete path');
select pg_temp.expect(photo_urls[2] = 'aaaaaaaa-0000-0000-0000-000000000008', 'replacement kept the slot position')
  from public.profiles where id = '00000000-0000-0000-0000-000000000001';
select pg_temp.expect(public.attach_media('bbbbbbbb-0000-0000-0000-000000000001') = '{}', 'B photo attached');

set role authenticated;
select pg_temp.as_user('01');

-- ---------------------------------------------------------------- column privileges
select pg_temp.expect_fail($$update public.profiles set photo_urls = '{x,y,z,w}' where id = auth.uid()$$, 'client sets photo list');
select pg_temp.expect_fail($$update public.profiles set completion_score = 100 where id = auth.uid()$$, 'client sets score');
select pg_temp.expect_fail($$update public.profiles set is_onboarded = true where id = auth.uid()$$, 'client flags itself onboarded');
select pg_temp.expect_fail($$update public.profiles set music_linked = true where id = auth.uid()$$, 'client fakes music link');
select pg_temp.expect_fail($$update public.profiles set music_artist_ids = '{abc}' where id = auth.uid()$$, 'client injects artist ids');
select pg_temp.expect_fail($$select * from public.music_accounts$$, 'client reads music tokens');
select pg_temp.expect_fail($$select * from public.music_oauth_states$$, 'client reads oauth states');

-- ---------------------------------------------------------------- validation
select pg_temp.expect_fail($$update public.profiles set lifestyle_attributes = '{"drinking":"every night, call me"}' where id = auth.uid()$$, 'free-text lifestyle value');
select pg_temp.expect_fail($$update public.profiles set lifestyle_attributes = '{"salary":"high"}' where id = auth.uid()$$, 'unknown lifestyle key');
select pg_temp.expect_fail($$update public.profiles set height_cm = 300 where id = auth.uid()$$, 'impossible height');
select pg_temp.expect_fail($$update public.profiles set occupation = 'DM me at insta: asha.m' where id = auth.uid()$$, 'contact info in occupation');
select pg_temp.expect_fail($$update public.profiles set interest_tags = '{Hiking,hiking}' where id = auth.uid()$$, 'duplicate tags');
select pg_temp.expect_fail($$update public.profiles set prompts = '[{"prompt_id":"p999","answer":"hi"}]' where id = auth.uid()$$, 'unknown prompt');
select pg_temp.expect_fail($$update public.profiles set prompts = jsonb_build_array(jsonb_build_object('prompt_id','p1','answer',repeat('a',151))) where id = auth.uid()$$, 'answer over 150');
select pg_temp.expect_fail($$update public.profiles set prompts = '[{"prompt_id":"p1","answer":"call 9876543210"}]' where id = auth.uid()$$, 'phone number in answer');
select pg_temp.expect_fail($$update public.profiles set prompts = '[{"prompt_id":"p1","answer":"a"},{"prompt_id":"p1","answer":"b"}]' where id = auth.uid()$$, 'same prompt twice');
update public.profiles set prompts = '[{"prompt_id":"p1","question":"Send me your number","answer":"Evening chai at Fort Kochi"}]' where id = auth.uid();
select pg_temp.expect((prompts -> 0 ->> 'question') = 'A small thing that makes my week', 'question text comes from the catalog')
  from public.profiles where id = auth.uid();

-- ---------------------------------------------------------------- onboarding gate
select pg_temp.expect_fail($$select public.complete_onboarding()$$, 'incomplete profile goes live');
select public.acknowledge_standards('2026-11-11');
update public.profiles set gender = 'woman', occupation = 'Product designer', education = 'CET Trivandrum',
  interest_tags = '{Hiking,Filter coffee,Photography,Board games,Poetry}', bio = 'Weekend trekker and weekday designer.',
  lifestyle_attributes = '{"intention":"long_term","activity":"often"}', languages = '{Malayalam,English}',
  prompts = '[{"prompt_id":"p1","answer":"Evening chai at Fort Kochi"},{"prompt_id":"p4","answer":"Sunrise at Marine Drive, appam, nap"}]'
 where id = auth.uid();
select public.complete_onboarding();
select pg_temp.expect(is_onboarded and onboarding_stage = 8 and standards_acknowledged_at is not null, 'onboarded after requirements met')
  from public.profiles where id = auth.uid();
select 'A completion score:', completion_score from public.profiles where id = auth.uid();

-- ---------------------------------------------------------------- photo reorder / remove
select pg_temp.expect_fail($$select public.reorder_photos(array['bbbbbbbb-0000-0000-0000-000000000001'] || (select photo_urls[2:6] from public.profiles where id = auth.uid()))$$,
  'reorder injects someone else''s photo');
select pg_temp.expect_fail($$select public.reorder_photos((select photo_urls[1:5] from public.profiles where id = auth.uid()))$$, 'reorder drops a photo');
select public.reorder_photos((select array(select x from unnest(photo_urls) with ordinality t(x, o) order by o desc) from public.profiles where id = auth.uid()));
select pg_temp.expect(avatar_urls[1] = 'aaaaaaaa-0000-0000-0000-000000000006', 'reorder moved the primary photo') from public.profiles where id = auth.uid();
select pg_temp.expect_fail($$select public.remove_photo('bbbbbbbb-0000-0000-0000-000000000001')$$, 'remove someone else''s photo');
select pg_temp.expect(public.remove_photo('aaaaaaaa-0000-0000-0000-000000000006') = 'u1/a6.bin', 'remove returns path for immediate delete');
select pg_temp.expect(cardinality(photo_urls) = 5, 'five photos left') from public.profiles where id = auth.uid();

-- ---------------------------------------------------------------- music connector
reset role;
select public.service_music_store('00000000-0000-0000-0000-000000000001', 'enc', 'v1', '[
  {"id":"4YRxDV8wJFPHPTeXepOstw","name":"Sushin Shyam","image":"https://i.scdn.co/image/abc123","genres":["malayalam indie"]},
  {"id":"1mYsTxnqsietFxj1OgoGbG","name":"A. R. Rahman","image":"javascript:alert(1)","genres":["filmi"]},
  {"id":"bad id!","name":"Injected"},
  {"id":"5f4QpKfy7ptCHwTqspnSJI","name":"Prateek Kuhad","genres":[]}]');
select public.service_music_store('00000000-0000-0000-0000-000000000002', 'enc', 'v1', '[
  {"id":"1mYsTxnqsietFxj1OgoGbG","name":"A. R. Rahman"},{"id":"5f4QpKfy7ptCHwTqspnSJI","name":"Prateek Kuhad"}]');
select pg_temp.expect(music_linked and cardinality(music_artist_ids) = 3, 'invalid artist id dropped on import')
  from public.profiles where id = '00000000-0000-0000-0000-000000000001';
select pg_temp.expect((music_top_artists -> 1 ->> 'image') is null, 'non-Spotify image URL dropped')
  from public.profiles where id = '00000000-0000-0000-0000-000000000001';
update public.profiles set is_onboarded = true, photo_urls = photo_urls || array['bbbbbbbb-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000003','bbbbbbbb-0000-0000-0000-000000000004']
 where id = '00000000-0000-0000-0000-000000000002';
set role authenticated;
select pg_temp.as_user('02');
select pg_temp.expect(jsonb_array_length(public.music_affinity('00000000-0000-0000-0000-000000000001')) = 2, 'B shares 2 artists with A');
select pg_temp.expect(cardinality(shared_artist_ids) = 2, 'feed carries shared artists') from public.get_feed(10) where id = '00000000-0000-0000-0000-000000000001';
select pg_temp.as_user('01');
select pg_temp.expect(jsonb_array_length(artists) = 3 and status = 'active', 'owner sees imported list, no token') from public.my_music();
select public.set_music_artist_visibility('1mYsTxnqsietFxj1OgoGbG', false);
select pg_temp.expect(not ('1mYsTxnqsietFxj1OgoGbG' = any (music_artist_ids)), 'hidden artist removed from public ids')
  from public.profiles where id = auth.uid();
select pg_temp.as_user('02');
select pg_temp.expect(jsonb_array_length(public.music_affinity('00000000-0000-0000-0000-000000000001')) = 1, 'hidden artist never matched');
select pg_temp.as_user('01');
select public.disconnect_music();
select pg_temp.expect(not music_linked and music_top_artists = '[]' and music_artist_ids = '{}', 'disconnect clears public music')
  from public.profiles where id = auth.uid();
select pg_temp.expect(not exists (select 1 from public.my_music()), 'disconnect removes tokens');

-- ---------------------------------------------------------------- prompt replies
select pg_temp.as_user('02');
select pg_temp.expect_fail($$insert into public.swipes_and_requests (sender_id, receiver_id, action, intro_prompt_id, intro_text)
  values (auth.uid(), '00000000-0000-0000-0000-000000000001', 'follow_requested', 'p1', 'hi')$$, 'direct insert with intro');
select pg_temp.expect_fail($$select public.send_prompt_reply('00000000-0000-0000-0000-000000000001', 'p9', 'hi')$$, 'reply to a prompt they don''t have');
select pg_temp.expect_fail($$select public.send_prompt_reply('00000000-0000-0000-0000-000000000001', 'p1', 'text me on 98765 43210')$$, 'contact info in reply');
select pg_temp.expect(public.send_prompt_reply('00000000-0000-0000-0000-000000000001', 'p1', 'Which chai stall? I need names.') = 'requested', 'reply sends a request');
select pg_temp.expect(intro_prompt_id = 'p1' and intro_text like 'Which chai%', 'reply anchored to the prompt')
  from public.swipes_and_requests where sender_id = auth.uid() and receiver_id = '00000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------- new users
select pg_temp.as_user('03');
select pg_temp.expect_fail($$insert into public.profiles (id, full_name, age, city, is_onboarded) values (auth.uid(), 'C', 25, 'Kochi', true)$$, 'insert pre-onboarded');
select pg_temp.expect_fail($$insert into public.profiles (id, full_name, age, city, photo_urls) values (auth.uid(), 'C', 25, 'Kochi', '{a,b,c,d}')$$, 'insert with photos');
select public.acknowledge_standards('2026-11-11');
insert into public.profiles (id, full_name, age, city) values (auth.uid(), 'Chitra', 25, 'Kochi');
select pg_temp.expect(standards_acknowledged_at is not null and completion_score = 0 and not is_onboarded, 'stage-1 acknowledgement carried onto new profile')
  from public.profiles where id = auth.uid();
select pg_temp.expect(not exists (select 1 from public.get_feed(10) where id = auth.uid()), 'self never in feed');
select pg_temp.as_user('02');
select pg_temp.expect(not exists (select 1 from public.get_feed(10) where id = '00000000-0000-0000-0000-000000000003'), 'non-onboarded profile hidden from Discover');
reset role;
