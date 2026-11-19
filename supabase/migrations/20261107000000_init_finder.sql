-- =============================================================================
-- Finder: private social connection network
-- Schema, RLS, RPCs, storage policies, realtime.
-- =============================================================================

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- Types
-- -----------------------------------------------------------------------------
do $$ begin
  create type public.swipe_action as enum ('pass', 'follow_requested', 'accepted', 'rejected');
exception when duplicate_object then null; end $$;

-- -----------------------------------------------------------------------------
-- Contact-info guard (server-side mirror of the client sanitizer).
-- Rejects phone numbers, @handles and URLs.
-- -----------------------------------------------------------------------------
create or replace function public.contains_contact_info(p_text text)
returns boolean
language sql
immutable
as $$
  select coalesce(p_text, '') ~* (
       '(\+?\d[\d\s\-().]{7,}\d)'                              -- phone numbers
    || '|(^|[^[:alnum:]_])@[a-z0-9_.]{2,}'                      -- @handles
    || '|((https?://|www\.)\S+)'                                -- explicit URLs
    || '|([a-z0-9-]+\.(com|in|net|org|io|me|co|app|link|ly|gg|xyz)(/\S*)?([^[:alnum:]]|$))'
  );
$$;

-- -----------------------------------------------------------------------------
-- profiles (public card data)
--   avatar_urls[1] is the primary photo (storage path in bucket 'avatars',
--   under '<uid>/primary/'). The locked gallery lives in profile_private.
-- -----------------------------------------------------------------------------
create table if not exists public.profiles (
  id                  uuid primary key references auth.users (id) on delete cascade,
  full_name           text        not null check (char_length(full_name) between 1 and 60),
  age                 smallint    not null check (age between 18 and 99),
  city                text        not null check (char_length(city) between 2 and 60),
  bio                 text        not null default '' check (char_length(bio) <= 300),
  avatar_urls         text[]      not null default '{}' check (cardinality(avatar_urls) <= 1),
  is_premium          boolean     not null default false,
  premium_expires_at  timestamptz,
  created_at          timestamptz not null default now(),
  constraint profiles_bio_clean check (not public.contains_contact_info(bio))
);

create index if not exists profiles_city_idx on public.profiles (lower(city));
create index if not exists profiles_premium_city_idx on public.profiles (lower(city)) where is_premium;

-- -----------------------------------------------------------------------------
-- profile_private (locked until follow is accepted)
-- -----------------------------------------------------------------------------
create table if not exists public.profile_private (
  id            uuid primary key references public.profiles (id) on delete cascade,
  interests     text[] not null default '{}' check (cardinality(interests) <= 15),
  gallery_urls  text[] not null default '{}' check (cardinality(gallery_urls) <= 9),
  updated_at    timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- swipes_and_requests
-- -----------------------------------------------------------------------------
create table if not exists public.swipes_and_requests (
  id           uuid primary key default gen_random_uuid(),
  sender_id    uuid not null references public.profiles (id) on delete cascade,
  receiver_id  uuid not null references public.profiles (id) on delete cascade,
  action       public.swipe_action not null,
  direct_note  text check (direct_note is null or char_length(direct_note) <= 100),
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  constraint swipes_unique_pair unique (sender_id, receiver_id),
  constraint swipes_no_self check (sender_id <> receiver_id),
  constraint swipes_note_clean check (not public.contains_contact_info(direct_note))
);

create index if not exists swipes_receiver_action_idx on public.swipes_and_requests (receiver_id, action);
create index if not exists swipes_sender_created_idx on public.swipes_and_requests (sender_id, created_at desc);

-- -----------------------------------------------------------------------------
-- messages
-- -----------------------------------------------------------------------------
create table if not exists public.messages (
  id           uuid primary key default gen_random_uuid(),
  sender_id    uuid not null references public.profiles (id) on delete cascade,
  receiver_id  uuid not null references public.profiles (id) on delete cascade,
  content      text check (content is null or char_length(content) <= 2000),
  audio_url    text,
  is_read      boolean not null default false,
  created_at   timestamptz not null default now(),
  constraint messages_has_body check (content is not null or audio_url is not null),
  constraint messages_no_self check (sender_id <> receiver_id)
);

create index if not exists messages_pair_created_idx
  on public.messages (least(sender_id, receiver_id), greatest(sender_id, receiver_id), created_at);
create index if not exists messages_receiver_unread_idx on public.messages (receiver_id) where not is_read;

-- -----------------------------------------------------------------------------
-- Helper functions (security definer so they can be used inside RLS
-- without recursive policy evaluation)
-- -----------------------------------------------------------------------------
create or replace function public.is_premium(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select p.is_premium and (p.premium_expires_at is null or p.premium_expires_at > now())
       from public.profiles p where p.id = p_uid),
    false);
