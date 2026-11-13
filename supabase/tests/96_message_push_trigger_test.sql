\set ON_ERROR_STOP 1
-- The message trigger never blocks or alters sending, with or without push configured.
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,2) i;
insert into public.profile_dob (user_id, dob) select id, date '2000-01-15' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, avatar_urls)
  select id, 'User '||right(id::text,2), 25, 'Kochi', '', array[gen_random_uuid()::text] from auth.users;
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;

-- unconfigured: plain insert works
insert into public.messages (id, sender_id, receiver_id, client_msg_id)
values ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', gen_random_uuid());
select pg_temp.expect((select count(*) from public.messages) = 1, 'message stored with push unconfigured');

-- configured but pg_net unavailable / unreachable: still stored
insert into public.app_private_settings (key, value) values ('push_webhook_url', 'http://127.0.0.1:9/none'), ('push_webhook_secret', 'x')
  on conflict (key) do update set value = excluded.value;
insert into public.messages (id, sender_id, receiver_id, client_msg_id)
values ('30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', gen_random_uuid());
select pg_temp.expect((select count(*) from public.messages) = 2, 'message stored with push configured but failing');

-- the trigger function is not callable by users
set role authenticated;
do $$ begin
  perform public.notify_new_message();
  raise exception 'EXPECTED FAILURE DID NOT HAPPEN: users can call the trigger function';
exception when insufficient_privilege then null; end $$;
