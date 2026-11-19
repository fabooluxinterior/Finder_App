\set ON_ERROR_STOP 1
-- Suggestions: scoring, preferences, allowance, refresh, exclusions, privacy.
-- A(01) is the viewer. B..H are candidates.
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,8) i;
insert into public.profile_dob (user_id, dob) select id, date '1998-01-01' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, gender, interest_tags, lifestyle_attributes)
select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid, 'User '||i, 25,
       case when i in (1,2,3) then 'Kochi' else 'Kozhikode' end, '',
       case when i % 2 = 0 then 'woman' else 'man' end,
       case i when 1 then '{Photography,Chai,Football,Poetry,Chess}'::text[]
              when 2 then '{Photography,Chai,Football,Poetry,Baking}'   -- 4 shared
              when 3 then '{Photography,Gym,Seafood,Comics,Yoga}'        -- 1 shared
              else '{Painting,Seafood,Comics,Yoga,Gym}' end,
       case i when 1 then '{"intention":"long_term","drinking":"never"}'::jsonb
              when 2 then '{"intention":"long_term","drinking":"never"}'::jsonb else '{}'::jsonb end
  from generate_series(1,8) i;
-- Onboard everyone with 4 photos (as superuser).
update public.profiles set is_onboarded = true,
  photo_urls = array[gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text];

create or replace function pg_temp.expect_fail(sql text, label text) returns text language plpgsql as $$
begin execute sql; raise exception 'EXPECTED FAILURE DID NOT HAPPEN: %', label;
exception when others then if sqlerrm like 'EXPECTED FAILURE%' then raise; end if; return 'ok (blocked): ' || label || ' -> ' || sqlerrm; end $$;
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false); $$;
grant execute on all functions in schema pg_temp to authenticated;

-- Music: A and C share an artist; D linked but hides it.
select public.service_music_store('00000000-0000-0000-0000-000000000001', null, null, '[{"id":"4YRxDV8wJFPHPTeXepOstw","name":"Sushin Shyam"}]');
select public.service_music_store('00000000-0000-0000-0000-000000000003', null, null, '[{"id":"4YRxDV8wJFPHPTeXepOstw","name":"Sushin Shyam"}]');
select public.service_music_store('00000000-0000-0000-0000-000000000004', null, null, '[{"id":"4YRxDV8wJFPHPTeXepOstw","name":"Sushin Shyam"}]');
update public.music_accounts set hidden_artist_ids = '{4YRxDV8wJFPHPTeXepOstw}' where user_id = '00000000-0000-0000-0000-000000000004';
select public.refresh_public_music('00000000-0000-0000-0000-000000000004');

-- Small allowance to test limits.
update public.recommendation_config set daily_limit = 4;

set role authenticated;
select pg_temp.as_user('01');

-- ---------------------------------------------------------------- privileges
select pg_temp.expect_fail($$insert into public.recommendation_history (user_id, target_id, section, score) values (auth.uid(), '00000000-0000-0000-0000-000000000002', 'main', 99)$$, 'client writes history');
select pg_temp.expect_fail($$update public.recommendation_config set daily_limit = 1000$$, 'client raises its own limit');
select pg_temp.expect_fail($$insert into public.recommendation_daily (user_id, day, shown) values (auth.uid(), current_date, -100)$$, 'client resets allowance');
select pg_temp.expect_fail($$select public.admin_set_recommendation_config(null, 1000, null)$$, 'non-admin changes config');
select pg_temp.expect_fail($$select public.suggestion_score(auth.uid(), '00000000-0000-0000-0000-000000000002', '{}')$$, 'client calls scorer directly');
select pg_temp.expect_fail($$select * from public.get_suggestions('everyone', 10)$$, 'unknown section');

-- ---------------------------------------------------------------- preferences
update public.profiles set pref_genders = '{woman}' where id = auth.uid();
select pg_temp.expect_fail($$update public.profiles set pref_age_min = 16 where id = auth.uid()$$, 'age range below 18');
select pg_temp.expect_fail($$update public.profiles set pref_genders = '{robot}' where id = auth.uid()$$, 'unknown gender pref');

-- ---------------------------------------------------------------- first page
create temporary table page1 as select * from public.get_suggestions('main', 50);
select 'page 1:', string_agg(right(id::text, 2) || ':' || compatibility, ', ' order by compatibility desc) from page1;
select pg_temp.expect((select count(*) from page1) = 4, 'four women, allowance 4');
select pg_temp.expect(not exists (select 1 from page1 where gender <> 'woman'), 'preferences respected');
select pg_temp.expect((select id from page1 order by compatibility desc limit 1) = '00000000-0000-0000-0000-000000000002', 'most shared signals ranks first');
select pg_temp.expect((select reasons @> '[{"kind":"interests","count":4}]' from page1 where id = '00000000-0000-0000-0000-000000000002'), 'reasons explain shared interests');
select pg_temp.expect((select reasons @> '[{"kind":"lifestyle"}]' from page1 where id = '00000000-0000-0000-0000-000000000002'), 'reasons explain shared lifestyle');
select pg_temp.expect(not exists (select 1 from page1, jsonb_array_elements(reasons) r where page1.id = '00000000-0000-0000-0000-000000000004' and r ->> 'kind' = 'music'),
  'hidden artist never becomes a music reason');
select pg_temp.expect((select remaining from public.suggestion_status()) = 0, 'allowance spent');

-- ---------------------------------------------------------------- refresh doesn't reset
create temporary table page2 as select * from public.get_suggestions('main', 10);
select pg_temp.expect((select count(*) from page2) = 4 and (select remaining from public.suggestion_status()) = 0,
  'refresh returns the same people and spends nothing');
select pg_temp.expect((select count(*) from public.get_suggestions('main', 10, array['00000000-0000-0000-0000-000000000002'::uuid])) = 3,
  'load more excludes what is on screen and adds none past the allowance');

-- ---------------------------------------------------------------- acted-on and blocked people drop out
select public.swipe_profile('00000000-0000-0000-0000-000000000002', 'pass');
select public.block_user('00000000-0000-0000-0000-000000000006');
select pg_temp.expect(not exists (select 1 from public.get_suggestions('main', 10) where id in
  ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000006')), 'passed and blocked never return');

-- ---------------------------------------------------------------- page limit
reset role;
update public.recommendation_config set daily_limit = 50, page_max = 2;
delete from public.recommendation_history;
delete from public.recommendation_daily;
update public.profiles set pref_genders = '{}' where id = '00000000-0000-0000-0000-000000000001';
set role authenticated;
select pg_temp.as_user('01');
select pg_temp.expect((select count(*) from public.get_suggestions('main', 50)) = 2, 'page size capped by backend config');

-- ---------------------------------------------------------------- music only counts when both linked
reset role;
update public.recommendation_config set page_max = 20;
set role authenticated;
select pg_temp.as_user('03');
select pg_temp.expect((select reasons @> '[{"kind":"music"}]' from public.get_suggestions('you_may_like', 20) where id = '00000000-0000-0000-0000-000000000001'),
  'shared artist explained when both linked');
select pg_temp.as_user('05');
select pg_temp.expect(not exists (select 1 from public.get_suggestions('main', 20) s, jsonb_array_elements(s.reasons) r where r ->> 'kind' = 'music'),
  'not linking Spotify is never required (no music reasons, still suggested)');
reset role;