$$;

create or replace function public.is_connected(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.swipes_and_requests s
     where s.action = 'accepted'
       and ((s.sender_id = p_a and s.receiver_id = p_b)
         or (s.sender_id = p_b and s.receiver_id = p_a))
  );
$$;

-- -----------------------------------------------------------------------------
-- Guard triggers
-- -----------------------------------------------------------------------------

-- Free tier: 10 follow requests / rolling 24h. Direct notes are premium only.
create or replace function public.tg_swipes_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  if new.action not in ('pass', 'follow_requested') then
    raise exception 'New swipes must be pass or follow_requested' using errcode = '22023';
  end if;

  if new.action = 'pass' then
    new.direct_note := null;
    return new;
  end if;

  if new.direct_note is not null and not public.is_premium(new.sender_id) then
    raise exception 'Direct DM Invite requires the Fast-Track pass' using errcode = 'P0001', hint = 'PREMIUM_REQUIRED';
  end if;

  if not public.is_premium(new.sender_id) then
    select count(*) into v_count
      from public.swipes_and_requests s
     where s.sender_id = new.sender_id
       and s.action <> 'pass'
       and s.created_at > now() - interval '24 hours';
    if v_count >= 10 then
      raise exception 'Daily follow request limit reached' using errcode = 'P0001', hint = 'SWIPE_LIMIT';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists swipes_before_insert on public.swipes_and_requests;
create trigger swipes_before_insert
  before insert on public.swipes_and_requests
  for each row execute function public.tg_swipes_before_insert();

-- Receiver may only move follow_requested -> accepted | rejected; nothing else changes.
create or replace function public.tg_swipes_before_update()
returns trigger
language plpgsql
as $$
begin
  if new.sender_id <> old.sender_id
     or new.receiver_id <> old.receiver_id
     or new.direct_note is distinct from old.direct_note
     or new.created_at <> old.created_at then
    raise exception 'Only the request status can change' using errcode = '42501';
  end if;
  if old.action <> 'follow_requested' or new.action not in ('accepted', 'rejected') then
    raise exception 'Invalid status transition % -> %', old.action, new.action using errcode = '22023';
  end if;
  new.responded_at := now();
  return new;
end;
$$;

drop trigger if exists swipes_before_update on public.swipes_and_requests;
create trigger swipes_before_update
  before update on public.swipes_and_requests
  for each row
  when (current_user in ('authenticated', 'anon'))
  execute function public.tg_swipes_before_update();

-- Messages: only is_read may be flipped (by the receiver).
create or replace function public.tg_messages_before_update()
returns trigger
language plpgsql
as $$
begin
  if new.sender_id <> old.sender_id or new.receiver_id <> old.receiver_id
     or new.content is distinct from old.content or new.audio_url is distinct from old.audio_url
     or new.created_at <> old.created_at then
    raise exception 'Messages are immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists messages_before_update on public.messages;
create trigger messages_before_update
  before update on public.messages
  for each row execute function public.tg_messages_before_update();

-- -----------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------
alter table public.profiles            enable row level security;
alter table public.profile_private     enable row level security;
alter table public.swipes_and_requests enable row level security;
alter table public.messages            enable row level security;

-- profiles: authenticated read; insert/update own row only.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated using (true);

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert to authenticated with check (id = auth.uid() and is_premium = false);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- is_premium / premium_expires_at are written only by the RevenueCat webhook (service role).
revoke update on public.profiles from authenticated;
grant  update (full_name, age, city, bio, avatar_urls) on public.profiles to authenticated;

-- profile_private: owner, or an accepted connection.
drop policy if exists profile_private_select on public.profile_private;
create policy profile_private_select on public.profile_private
  for select to authenticated
  using (id = auth.uid() or public.is_connected(auth.uid(), id));

drop policy if exists profile_private_insert_own on public.profile_private;
create policy profile_private_insert_own on public.profile_private
  for insert to authenticated with check (id = auth.uid());

