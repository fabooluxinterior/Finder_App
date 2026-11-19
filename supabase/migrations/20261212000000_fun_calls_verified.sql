-- migration-id: 20261212000000_fun_calls_verified
-- description: (1) When staff verify a profile the person gets a "You're verified" notification at once (push + live list
--   update), so every screen refreshes together. (2) Fun lines in Malayalam / Manglish for new users and for the call
--   lock, stored in the database and edited from the web dashboard. (3) Calling: the number of days a connection must
--   wait before calling opens (default 4, editable by an admin), who may start a (demo) call, and a job that tells both
--   people when calling has opened. Nothing is deleted or rewritten; older app versions keep working.
-- tables: public.fun_lines, public.call_settings (new); public.user_notifications (added to realtime)
-- columns-added: none
-- backward-compat: Additive. New functions only; existing notification kinds and RPCs are unchanged.
-- recovery: drop trigger profiles_verified_notice on public.profiles; drop function public.tg_profiles_verified_notice();
--   drop function public.fun_lines_list(), public.connected_since(uuid), public.call_unlock_days(), public.start_demo_call(uuid),
--   public.service_notify_call_unlock(), public.admin_fun_lines(), public.admin_fun_line_save(uuid, text, text, boolean, int),
--   public.admin_fun_line_delete(uuid), public.admin_set_call_days(int); drop table public.fun_lines, public.call_settings;
--   alter publication supabase_realtime drop table public.user_notifications;
-- user-data: none changed.
-- =============================================================================

-- ------------------------------------------------------------- verified ----
create or replace function public.tg_profiles_verified_notice() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.is_verified and not coalesce(old.is_verified, false) then
    insert into public.user_notifications (user_id, kind, title, body, dedupe_key)
    values (new.id, 'verification', 'You’re verified ✓', 'Super! Your profile now has the verified badge. Ini adichu polikk!', 'verified')
    on conflict do nothing;
  end if;
  return new;
end $$;
drop trigger if exists profiles_verified_notice on public.profiles;
create trigger profiles_verified_notice after update of is_verified on public.profiles
  for each row execute function public.tg_profiles_verified_notice();

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'user_notifications') then
    alter publication supabase_realtime add table public.user_notifications;
  end if;
end $$;

-- ------------------------------------------------------------ fun lines ----
create table if not exists public.fun_lines (
  id         uuid primary key default gen_random_uuid(),
  slot       text not null check (slot in ('welcome', 'tip', 'call_locked', 'call_ready', 'call_started', 'empty_chat')),
  text       text not null check (char_length(btrim(text)) between 1 and 220),
  enabled    boolean not null default true,
  sort       int not null default 0,
  created_at timestamptz not null default now()
);
alter table public.fun_lines enable row level security;
revoke all on public.fun_lines from anon, authenticated;

-- {n} in a line becomes the number of days left, {name} the other person's first name (done in the app).
insert into public.fun_lines (slot, text, sort)
select v.slot, v.text, v.sort from (values
  ('welcome', 'Vouby-lekku swagatham! Oru chai edukkam, ennitt nammukku parichayappedam ☕', 0),
  ('welcome', 'Kerala-yude ishtam ellaam ivide. Nalla oru aal ninakku vendi kaathirikkunnu 💛', 1),
  ('welcome', 'Adipoli! Profile onnu polichu vechaal match onnu kittum, urappu 😉', 2),
  ('tip', 'Oru nalla photo + oru nalla bio = pakuthi joli kazhinju 📸', 0),
  ('tip', 'Aadyam “Hi” maathram vendaa. Oru chodyam chodikku, chaya pole 😄', 1),
  ('tip', 'Sheriyaaya aal thiranjedukkaan thidukkam venda, samayam eduthu nokku 🌴', 2),
  ('call_locked', 'Aadyam onnu parichayappedu, ennitt vilikkaam. {n} divasam koodi kshamikku 😄', 0),
  ('call_locked', 'Thidukkam venda! Vilikkaan {n} divasam koodi. Appo vare chat cheyyu ☕', 1),
  ('call_locked', 'Pazhaya aalukal parayum: “Aadyam samsaarikku, pinne vilikku”. {n} divasam baakki 🙂', 2),
  ('call_ready', 'Ini vilikkaam! Randu perum parichayappettu, ippo oru call aakaam 📞', 0),
  ('call_started', 'Oru chiriyode thudangaam 😊', 0),
  ('empty_chat', 'Oru “Hi” ayakku, baakki njan nokkaam 😄', 0)
) as v(slot, text, sort)
where not exists (select 1 from public.fun_lines);

create or replace function public.fun_lines_list()
returns table (slot text, text text) language sql stable security definer set search_path = public as $$
  select f.slot, f.text from public.fun_lines f where f.enabled and auth.uid() is not null order by f.slot, f.sort, f.created_at;
$$;

create or replace function public.admin_fun_lines()
returns table (id uuid, slot text, text text, enabled boolean, sort int) language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return query select f.id, f.slot, f.text, f.enabled, f.sort from public.fun_lines f order by f.slot, f.sort, f.created_at;
end $$;

create or replace function public.admin_fun_line_save(p_id uuid, p_slot text, p_text text, p_enabled boolean, p_sort int)
returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  if p_id is null then
    insert into public.fun_lines (slot, text, enabled, sort) values (p_slot, btrim(p_text), coalesce(p_enabled, true), coalesce(p_sort, 0)) returning id into v;
  else
    update public.fun_lines set slot = p_slot, text = btrim(p_text), enabled = coalesce(p_enabled, true), sort = coalesce(p_sort, 0) where id = p_id returning id into v;
  end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason) values (auth.uid(), 'fun_line_save', 'fun_line', v::text, null);
  return v;
