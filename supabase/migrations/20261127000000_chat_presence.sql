-- migration-id: 20261127000000_chat_presence
-- description: Live "typing / recording audio / sending a photo" signals between the two people in a chat.
--   They travel over a private Realtime broadcast channel named chat:<userA>_<userB>. Row-level rules on the
--   Realtime messages table allow only the two connected, unblocked people to read or send on their own channel.
--   Nothing is stored: broadcast messages are not persisted.
-- tables: none (two policies added on realtime.messages when it exists; one helper function)
-- columns-added: none
-- backward-compat: Additive. Older app versions never join these channels. No existing policy or function changes.
-- recovery: drop policy chat_presence_read on realtime.messages; drop policy chat_presence_write on realtime.messages;
--   drop function public.chat_topic_allowed(text);
-- user-data: none
-- =============================================================================

-- True when the caller is one of the two people named in a chat:<a>_<b> topic, and they are connected.
create or replace function public.chat_topic_allowed(p_topic text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare m text[]; a uuid; b uuid;
begin
  if auth.uid() is null then return false; end if;
  m := regexp_match(coalesce(p_topic, ''), '^chat:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})_([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$');
  if m is null then return false; end if;
  a := m[1]::uuid; b := m[2]::uuid;
  if a >= b then return false; end if;                       -- one canonical name per pair
  if auth.uid() <> a and auth.uid() <> b then return false; end if;
  return public.is_connected(a, b) and not public.is_blocked(a, b);
end $$;
revoke all on function public.chat_topic_allowed(text) from public, anon;
grant execute on function public.chat_topic_allowed(text) to authenticated;

do $$ begin
  if to_regclass('realtime.messages') is not null then
    execute 'drop policy if exists chat_presence_read on realtime.messages';
    execute 'create policy chat_presence_read on realtime.messages for select to authenticated
             using (realtime.messages.extension = ''broadcast'' and public.chat_topic_allowed(realtime.topic()))';
    execute 'drop policy if exists chat_presence_write on realtime.messages';
    execute 'create policy chat_presence_write on realtime.messages for insert to authenticated
             with check (realtime.messages.extension = ''broadcast'' and public.chat_topic_allowed(realtime.topic()))';
  else
    raise notice 'realtime.messages not present here; policies are added where Realtime is installed';
  end if;
exception when others then
  raise notice 'could not add realtime policies (%)', sqlerrm;
end $$;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261127000000_chat_presence',
        'Private realtime channel rules for typing / recording / sending-photo signals between connected people',
        array['realtime.messages'], array[]::text[])
on conflict (migration_id) do nothing;
