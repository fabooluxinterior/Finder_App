-- migration-id: 20261210000000_presence_offline
-- description: "Online" now ends the moment the app is closed or the screen is locked, like WhatsApp. A phone says
--   "I left" (presence_offline) and "I'm back" (presence_ping); the other person's app asks peer_presence_v2 and gets the
--   last-seen time plus an online flag (online only when the person did not leave and was active in the last 90 seconds).
--   The old touch_presence / peer_presence functions are untouched, so older app versions keep working.
-- tables: public.user_presence (column added)
-- columns-added: user_presence.offline_at (timestamptz, nullable)
-- backward-compat: Additive. Old apps keep using touch_presence and peer_presence with their 2-minute rule.
-- recovery: drop function public.presence_ping(); drop function public.presence_offline();
--   drop function public.peer_presence_v2(uuid); alter table public.user_presence drop column offline_at;
-- user-data: none changed. Existing rows keep last_active_at; offline_at starts empty.
-- =============================================================================

alter table public.user_presence add column if not exists offline_at timestamptz;

-- "I'm using the app": always records the time (no throttle) and clears a previous "left".
create or replace function public.presence_ping()
returns void language sql security definer set search_path = public as $$
  insert into public.user_presence (user_id, last_active_at, offline_at)
  select auth.uid(), now(), null where auth.uid() is not null and exists (select 1 from public.profiles where id = auth.uid())
  on conflict (user_id) do update set last_active_at = now(), offline_at = null
   where public.user_presence.offline_at is not null or public.user_presence.last_active_at < now() - interval '10 seconds';
$$;

-- "I left": the app went to the background or the screen was locked. Last seen = now.
create or replace function public.presence_offline()
returns void language sql security definer set search_path = public as $$
  update public.user_presence set last_active_at = now(), offline_at = now() where user_id = auth.uid();
$$;

create or replace function public.peer_presence_v2(p_peer uuid)
returns table (last_active_at timestamptz, online boolean) language sql stable security definer set search_path = public as $$
  select up.last_active_at,
         (up.offline_at is null or up.last_active_at > up.offline_at) and up.last_active_at > now() - interval '90 seconds'
    from public.user_presence up
   where up.user_id = p_peer and auth.uid() is not null
     and public.is_connected(auth.uid(), p_peer) and not public.is_blocked(auth.uid(), p_peer);
$$;

revoke all on function public.presence_ping(), public.presence_offline(), public.peer_presence_v2(uuid) from public, anon;
grant execute on function public.presence_ping(), public.presence_offline(), public.peer_presence_v2(uuid) to authenticated;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261210000000_presence_offline', 'Online ends when the app is closed or the screen locks (presence_offline / peer_presence_v2)',
        array['public.user_presence'], array['user_presence.offline_at'])
on conflict (migration_id) do nothing;
