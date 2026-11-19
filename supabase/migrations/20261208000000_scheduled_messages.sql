-- migration-id: 20261208000000_scheduled_messages
-- description: Scheduled messages that are delivered by the server, so they are sent at the chosen time even if the
--   sender's phone is off, offline, logged out or the app is closed. Chats are end-to-end encrypted, so the sender's
--   phone encrypts the message when scheduling it (exactly as for a normal send) and the server only stores and
--   releases that ciphertext; it never sees the text. A job runs every 15 seconds (pg_cron), is idempotent
--   (one row per client message id; delivery inserts at most one message), retries failures with back-off and
--   survives restarts because everything lives in the database.
-- tables: public.scheduled_messages (new)
-- columns-added: none
-- backward-compat: Additive. send_message and the messages table are unchanged; the recipient receives a normal message.
-- recovery: select cron.unschedule('vouby-deliver-scheduled'); drop function public.schedule_message(uuid, uuid, uuid, jsonb, timestamptz, text),
--   public.cancel_scheduled_message(uuid), public.my_scheduled_messages(uuid), public.service_deliver_scheduled();
--   drop table public.scheduled_messages;
-- user-data: none changed
-- =============================================================================

create table if not exists public.scheduled_messages (
  id              uuid primary key default gen_random_uuid(),
  sender_id       uuid not null references public.profiles (id) on delete cascade,
  receiver_id     uuid not null references public.profiles (id) on delete cascade,
  client_msg_id   uuid not null,
  sender_device_id uuid not null,
  envelopes       jsonb not null check (jsonb_typeof(envelopes) = 'array'),
  send_at         timestamptz not null,
  tz              text check (tz is null or char_length(tz) <= 64),
  status          text not null default 'scheduled' check (status in ('scheduled', 'sent', 'failed', 'cancelled')),
  attempts        int not null default 0,
  next_attempt_at timestamptz not null default now(),
  last_error      text,
  message_id      uuid,
  created_at      timestamptz not null default now(),
  sent_at         timestamptz,
  unique (sender_id, client_msg_id)
);
create index if not exists scheduled_messages_due_idx on public.scheduled_messages (next_attempt_at) where status = 'scheduled';
create index if not exists scheduled_messages_sender_idx on public.scheduled_messages (sender_id, created_at desc);
alter table public.scheduled_messages enable row level security;
revoke all on public.scheduled_messages from anon, authenticated;

