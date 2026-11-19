-- migration-id: 20261207000000_message_receipts
-- description: Fixes saving "read" on the server (an outdated guard made every message update fail) and adds real
--   delivery and read receipts for chat. Each message now records when it reached the other person's
--   device (delivered_at), when it was read (read_at) and, for voice notes, when it was played (listened_at). Times
--   are set by the server, never by a phone. The existing is_read flag keeps working: marking a message read (by an
--   older or newer app) also fills read_at and delivered_at.
-- tables: public.messages (columns added)
-- columns-added: messages.delivered_at, messages.read_at, messages.listened_at
-- backward-compat: Additive. is_read and its update policy are unchanged; older apps keep working and simply do not
--   report "delivered".
-- recovery: drop trigger messages_receipts on public.messages; drop function public.tg_message_receipts();
--   drop function public.mark_delivered(uuid[]); drop function public.mark_listened(uuid);
--   alter table public.messages drop column delivered_at, drop column read_at, drop column listened_at;
-- user-data: none changed. Existing messages that are already read get read_at = created_at as a floor only for display.
-- =============================================================================

alter table public.messages
  add column if not exists delivered_at timestamptz,
  add column if not exists read_at timestamptz,
  add column if not exists listened_at timestamptz;

-- The old "messages are immutable" guard still named the content and audio columns that end-to-end encryption
-- removed, so every update of a message failed ("record new has no field content"): reading a message could never
-- be saved on the server. It now guards the columns that exist. Only the receipt columns can change.
create or replace function public.tg_messages_before_update() returns trigger
language plpgsql as $$
begin
  if new.sender_id <> old.sender_id or new.receiver_id <> old.receiver_id
     or new.created_at <> old.created_at
     or new.client_msg_id is distinct from old.client_msg_id
     or new.sender_device_id is distinct from old.sender_device_id
     or new.kind is distinct from old.kind then
    raise exception 'Messages are immutable' using errcode = '42501';
  end if;
  return new;
end $$;

-- Reading always implies delivery; the time is the server's.
create or replace function public.tg_message_receipts() returns trigger
language plpgsql as $$
begin
  if new.is_read and not old.is_read then
    new.read_at := coalesce(new.read_at, now());
    new.delivered_at := coalesce(new.delivered_at, new.read_at);
  end if;
  return new;
end $$;
drop trigger if exists messages_receipts on public.messages;
create trigger messages_receipts before update on public.messages
  for each row execute function public.tg_message_receipts();

-- The receiving device reports that the messages arrived (after it decrypted and stored them).
create or replace function public.mark_delivered(p_message_ids uuid[])
returns int language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  update public.messages set delivered_at = now()
   where id = any (p_message_ids) and receiver_id = auth.uid() and kind = 0 and delivered_at is null;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- A voice note was played. Playing it also means it was seen.
create or replace function public.mark_listened(p_message_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  update public.messages set
      listened_at = coalesce(listened_at, now()),
      delivered_at = coalesce(delivered_at, now()),
      is_read = true,
      read_at = coalesce(read_at, now())
   where id = p_message_id and receiver_id = auth.uid() and kind = 0;
end $$;

revoke all on function public.mark_delivered(uuid[]), public.mark_listened(uuid) from public, anon;
grant execute on function public.mark_delivered(uuid[]), public.mark_listened(uuid) to authenticated;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261207000000_message_receipts', 'Delivery, read and listened times on messages',
        array['public.messages'], array['messages.delivered_at', 'messages.read_at', 'messages.listened_at'])
on conflict (migration_id) do nothing;