end $$;

create or replace function public.admin_fun_line_delete(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  delete from public.fun_lines where id = p_id;
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason) values (auth.uid(), 'fun_line_delete', 'fun_line', p_id::text, null);
end $$;

-- --------------------------------------------------------------- calling ----
create table if not exists public.call_settings (
  id          boolean primary key default true check (id),
  unlock_days int not null default 4 check (unlock_days between 0 and 60),
  updated_at  timestamptz not null default now()
);
insert into public.call_settings (id) values (true) on conflict do nothing;
alter table public.call_settings enable row level security;
revoke all on public.call_settings from anon, authenticated;

create or replace function public.call_unlock_days()
returns int language sql stable security definer set search_path = public as $$
  select unlock_days from public.call_settings where id = true;
$$;

create or replace function public.admin_set_call_days(p_days int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  if p_days is null or p_days < 0 or p_days > 60 then raise exception 'Days must be between 0 and 60' using errcode = '22023'; end if;
  update public.call_settings set unlock_days = p_days, updated_at = now() where id = true;
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason) values (auth.uid(), 'call_days', 'call_settings', p_days::text, null);
end $$;

-- When the two people connected (null when not connected).
create or replace function public.connected_since(p_peer uuid)
returns timestamptz language sql stable security definer set search_path = public as $$
  select max(coalesce(s.responded_at, s.created_at)) from public.swipes_and_requests s
   where s.action = 'accepted' and auth.uid() is not null
     and ((s.sender_id = auth.uid() and s.receiver_id = p_peer) or (s.sender_id = p_peer and s.receiver_id = auth.uid()))
     and not public.is_blocked(auth.uid(), p_peer);
$$;

-- Demo call: checks the waiting time on the server, then rings the other phone with a notification (no audio yet).
create or replace function public.start_demo_call(p_peer uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_since timestamptz; v_days int; v_name text;
begin
  if auth.uid() is null then raise exception 'Not signed in' using errcode = '28000'; end if;
  v_since := public.connected_since(p_peer);
  if v_since is null then raise exception 'Not connected' using errcode = '42501'; end if;
  v_days := public.call_unlock_days();
  if v_since + make_interval(days => v_days) > now() then raise exception 'Calling is not open yet' using errcode = '42501'; end if;
  select split_part(full_name, ' ', 1) into v_name from public.profiles where id = auth.uid();
  insert into public.user_notifications (user_id, kind, title, body, dedupe_key)
  values (p_peer, 'call', coalesce(v_name, 'Someone') || ' is calling you 📞', 'Demo call: open Vouby to answer.', 'call:' || auth.uid()::text || ':' || (extract(epoch from now())::bigint / 60)::text)
  on conflict do nothing;
  return true;
end $$;

-- Tells both people when calling has opened for their connection (every 30 minutes; once per pair).
create or replace function public.service_notify_call_unlock()
returns int language plpgsql security definer set search_path = public as $$
declare v int := 0; r record; v_days int := public.call_unlock_days();
begin
  for r in
    select s.sender_id a, s.receiver_id b from public.swipes_and_requests s
     where s.action = 'accepted' and coalesce(s.responded_at, s.created_at) + make_interval(days => v_days) <= now()
       and coalesce(s.responded_at, s.created_at) + make_interval(days => v_days) > now() - interval '30 days'
  loop
    insert into public.user_notifications (user_id, kind, title, body, dedupe_key)
    values (r.a, 'call', 'Calling is open 📞', 'Ini vilikkaam! You can call your connection now.', 'call_open:' || r.b::text),
           (r.b, 'call', 'Calling is open 📞', 'Ini vilikkaam! You can call your connection now.', 'call_open:' || r.a::text)
    on conflict do nothing;
    v := v + 1;
  end loop;
  return v;
end $$;
revoke all on function public.service_notify_call_unlock() from public, anon, authenticated;
grant execute on function public.service_notify_call_unlock() to service_role;

do $$ begin
  create extension if not exists pg_cron with schema pg_catalog;
  perform cron.schedule('vouby-call-unlock', '*/30 * * * *', 'select public.service_notify_call_unlock()');
exception when others then
  raise notice 'pg_cron is not available here (%); schedule service_notify_call_unlock() elsewhere', sqlerrm;
end $$;

revoke all on function public.fun_lines_list(), public.call_unlock_days(), public.connected_since(uuid), public.start_demo_call(uuid),
  public.admin_fun_lines(), public.admin_fun_line_save(uuid, text, text, boolean, int), public.admin_fun_line_delete(uuid),
  public.admin_set_call_days(int) from public, anon;
grant execute on function public.fun_lines_list(), public.call_unlock_days(), public.connected_since(uuid), public.start_demo_call(uuid),
  public.admin_fun_lines(), public.admin_fun_line_save(uuid, text, text, boolean, int), public.admin_fun_line_delete(uuid),
  public.admin_set_call_days(int) to authenticated;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261212000000_fun_calls_verified', 'Verified notice, editable Malayalam fun lines, call unlock days, demo call, call-open job',
        array['public.fun_lines', 'public.call_settings', 'public.user_notifications'], array[]::text[])
on conflict (migration_id) do nothing;
