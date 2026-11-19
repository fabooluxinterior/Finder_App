-- =============================================================================
-- Finder security architecture
--   * End-to-end encrypted chat (Olm / Double Ratchet via vodozemac on device):
--     the server stores only per-device ciphertext envelopes and public keys.
--   * Encrypted media: originals are AES-256-GCM encrypted by the
--     process-image edge function and served only through the authorised
--     media function. No client can read the media buckets directly.
--   * Blocks, unmatch, reports with voluntary evidence, staff roles with an
--     append-only access audit trail, rate limits and security events.
-- Depends on 20261107000000_init_finder.sql.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Staff roles, audit trail, security events, rate limits
-- -----------------------------------------------------------------------------
create table if not exists public.staff_roles (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  role       text not null check (role in ('moderator', 'admin')),
  granted_by uuid references auth.users (id),
  granted_at timestamptz not null default now()
);
alter table public.staff_roles enable row level security;
-- No policies: only service role / security-definer functions can read it.

-- Sessions that completed MFA carry aal2 in the JWT.
create or replace function public.current_aal()
returns text language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'aal', 'aal1');
$$;

create or replace function public.mfa_enrolled(p_uid uuid)
returns boolean language sql stable security definer set search_path = public, auth as $$
  select exists (select 1 from auth.mfa_factors f where f.user_id = p_uid and f.status = 'verified');
$$;

-- Users who enrolled a second factor must use it for sensitive operations.
create or replace function public.mfa_satisfied()
returns boolean language sql stable security definer set search_path = public as $$
  select public.current_aal() = 'aal2' or not public.mfa_enrolled(auth.uid());
$$;

-- Staff must always be on an MFA (aal2) session.
create or replace function public.is_staff(p_role text default 'moderator')
returns boolean language sql stable security definer set search_path = public as $$
  select public.current_aal() = 'aal2' and exists (
    select 1 from public.staff_roles r
     where r.user_id = auth.uid()
       and (r.role = 'admin' or r.role = p_role));
$$;

