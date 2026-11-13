-- =============================================================================
-- Profile builder: 6-slot photos, structured identity + lifestyle, interest
-- tags, conversation prompts, completion score, 7-stage onboarding, prompt
-- replies (icebreakers) and the music-service connector (Spotify).
--
-- Trust model (unchanged): clients can edit their own descriptive fields
-- only; photos, music data, the completion score and the onboarded flag are
-- written by SECURITY DEFINER functions or service-side edge functions.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Option catalogs (single source of truth for validation)
-- -----------------------------------------------------------------------------
-- Allowed values per lifestyle key. The app ships the same lists; the
-- database refuses anything else so a modified client can't inject free text.
create or replace function public.lifestyle_options()
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'intention', jsonb_build_array('long_term', 'long_term_open', 'short_term_open', 'figuring_out', 'friendship'),
    'activity',  jsonb_build_array('daily', 'often', 'sometimes', 'rarely'),
    'drinking',  jsonb_build_array('never', 'socially', 'regularly', 'sober'),
    'smoking',   jsonb_build_array('never', 'socially', 'regularly', 'quitting'),
    'zodiac',    jsonb_build_array('aries', 'taurus', 'gemini', 'cancer', 'leo', 'virgo', 'libra', 'scorpio',
                                   'sagittarius', 'capricorn', 'aquarius', 'pisces'),
    'culture',   jsonb_build_array('malayali', 'tamil', 'kannadiga', 'telugu', 'marathi', 'gujarati', 'bengali',
                                   'punjabi', 'hindi_belt', 'northeast', 'anglo_indian', 'mixed', 'other')
  );
$$;

