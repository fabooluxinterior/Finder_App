-- migration-id: 20261211000000_presence_realtime
-- description: Lets a chat header show "online" / "last seen" the instant it changes. People you are connected to (and
--   have not blocked, either way) may read your presence row and receive live changes to it; nobody else can.
--   The row only holds the last-active time and the "left the app" time, which peer_presence_v2 already shows them.
-- tables: public.user_presence (read policy + realtime publication)
-- columns-added: none
-- backward-compat: Additive. peer_presence / peer_presence_v2 / touch_presence are unchanged.
-- recovery: drop policy presence_read_connected on public.user_presence;
--   alter publication supabase_realtime drop table public.user_presence; revoke select on public.user_presence from authenticated;
-- user-data: none changed.
-- =============================================================================

grant select (user_id, last_active_at, offline_at) on public.user_presence to authenticated;

drop policy if exists presence_read_connected on public.user_presence;
create policy presence_read_connected on public.user_presence for select to authenticated
  using (
    user_id = auth.uid()
    or (public.is_connected(auth.uid(), user_id) and not public.is_blocked(auth.uid(), user_id))
  );

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'user_presence') then
    alter publication supabase_realtime add table public.user_presence;
  end if;
end $$;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261211000000_presence_realtime', 'Connected people can read and receive live changes of each other''s presence row',
        array['public.user_presence'], array[]::text[])
on conflict (migration_id) do nothing;