-- The sender hands over an already-encrypted message and the time to release it.
create or replace function public.schedule_message(
  p_receiver uuid, p_client_msg_id uuid, p_sender_device uuid, p_envelopes jsonb, p_send_at timestamptz, p_tz text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_bad int;
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
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
  if p_send_at is null or p_send_at < now() + interval '20 seconds' then
    raise exception 'Choose a time in the future' using errcode = '22023';
  end if;
  perform public.enforce_rate_limit('schedule_message', 60, interval '1 hour');
  -- No limit on how far ahead; only a generous cap on how many are waiting at once (abuse protection).
  if (select count(*) from public.scheduled_messages where sender_id = auth.uid() and status = 'scheduled') >= 500 then
    raise exception 'Too many scheduled messages waiting' using errcode = '53400';
  end if;
  if jsonb_array_length(p_envelopes) = 0 or jsonb_array_length(p_envelopes) > 12 then
    raise exception 'Invalid envelopes' using errcode = '22023';
  end if;
  select count(*) into v_bad from jsonb_array_elements(p_envelopes) e
   where not exists (select 1 from public.devices d
                      where d.id = (e ->> 'device_id')::uuid and d.revoked_at is null
                        and d.user_id in (auth.uid(), p_receiver));
  if v_bad > 0 then raise exception 'Envelope for unknown device' using errcode = '42501'; end if;

  insert into public.scheduled_messages (sender_id, receiver_id, client_msg_id, sender_device_id, envelopes, send_at, tz, next_attempt_at)
  values (auth.uid(), p_receiver, p_client_msg_id, p_sender_device, p_envelopes, p_send_at, left(p_tz, 64), p_send_at)
  on conflict (sender_id, client_msg_id) do nothing
  returning id into v_id;
  if v_id is null then  -- idempotent retry of the same request
    select id into v_id from public.scheduled_messages where sender_id = auth.uid() and client_msg_id = p_client_msg_id;
  end if;
  return v_id;
end $$;

create or replace function public.cancel_scheduled_message(p_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  update public.scheduled_messages set status = 'cancelled', envelopes = '[]'
   where id = p_id and sender_id = auth.uid() and status = 'scheduled';
  get diagnostics v_n = row_count;
  return v_n > 0;
end $$;

-- The sender's list (optionally for one chat): waiting, sent, failed and cancelled in the last 30 days.
create or replace function public.my_scheduled_messages(p_peer uuid default null)
returns table (id uuid, receiver_id uuid, client_msg_id uuid, send_at timestamptz, tz text, status text,
               attempts int, last_error text, message_id uuid, sent_at timestamptz, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select s.id, s.receiver_id, s.client_msg_id, s.send_at, s.tz, s.status, s.attempts, s.last_error, s.message_id, s.sent_at, s.created_at
    from public.scheduled_messages s
   where s.sender_id = auth.uid() and (p_peer is null or s.receiver_id = p_peer)
     and (s.status = 'scheduled' or s.created_at > now() - interval '30 days')
   order by case s.status when 'scheduled' then 0 else 1 end, s.send_at;
$$;

-- Releases everything that is due. Safe to run concurrently and repeatedly.
create or replace function public.service_deliver_scheduled()
returns int language plpgsql security definer set search_path = public as $$
declare r public.scheduled_messages; v_id uuid; v_done int := 0; v_reason text;
begin
  for r in
    select * from public.scheduled_messages
     where status = 'scheduled' and send_at <= now() and next_attempt_at <= now()
     order by send_at limit 200
     for update skip locked
  loop
    begin
      v_reason := null;
      if not public.is_connected(r.sender_id, r.receiver_id) then v_reason := 'You are no longer connected.';
      elsif not exists (select 1 from public.devices where id = r.sender_device_id and user_id = r.sender_id and revoked_at is null)
        then v_reason := 'The phone that scheduled this was signed out.';
      elsif not public.has_fast_track(r.sender_id) then v_reason := 'Messaging needs Fast-Track.';
      elsif public.active_restriction(r.sender_id) is not null then v_reason := 'Your account can’t send messages right now.';
      end if;
      if v_reason is not null then
        update public.scheduled_messages set status = 'failed', last_error = v_reason, envelopes = '[]' where id = r.id;
        insert into public.user_notifications (user_id, kind, title, body)
        values (r.sender_id, 'scheduled_failed', 'A scheduled message wasn’t sent', v_reason);
        continue;
      end if;

      insert into public.messages (sender_id, receiver_id, client_msg_id, sender_device_id)
      values (r.sender_id, r.receiver_id, r.client_msg_id, r.sender_device_id)
      on conflict (sender_id, client_msg_id) do nothing
      returning id into v_id;
      if v_id is null then
        select id into v_id from public.messages where sender_id = r.sender_id and client_msg_id = r.client_msg_id;
      else
        insert into public.message_envelopes (message_id, recipient_device_id, message_type, ciphertext)
        select v_id, (e ->> 'device_id')::uuid, (e ->> 'type')::smallint, e ->> 'ciphertext'
          from jsonb_array_elements(r.envelopes) e
         where (e ->> 'device_id')::uuid <> r.sender_device_id
           and exists (select 1 from public.devices d where d.id = (e ->> 'device_id')::uuid and d.revoked_at is null
                        and d.user_id in (r.sender_id, r.receiver_id));
      end if;
      update public.scheduled_messages set status = 'sent', message_id = v_id, sent_at = now(), envelopes = '[]', last_error = null where id = r.id;
      v_done := v_done + 1;
    exception when others then
      -- Retry later with back-off (1, 5, 15, 60 minutes); give up after five attempts and tell the sender.
      update public.scheduled_messages set
          attempts = attempts + 1,
          last_error = left(sqlerrm, 300),
          next_attempt_at = now() + case attempts when 0 then interval '1 minute' when 1 then interval '5 minutes'
                                                  when 2 then interval '15 minutes' else interval '60 minutes' end,
          status = case when attempts + 1 >= 5 then 'failed' else 'scheduled' end,
          envelopes = case when attempts + 1 >= 5 then '[]'::jsonb else envelopes end
       where id = r.id;
      if r.attempts + 1 >= 5 then
        insert into public.user_notifications (user_id, kind, title, body)
        values (r.sender_id, 'scheduled_failed', 'A scheduled message wasn’t sent', 'It could not be delivered. Please schedule it again.');
      end if;
    end;
  end loop;
  return v_done;
end $$;

revoke all on function public.schedule_message(uuid, uuid, uuid, jsonb, timestamptz, text), public.cancel_scheduled_message(uuid),
  public.my_scheduled_messages(uuid), public.service_deliver_scheduled() from public, anon;
grant execute on function public.schedule_message(uuid, uuid, uuid, jsonb, timestamptz, text), public.cancel_scheduled_message(uuid),
  public.my_scheduled_messages(uuid) to authenticated;
grant execute on function public.service_deliver_scheduled() to service_role;

-- The persistent scheduler: every 15 seconds. Where pg_cron isn't installed (a plain test database) this is skipped.
do $$
begin
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname = 'vouby-deliver-scheduled';
  perform cron.schedule('vouby-deliver-scheduled', '15 seconds', 'select public.service_deliver_scheduled()');
exception when others then
  raise notice 'pg_cron not available, scheduled delivery job not created: %', sqlerrm;
end $$;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261208000000_scheduled_messages', 'Server-side scheduled messages (end-to-end encrypted, delivered by a persistent job)',
        array['public.scheduled_messages'], array[]::text[])
on conflict (migration_id) do nothing;
