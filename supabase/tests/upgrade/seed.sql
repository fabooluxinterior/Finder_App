\set ON_ERROR_STOP 1
-- Upgrade-preservation seed: realistic data at the BASELINE schema, then a
-- full-row snapshot of every public table into schema _upgrade. After the
-- newer migrations run, 60_upgrade_preservation_test.sql checks that every
-- old row still exists with every old value unchanged.
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,6) i;
insert into public.profile_dob (user_id, dob) select id, date '1997-05-01' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, gender, occupation, interest_tags, lifestyle_attributes)
select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid, 'User '||i, 27,
       case when i % 2 = 0 then 'Kochi' else 'Thrissur' end, 'Filter coffee and long walks by the sea.',
       case when i % 2 = 0 then 'woman' else 'man' end,
       case when i <= 3 then 'Designer' else null end,          -- half have a profession
       '{Photography,Chai,Football,Poetry,Chess}'::text[], '{"intention":"long_term"}'::jsonb
  from generate_series(1,6) i;
update public.profiles set is_onboarded = true,
  photo_urls = array[gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text]
 where id <> '00000000-0000-0000-0000-000000000006';               -- one user still onboarding
update public.profiles set is_premium = true where id = '00000000-0000-0000-0000-000000000001';

insert into public.user_consents (user_id, policy_type, policy_version)
select id, t, '2026-11-11' from auth.users, unnest(array['terms','privacy','community_guidelines','age_18_plus']) t;

insert into public.swipes_and_requests (sender_id, receiver_id, action) values
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'follow_requested'),
  ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000002', 'follow_requested'),
  ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000005', 'pass');
-- User 2 (premium) accepts user 1's request, as in the app.
update public.profiles set is_premium = true where id = '00000000-0000-0000-0000-000000000002';
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);
select public.respond_to_request((select id from public.swipes_and_requests where sender_id = '00000000-0000-0000-0000-000000000001' and receiver_id = '00000000-0000-0000-0000-000000000002'), true);
select set_config('request.jwt.claim.sub', '', false);

insert into public.devices (user_id, curve25519, ed25519, platform)
select id, rpad(left(replace(id::text, '-', ''), 32), 43, 'A'), rpad(left(replace(id::text, '-', ''), 32), 43, 'B'), 'android'
  from auth.users where id in ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002');
insert into public.messages (id, sender_id, receiver_id, client_msg_id)
values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', gen_random_uuid()),
       ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', gen_random_uuid());
insert into public.message_envelopes (message_id, recipient_device_id, message_type, ciphertext)
select m.id, d.id, 1, 'ciphertext-' || m.id from public.messages m join public.devices d on d.user_id = m.receiver_id;

insert into public.media_objects (owner_id, kind, status, storage_path, wrapped_dek, kek_id, nonce, sha256, width, height, bytes)
select id, 'photo', 'approved', id || '/a.bin', 'dek', 'k1', 'nonce', 'sha', 1080, 1350, 90000 from public.profiles where is_onboarded;
insert into public.blocks (blocker_id, blocked_id) values ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000006');
insert into public.reports (reporter_id, reported_id, reason, details) values
  ('00000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000006', 'spam_or_scam', 'Asked to move to another app');
insert into public.staff_roles (user_id, role) values ('00000000-0000-0000-0000-000000000001', 'admin');
select public.service_music_store('00000000-0000-0000-0000-000000000002', null, null,
  '[{"id":"4YRxDV8wJFPHPTeXepOstw","name":"Sushin Shyam"}]');

-- Full-row snapshot of every public table.
create schema _upgrade;
create table _upgrade.rows (tbl text, data jsonb);
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('insert into _upgrade.rows select %L, to_jsonb(x) from public.%I x', t, t);
  end loop;
end $$;
create table _upgrade.counts as select tbl, count(*) n from _upgrade.rows group by tbl;
select 'seeded ' || sum(n) || ' rows in ' || count(*) || ' tables' from _upgrade.counts;
