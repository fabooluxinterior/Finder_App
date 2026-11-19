-- =============================================================================
-- Subscription model (no free trial)
--   Free:         browse profiles, pass, send follow requests (no daily cap).
--   Fast-Track:   see who requested you, accept requests, send messages.
--   Direct DM notes are removed.
-- Every rule is enforced here; the app only reflects it.
-- =============================================================================

-- Direct DM notes are gone.
alter table public.swipes_and_requests drop constraint if exists swipes_note_clean;
alter table public.swipes_and_requests drop column if exists direct_note;

-- New swipes: pass or follow_requested, free for everyone (rate limited by
-- tg_swipes_rate_limit). No daily cap and no premium-only notes.
create or replace function public.tg_swipes_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.action not in ('pass', 'follow_requested') then
    raise exception 'New swipes must be pass or follow_requested' using errcode = '22023';
  end if;
  return new;
end $$;

-- Receiver may only move follow_requested -> accepted | rejected.
create or replace function public.tg_swipes_before_update()
returns trigger language plpgsql as $$
begin
  if new.sender_id <> old.sender_id or new.receiver_id <> old.receiver_id or new.created_at <> old.created_at then
    raise exception 'Only the request status can change' using errcode = '42501';
  end if;
  if old.action <> 'follow_requested' or new.action not in ('accepted', 'rejected') then
    raise exception 'Invalid status transition % -> %', old.action, new.action using errcode = '22023';
  end if;
  new.responded_at := now();
  return new;
end $$;

-- Direct status updates are replaced by respond_to_request (subscription check).
drop policy if exists swipes_update_receiver on public.swipes_and_requests;
revoke update on public.swipes_and_requests from authenticated;

drop function if exists public.swipe_profile(uuid, public.swipe_action, text);
drop function if exists public.remaining_swipes();

-- Single entry point for swiping. A mutual request is an instant match for
-- everyone; chatting afterwards still needs Fast-Track.
create or replace function public.swipe_profile(p_target uuid, p_action public.swipe_action)
returns text language plpgsql security definer set search_path = public as $$
declare v_me uuid := auth.uid(); v_reverse public.swipes_and_requests;
begin
  if v_me is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_action not in ('pass', 'follow_requested') then
    raise exception 'Invalid swipe action' using errcode = '22023';
  end if;

  delete from public.swipes_and_requests
   where sender_id = v_me and receiver_id = p_target
     and action = 'pass' and created_at < now() - interval '7 days';

  if p_action = 'pass' then
    insert into public.swipes_and_requests (sender_id, receiver_id, action)
    values (v_me, p_target, 'pass') on conflict (sender_id, receiver_id) do nothing;
    return 'passed';
  end if;

  select * into v_reverse from public.swipes_and_requests
   where sender_id = p_target and receiver_id = v_me and action = 'follow_requested' for update;
  if found then
    update public.swipes_and_requests set action = 'accepted', responded_at = now() where id = v_reverse.id;
    return 'matched';
  end if;

  insert into public.swipes_and_requests (sender_id, receiver_id, action)
  values (v_me, p_target, 'follow_requested')
  on conflict (sender_id, receiver_id) do nothing;
  return 'requested';
end $$;

