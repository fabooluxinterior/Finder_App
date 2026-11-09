-- =============================================================================
-- Update 01: Spotify card with top artists, top tracks and recently played.
-- Adds scope user-read-recently-played. Tracks are imported server-side with
-- the existing encrypted-token flow; the owner chooses whether each section is
-- shown. Public columns only ever hold what the owner made visible.
-- =============================================================================

alter table public.music_accounts
  add column if not exists top_tracks     jsonb not null default '[]' check (jsonb_typeof(top_tracks) = 'array'),
  add column if not exists recent_tracks  jsonb not null default '[]' check (jsonb_typeof(recent_tracks) = 'array'),
  add column if not exists granted_scopes text  not null default 'user-top-read',
  add column if not exists show_top_tracks boolean not null default true,
  add column if not exists show_recent    boolean not null default true;

alter table public.profiles
  add column if not exists music_top_tracks    jsonb not null default '[]',
  add column if not exists music_recent_tracks jsonb not null default '[]';
alter table public.profiles drop constraint if exists profiles_music_tracks_arrays;
alter table public.profiles add constraint profiles_music_tracks_arrays
  check (jsonb_typeof(music_top_tracks) = 'array' and jsonb_typeof(music_recent_tracks) = 'array');

-- Track entries: id, name, artists (names), album image, rank or played_at.
create or replace function public.normalize_tracks(p jsonb, p_recent boolean)
returns jsonb language sql immutable as $$
  select coalesce(jsonb_agg(
           jsonb_strip_nulls(jsonb_build_object(
             'id', x ->> 'id',
             'name', left(x ->> 'name', 100),
             'artists', coalesce((select jsonb_agg(left(a #>> '{}', 80)) from (
                          select a from jsonb_array_elements(coalesce(x -> 'artists', '[]')) a limit 3) aa), '[]'),
             'image', case when (x ->> 'image') ~ '^https://i\.scdn\.co/image/[A-Za-z0-9]+$' then x ->> 'image' end,
             'rank', case when not p_recent then ord end,
             'played_at', case when p_recent and (x ->> 'played_at') ~ '^\d{4}-\d{2}-\d{2}T' then x ->> 'played_at' end))
         order by ord), '[]')
    from jsonb_array_elements(coalesce(p, '[]')) with ordinality t(x, ord)
   where ord <= 10 and (x ->> 'id') ~ '^[A-Za-z0-9]{10,40}$' and coalesce(x ->> 'name', '') <> '';
$$;

create or replace function public.refresh_public_music(p_user uuid)
returns void language sql security definer set search_path = public as $$
  update public.profiles p set
    music_linked = (a.user_id is not null),
    music_top_artists = coalesce((
      select jsonb_agg(x order by ord) from jsonb_array_elements(a.all_artists) with ordinality t(x, ord)
       where not ((x ->> 'id') = any (a.hidden_artist_ids))), '[]'),
    music_artist_ids = coalesce(array(
      select x ->> 'id' from jsonb_array_elements(a.all_artists) with ordinality t(x, ord)
       where not ((x ->> 'id') = any (a.hidden_artist_ids)) order by ord), '{}'),
    music_top_tracks = case when a.show_top_tracks then coalesce(a.top_tracks, '[]') else '[]' end,
    music_recent_tracks = case when a.show_recent then coalesce(a.recent_tracks, '[]') else '[]' end
  from (select p_user as uid) u left join public.music_accounts a on a.user_id = u.uid
  where p.id = u.uid;
$$;

-- Service-only. p_recent = null keeps the stored list (e.g. the token lacks
-- the recently-played scope or Spotify didn't answer).
create or replace function public.service_music_store_v2(
  p_user uuid, p_token_enc text, p_kek text, p_artists jsonb, p_tracks jsonb, p_recent jsonb, p_scopes text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.service_music_store(p_user, p_token_enc, p_kek, p_artists);
  update public.music_accounts set
    top_tracks = public.normalize_tracks(p_tracks, false),
    recent_tracks = case when p_recent is null then recent_tracks else public.normalize_tracks(p_recent, true) end,
    granted_scopes = coalesce(nullif(btrim(p_scopes), ''), granted_scopes)
  where user_id = p_user;
  perform public.refresh_public_music(p_user);
end $$;

drop function if exists public.my_music();
create function public.my_music()
returns table (connected boolean, status text, synced_at timestamptz, artists jsonb, top_tracks jsonb,
               recent_tracks jsonb, show_top_tracks boolean, show_recent boolean, recent_scope boolean)
language sql stable security definer set search_path = public as $$
  select true, a.status, a.synced_at,
         coalesce((select jsonb_agg(x || jsonb_build_object('visible', not ((x ->> 'id') = any (a.hidden_artist_ids))) order by ord)
                     from jsonb_array_elements(a.all_artists) with ordinality t(x, ord)), '[]'),
         a.top_tracks, a.recent_tracks, a.show_top_tracks, a.show_recent,
         a.granted_scopes ~ '(^| )user-read-recently-played( |$)'
    from public.music_accounts a where a.user_id = auth.uid();
$$;

create or replace function public.set_music_section_visibility(p_section text, p_visible boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_section not in ('top_tracks', 'recent') then raise exception 'Unknown section' using errcode = '22023'; end if;
  update public.music_accounts
     set show_top_tracks = case when p_section = 'top_tracks' then p_visible else show_top_tracks end,
         show_recent = case when p_section = 'recent' then p_visible else show_recent end
   where user_id = auth.uid();
  if not found then raise exception 'Spotify isn''t connected' using errcode = 'P0002'; end if;
  perform public.refresh_public_music(auth.uid());
end $$;

-- Feed and profile card carry the public track lists.
drop function if exists public.get_profile_card(uuid);
create function public.get_profile_card(p_id uuid)
returns table (id uuid, full_name text, age smallint, city text, bio text, primary_photo text,
               is_premium boolean, is_verified boolean, photo_count int,
               photo_urls text[], prompts jsonb, interest_tags text[], occupation text, education text,
               height_cm int, gender text, pronouns text, languages text[], lifestyle_attributes jsonb,
               music_top_artists jsonb, shared_artist_ids text[], shared_interest_count int,
               music_top_tracks jsonb, music_recent_tracks jsonb)
language sql stable security definer set search_path = public as $$
  select p.id, p.full_name, p.age, p.city, p.bio, p.photo_urls[1], public.is_premium(p.id), p.is_verified,
         cardinality(p.photo_urls), p.photo_urls, p.prompts, p.interest_tags, p.occupation, p.education,
         p.height_cm, p.gender, p.pronouns, p.languages, p.lifestyle_attributes, p.music_top_artists,
         array(select unnest(p.music_artist_ids) intersect select unnest(me.music_artist_ids)),
         (select count(*)::int from (select unnest(p.interest_tags) intersect select unnest(me.interest_tags)) s),
         p.music_top_tracks, p.music_recent_tracks
    from public.profiles p, public.profiles me
   where p.id = p_id and me.id = auth.uid()
     and (p.id = me.id or (not public.is_blocked(me.id, p.id) and not p.hidden_pending_review));
$$;

revoke all on function public.normalize_tracks(jsonb, boolean),
  public.service_music_store_v2(uuid, text, text, jsonb, jsonb, jsonb, text),
  public.my_music(), public.set_music_section_visibility(text, boolean), public.get_profile_card(uuid)
  from public, anon;
grant execute on function public.my_music(), public.set_music_section_visibility(text, boolean),
  public.get_profile_card(uuid) to authenticated;
grant execute on function public.normalize_tracks(jsonb, boolean),
  public.service_music_store_v2(uuid, text, text, jsonb, jsonb, jsonb, text) to service_role;