drop policy if exists profile_private_update_own on public.profile_private;
create policy profile_private_update_own on public.profile_private
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- swipes: participants only. Pending incoming requests are hidden from free
-- receivers (the "Who Requested You" blur is enforced server-side, not just in UI).
drop policy if exists swipes_select on public.swipes_and_requests;
create policy swipes_select on public.swipes_and_requests
  for select to authenticated
  using (
    sender_id = auth.uid()
    or (receiver_id = auth.uid()
        and (action <> 'follow_requested' or public.is_premium(auth.uid())))
  );

drop policy if exists swipes_insert on public.swipes_and_requests;
create policy swipes_insert on public.swipes_and_requests
  for insert to authenticated
  with check (sender_id = auth.uid() and action in ('pass', 'follow_requested'));

drop policy if exists swipes_update_receiver on public.swipes_and_requests;
create policy swipes_update_receiver on public.swipes_and_requests
  for update to authenticated
  using (receiver_id = auth.uid())
  with check (receiver_id = auth.uid() and action in ('accepted', 'rejected'));

-- messages: only between accepted connections.
drop policy if exists messages_select on public.messages;
create policy messages_select on public.messages
  for select to authenticated
  using (
    (sender_id = auth.uid() or receiver_id = auth.uid())
    and public.is_connected(sender_id, receiver_id)
  );

drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and is_read = false
    and public.is_connected(sender_id, receiver_id)
  );

drop policy if exists messages_mark_read on public.messages;
create policy messages_mark_read on public.messages
  for update to authenticated
  using (receiver_id = auth.uid() and public.is_connected(sender_id, receiver_id))
  with check (receiver_id = auth.uid());

revoke update on public.messages from authenticated;
grant  update (is_read) on public.messages to authenticated;

-- -----------------------------------------------------------------------------
-- RPCs
-- -----------------------------------------------------------------------------

