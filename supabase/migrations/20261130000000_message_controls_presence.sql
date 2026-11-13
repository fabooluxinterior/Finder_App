-- migration-id: 20261130000000_message_controls_presence
-- description: (1) Edit and delete for sent chat messages. Messages are end-to-end encrypted, so an edit or a delete
--   travels as one more encrypted message that points at the original; the server only sees an ordinary hidden
--   message (kind 1 = edit, 2 = delete). Hidden messages are born read and never raise a notification.
--   (2) Online / last seen: a tiny table of "last active" times, readable only through peer_presence(), which
--   answers only for people you are connected to and have not blocked.
-- tables: public.messages (column kind added), public.user_presence (new)
-- columns-added: messages.kind
-- backward-compat: Additive. send_message() is unchanged; older app versions never send kind 1/2 and ignore nothing
--   new. An older app that receives an edit or delete shows it as a short plain message.
-- recovery: drop function public.send_message_control(uuid, uuid, uuid, jsonb, smallint); drop function public.touch_presence();
--   drop function public.peer_presence(uuid); drop table public.user_presence; alter table public.messages drop column kind;
--   (restore notify_new_message() from 20261124000000_message_push_trigger.sql)
-- user-data: none changed; every existing message keeps kind 0
-- =============================================================================

alter table public.messages add column if not exists kind smallint not null default 0;
alter table public.messages drop constraint if exists messages_kind_valid;
alter table public.messages add constraint messages_kind_valid check (kind in (0, 1, 2));

-- No notification-bar alert for edits and deletes.
create or replace function public.notify_new_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_url text; v_secret text;
begin
  begin
    if new.kind <> 0 then return new; end if;
    if to_regproc('net.http_post') is null then return new; end if;
    select value into v_url from public.app_private_settings where key = 'push_webhook_url';
    select value into v_secret from public.app_private_settings where key = 'push_webhook_secret';
    if coalesce(v_url, '') = '' or coalesce(v_secret, '') = '' then return new; end if;
    perform net.http_post(
      url := v_url,
      body := jsonb_build_object('message_id', new.id),
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
      timeout_milliseconds := 5000);
  exception when others then
    null;
  end;
  return new;
end $$;
revoke all on function public.notify_new_message() from public, anon, authenticated;

-- Sends an encrypted edit (kind 1) or delete (kind 2). Same checks as send_message().
create or replace function public.send_message_control(
  p_receiver uuid, p_client_msg_id uuid, p_sender_device uuid, p_envelopes jsonb, p_kind smallint)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_bad int;
begin
  if p_kind not in (1, 2) then raise exception 'Invalid kind' using errcode = '22023'; end if;
  if not public.is_connected(auth.uid(), p_receiver) then
    raise exception 'Chat unlocks once the follow request is accepted' using errcode = '42501';
  end if;
  if not exists (select 1 from public.devices where id = p_sender_device and user_id = auth.uid() and revoked_at is null) then
    raise exception 'Unknown sender device' using errcode = '42501';
  end if;
  if not public.has_fast_track(auth.uid()) then
    raise exception 'Messaging is part of Fast-Track' using errcode = 'P0001', hint = 'SUBSCRIPTION_REQUIRED';
  end if;
  if public.active_restriction(auth.uid()) is not null then
    raise exception 'Your account can’t send messages right now' using errcode = 'P0001', hint = 'ACCOUNT_RESTRICTED';
  end if;
  perform public.enforce_rate_limit('send_message_control', 60, interval '1 minute');
  if jsonb_array_length(p_envelopes) = 0 or jsonb_array_length(p_envelopes) > 12 then
    raise exception 'Invalid envelopes' using errcode = '22023';
  end if;
  select count(*) into v_bad from jsonb_array_elements(p_envelopes) e
   where not exists (select 1 from public.devices d
                      where d.id = (e ->> 'device_id')::uuid and d.revoked_at is null
                        and d.user_id in (auth.uid(), p_receiver));
  if v_bad > 0 then raise exception 'Envelope for unknown device' using errcode = '42501'; end if;

  insert into public.messages (sender_id, receiver_id, client_msg_id, sender_device_id, kind, is_read)
  values (auth.uid(), p_receiver, p_client_msg_id, p_sender_device, p_kind, true)
  on conflict (sender_id, client_msg_id) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.messages where sender_id = auth.uid() and client_msg_id = p_client_msg_id;
    return v_id;
  end if;
  insert into public.message_envelopes (message_id, recipient_device_id, message_type, ciphertext)
  select v_id, (e ->> 'device_id')::uuid, (e ->> 'type')::smallint, e ->> 'ciphertext'
    from jsonb_array_elements(p_envelopes) e
   where (e ->> 'device_id')::uuid <> p_sender_device;
  return v_id;
end $$;
revoke all on function public.send_message_control(uuid, uuid, uuid, jsonb, smallint) from public, anon;
grant execute on function public.send_message_control(uuid, uuid, uuid, jsonb, smallint) to authenticated;

-- Online / last seen.
create table if not exists public.user_presence (
  user_id        uuid primary key references public.profiles (id) on delete cascade,
  last_active_at timestamptz not null default now()
);
alter table public.user_presence enable row level security;
revoke all on public.user_presence from anon, authenticated;

create or replace function public.touch_presence()
returns void language sql security definer set search_path = public as $$
  insert into public.user_presence (user_id, last_active_at)
  select auth.uid(), now() where auth.uid() is not null and exists (select 1 from public.profiles where id = auth.uid())
  on conflict (user_id) do update set last_active_at = now()
   where public.user_presence.last_active_at < now() - interval '20 seconds';
$$;
revoke all on function public.touch_presence() from public, anon;
grant execute on function public.touch_presence() to authenticated;

create or replace function public.peer_presence(p_peer uuid)
returns timestamptz language sql stable security definer set search_path = public as $$
  select up.last_active_at from public.user_presence up
   where up.user_id = p_peer and auth.uid() is not null
     and public.is_connected(auth.uid(), p_peer) and not public.is_blocked(auth.uid(), p_peer);
$$;
revoke all on function public.peer_presence(uuid) from public, anon;
grant execute on function public.peer_presence(uuid) to authenticated;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261130000000_message_controls_presence',
        'Encrypted edit/delete control messages (messages.kind) and online / last seen presence (user_presence)',
        array['public.messages', 'public.user_presence'], array['messages.kind'])
on conflict (migration_id) do nothing;