create or replace function public.valid_lifestyle(p jsonb)
returns boolean language sql immutable as $$
  select jsonb_typeof(p) = 'object'
     and not exists (
       select 1 from jsonb_each(p) e
        where not (public.lifestyle_options() ? e.key)
           or jsonb_typeof(e.value) <> 'string'
           or not (public.lifestyle_options() -> e.key) ? (e.value #>> '{}'));
$$;

-- Original prompt catalog. Questions are copied from here into a profile by
-- trigger, so a client can't rewrite the question text.
create table if not exists public.prompt_catalog (
  id        text primary key check (id ~ '^p[0-9]{1,3}$'),
  category  text not null,
  question  text not null check (char_length(question) between 10 and 120),
  tip       text not null check (char_length(tip) between 10 and 160),
  active    boolean not null default true
);
insert into public.prompt_catalog (id, category, question, tip) values
  ('p1',  'Everyday',  'A small thing that makes my week',            'Name the exact thing: “filter coffee from the stall near my office”, not “coffee”.'),
  ('p2',  'Everyday',  'My most unpopular food opinion',               'Pick a side someone could argue with. Debates make easy first messages.'),
  ('p3',  'Everyday',  'The last thing I got weirdly excited about',   'Recent and specific beats impressive. Say when it happened.'),
  ('p4',  'Plans',     'A perfect Sunday in my city looks like',       'Give a route: a place, a time of day, a person you''d bring.'),
  ('p5',  'Plans',     'Next trip I''m quietly planning',               'Where, and the one thing you have to do there.'),
  ('p6',  'Plans',     'Ask me for a recommendation about',            'Choose a topic you can talk about for twenty minutes.'),
  ('p7',  'About me',  'Friends would describe me as',                 'Quote a friend if you can. It sounds more like you than a list of adjectives.'),
  ('p8',  'About me',  'I''m quietly competitive about',                'The smaller the thing, the better: carrom, crosswords, parking.'),
  ('p9',  'About me',  'A skill I''m learning right now',               'Say how far along you are. Beginners invite questions.'),
  ('p10', 'About me',  'I geek out about',                             'Add one detail only a fan would know.'),
  ('p11', 'Connection','We''ll get along if you',                       'Describe a behaviour, not a type: “reply to voice notes with voice notes”.'),
  ('p12', 'Connection','The way to win me over is',                    'Keep it kind and concrete. Something a stranger could actually do.'),
  ('p13', 'Connection','A green flag I always notice',                 'Pick something you''d genuinely look for on a first chat.'),
  ('p14', 'Connection','Let''s debate this',                            'State your position in one line so they know which side to take.'),
  ('p15', 'Stories',   'The story my family won''t stop telling',       'Give the setup and leave the punchline for the chat.'),
  ('p16', 'Stories',   'Two truths and a lie',                         'Make the lie believable. People love guessing.')
on conflict (id) do update set category = excluded.category, question = excluded.question, tip = excluded.tip;
alter table public.prompt_catalog enable row level security;
drop policy if exists prompt_catalog_read on public.prompt_catalog;
create policy prompt_catalog_read on public.prompt_catalog for select to authenticated using (active);
revoke insert, update, delete on public.prompt_catalog from authenticated, anon;

-- -----------------------------------------------------------------------------
-- 1. Profile columns
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists photo_urls            text[]      not null default '{}',
  add column if not exists occupation            text,
  add column if not exists education             text,
  add column if not exists height_cm             int,
  add column if not exists gender                text,
  add column if not exists pronouns              text,
  add column if not exists languages             text[]      not null default '{}',
  add column if not exists lifestyle_attributes  jsonb       not null default '{}',
  add column if not exists interest_tags         text[]      not null default '{}',
  add column if not exists prompts               jsonb       not null default '[]',
  add column if not exists completion_score      int         not null default 0,
  add column if not exists onboarding_stage      int         not null default 1,
  add column if not exists is_onboarded          boolean     not null default false,
  add column if not exists standards_acknowledged_at timestamptz,
  add column if not exists music_linked          boolean     not null default false,
  add column if not exists music_top_artists     jsonb       not null default '[]',
  add column if not exists music_artist_ids      text[]      not null default '{}';

create index if not exists idx_profiles_music_artist_ids on public.profiles using gin (music_artist_ids);
create index if not exists idx_profiles_interest_tags   on public.profiles using gin (interest_tags);

alter table public.profiles drop constraint if exists profiles_builder_checks;
alter table public.profiles add constraint profiles_builder_checks check (
      cardinality(photo_urls) <= 6
  and (occupation is null or (char_length(occupation) between 2 and 60 and not public.contains_contact_info(occupation)))
  and (education  is null or (char_length(education)  between 2 and 60 and not public.contains_contact_info(education)))
  and (height_cm  is null or height_cm between 120 and 230)
  and (gender     is null or gender in ('woman', 'man', 'non_binary'))
  and (pronouns   is null or pronouns in ('she/her', 'he/him', 'they/them', 'she/they', 'he/they'))
  and cardinality(languages) <= 6
  and cardinality(interest_tags) <= 15
  and onboarding_stage between 1 and 8
  and completion_score between 0 and 100
  and jsonb_typeof(music_top_artists) = 'array'
  and cardinality(music_artist_ids) <= 10
);
alter table public.profiles drop constraint if exists profiles_lifestyle_valid;
alter table public.profiles add constraint profiles_lifestyle_valid check (public.valid_lifestyle(lifestyle_attributes));

-- Tags and languages: short, plain, no contact details.
create or replace function public.valid_tag_list(p text[], p_max_len int)
returns boolean language sql immutable as $$
  select not exists (select 1 from unnest(p) t
                      where char_length(t) not between 2 and p_max_len or t !~ '^[A-Za-z][A-Za-z &''/-]*$')
     and cardinality(p) = (select count(distinct lower(t)) from unnest(p) t);
$$;
alter table public.profiles drop constraint if exists profiles_tags_valid;
alter table public.profiles add constraint profiles_tags_valid
  check (public.valid_tag_list(interest_tags, 30) and public.valid_tag_list(languages, 24));

-- Backfill the ordered photo list from the legacy primary + gallery.
update public.profiles p
   set photo_urls = (p.avatar_urls || coalesce((select pp.gallery_urls from public.profile_private pp where pp.id = p.id), '{}'))[1:6]
 where cardinality(p.photo_urls) = 0 and cardinality(p.avatar_urls) > 0;
update public.profiles p
   set interest_tags = (select array(select distinct t from unnest(pp.interests) t
                                     where char_length(t) between 2 and 30 and t ~ '^[A-Za-z][A-Za-z &''/-]*$' limit 15))
  from public.profile_private pp
 where pp.id = p.id and cardinality(p.interest_tags) = 0;

-- -----------------------------------------------------------------------------
-- 2. Prompts: validated, questions from the catalog, answers ≤150 chars
-- -----------------------------------------------------------------------------
create or replace function public.normalize_prompts(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_out jsonb := '[]'; e jsonb; v_q text; v_a text; v_ids text[] := '{}';
begin
  if jsonb_typeof(p) <> 'array' then raise exception 'Prompts must be a list' using errcode = '22023'; end if;
  if jsonb_array_length(p) > 3 then raise exception 'Up to 3 prompts' using errcode = '22023'; end if;
  for e in select * from jsonb_array_elements(p) loop
    select question into v_q from public.prompt_catalog where id = e ->> 'prompt_id' and active;
    if v_q is null then raise exception 'Unknown prompt' using errcode = '22023'; end if;
    if (e ->> 'prompt_id') = any (v_ids) then raise exception 'Each prompt only once' using errcode = '22023'; end if;
    v_a := btrim(coalesce(e ->> 'answer', ''));
    if char_length(v_a) not between 1 and 150 then
      raise exception 'Answers are 1 to 150 characters' using errcode = '22023';
    end if;
    if public.contains_contact_info(v_a) then
      raise exception 'Answers can''t include phone numbers, handles or links' using errcode = '23514', hint = 'CONTACT_INFO';
    end if;
    v_ids := v_ids || (e ->> 'prompt_id');
    v_out := v_out || jsonb_build_object('prompt_id', e ->> 'prompt_id', 'question', v_q, 'answer', v_a);
  end loop;
  return v_out;
end $$;

-- -----------------------------------------------------------------------------
-- 3. Completion score (0–100)
--    photos 7.5 each up to 4 (30) · occupation 5 + education 5 (10)
--    lifestyle 7 items (20) · interests 3 each up to 5 (15)
--    bio ≥20 chars (10) · prompts 5 each up to 2 (10) · music linked (5)
--    Mirrored exactly in lib/models/profile_completion.dart.
-- -----------------------------------------------------------------------------
create or replace function public.profile_completion(
  p_photos int, p_occupation text, p_education text, p_lifestyle jsonb, p_languages int,
  p_tags int, p_bio text, p_prompts int, p_music boolean)
returns int language sql immutable as $$
  select round(
      least(p_photos, 4) * 7.5
    + case when coalesce(btrim(p_occupation), '') <> '' then 5 else 0 end
    + case when coalesce(btrim(p_education), '') <> '' then 5 else 0 end
    + 20.0 * ((select count(*) from jsonb_object_keys(coalesce(p_lifestyle, '{}')))
              + case when p_languages > 0 then 1 else 0 end) / 7
    + least(p_tags, 5) * 3
    + case when char_length(btrim(coalesce(p_bio, ''))) >= 20 then 10 else 0 end
    + least(p_prompts, 2) * 5
    + case when p_music then 5 else 0 end
  )::int;
$$;

create or replace function public.tg_profiles_builder() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.prompts is distinct from old.prompts then
    new.prompts := public.normalize_prompts(new.prompts);
  end if;
  -- The ordered photo list drives the legacy primary/gallery columns that
  -- media access and older RPCs read.
  if (tg_op = 'INSERT' and cardinality(new.photo_urls) > 0)
     or (tg_op = 'UPDATE' and new.photo_urls is distinct from old.photo_urls) then
    new.avatar_urls := new.photo_urls[1:1];
  end if;
  new.completion_score := public.profile_completion(
    cardinality(new.photo_urls), new.occupation, new.education, new.lifestyle_attributes,
    cardinality(new.languages), cardinality(new.interest_tags), new.bio,
    jsonb_array_length(new.prompts), new.music_linked);
  return new;
end $$;
drop trigger if exists profiles_builder on public.profiles;
create trigger profiles_builder before insert or update on public.profiles
  for each row execute function public.tg_profiles_builder();

create or replace function public.tg_profiles_photos_after() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'INSERT' and cardinality(new.photo_urls) > 0)
     or (tg_op = 'UPDATE' and new.photo_urls is distinct from old.photo_urls) then
    insert into public.profile_private (id, gallery_urls) values (new.id, coalesce(new.photo_urls[2:6], '{}'))
    on conflict (id) do update set gallery_urls = excluded.gallery_urls, updated_at = now();
  end if;
  return null;
end $$;
drop trigger if exists profiles_photos_after on public.profiles;
create trigger profiles_photos_after after insert or update of photo_urls on public.profiles
  for each row execute function public.tg_profiles_photos_after();

-- Recompute existing rows once.
update public.profiles set prompts = prompts;

-- -----------------------------------------------------------------------------
-- 4. Privileges on profile columns
-- -----------------------------------------------------------------------------
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert to authenticated
  with check (id = auth.uid() and is_premium = false and avatar_urls = '{}' and photo_urls = '{}'
              and is_verified = false and hidden_pending_review = false and is_onboarded = false
              and music_linked = false and music_top_artists = '[]' and music_artist_ids = '{}');

revoke update on public.profiles from authenticated;
grant update (full_name, city, bio, occupation, education, height_cm, gender, pronouns, languages,
              lifestyle_attributes, interest_tags, prompts, onboarding_stage) on public.profiles to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Onboarding
-- -----------------------------------------------------------------------------
alter table public.user_consents drop constraint if exists user_consents_policy_type_check;
alter table public.user_consents add constraint user_consents_policy_type_check
  check (policy_type in ('terms', 'privacy', 'community_guidelines', 'age_18_plus', 'community_standards'));

-- Stage 1 happens before the profile row exists, so the acknowledgement is
-- kept with the other consents and copied onto the profile when it's created.
create or replace function public.acknowledge_standards(p_version text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_version !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Invalid version' using errcode = '22023'; end if;
  insert into public.user_consents (user_id, policy_type, policy_version)
  values (auth.uid(), 'community_standards', p_version) on conflict do nothing;
  update public.profiles set standards_acknowledged_at = coalesce(standards_acknowledged_at, now()) where id = auth.uid();
end $$;

create or replace function public.tg_profiles_standards() returns trigger language plpgsql security definer set search_path = public as $$
begin
  select min(accepted_at) into new.standards_acknowledged_at from public.user_consents
   where user_id = new.id and policy_type = 'community_standards';
  return new;
end $$;
drop trigger if exists profiles_standards on public.profiles;
create trigger profiles_standards before insert on public.profiles
  for each row execute function public.tg_profiles_standards();

-- What's still missing before a profile can go live (empty = ready).
create or replace function public.onboarding_missing(p_user uuid)
returns text[] language sql stable security definer set search_path = public as $$
  select array_remove(array[
    case when p.standards_acknowledged_at is null then 'community_standards' end,
    case when not exists (select 1 from public.profile_dob d where d.user_id = p.id) then 'birthdate' end,
    case when p.gender is null then 'gender' end,
    case when cardinality(p.photo_urls) < 4 then 'photos' end,
    case when cardinality(p.interest_tags) < 5 then 'interests' end,
    case when jsonb_array_length(p.prompts) < 2 then 'prompts' end
  ], null)
  from public.profiles p where p.id = p_user;
$$;

create or replace function public.complete_onboarding()
returns void language plpgsql security definer set search_path = public as $$
declare v_missing text[];
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  v_missing := public.onboarding_missing(auth.uid());
  if v_missing is null then raise exception 'Create your profile first' using errcode = 'P0002'; end if;
  if cardinality(v_missing) > 0 then
    raise exception 'Profile incomplete: %', array_to_string(v_missing, ', ')
      using errcode = 'P0001', hint = 'ONBOARDING_INCOMPLETE';
  end if;
  update public.profiles set is_onboarded = true, onboarding_stage = 8 where id = auth.uid();
end $$;

-- -----------------------------------------------------------------------------
-- 6. Photos: 6 ordered slots, replace in place, remove, reorder
-- -----------------------------------------------------------------------------
alter table public.media_objects drop constraint if exists media_objects_kind_check;
alter table public.media_objects add constraint media_objects_kind_check
  check (kind in ('primary', 'gallery', 'selfie', 'photo'));
alter table public.media_objects add column if not exists replaces uuid;

create or replace function public.can_view_media(p_viewer uuid, p_media uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.media_objects m
     where m.id = p_media and m.status <> 'deleted'
       and not public.is_blocked(p_viewer, m.owner_id)
       and (m.owner_id = p_viewer
            or (m.status = 'approved' and m.kind in ('primary', 'gallery', 'photo'))));
$$;

-- Publishes an approved photo. For kind 'photo' it fills the next free slot,
-- or replaces the photo named in media_objects.replaces in place. Returns the
-- storage paths that are now obsolete so the caller deletes them right away.
drop function if exists public.attach_media(uuid);
create function public.attach_media(p_media uuid)
returns text[] language plpgsql security definer set search_path = public as $$
declare m public.media_objects; v_photos text[]; v_pos int; v_dead text[] := '{}';
begin
  select * into m from public.media_objects where id = p_media and status = 'approved';
  if not found then raise exception 'Media not approved' using errcode = 'P0002'; end if;

  if m.kind = 'photo' then
    select photo_urls into v_photos from public.profiles where id = m.owner_id for update;
    v_pos := case when m.replaces is null then null else array_position(v_photos, m.replaces::text) end;
    if v_pos is not null then
      v_photos[v_pos] := m.id::text;
      with gone as (
        update public.media_objects set status = 'deleted'
         where id = m.replaces and owner_id = m.owner_id and status <> 'deleted' returning storage_path)
      select coalesce(array_agg(storage_path), '{}') into v_dead from gone;
    elsif cardinality(v_photos) >= 6 then
      -- (the caller deletes the rejected upload; a raise rolls back any update here)
      raise exception 'All 6 photo slots are full' using errcode = 'P0001', hint = 'PHOTO_SLOTS_FULL';
    else
      v_photos := array_append(v_photos, m.id::text);
    end if;
    update public.profiles set photo_urls = v_photos where id = m.owner_id;
  elsif m.kind = 'primary' then
    update public.media_objects set status = 'deleted'
     where owner_id = m.owner_id and kind = 'primary' and id <> m.id and status <> 'deleted';
    update public.profiles set avatar_urls = array[m.id::text] where id = m.owner_id;
  else
    insert into public.profile_private (id) values (m.owner_id) on conflict (id) do nothing;
    update public.profile_private
       set gallery_urls = (array_append(array_remove(gallery_urls, m.id::text), m.id::text))[1:9]
     where id = m.owner_id;
  end if;
  return v_dead;
end $$;
revoke all on function public.attach_media(uuid) from public, anon, authenticated;
grant execute on function public.attach_media(uuid) to service_role;

-- Removes a photo from the profile and marks its object deleted. Returns the
-- storage path so the photo-remove function can delete the object at once
-- (media-maintenance purges anything left behind as a backstop).
create or replace function public.remove_photo(p_media uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_path text;
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  update public.media_objects set status = 'deleted'
   where id = p_media and owner_id = auth.uid() and kind in ('photo', 'primary', 'gallery') and status <> 'deleted'
  returning storage_path into v_path;
  if v_path is null then raise exception 'Photo not found' using errcode = 'P0002'; end if;
  update public.profiles set photo_urls = array_remove(photo_urls, p_media::text) where id = auth.uid();
  return v_path;
end $$;

-- New order must be a permutation of the current photos (no injecting ids).
create or replace function public.reorder_photos(p_order text[])
returns void language plpgsql security definer set search_path = public as $$
declare v_current text[];
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  select photo_urls into v_current from public.profiles where id = auth.uid() for update;
  if v_current is null
     or cardinality(p_order) <> cardinality(v_current)
     or exists (select unnest(p_order) except select unnest(v_current))
     or (select count(distinct x) from unnest(p_order) x) <> cardinality(v_current) then
    raise exception 'Order must contain exactly your current photos' using errcode = '22023';
  end if;
  update public.profiles set photo_urls = p_order where id = auth.uid();
end $$;

-- Owner's slots including uploads still in review.
create or replace function public.my_photo_slots()
returns table (media_id uuid, status text, slot int) language sql stable security definer set search_path = public as $$
  select m.id, m.status, array_position(p.photo_urls, m.id::text)
    from public.media_objects m join public.profiles p on p.id = m.owner_id
   where m.owner_id = auth.uid() and m.kind in ('photo', 'primary', 'gallery') and m.status in ('approved', 'pending')
     and (m.status = 'pending' or m.id::text = any (p.photo_urls))
   order by array_position(p.photo_urls, m.id::text) nulls last, m.created_at;
$$;

-- -----------------------------------------------------------------------------
-- 7. Music connector (Spotify, scope user-top-read)
-- -----------------------------------------------------------------------------
-- Tokens and the full imported list live here: service-only, never exposed.
create table if not exists public.music_accounts (
  user_id            uuid primary key references public.profiles (id) on delete cascade,
  provider           text not null default 'spotify' check (provider = 'spotify'),
  refresh_token_enc  text,           -- AES-256-GCM envelope (see _shared/media_crypto.ts)
  kek_id             text,
  all_artists        jsonb not null default '[]' check (jsonb_typeof(all_artists) = 'array'),
  hidden_artist_ids  text[] not null default '{}',
  status             text not null default 'active' check (status in ('active', 'reauth_required')),
  connected_at       timestamptz not null default now(),
  synced_at          timestamptz
);
alter table public.music_accounts enable row level security;
revoke all on public.music_accounts from authenticated, anon;

-- One-time OAuth state (CSRF protection), 10-minute life.
create table if not exists public.music_oauth_states (
  state          text primary key check (char_length(state) >= 32),
  user_id        uuid not null references auth.users (id) on delete cascade,
  created_at     timestamptz not null default now()
);
alter table public.music_oauth_states enable row level security;
revoke all on public.music_oauth_states from authenticated, anon;

-- Publishes the visible part of the imported list onto the profile.
create or replace function public.refresh_public_music(p_user uuid)
returns void language sql security definer set search_path = public as $$
  update public.profiles p set
    music_linked = (a.user_id is not null),
    music_top_artists = coalesce((
      select jsonb_agg(x order by ord) from jsonb_array_elements(a.all_artists) with ordinality t(x, ord)
       where not ((x ->> 'id') = any (a.hidden_artist_ids))), '[]'),
    music_artist_ids = coalesce(array(
      select x ->> 'id' from jsonb_array_elements(a.all_artists) with ordinality t(x, ord)
       where not ((x ->> 'id') = any (a.hidden_artist_ids)) order by ord), '{}')
  from (select p_user as uid) u left join public.music_accounts a on a.user_id = u.uid
  where p.id = u.uid;
$$;

-- Artist entries are normalised server-side: id, name, image, genres only.
create or replace function public.normalize_artists(p jsonb)
returns jsonb language sql immutable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', x ->> 'id',
           'name', left(x ->> 'name', 80),
           'image', case when (x ->> 'image') ~ '^https://i\.scdn\.co/image/[A-Za-z0-9]+$' then x ->> 'image' end,
           'genres', coalesce((select jsonb_agg(left(g #>> '{}', 40)) from (
                       select g from jsonb_array_elements(coalesce(x -> 'genres', '[]')) g limit 5) gg), '[]'))
         order by ord), '[]')
    from jsonb_array_elements(coalesce(p, '[]')) with ordinality t(x, ord)
   where ord <= 10 and (x ->> 'id') ~ '^[A-Za-z0-9]{10,40}$' and coalesce(x ->> 'name', '') <> '';
$$;

-- Service-only: store tokens + imported artists after OAuth or a refresh.
create or replace function public.service_music_store(p_user uuid, p_token_enc text, p_kek text, p_artists jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_artists jsonb := public.normalize_artists(p_artists);
begin
  insert into public.music_accounts (user_id, refresh_token_enc, kek_id, all_artists, status, synced_at)
  values (p_user, p_token_enc, p_kek, v_artists, 'active', now())
  on conflict (user_id) do update set
    refresh_token_enc = coalesce(excluded.refresh_token_enc, music_accounts.refresh_token_enc),
    kek_id = coalesce(excluded.kek_id, music_accounts.kek_id),
    all_artists = excluded.all_artists,
    -- keep hidden choices only for artists that are still in the list
    hidden_artist_ids = array(select h from unnest(music_accounts.hidden_artist_ids) h
                               where exists (select 1 from jsonb_array_elements(excluded.all_artists) x where x ->> 'id' = h)),
    status = 'active', synced_at = now();
  perform public.refresh_public_music(p_user);
end $$;

-- Service-only: the refresh token was revoked or expired for good.
create or replace function public.service_music_reauth(p_user uuid)
returns void language sql security definer set search_path = public as $$
  update public.music_accounts set status = 'reauth_required', refresh_token_enc = null, kek_id = null where user_id = p_user;
$$;

-- Owner view: imported artists with visibility, never the token.
create or replace function public.my_music()
returns table (connected boolean, status text, synced_at timestamptz, artists jsonb)
language sql stable security definer set search_path = public as $$
  select true, a.status, a.synced_at,
         coalesce((select jsonb_agg(x || jsonb_build_object('visible', not ((x ->> 'id') = any (a.hidden_artist_ids))) order by ord)
                     from jsonb_array_elements(a.all_artists) with ordinality t(x, ord)), '[]')
    from public.music_accounts a where a.user_id = auth.uid();
$$;

create or replace function public.set_music_artist_visibility(p_artist_id text, p_visible boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  update public.music_accounts
     set hidden_artist_ids = case when p_visible then array_remove(hidden_artist_ids, p_artist_id)
                                  else array_append(array_remove(hidden_artist_ids, p_artist_id), p_artist_id) end
   where user_id = auth.uid()
     and exists (select 1 from jsonb_array_elements(all_artists) x where x ->> 'id' = p_artist_id);
  if not found then raise exception 'Artist not found' using errcode = 'P0002'; end if;
  perform public.refresh_public_music(auth.uid());
end $$;

create or replace function public.disconnect_music()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  delete from public.music_accounts where user_id = auth.uid();
  delete from public.music_oauth_states where user_id = auth.uid();
  perform public.refresh_public_music(auth.uid());
end $$;

-- Shared artists between the caller and another profile: set intersection of
-- the public (visible) id arrays, so hidden artists never leak.
create or replace function public.music_affinity(p_other uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x), '[]')
    from public.profiles o, jsonb_array_elements(o.music_top_artists) x
   where o.id = p_other
     and not public.is_blocked(auth.uid(), p_other)
     and (x ->> 'id') = any (select unnest(me.music_artist_ids) from public.profiles me where me.id = auth.uid());
$$;

-- -----------------------------------------------------------------------------
-- 8. Prompt replies (icebreakers anchored to an answer)
-- -----------------------------------------------------------------------------
-- Chat stays locked until the request is accepted, so a reply travels with
-- the follow request and is shown as the conversation's opening context.
alter table public.swipes_and_requests
  add column if not exists intro_prompt_id text,
  add column if not exists intro_text text;
alter table public.swipes_and_requests drop constraint if exists swipes_intro_valid;
alter table public.swipes_and_requests add constraint swipes_intro_valid check (
  (intro_prompt_id is null and intro_text is null)
  or (intro_prompt_id ~ '^p[0-9]{1,3}$' and char_length(btrim(intro_text)) between 1 and 150
      and not public.contains_contact_info(intro_text)));

-- Direct inserts can't attach an intro; only send_prompt_reply can.
create or replace function public.tg_swipes_intro_guard() returns trigger language plpgsql as $$
begin
  if new.intro_text is not null and current_setting('app.prompt_reply', true) is distinct from 'on' then
    raise exception 'Use send_prompt_reply' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists swipes_intro_guard on public.swipes_and_requests;
create trigger swipes_intro_guard before insert or update of intro_text on public.swipes_and_requests
  for each row execute function public.tg_swipes_intro_guard();

create or replace function public.send_prompt_reply(p_receiver uuid, p_prompt_id text, p_text text)
returns text language plpgsql security definer set search_path = public as $$
declare v_me uuid := auth.uid(); v_text text := btrim(coalesce(p_text, '')); v_outcome text;
begin
  if v_me is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if v_me = p_receiver or public.is_blocked(v_me, p_receiver) then
    raise exception 'Not available' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.profiles p, jsonb_array_elements(p.prompts) e
                  where p.id = p_receiver and e ->> 'prompt_id' = p_prompt_id) then
    raise exception 'That prompt is no longer on their profile' using errcode = 'P0002';
  end if;
  if char_length(v_text) not between 1 and 150 then
    raise exception 'Replies are 1 to 150 characters' using errcode = '22023';
  end if;
  if public.contains_contact_info(v_text) then
    raise exception 'Replies can''t include phone numbers, handles or links' using errcode = '23514', hint = 'CONTACT_INFO';
  end if;
  v_outcome := public.swipe_profile(p_receiver, 'follow_requested');
  perform set_config('app.prompt_reply', 'on', true);
  update public.swipes_and_requests set intro_prompt_id = p_prompt_id, intro_text = v_text
   where sender_id = v_me and receiver_id = p_receiver and intro_text is null;
  perform set_config('app.prompt_reply', 'off', true);
  return v_outcome;
end $$;

-- -----------------------------------------------------------------------------
-- 9. Feed + full profile card with affinity
-- -----------------------------------------------------------------------------
drop function if exists public.get_feed(int);
create function public.get_feed(p_limit int default 20)
returns table (id uuid, full_name text, age smallint, city text, bio text, primary_photo text,
               is_premium boolean, is_verified boolean, photo_count int,
               photo_urls text[], prompts jsonb, interest_tags text[], occupation text, education text,
               height_cm int, gender text, pronouns text, languages text[], lifestyle_attributes jsonb,
               music_top_artists jsonb, shared_artist_ids text[], shared_interest_count int)
language sql stable security definer set search_path = public as $$
  with me as (select p.id, lower(p.city) as city, p.music_artist_ids, p.interest_tags
                from public.profiles p where p.id = auth.uid())
  select p.id, p.full_name, p.age, p.city, p.bio, p.photo_urls[1], public.is_premium(p.id), p.is_verified,
         cardinality(p.photo_urls), p.photo_urls, p.prompts, p.interest_tags, p.occupation, p.education,
         p.height_cm, p.gender, p.pronouns, p.languages, p.lifestyle_attributes, p.music_top_artists,
         array(select unnest(p.music_artist_ids) intersect select unnest(me.music_artist_ids)),
         (select count(*)::int from (select unnest(p.interest_tags) intersect select unnest(me.interest_tags)) s)
    from public.profiles p, me
   where p.id <> me.id
     and p.is_onboarded
     and cardinality(p.photo_urls) >= 4
     and not p.hidden_pending_review
     and not public.is_blocked(me.id, p.id)
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
     cardinality(array(select unnest(p.music_artist_ids) intersect select unnest(me.music_artist_ids))) desc,
     p.created_at desc
   limit least(greatest(p_limit, 1), 50);
$$;

create or replace function public.get_profile_card(p_id uuid)
returns table (id uuid, full_name text, age smallint, city text, bio text, primary_photo text,
               is_premium boolean, is_verified boolean, photo_count int,
               photo_urls text[], prompts jsonb, interest_tags text[], occupation text, education text,
               height_cm int, gender text, pronouns text, languages text[], lifestyle_attributes jsonb,
               music_top_artists jsonb, shared_artist_ids text[], shared_interest_count int)
language sql stable security definer set search_path = public as $$
  select p.id, p.full_name, p.age, p.city, p.bio, p.photo_urls[1], public.is_premium(p.id), p.is_verified,
         cardinality(p.photo_urls), p.photo_urls, p.prompts, p.interest_tags, p.occupation, p.education,
         p.height_cm, p.gender, p.pronouns, p.languages, p.lifestyle_attributes, p.music_top_artists,
         array(select unnest(p.music_artist_ids) intersect select unnest(me.music_artist_ids)),
         (select count(*)::int from (select unnest(p.interest_tags) intersect select unnest(me.interest_tags)) s)
    from public.profiles p, public.profiles me
   where p.id = p_id and me.id = auth.uid()
     and (p.id = me.id or (not public.is_blocked(me.id, p.id) and not p.hidden_pending_review));
$$;

-- -----------------------------------------------------------------------------
-- 10. Retention: abandoned OAuth states
-- -----------------------------------------------------------------------------
create or replace function public.purge_music_states()
returns void language sql security definer set search_path = public as $$
  delete from public.music_oauth_states where created_at < now() - interval '10 minutes';
$$;

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
revoke all on function
  public.lifestyle_options(), public.valid_lifestyle(jsonb), public.valid_tag_list(text[], int),
  public.normalize_prompts(jsonb), public.profile_completion(int, text, text, jsonb, int, int, text, int, boolean),
  public.acknowledge_standards(text), public.onboarding_missing(uuid), public.complete_onboarding(),
  public.remove_photo(uuid), public.reorder_photos(text[]), public.my_photo_slots(),
  public.refresh_public_music(uuid), public.normalize_artists(jsonb), public.service_music_store(uuid, text, text, jsonb),
  public.service_music_reauth(uuid), public.my_music(), public.set_music_artist_visibility(text, boolean),
  public.disconnect_music(), public.music_affinity(uuid), public.send_prompt_reply(uuid, text, text),
  public.get_feed(int), public.get_profile_card(uuid), public.purge_music_states()
  from public, anon;
grant execute on function
  public.lifestyle_options(), public.valid_lifestyle(jsonb), public.valid_tag_list(text[], int),
  public.profile_completion(int, text, text, jsonb, int, int, text, int, boolean),
  public.acknowledge_standards(text), public.complete_onboarding(),
  public.remove_photo(uuid), public.reorder_photos(text[]), public.my_photo_slots(),
  public.my_music(), public.set_music_artist_visibility(text, boolean), public.disconnect_music(),
  public.music_affinity(uuid), public.send_prompt_reply(uuid, text, text),
  public.get_feed(int), public.get_profile_card(uuid)
  to authenticated;
grant execute on function
  public.onboarding_missing(uuid), public.refresh_public_music(uuid), public.normalize_artists(jsonb),
  public.service_music_store(uuid, text, text, jsonb), public.service_music_reauth(uuid), public.purge_music_states()
  to service_role;
-- normalize_prompts runs inside the profile trigger (definer); not callable directly.