-- Discovery feed: excludes self, connections, anyone I already requested,
-- passes from the last 7 days and people who rejected me.
-- Ordering: Kerala City Boost (premium users in my city) -> same city ->
-- people who already requested me -> newest.
create or replace function public.get_feed(p_limit int default 20)
returns table (
  id uuid, full_name text, age smallint, city text, bio text,
  primary_photo text, is_premium boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with me as (select p.id, lower(p.city) as city from public.profiles p where p.id = auth.uid())
  select p.id, p.full_name, p.age, p.city, p.bio, p.avatar_urls[1],
         public.is_premium(p.id)
    from public.profiles p, me
   where p.id <> me.id
     and not exists (
       select 1 from public.swipes_and_requests s
        where s.sender_id = me.id and s.receiver_id = p.id
          and not (s.action = 'pass' and s.created_at < now() - interval '7 days'))
     and not exists (
       select 1 from public.swipes_and_requests s
        where s.sender_id = p.id and s.receiver_id = me.id
          and s.action in ('accepted', 'rejected'))
   order by
     (public.is_premium(p.id) and lower(p.city) = me.city) desc,
     (lower(p.city) = me.city) desc,
     exists (select 1 from public.swipes_and_requests s
              where s.sender_id = p.id and s.receiver_id = me.id
                and s.action = 'follow_requested') desc,
     p.created_at desc
   limit least(greatest(p_limit, 1), 50);
$$;

-- Single entry point for swiping. Handles:
--   * re-swiping after a 7-day pass expiry,
--   * instant mutual match when the target already requested me.
-- Returns 'passed' | 'requested' | 'matched'.
create or replace function public.swipe_profile(
  p_target uuid, p_action public.swipe_action, p_note text default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_reverse public.swipes_and_requests;
begin
  if v_me is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_action not in ('pass', 'follow_requested') then
    raise exception 'Invalid swipe action' using errcode = '22023';
  end if;

  -- Expired pass: drop it so the user can swipe again.
  delete from public.swipes_and_requests
   where sender_id = v_me and receiver_id = p_target
     and action = 'pass' and created_at < now() - interval '7 days';

  if p_action = 'pass' then
    insert into public.swipes_and_requests (sender_id, receiver_id, action)
    values (v_me, p_target, 'pass')
    on conflict (sender_id, receiver_id) do nothing;
    return 'passed';
  end if;

  select * into v_reverse from public.swipes_and_requests
   where sender_id = p_target and receiver_id = v_me and action = 'follow_requested'
   for update;

  if found then
    update public.swipes_and_requests
       set action = 'accepted', responded_at = now()
     where id = v_reverse.id;
    return 'matched';
  end if;

  insert into public.swipes_and_requests (sender_id, receiver_id, action, direct_note)
  values (v_me, p_target, 'follow_requested', nullif(btrim(p_note), ''));
  return 'requested';
end;
$$;

-- Receiver accepts / rejects a pending request.
create or replace function public.respond_to_request(p_request_id uuid, p_accept boolean)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  update public.swipes_and_requests
     set action = case when p_accept then 'accepted'::public.swipe_action else 'rejected'::public.swipe_action end
   where id = p_request_id and receiver_id = auth.uid() and action = 'follow_requested';
  if not found then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;
end;
$$;

-- Count of pending incoming requests (visible to free users as a teaser).
create or replace function public.incoming_request_count()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int from public.swipes_and_requests
   where receiver_id = auth.uid() and action = 'follow_requested';
$$;

-- Remaining free follow requests in the rolling 24h window (-1 = unlimited).
create or replace function public.remaining_swipes()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select case when public.is_premium(auth.uid()) then -1
    else greatest(0, 10 - (select count(*)::int from public.swipes_and_requests
                             where sender_id = auth.uid() and action <> 'pass'
                               and created_at > now() - interval '24 hours'))
  end;
$$;

revoke all on function public.get_feed(int)                                 from public, anon;
revoke all on function public.swipe_profile(uuid, public.swipe_action, text) from public, anon;
revoke all on function public.respond_to_request(uuid, boolean)            from public, anon;
revoke all on function public.incoming_request_count()                     from public, anon;
revoke all on function public.remaining_swipes()                           from public, anon;
grant execute on function public.get_feed(int)                                 to authenticated;
grant execute on function public.swipe_profile(uuid, public.swipe_action, text) to authenticated;
grant execute on function public.respond_to_request(uuid, boolean)            to authenticated;
grant execute on function public.incoming_request_count()                     to authenticated;
grant execute on function public.remaining_swipes()                           to authenticated;

-- -----------------------------------------------------------------------------
-- Storage
--   avatars:     <uid>/primary/<file>.webp  -> any authenticated user
--                <uid>/gallery/<file>.webp  -> owner or accepted connection
--   voice_notes: <uidA>_<uidB>/<file>.m4a   (uids sorted) -> the two connected participants
--   Size caps: avatars 100 KB (800x800 WebP q70). voice_notes 192 KB: 45 s of
--   AAC-LC at 32 kbps is ~176 KB, so a 120 KB cap would reject long notes.
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars',     'avatars',     false, 102400, array['image/webp']),
  ('voice_notes', 'voice_notes', false, 196608, array['audio/mp4', 'audio/aac', 'audio/m4a', 'audio/x-m4a'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists avatars_read on storage.objects;
create policy avatars_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'avatars' and (
      (storage.foldername(name))[2] = 'primary'
      or (storage.foldername(name))[1] = auth.uid()::text
      or public.is_connected(auth.uid(), ((storage.foldername(name))[1])::uuid)
    )
  );

drop policy if exists avatars_write_own on storage.objects;
create policy avatars_write_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
    and (storage.foldername(name))[2] in ('primary', 'gallery')
  );

drop policy if exists avatars_delete_own on storage.objects;
create policy avatars_delete_own on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists voice_read on storage.objects;
create policy voice_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'voice_notes'
    and auth.uid()::text = any (string_to_array((storage.foldername(name))[1], '_'))
    and public.is_connected(
          (split_part((storage.foldername(name))[1], '_', 1))::uuid,
          (split_part((storage.foldername(name))[1], '_', 2))::uuid)
  );

drop policy if exists voice_write on storage.objects;
create policy voice_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'voice_notes'
    and auth.uid()::text = any (string_to_array((storage.foldername(name))[1], '_'))
    and public.is_connected(
          (split_part((storage.foldername(name))[1], '_', 1))::uuid,
          (split_part((storage.foldername(name))[1], '_', 2))::uuid)
  );

-- -----------------------------------------------------------------------------
-- Realtime
-- -----------------------------------------------------------------------------
alter table public.messages replica identity full;
alter table public.swipes_and_requests replica identity full;

do $$ begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.swipes_and_requests;
exception when duplicate_object then null; end $$;