create table if not exists public.security_events (
  id         bigint generated always as identity primary key,
  user_id    uuid references auth.users (id) on delete set null,
  kind       text not null,
  severity   text not null default 'info' check (severity in ('info', 'warning', 'critical')),
  details    jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists security_events_created_idx on public.security_events (created_at desc);
create index if not exists security_events_user_idx on public.security_events (user_id, created_at desc);
alter table public.security_events enable row level security;

-- Never put message content, keys, tokens or contact details in `details`.
create or replace function public.log_security_event(p_kind text, p_severity text, p_details jsonb default '{}', p_user uuid default auth.uid())
returns void language sql security definer set search_path = public as $$
  insert into public.security_events (user_id, kind, severity, details) values (p_user, p_kind, p_severity, coalesce(p_details, '{}'));
$$;

-- Append-only record of every staff access to private data.
create table if not exists public.access_audit_log (
  id         bigint generated always as identity primary key,
  actor_id   uuid not null references auth.users (id),
  action     text not null,
  target_type text not null,
  target_id  text not null,
  reason     text,
  created_at timestamptz not null default now()
);
alter table public.access_audit_log enable row level security;
revoke update, delete, truncate on public.access_audit_log from public, anon, authenticated, service_role;

create or replace function public.tg_block_mutation() returns trigger language plpgsql as $$
begin
  raise exception 'access_audit_log is append-only' using errcode = '42501';
end $$;
drop trigger if exists access_audit_log_immutable on public.access_audit_log;
create trigger access_audit_log_immutable before update or delete on public.access_audit_log
  for each row execute function public.tg_block_mutation();

create table if not exists public.rate_limits (
  user_id      uuid not null,
  bucket       text not null,
  window_start timestamptz not null,
  hits         int not null default 0,
  primary key (user_id, bucket, window_start)
);
alter table public.rate_limits enable row level security;

-- Fixed-window limiter. Raises RATE_LIMIT and logs a security event when exceeded.
create or replace function public.enforce_rate_limit(p_bucket text, p_max int, p_window interval)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_start timestamptz := to_timestamp(floor(extract(epoch from now()) / extract(epoch from p_window)) * extract(epoch from p_window));
  v_hits int;
begin
  if auth.uid() is null then return; end if;  -- trusted server context (service role)
  insert into public.rate_limits (user_id, bucket, window_start, hits)
  values (auth.uid(), p_bucket, v_start, 1)
  on conflict (user_id, bucket, window_start) do update set hits = public.rate_limits.hits + 1
  returning hits into v_hits;
  if v_hits > p_max then
    if v_hits = p_max + 1 then
      perform public.log_security_event('rate_limited', 'warning', jsonb_build_object('bucket', p_bucket));
    end if;
    raise exception 'Too many requests' using errcode = 'P0001', hint = 'RATE_LIMIT';
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- Blocks & connection semantics
-- -----------------------------------------------------------------------------
create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
alter table public.blocks enable row level security;
drop policy if exists blocks_own on public.blocks;
create policy blocks_own on public.blocks for select to authenticated using (blocker_id = auth.uid());

create or replace function public.is_blocked(p_a uuid, p_b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.blocks b
                  where (b.blocker_id = p_a and b.blocked_id = p_b)
                     or (b.blocker_id = p_b and b.blocked_id = p_a));
$$;

-- Connected = accepted follow AND no block in either direction.
-- Every chat, media and key-claim policy goes through this function, so a
-- block or unmatch cuts access immediately.
create or replace function public.is_connected(p_a uuid, p_b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.swipes_and_requests s
     where s.action = 'accepted'
       and ((s.sender_id = p_a and s.receiver_id = p_b) or (s.sender_id = p_b and s.receiver_id = p_a))
  ) and not public.is_blocked(p_a, p_b);
$$;

-- -----------------------------------------------------------------------------
-- E2EE: devices and one-time keys (public keys only)
-- -----------------------------------------------------------------------------
create table if not exists public.devices (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  curve25519  text not null unique check (char_length(curve25519) = 43),
  ed25519     text not null unique check (char_length(ed25519) = 43),
  label       text not null default 'Device' check (char_length(label) <= 60),
  platform    text not null check (platform in ('android', 'ios', 'web')),
  created_at  timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at  timestamptz
);
create index if not exists devices_user_idx on public.devices (user_id) where revoked_at is null;
alter table public.devices enable row level security;

-- Own devices, plus active devices of people you're connected to (needed to encrypt to them).
drop policy if exists devices_select on public.devices;
create policy devices_select on public.devices for select to authenticated
  using (user_id = auth.uid() or (revoked_at is null and public.is_connected(auth.uid(), user_id)));
revoke insert, update, delete on public.devices from authenticated, anon;

create table if not exists public.one_time_keys (
  id          bigint generated always as identity primary key,
  device_id   uuid not null references public.devices (id) on delete cascade,
  key_id      text not null,
  public_key  text not null check (char_length(public_key) = 43),
  signature   text not null check (char_length(signature) = 86),
  is_fallback boolean not null default false,
  created_at  timestamptz not null default now(),
  unique (device_id, key_id)
);
create index if not exists otk_device_idx on public.one_time_keys (device_id, is_fallback);
alter table public.one_time_keys enable row level security;
revoke all on public.one_time_keys from authenticated, anon;

-- Register this device's identity keys. New devices need MFA when enrolled.
create or replace function public.register_device(p_curve25519 text, p_ed25519 text, p_label text, p_platform text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_active int;
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if not public.mfa_satisfied() then
    raise exception 'Verify with your authenticator app to add a device' using errcode = '42501', hint = 'MFA_REQUIRED';
  end if;
  perform public.enforce_rate_limit('register_device', 5, interval '1 hour');

  select id into v_id from public.devices where user_id = auth.uid() and curve25519 = p_curve25519 and revoked_at is null;
  if found then
    update public.devices set last_seen_at = now() where id = v_id;
    return v_id;
  end if;

  select count(*) into v_active from public.devices where user_id = auth.uid() and revoked_at is null;
  if v_active >= 5 then
    raise exception 'Device limit reached. Remove a device first.' using errcode = 'P0001', hint = 'DEVICE_LIMIT';
  end if;

  insert into public.devices (user_id, curve25519, ed25519, label, platform)
  values (auth.uid(), p_curve25519, p_ed25519, left(coalesce(p_label, 'Device'), 60), p_platform)
  returning id into v_id;
  perform public.log_security_event('device_added', case when v_active > 0 then 'warning' else 'info' end,
    jsonb_build_object('device_id', v_id, 'platform', p_platform));
  return v_id;
end $$;

-- Revoking a device stops all new messages being encrypted to it and drops its pending envelopes.
create or replace function public.revoke_device(p_device uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.mfa_satisfied() then
    raise exception 'MFA required' using errcode = '42501', hint = 'MFA_REQUIRED';
  end if;
  update public.devices set revoked_at = now() where id = p_device and user_id = auth.uid() and revoked_at is null;
  if not found then raise exception 'Device not found' using errcode = 'P0002'; end if;
  delete from public.one_time_keys where device_id = p_device;
  delete from public.message_envelopes where recipient_device_id = p_device;
  perform public.log_security_event('device_revoked', 'warning', jsonb_build_object('device_id', p_device));
end $$;

-- Upload signed one-time keys for one of my devices.
create or replace function public.upload_one_time_keys(p_device uuid, p_keys jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  if not exists (select 1 from public.devices where id = p_device and user_id = auth.uid() and revoked_at is null) then
    raise exception 'Device not found' using errcode = '42501';
  end if;
  perform public.enforce_rate_limit('upload_otk', 30, interval '1 hour');
  if jsonb_array_length(p_keys) > 100 then raise exception 'Too many keys' using errcode = '22023'; end if;

  -- A new fallback key replaces the old one.
  if exists (select 1 from jsonb_array_elements(p_keys) k where (k ->> 'fallback')::boolean) then
    delete from public.one_time_keys where device_id = p_device and is_fallback;
  end if;
  insert into public.one_time_keys (device_id, key_id, public_key, signature, is_fallback)
  select p_device, k ->> 'key_id', k ->> 'public_key', k ->> 'signature', coalesce((k ->> 'fallback')::boolean, false)
    from jsonb_array_elements(p_keys) k
  on conflict (device_id, key_id) do nothing;

  select count(*) into v_count from public.one_time_keys where device_id = p_device and not is_fallback;
  return v_count;
end $$;

create or replace function public.one_time_key_count(p_device uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from public.one_time_keys k join public.devices d on d.id = k.device_id
   where k.device_id = p_device and d.user_id = auth.uid() and not k.is_fallback;
$$;

-- Atomically claim one key per active device of p_user (a peer you're
-- connected to, or yourself for your other devices). One-time keys are
-- deleted on claim; the fallback key is returned only when none remain.
-- Clients verify each key's Ed25519 signature before using it.
create or replace function public.claim_device_keys(p_user uuid, p_exclude uuid[] default '{}')
returns table (device_id uuid, curve25519 text, ed25519 text, key_id text, public_key text, signature text)
language plpgsql security definer set search_path = public as $$
declare d record; k record;
begin
  if p_user <> auth.uid() and not public.is_connected(auth.uid(), p_user) then
    perform public.log_security_event('key_claim_denied', 'warning', jsonb_build_object('target', p_user));
    raise exception 'Not connected' using errcode = '42501';
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

-- -----------------------------------------------------------------------------
-- E2EE messages: metadata row + one ciphertext envelope per recipient device
-- -----------------------------------------------------------------------------
alter table public.messages drop constraint if exists messages_has_body;
alter table public.messages drop column if exists content;
alter table public.messages drop column if exists audio_url;
alter table public.messages add column if not exists client_msg_id uuid;
alter table public.messages add column if not exists sender_device_id uuid references public.devices (id) on delete set null;
create unique index if not exists messages_client_id_idx on public.messages (sender_id, client_msg_id);

create table if not exists public.message_envelopes (
  message_id          uuid not null references public.messages (id) on delete cascade,
  recipient_device_id uuid not null references public.devices (id) on delete cascade,
  message_type        smallint not null check (message_type in (0, 1)),
  ciphertext          text not null check (char_length(ciphertext) <= 65536),
  created_at          timestamptz not null default now(),
  primary key (message_id, recipient_device_id)
);
create index if not exists envelopes_device_idx on public.message_envelopes (recipient_device_id, created_at);
alter table public.message_envelopes enable row level security;

drop policy if exists envelopes_select on public.message_envelopes;
create policy envelopes_select on public.message_envelopes for select to authenticated
  using (exists (
    select 1 from public.devices d join public.messages m on m.id = message_envelopes.message_id
     where d.id = message_envelopes.recipient_device_id and d.user_id = auth.uid() and d.revoked_at is null
       and public.is_connected(m.sender_id, m.receiver_id)));
revoke insert, update, delete on public.message_envelopes from authenticated, anon;

-- Direct inserts into messages are replaced by send_message().
drop policy if exists messages_insert on public.messages;
revoke insert on public.messages from authenticated;

-- Sends one E2EE message. p_envelopes: [{device_id, type, ciphertext}], one
-- per active device of the receiver and of the sender's other devices.
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

-- A device acknowledges envelopes after decrypting and storing them locally;
-- the server copy is deleted, so delivered ciphertext doesn't linger.
create or replace function public.ack_envelopes(p_device uuid, p_message_ids uuid[])
returns void language sql security definer set search_path = public as $$
  delete from public.message_envelopes e
   using public.devices d
   where d.id = p_device and d.user_id = auth.uid()
     and e.recipient_device_id = p_device and e.message_id = any (p_message_ids);
$$;

-- -----------------------------------------------------------------------------
-- Encrypted media (profile & gallery images)
-- -----------------------------------------------------------------------------
create table if not exists public.media_objects (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references public.profiles (id) on delete cascade,
  kind         text not null check (kind in ('primary', 'gallery')),
  status       text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'deleted')),
  storage_path text not null,
  wrapped_dek  text not null,  -- data key wrapped by the active KEK (never the KEK itself)
  kek_id       text not null,
  nonce        text not null,
  sha256       text not null,
  width        int not null,
  height       int not null,
  bytes        int not null,
  moderation   jsonb not null default '{}',  -- service-only
  created_at   timestamptz not null default now(),
  reviewed_at  timestamptz
);
create index if not exists media_owner_idx on public.media_objects (owner_id, kind);
alter table public.media_objects enable row level security;
revoke all on public.media_objects from authenticated, anon;

-- Owner-facing view without key material or moderation details.
create or replace view public.my_media with (security_invoker = false) as
  select id, kind, status, created_at from public.media_objects where owner_id = auth.uid() and status <> 'deleted';
grant select on public.my_media to authenticated;

-- Server-side authorisation used by the media delivery function.
create or replace function public.can_view_media(p_viewer uuid, p_media uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.media_objects m
     where m.id = p_media and m.status <> 'deleted'
       and not public.is_blocked(p_viewer, m.owner_id)
       and (
         m.owner_id = p_viewer
         or (m.status = 'approved' and m.kind = 'primary')
         or (m.status = 'approved' and m.kind = 'gallery' and public.is_connected(p_viewer, m.owner_id))
       ));
$$;

-- Client-facing media lists now carry media ids, never storage paths.
-- Only approved media is ever attached to a profile (done by process-image).
revoke update (avatar_urls) on public.profiles from authenticated;

create or replace function public.remove_media(p_media uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.media_objects set status = 'deleted' where id = p_media and owner_id = auth.uid();
  if not found then raise exception 'Not found' using errcode = 'P0002'; end if;
  update public.profiles set avatar_urls = array_remove(avatar_urls, p_media::text) where id = auth.uid();
  update public.profile_private set gallery_urls = array_remove(gallery_urls, p_media::text) where id = auth.uid();
  -- The encrypted object is purged by the purge-media job (storage API, service role).
end $$;

-- Lock down legacy direct-upload paths: uploads go to the quarantine bucket
-- and are processed server-side. Clients never read any media bucket.
drop policy if exists avatars_read on storage.objects;
drop policy if exists avatars_write_own on storage.objects;
drop policy if exists avatars_delete_own on storage.objects;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('uploads_quarantine', 'uploads_quarantine', false, 8388608, array['image/jpeg', 'image/png', 'image/webp']),
  ('media_encrypted',    'media_encrypted',    false, 2097152, array['application/octet-stream'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- Voice notes are now E2EE blobs (ciphertext only).
update storage.buckets set allowed_mime_types = array['application/octet-stream'] where id = 'voice_notes';

drop policy if exists quarantine_insert_own on storage.objects;
create policy quarantine_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'uploads_quarantine' and (storage.foldername(name))[1] = auth.uid()::text);

-- -----------------------------------------------------------------------------
-- Unmatch, block, reports
-- -----------------------------------------------------------------------------
-- Unmatch: ends the connection for both people and deletes server-side
-- message metadata and undelivered ciphertext for the pair.
create or replace function public.unmatch(p_peer uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.swipes_and_requests set action = 'rejected', responded_at = now()
   where action = 'accepted'
     and ((sender_id = auth.uid() and receiver_id = p_peer) or (sender_id = p_peer and receiver_id = auth.uid()));
  delete from public.messages
   where (sender_id = auth.uid() and receiver_id = p_peer) or (sender_id = p_peer and receiver_id = auth.uid());
end $$;

create or replace function public.block_user(p_peer uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_peer = auth.uid() then raise exception 'Invalid' using errcode = '22023'; end if;
  insert into public.blocks (blocker_id, blocked_id) values (auth.uid(), p_peer) on conflict do nothing;
  perform public.unmatch(p_peer);
  delete from public.swipes_and_requests
   where (sender_id = p_peer and receiver_id = auth.uid() and action = 'follow_requested');
end $$;

create table if not exists public.reports (
  id            uuid primary key default gen_random_uuid(),
  reporter_id   uuid not null references public.profiles (id) on delete cascade,
  reported_id   uuid not null references public.profiles (id) on delete cascade,
  reason        text not null check (reason in ('sexual_content', 'harassment', 'spam_or_scam', 'fake_profile', 'underage', 'malicious_link', 'other')),
  details       text check (char_length(details) <= 1000),
  -- Content the reporter chose to share, decrypted on their device.
  -- Shared only after an explicit consent prompt in the app.
  evidence      jsonb,
  evidence_consent_at timestamptz,
  status        text not null default 'open' check (status in ('open', 'reviewing', 'actioned', 'dismissed')),
  resolution    text,
  created_at    timestamptz not null default now(),
  resolved_at   timestamptz,
  resolved_by   uuid references auth.users (id),
  check (evidence is null or evidence_consent_at is not null)
);
create index if not exists reports_status_idx on public.reports (status, created_at);
alter table public.reports enable row level security;
-- Reporters can see the status of their own reports; evidence goes through staff RPCs only.
drop policy if exists reports_own on public.reports;
create policy reports_own on public.reports for select to authenticated using (reporter_id = auth.uid());
revoke all on public.reports from authenticated, anon;
grant select (id, reported_id, reason, status, created_at, resolved_at) on public.reports to authenticated;

create or replace function public.submit_report(p_reported uuid, p_reason text, p_details text, p_evidence jsonb, p_block boolean default true)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform public.enforce_rate_limit('report', 10, interval '1 day');
  if p_evidence is not null and (jsonb_typeof(p_evidence) <> 'array' or jsonb_array_length(p_evidence) > 20
                                 or octet_length(p_evidence::text) > 200000) then
    raise exception 'Evidence too large' using errcode = '22023';
  end if;
  insert into public.reports (reporter_id, reported_id, reason, details, evidence, evidence_consent_at)
  values (auth.uid(), p_reported, p_reason, p_details, p_evidence, case when p_evidence is null then null else now() end)
  returning id into v_id;
  if p_block then perform public.block_user(p_reported); end if;
  return v_id;
end $$;

-- -----------------------------------------------------------------------------
-- Staff (moderator / admin) RPCs. Every evidence read is audit-logged.
-- -----------------------------------------------------------------------------
create or replace function public.mod_list_reports(p_status text default 'open')
returns table (id uuid, reported_id uuid, reason text, has_evidence boolean, report_count bigint, created_at timestamptz, status text)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return query
    select r.id, r.reported_id, r.reason, r.evidence is not null,
           (select count(*) from public.reports x where x.reported_id = r.reported_id), r.created_at, r.status
      from public.reports r where r.status = p_status order by r.created_at limit 200;
end $$;

create or replace function public.mod_open_report(p_report uuid, p_reason text)
returns table (id uuid, reporter_id uuid, reported_id uuid, reason text, details text, evidence jsonb, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then
    perform public.log_security_event('staff_access_denied', 'critical', jsonb_build_object('report', p_report));
    raise exception 'Forbidden' using errcode = '42501';
  end if;
  if coalesce(char_length(trim(p_reason)), 0) < 5 then raise exception 'An access reason is required' using errcode = '22023'; end if;
  if p_report is null or not exists (select 1 from public.reports r where r.id = p_report) then
    raise exception 'Report not found' using errcode = 'P0002';
  end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason)
  values (auth.uid(), 'open_report_evidence', 'report', p_report::text, p_reason);
  update public.reports set status = 'reviewing' where reports.id = p_report and status = 'open';
  return query select r.id, r.reporter_id, r.reported_id, r.reason, r.details, r.evidence, r.created_at
                 from public.reports r where r.id = p_report;
end $$;

create or replace function public.mod_resolve_report(p_report uuid, p_status text, p_resolution text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  if p_status not in ('actioned', 'dismissed') then raise exception 'Invalid status' using errcode = '22023'; end if;
  update public.reports set status = p_status, resolution = p_resolution, resolved_at = now(), resolved_by = auth.uid()
   where id = p_report;
  -- Evidence is deleted 90 days after resolution by the retention job.
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason)
  values (auth.uid(), 'resolve_report:' || p_status, 'report', p_report::text, p_resolution);
end $$;

create or replace function public.admin_security_overview()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff('admin') then
    perform public.log_security_event('staff_access_denied', 'critical', '{"area":"security_overview"}');
    raise exception 'Forbidden' using errcode = '42501';
  end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id)
  values (auth.uid(), 'view_security_overview', 'dashboard', 'security');
  return jsonb_build_object(
    'events_24h', (select coalesce(jsonb_object_agg(kind, n), '{}') from (
        select kind, count(*) n from public.security_events where created_at > now() - interval '24 hours' group by kind) t),
    'critical_24h', (select count(*) from public.security_events where severity = 'critical' and created_at > now() - interval '24 hours'),
    'open_reports', (select count(*) from public.reports where status in ('open', 'reviewing')),
    'pending_media', (select count(*) from public.media_objects where status = 'pending'),
    'recent_events', (select coalesce(jsonb_agg(e order by e.created_at desc), '[]') from (
        select id, kind, severity, details, created_at from public.security_events order by created_at desc limit 50) e),
    'recent_staff_access', (select coalesce(jsonb_agg(a order by a.created_at desc), '[]') from (
        select actor_id, action, target_type, target_id, created_at from public.access_audit_log order by created_at desc limit 50) a)
  );
end $$;

-- -----------------------------------------------------------------------------
-- Sessions (Supabase Auth): list and revoke my own sessions
-- -----------------------------------------------------------------------------
create or replace function public.my_sessions()
returns table (id uuid, created_at timestamptz, updated_at timestamptz, user_agent text, aal text)
language sql stable security definer set search_path = public, auth as $$
  select s.id, s.created_at, s.updated_at, s.user_agent, s.aal::text
    from auth.sessions s where s.user_id = auth.uid() order by s.updated_at desc nulls last;
$$;

create or replace function public.revoke_session(p_session uuid)
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  delete from auth.sessions where id = p_session and user_id = auth.uid();  -- refresh tokens cascade
  if not found then raise exception 'Session not found' using errcode = 'P0002'; end if;
  perform public.log_security_event('session_revoked', 'info', jsonb_build_object('session', p_session));
end $$;

-- -----------------------------------------------------------------------------
-- Hardening of existing objects
-- -----------------------------------------------------------------------------
-- Rate limit swipes (in addition to the free-tier daily cap).
create or replace function public.tg_swipes_rate_limit() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.enforce_rate_limit('swipe', 120, interval '1 minute');
  if public.is_blocked(new.sender_id, new.receiver_id) then
    raise exception 'Not available' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists swipes_rate_limit on public.swipes_and_requests;
create trigger swipes_rate_limit before insert on public.swipes_and_requests
  for each row execute function public.tg_swipes_rate_limit();

-- Feed: also exclude blocked users in both directions.
create or replace function public.get_feed(p_limit int default 20)
returns table (id uuid, full_name text, age smallint, city text, bio text, primary_photo text, is_premium boolean)
language sql stable security definer set search_path = public as $$
  with me as (select p.id, lower(p.city) as city from public.profiles p where p.id = auth.uid())
  select p.id, p.full_name, p.age, p.city, p.bio, p.avatar_urls[1], public.is_premium(p.id)
    from public.profiles p, me
   where p.id <> me.id
     and not public.is_blocked(me.id, p.id)
     and cardinality(p.avatar_urls) > 0
     and not exists (
       select 1 from public.swipes_and_requests s
        where s.sender_id = me.id and s.receiver_id = p.id
          and not (s.action = 'pass' and s.created_at < now() - interval '7 days'))
     and not exists (
       select 1 from public.swipes_and_requests s
        where s.sender_id = p.id and s.receiver_id = me.id and s.action in ('accepted', 'rejected'))
   order by
     (public.is_premium(p.id) and lower(p.city) = me.city) desc,
     (lower(p.city) = me.city) desc,
     exists (select 1 from public.swipes_and_requests s
              where s.sender_id = p.id and s.receiver_id = me.id and s.action = 'follow_requested') desc,
     p.created_at desc
   limit least(greatest(p_limit, 1), 50);
$$;

-- Profiles: blocked users can't read each other's rows.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (not public.is_blocked(auth.uid(), id));

-- Account deletion (called by the delete-account edge function with the
-- user's JWT; that function then deletes the auth user and purges storage).
create or replace function public.prepare_account_deletion()
returns setof text language plpgsql security definer set search_path = public as $$
begin
  if not public.mfa_satisfied() then
    raise exception 'MFA required' using errcode = '42501', hint = 'MFA_REQUIRED';
  end if;
  perform public.log_security_event('account_deletion', 'info', '{}');
  update public.media_objects set status = 'deleted' where owner_id = auth.uid();
  return query select storage_path from public.media_objects where owner_id = auth.uid();
end $$;

-- Retention: drop old rate-limit windows, undelivered envelopes after 30
-- days, report evidence 90 days after resolution, security events after 1 year.
create or replace function public.run_retention()
returns void language sql security definer set search_path = public as $$
  delete from public.rate_limits where window_start < now() - interval '1 day';
  delete from public.message_envelopes where created_at < now() - interval '30 days';
  update public.reports set evidence = null where resolved_at < now() - interval '90 days' and evidence is not null;
  delete from public.security_events where created_at < now() - interval '365 days';
$$;

-- -----------------------------------------------------------------------------
-- Function privileges: nothing callable by anon; internal helpers not callable by clients.
-- -----------------------------------------------------------------------------
revoke all on all functions in schema public from public, anon;
grant execute on function
  public.register_device(text, text, text, text), public.revoke_device(uuid),
  public.upload_one_time_keys(uuid, jsonb), public.one_time_key_count(uuid),
  public.claim_device_keys(uuid, uuid[]), public.send_message(uuid, uuid, uuid, jsonb),
  public.ack_envelopes(uuid, uuid[]), public.remove_media(uuid),
  public.unmatch(uuid), public.block_user(uuid), public.submit_report(uuid, text, text, jsonb, boolean),
  public.mod_list_reports(text), public.mod_open_report(uuid, text), public.mod_resolve_report(uuid, text, text),
  public.admin_security_overview(), public.my_sessions(), public.revoke_session(uuid),
  public.prepare_account_deletion(),
  public.get_feed(int), public.swipe_profile(uuid, public.swipe_action, text),
  public.respond_to_request(uuid, boolean), public.incoming_request_count(), public.remaining_swipes(),
  -- used inside RLS policies evaluated as the caller:
  public.is_connected(uuid, uuid), public.is_blocked(uuid, uuid), public.is_premium(uuid),
  public.contains_contact_info(text), public.current_aal(), public.mfa_satisfied(), public.is_staff(text)
to authenticated;
revoke execute on function public.run_retention(), public.can_view_media(uuid, uuid),
  public.log_security_event(text, text, jsonb, uuid), public.enforce_rate_limit(text, int, interval)
  from authenticated;
grant execute on function public.can_view_media(uuid, uuid), public.run_retention() to service_role;

-- Realtime: envelopes are what devices subscribe to.
alter table public.message_envelopes replica identity full;
do $$ begin
  alter publication supabase_realtime add table public.message_envelopes;
exception when duplicate_object then null; end $$;

-- Schedule retention daily if pg_cron is available.
do $$ begin
  perform cron.schedule('finder-retention', '17 3 * * *', 'select public.run_retention()');
exception when others then null; end $$;

-- -----------------------------------------------------------------------------
-- Service-side helpers used by edge functions (service role only)
-- -----------------------------------------------------------------------------
create or replace function public.service_rate_limit(p_user uuid, p_bucket text, p_max int, p_window_seconds int)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_start timestamptz := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);
  v_hits int;
begin
  insert into public.rate_limits (user_id, bucket, window_start, hits) values (p_user, p_bucket, v_start, 1)
  on conflict (user_id, bucket, window_start) do update set hits = public.rate_limits.hits + 1
  returning hits into v_hits;
  return v_hits <= p_max;
end $$;

-- Attach an approved image to its owner's profile (primary replaces, gallery appends, max 9).
create or replace function public.attach_media(p_media uuid)
returns void language plpgsql security definer set search_path = public as $$
declare m public.media_objects;
begin
  select * into m from public.media_objects where id = p_media and status = 'approved';
  if not found then raise exception 'Media not approved' using errcode = 'P0002'; end if;
  if m.kind = 'primary' then
    update public.media_objects set status = 'deleted'
     where owner_id = m.owner_id and kind = 'primary' and id <> m.id and status <> 'deleted';
    update public.profiles set avatar_urls = array[m.id::text] where id = m.owner_id;
  else
    insert into public.profile_private (id) values (m.owner_id) on conflict (id) do nothing;
    update public.profile_private
       set gallery_urls = (array_append(array_remove(gallery_urls, m.id::text), m.id::text))[1:9]
     where id = m.owner_id;
  end if;
end $$;

-- Moderators approve or reject images that were held for review.
create or replace function public.mod_review_media(p_media uuid, p_approve boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  update public.media_objects set status = case when p_approve then 'approved' else 'rejected' end, reviewed_at = now()
   where id = p_media and status = 'pending';
  if not found then raise exception 'Not pending' using errcode = 'P0002'; end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id)
  values (auth.uid(), case when p_approve then 'approve_media' else 'reject_media' end, 'media', p_media::text);
  if p_approve then perform public.attach_media(p_media); end if;
end $$;

revoke all on function public.service_rate_limit(uuid, text, int, int), public.attach_media(uuid) from public, anon, authenticated;
grant execute on function public.service_rate_limit(uuid, text, int, int), public.attach_media(uuid) to service_role;
grant execute on function public.mod_review_media(uuid, boolean) to authenticated;

-- Defence in depth: internal tables are not readable by clients at all
-- (RLS with no policies already returns nothing).
revoke all on public.staff_roles, public.security_events, public.access_audit_log, public.rate_limits
  from authenticated, anon;

-- Photos are attached only by process-image after validation + moderation:
-- clients can't point their profile at someone else's media ids.
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert to authenticated with check (id = auth.uid() and is_premium = false and avatar_urls = '{}');

revoke insert, update on public.profile_private from authenticated;
grant insert (id, interests) on public.profile_private to authenticated;
grant update (interests, updated_at) on public.profile_private to authenticated;

-- Staff helpers for the in-app admin area.
create or replace function public.my_staff_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.staff_roles where user_id = auth.uid();
$$;

create or replace function public.mod_pending_media()
returns table (id uuid, owner_id uuid, kind text, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return query select m.id, m.owner_id, m.kind, m.created_at from public.media_objects m
                where m.status = 'pending' order by m.created_at limit 100;
end $$;

-- Lets the media function show pending images to moderators (audited there).
create or replace function public.staff_role_of(p_user uuid)
returns text language sql stable security definer set search_path = public as $$
  select role from public.staff_roles where user_id = p_user;
$$;
revoke all on function public.staff_role_of(uuid) from public, anon, authenticated;
grant execute on function public.staff_role_of(uuid) to service_role;
grant execute on function public.my_staff_role(), public.mod_pending_media() to authenticated;
