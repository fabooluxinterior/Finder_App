-- migration-id: 20261206000000_disappearing_messages
-- description: Disappearing messages per chat (24 hours, 7 days or 1 month). Either person in a connection can turn it
--   on or off from the chat menu. It only applies to messages sent after it was turned on: older messages are never
--   touched. Expired messages are removed from the server (purge_expired_messages); the app also hides them at once.
-- tables: public.chat_disappearing (new)
-- columns-added: none
-- backward-compat: Additive. send_message and the messages table are unchanged; older apps keep working and simply do
--   not hide expired messages locally (the server still removes them).
-- recovery: drop function public.get_disappearing(uuid), public.set_disappearing(uuid, int),
--   public.purge_expired_messages(uuid), public.service_purge_expired_messages(); drop table public.chat_disappearing;
-- user-data: none changed when turned off. When on, expired messages are deleted by design.
-- =============================================================================

create table if not exists public.chat_disappearing (
  user_lo uuid not null references public.profiles (id) on delete cascade,
  user_hi uuid not null references public.profiles (id) on delete cascade,
  seconds int not null default 0 check (seconds in (0, 86400, 604800, 2592000)),
  set_by  uuid references public.profiles (id) on delete set null,
  set_at  timestamptz not null default now(),
  primary key (user_lo, user_hi),
  check (user_lo < user_hi)
);
alter table public.chat_disappearing enable row level security;
revoke all on public.chat_disappearing from anon, authenticated;

create or replace function public.get_disappearing(p_peer uuid)
returns table (seconds int, set_by uuid, set_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  return query select d.seconds, d.set_by, d.set_at from public.chat_disappearing d
   where d.user_lo = least(auth.uid(), p_peer) and d.user_hi = greatest(auth.uid(), p_peer);
end $$;

create or replace function public.set_disappearing(p_peer uuid, p_seconds int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_seconds not in (0, 86400, 604800, 2592000) then raise exception 'Invalid duration' using errcode = '22023'; end if;
  if p_peer = auth.uid() or not public.is_connected(auth.uid(), p_peer) then
    raise exception 'You can only set this in a chat with a connection' using errcode = '42501';
  end if;
  perform public.enforce_rate_limit('set_disappearing', 30, interval '1 hour');
  insert into public.chat_disappearing (user_lo, user_hi, seconds, set_by, set_at)
  values (least(auth.uid(), p_peer), greatest(auth.uid(), p_peer), p_seconds, auth.uid(), now())
  on conflict (user_lo, user_hi) do update set seconds = excluded.seconds, set_by = excluded.set_by, set_at = excluded.set_at;
  perform public.log_security_event('set_disappearing', 'info', jsonb_build_object('peer', p_peer, 'seconds', p_seconds));
end $$;

-- Removes this chat's expired messages (only ones sent after the setting was turned on). Returns how many.
create or replace function public.purge_expired_messages(p_peer uuid)
returns int language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  with d as (
    select seconds, set_at from public.chat_disappearing
     where user_lo = least(auth.uid(), p_peer) and user_hi = greatest(auth.uid(), p_peer) and seconds > 0),
  del as (
    delete from public.messages m using d
     where least(m.sender_id, m.receiver_id) = least(auth.uid(), p_peer)
       and greatest(m.sender_id, m.receiver_id) = greatest(auth.uid(), p_peer)
       and m.created_at >= d.set_at and m.created_at < now() - make_interval(secs => d.seconds)
    returning 1)
  select count(*) into v_n from del;
  return coalesce(v_n, 0);
end $$;

-- For the scheduled maintenance job: every chat at once.
create or replace function public.service_purge_expired_messages()
returns int language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  with del as (
    delete from public.messages m using public.chat_disappearing d
     where d.seconds > 0
       and least(m.sender_id, m.receiver_id) = d.user_lo and greatest(m.sender_id, m.receiver_id) = d.user_hi
       and m.created_at >= d.set_at and m.created_at < now() - make_interval(secs => d.seconds)
    returning 1)
  select count(*) into v_n from del;
  return coalesce(v_n, 0);
end $$;

revoke all on function public.get_disappearing(uuid), public.set_disappearing(uuid, int), public.purge_expired_messages(uuid),
  public.service_purge_expired_messages() from public, anon;
grant execute on function public.get_disappearing(uuid), public.set_disappearing(uuid, int), public.purge_expired_messages(uuid) to authenticated;
grant execute on function public.service_purge_expired_messages() to service_role;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261206000000_disappearing_messages', 'Disappearing messages per chat: 24 hours, 7 days, 1 month',
        array['public.chat_disappearing'], array[]::text[])
on conflict (migration_id) do nothing;