-- Seeing and answering received requests is a Fast-Track feature.
-- (Pending rows are already hidden from free users by swipes_select.)
create or replace function public.respond_to_request(p_request_id uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_premium(auth.uid()) then
    raise exception 'Seeing requests is part of Fast-Track' using errcode = 'P0001', hint = 'SUBSCRIPTION_REQUIRED';
  end if;
  update public.swipes_and_requests
     set action = case when p_accept then 'accepted'::public.swipe_action else 'rejected'::public.swipe_action end,
         responded_at = now()
   where id = p_request_id and receiver_id = auth.uid() and action = 'follow_requested';
  if not found then raise exception 'Request not found' using errcode = 'P0002'; end if;
end $$;

-- Messaging requires an active subscription (checked on every send).
create or replace function public.send_message(p_receiver uuid, p_client_msg_id uuid, p_sender_device uuid, p_envelopes jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_bad int;
begin
  if not public.is_connected(auth.uid(), p_receiver) then
    perform public.log_security_event('send_denied', 'warning', jsonb_build_object('target', p_receiver));
    raise exception 'Chat unlocks once the follow request is accepted' using errcode = '42501';
  end if;
  if not exists (select 1 from public.devices where id = p_sender_device and user_id = auth.uid() and revoked_at is null) then
    raise exception 'Unknown sender device' using errcode = '42501';
  end if;
  if not public.is_premium(auth.uid()) then
    raise exception 'Messaging is part of Fast-Track' using errcode = 'P0001', hint = 'SUBSCRIPTION_REQUIRED';
  end if;
  perform public.enforce_rate_limit('send_message', 40, interval '1 minute');
  if jsonb_array_length(p_envelopes) = 0 or jsonb_array_length(p_envelopes) > 12 then
    raise exception 'Invalid envelopes' using errcode = '22023';
  end if;

  -- Every envelope must target an active device of the sender or receiver.
  select count(*) into v_bad from jsonb_array_elements(p_envelopes) e
   where not exists (select 1 from public.devices d
                      where d.id = (e ->> 'device_id')::uuid and d.revoked_at is null
                        and d.user_id in (auth.uid(), p_receiver));
  if v_bad > 0 then raise exception 'Envelope for unknown device' using errcode = '42501'; end if;

  insert into public.messages (sender_id, receiver_id, client_msg_id, sender_device_id)
  values (auth.uid(), p_receiver, p_client_msg_id, p_sender_device)
  on conflict (sender_id, client_msg_id) do nothing
  returning id into v_id;
  if v_id is null then  -- idempotent retry
    select id into v_id from public.messages where sender_id = auth.uid() and client_msg_id = p_client_msg_id;
    return v_id;
  end if;

  insert into public.message_envelopes (message_id, recipient_device_id, message_type, ciphertext)
  select v_id, (e ->> 'device_id')::uuid, (e ->> 'type')::smallint, e ->> 'ciphertext'
    from jsonb_array_elements(p_envelopes) e
    -- Never store an envelope addressed to the sending device itself.
   where (e ->> 'device_id')::uuid <> p_sender_device;
  return v_id;
end $$;

create or replace function public.claim_device_keys(p_user uuid, p_exclude uuid[] default '{}')
returns table (device_id uuid, curve25519 text, ed25519 text, key_id text, public_key text, signature text)
language plpgsql security definer set search_path = public as $$
declare d record; k record;
begin
  if p_user <> auth.uid() and not public.is_connected(auth.uid(), p_user) then
    perform public.log_security_event('key_claim_denied', 'warning', jsonb_build_object('target', p_user));
    raise exception 'Not connected' using errcode = '42501';
  end if;
  -- Keys of other people are only needed to send them messages: subscribers only.
  if p_user <> auth.uid() and not public.is_premium(auth.uid()) then
    raise exception 'Messaging is part of Fast-Track' using errcode = 'P0001', hint = 'SUBSCRIPTION_REQUIRED';
  end if;
  perform public.enforce_rate_limit('claim_keys', 120, interval '1 hour');

  for d in select * from public.devices x
            where x.user_id = p_user and x.revoked_at is null and not (x.id = any (p_exclude))
  loop
    select * into k from public.one_time_keys o
     where o.device_id = d.id and not o.is_fallback
     order by o.id limit 1 for update skip locked;
    if found then
      delete from public.one_time_keys where id = k.id;
    else
      select * into k from public.one_time_keys o where o.device_id = d.id and o.is_fallback limit 1;
      if not found then continue; end if;
    end if;
    device_id := d.id; curve25519 := d.curve25519; ed25519 := d.ed25519;
    key_id := k.key_id; public_key := k.public_key; signature := k.signature;
    return next;
  end loop;
end $$;

revoke all on function public.swipe_profile(uuid, public.swipe_action), public.respond_to_request(uuid, boolean),
  public.send_message(uuid, uuid, uuid, jsonb), public.claim_device_keys(uuid, uuid[]) from public, anon;
grant execute on function public.swipe_profile(uuid, public.swipe_action), public.respond_to_request(uuid, boolean),
  public.send_message(uuid, uuid, uuid, jsonb), public.claim_device_keys(uuid, uuid[]) to authenticated;
