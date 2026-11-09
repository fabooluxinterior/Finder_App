-- =============================================================================
-- Update 02: Suggestions ("People you might like") and "You may like".
-- Recommendations are computed server-side from explainable shared signals,
-- with configurable weights, a daily allowance, page limits and a history so
-- people aren't shown twice in the same cycle. Clients can't change limits.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Discovery preferences (age range, who to show)
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists pref_age_min smallint not null default 18,
  add column if not exists pref_age_max smallint not null default 60,
  add column if not exists pref_genders text[]   not null default '{}';
alter table public.profiles drop constraint if exists profiles_prefs_valid;
alter table public.profiles add constraint profiles_prefs_valid check (
  pref_age_min between 18 and 99 and pref_age_max between pref_age_min and 99
  and pref_genders <@ array['woman', 'man', 'non_binary']);
grant update (pref_age_min, pref_age_max, pref_genders) on public.profiles to authenticated;

-- Both people fit each other's preferences (an empty gender list = everyone).
create or replace function public.prefs_match(p_a uuid, p_b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select a.age between b.pref_age_min and b.pref_age_max
     and b.age between a.pref_age_min and a.pref_age_max
     and (cardinality(a.pref_genders) = 0 or b.gender = any (a.pref_genders))
     and (cardinality(b.pref_genders) = 0 or a.gender = any (b.pref_genders))
    from public.profiles a, public.profiles b where a.id = p_a and b.id = p_b;
$$;

-- -----------------------------------------------------------------------------
-- 2. Configuration (backend-only; staff can tune it)
-- -----------------------------------------------------------------------------
create table if not exists public.recommendation_config (
  id               boolean primary key default true check (id),
  weights          jsonb not null default '{"interests":0.35,"music":0.20,"lifestyle":0.15,"hobbies":0.15,"location":0.10,"completeness":0.05}',
  you_may_like_weights jsonb not null default '{"music":0.45,"hobbies":0.35,"interests":0.20}',
  page_default     int not null default 10 check (page_default between 1 and 50),
  page_max         int not null default 20 check (page_max between 1 and 50),
  daily_limit      int not null default 50 check (daily_limit between 1 and 1000),
  repeat_days      int not null default 7  check (repeat_days between 1 and 90),
  hobby_categories text[] not null default array['Active & sports', 'Creative arts', 'Gaming'],
  updated_at       timestamptz not null default now()
);
insert into public.recommendation_config (id) values (true) on conflict (id) do nothing;
alter table public.recommendation_config enable row level security;
drop policy if exists recommendation_config_read on public.recommendation_config;
create policy recommendation_config_read on public.recommendation_config for select to authenticated using (true);
revoke insert, update, delete on public.recommendation_config from authenticated, anon;

create or replace function public.admin_set_recommendation_config(p_weights jsonb, p_daily_limit int, p_page_max int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  update public.recommendation_config set
    weights = coalesce(p_weights, weights), daily_limit = coalesce(p_daily_limit, daily_limit),
    page_max = coalesce(p_page_max, page_max), updated_at = now();
  insert into public.access_audit_log (actor_id, action, target_type, target_id)
  values (auth.uid(), 'update_recommendation_config', 'config', 'recommendation_config');
end $$;

-- Interest tag -> category (mirrors lib/models/profile_catalog.dart).
create table if not exists public.interest_catalog (
  tag      text primary key,
  category text not null
);
insert into public.interest_catalog (tag, category) values
  ('Photography', 'Creative arts'),
  ('Painting', 'Creative arts'),
  ('Sketching', 'Creative arts'),
  ('Writing', 'Creative arts'),
  ('Poetry', 'Creative arts'),
  ('Film making', 'Creative arts'),
  ('Theatre', 'Creative arts'),
  ('Music production', 'Creative arts'),
  ('Singing', 'Creative arts'),
  ('Dance', 'Creative arts'),
  ('Kathakali', 'Creative arts'),
  ('Crafts', 'Creative arts'),
  ('Street food', 'Food & cuisine'),
  ('Home cooking', 'Food & cuisine'),
  ('Baking', 'Food & cuisine'),
  ('Filter coffee', 'Food & cuisine'),
  ('Chai', 'Food & cuisine'),
  ('Biryani hunts', 'Food & cuisine'),
  ('Seafood', 'Food & cuisine'),
  ('Vegan food', 'Food & cuisine'),
  ('Cafés', 'Food & cuisine'),
  ('Toddy shops', 'Food & cuisine'),
  ('Football', 'Active & sports'),
  ('Cricket', 'Active & sports'),
  ('Badminton', 'Active & sports'),
  ('Running', 'Active & sports'),
  ('Trekking', 'Active & sports'),
  ('Cycling', 'Active & sports'),
  ('Swimming', 'Active & sports'),
  ('Yoga', 'Active & sports'),
  ('Gym', 'Active & sports'),
  ('Kayaking', 'Active & sports'),
  ('Kalaripayattu', 'Active & sports'),
  ('Console games', 'Gaming'),
  ('PC games', 'Gaming'),
  ('Mobile games', 'Gaming'),
  ('Board games', 'Gaming'),
  ('Carrom', 'Gaming'),
  ('Chess', 'Gaming'),
  ('Card games', 'Gaming'),
  ('Esports', 'Gaming'),
  ('Fiction', 'Reading'),
  ('Malayalam literature', 'Reading'),
  ('Poetry books', 'Reading'),
  ('History', 'Reading'),
  ('Science', 'Reading'),
  ('Comics', 'Reading'),
  ('Self-help', 'Reading'),
  ('Podcasts', 'Reading')
on conflict (tag) do update set category = excluded.category;
alter table public.interest_catalog enable row level security;
drop policy if exists interest_catalog_read on public.interest_catalog;
create policy interest_catalog_read on public.interest_catalog for select to authenticated using (true);
revoke insert, update, delete on public.interest_catalog from authenticated, anon;

-- -----------------------------------------------------------------------------
-- 3. History and daily usage (own rows readable; written only by RPCs)
-- -----------------------------------------------------------------------------
create table if not exists public.recommendation_history (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  target_id   uuid not null references public.profiles (id) on delete cascade,
  section     text not null check (section in ('main', 'you_may_like')),
  score       int  not null,
  reasons     jsonb not null default '[]',
  shown_at    timestamptz not null default now(),
  primary key (user_id, target_id)
);
create index if not exists recommendation_history_recent on public.recommendation_history (user_id, shown_at desc);
alter table public.recommendation_history enable row level security;
drop policy if exists recommendation_history_own on public.recommendation_history;
create policy recommendation_history_own on public.recommendation_history for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on public.recommendation_history from authenticated, anon;

create table if not exists public.recommendation_daily (
  user_id uuid not null references public.profiles (id) on delete cascade,
  day     date not null,
  shown   int  not null default 0,
  primary key (user_id, day)
);
alter table public.recommendation_daily enable row level security;
drop policy if exists recommendation_daily_own on public.recommendation_daily;
create policy recommendation_daily_own on public.recommendation_daily for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on public.recommendation_daily from authenticated, anon;

-- -----------------------------------------------------------------------------
-- 4. Scoring: explainable shared signals, weighted, normalised over the
--    signals that apply (music only counts when both linked Spotify, so it's
--    never mandatory). Returns 0–100 and the reasons shown to the user.
-- -----------------------------------------------------------------------------
create or replace function public.suggestion_score(p_me uuid, p_other uuid, p_weights jsonb)
returns table (score int, reasons jsonb)
language plpgsql stable security definer set search_path = public as $$
declare
  me public.profiles; o public.profiles; cfg public.recommendation_config;
  w_sum numeric := 0; total numeric := 0; s numeric; w numeric;
  shared_tags text[]; my_hobbies text[]; their_hobbies text[]; shared_hobbies text[];
  shared_artists jsonb; ls_keys int; ls_same text[]; r jsonb := '[]';
begin
  select * into me from public.profiles where id = p_me;
  select * into o from public.profiles where id = p_other;
  select * into cfg from public.recommendation_config;

  -- interests
  shared_tags := array(select unnest(me.interest_tags) intersect select unnest(o.interest_tags));
  w := coalesce((p_weights ->> 'interests')::numeric, 0);
  if w > 0 then
    s := case when least(cardinality(me.interest_tags), cardinality(o.interest_tags)) = 0 then 0
              else least(1, cardinality(shared_tags)::numeric / least(cardinality(me.interest_tags), cardinality(o.interest_tags), 5)) end;
    total := total + w * s; w_sum := w_sum + w;
  end if;
  if cardinality(shared_tags) > 0 then
    r := r || jsonb_build_object('kind', 'interests', 'items', to_jsonb(shared_tags[1:5]), 'count', cardinality(shared_tags));
  end if;

  -- hobbies (interest tags in the hobby categories)
  my_hobbies := array(select t from unnest(me.interest_tags) t join public.interest_catalog c on c.tag = t
                       where c.category = any (cfg.hobby_categories));
  their_hobbies := array(select t from unnest(o.interest_tags) t join public.interest_catalog c on c.tag = t
                          where c.category = any (cfg.hobby_categories));
  shared_hobbies := array(select unnest(my_hobbies) intersect select unnest(their_hobbies));
  w := coalesce((p_weights ->> 'hobbies')::numeric, 0);
  if w > 0 and (cardinality(my_hobbies) > 0 or cardinality(their_hobbies) > 0) then
    s := case when least(cardinality(my_hobbies), cardinality(their_hobbies)) = 0 then 0
              else least(1, cardinality(shared_hobbies)::numeric / least(cardinality(my_hobbies), cardinality(their_hobbies), 3)) end;
    total := total + w * s; w_sum := w_sum + w;
  end if;

  -- music (only when both linked; visible artists only)
  w := coalesce((p_weights ->> 'music')::numeric, 0);
  if me.music_linked and o.music_linked and cardinality(me.music_artist_ids) > 0 and cardinality(o.music_artist_ids) > 0 then
    select coalesce(jsonb_agg(x ->> 'name'), '[]') into shared_artists
      from jsonb_array_elements(o.music_top_artists) x where (x ->> 'id') = any (me.music_artist_ids);
    if w > 0 then
      s := least(1, jsonb_array_length(shared_artists)::numeric / least(cardinality(me.music_artist_ids), cardinality(o.music_artist_ids), 3));
      total := total + w * s; w_sum := w_sum + w;
    end if;
    if jsonb_array_length(shared_artists) > 0 then
      r := r || jsonb_build_object('kind', 'music', 'items', shared_artists, 'count', jsonb_array_length(shared_artists));
    end if;
  end if;

  -- lifestyle (keys both answered; same answer = match)
  select count(*), coalesce(array_agg(k) filter (where me.lifestyle_attributes ->> k = o.lifestyle_attributes ->> k), '{}')
    into ls_keys, ls_same
    from jsonb_object_keys(me.lifestyle_attributes) k where o.lifestyle_attributes ? k;
  w := coalesce((p_weights ->> 'lifestyle')::numeric, 0);
  if w > 0 and ls_keys > 0 then
    total := total + w * cardinality(ls_same)::numeric / ls_keys; w_sum := w_sum + w;
  end if;
  if cardinality(ls_same) > 0 then
    r := r || jsonb_build_object('kind', 'lifestyle', 'items', to_jsonb(ls_same), 'count', cardinality(ls_same));
  end if;

  -- location (same district; no GPS is ever collected)
  w := coalesce((p_weights ->> 'location')::numeric, 0);
  if w > 0 then
    s := case when lower(me.city) = lower(o.city) then 1 else 0 end;
    total := total + w * s; w_sum := w_sum + w;
  end if;
  if lower(me.city) = lower(o.city) then r := r || jsonb_build_object('kind', 'city', 'items', jsonb_build_array(o.city)); end if;

  -- profile completeness
  w := coalesce((p_weights ->> 'completeness')::numeric, 0);
  if w > 0 then total := total + w * o.completion_score / 100.0; w_sum := w_sum + w; end if;

  score := case when w_sum = 0 then 0 else round(100 * total / w_sum)::int end;
  reasons := r;
  return next;
end $$;

-- -----------------------------------------------------------------------------
-- 5. Serving suggestions
--    * Already-shown-today (not acted on) come back first, so a refresh never
--      spends the allowance again.
--    * New ones fill the page up to min(page_max, remaining daily allowance).
--    * Never: yourself, blocked, not onboarded, hidden for review, outside
--      either person's preferences, already swiped (passes hide for 7 days),
--      or shown within the repeat window.
-- -----------------------------------------------------------------------------
create or replace function public.get_suggestions(p_section text default 'main', p_limit int default 10, p_exclude uuid[] default '{}')
returns table (id uuid, full_name text, age smallint, city text, bio text, primary_photo text,
               is_premium boolean, is_verified boolean, photo_count int,
               photo_urls text[], prompts jsonb, interest_tags text[], occupation text, education text,
               height_cm int, gender text, pronouns text, languages text[], lifestyle_attributes jsonb,
               music_top_artists jsonb, shared_artist_ids text[], shared_interest_count int,
               compatibility int, reasons jsonb, section text)
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid(); cfg public.recommendation_config; v_limit int; v_remaining int; v_today date := current_date;
  v_weights jsonb; v_room int; v_taken int := 0; c record;
begin
  if v_me is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_section not in ('main', 'you_may_like') then raise exception 'Unknown section' using errcode = '22023'; end if;
  if not exists (select 1 from public.profiles where profiles.id = v_me and is_onboarded) then return; end if;
  perform public.enforce_rate_limit('suggestions', 120, interval '1 hour');
  select * into cfg from public.recommendation_config;
  v_limit := least(greatest(coalesce(p_limit, cfg.page_default), 1), cfg.page_max);
  v_weights := case when p_section = 'main' then cfg.weights else cfg.you_may_like_weights end;
  select cfg.daily_limit - coalesce((select shown from public.recommendation_daily d where d.user_id = v_me and d.day = v_today), 0)
    into v_remaining;

  create temporary table if not exists _sugg (target uuid primary key, score int, reasons jsonb, sec text, ord int) on commit drop;
  truncate _sugg;

  -- (a) shown earlier today in this section, still eligible
  insert into _sugg
  select h.target_id, h.score, h.reasons, h.section, row_number() over (order by h.score desc)
    from public.recommendation_history h join public.profiles p on p.id = h.target_id
   where h.user_id = v_me and h.section = p_section and h.shown_at >= v_today
     and not (h.target_id = any (p_exclude))
     and p.is_onboarded and not p.hidden_pending_review and not public.is_blocked(v_me, p.id)
     and not exists (select 1 from public.swipes_and_requests s where s.sender_id = v_me and s.receiver_id = p.id)
   order by h.score desc
   limit v_limit;
  get diagnostics v_taken = row_count;

  -- (b) new candidates, within the remaining allowance
  v_room := least(v_limit - v_taken, greatest(v_remaining, 0));
  if v_room > 0 then
    for c in
      select p.id as pid, sc.score, sc.reasons
        from public.profiles p
        cross join lateral public.suggestion_score(v_me, p.id, v_weights) sc
       where p.id <> v_me
         and p.is_onboarded and cardinality(p.photo_urls) >= 4 and not p.hidden_pending_review
         and not public.is_blocked(v_me, p.id)
         and public.prefs_match(v_me, p.id)
         and not (p.id = any (p_exclude))
         and not exists (select 1 from _sugg x where x.target = p.id)
         and not exists (select 1 from public.recommendation_history h
                          where h.user_id = v_me and h.target_id = p.id and h.shown_at > now() - make_interval(days => cfg.repeat_days))
         and not exists (select 1 from public.swipes_and_requests s
                          where s.sender_id = v_me and s.receiver_id = p.id
                            and not (s.action = 'pass' and s.created_at < now() - interval '7 days'))
         and not exists (select 1 from public.swipes_and_requests s
                          where s.sender_id = p.id and s.receiver_id = v_me and s.action in ('accepted', 'rejected'))
       order by sc.score desc, p.created_at desc
       limit v_room
    loop
      insert into _sugg values (c.pid, c.score, c.reasons, p_section, 1000 + v_taken);
      insert into public.recommendation_history (user_id, target_id, section, score, reasons)
      values (v_me, c.pid, p_section, c.score, c.reasons)
      on conflict (user_id, target_id) do update set section = excluded.section, score = excluded.score,
        reasons = excluded.reasons, shown_at = now();
      v_taken := v_taken + 1;
    end loop;
    insert into public.recommendation_daily (user_id, day, shown)
    values (v_me, v_today, (select count(*) from _sugg where ord >= 1000))
    on conflict (user_id, day) do update set shown = recommendation_daily.shown + excluded.shown;
  end if;

  return query
  select f.id, f.full_name, f.age, f.city, f.bio, f.primary_photo, f.is_premium, f.is_verified, f.photo_count,
         f.photo_urls, f.prompts, f.interest_tags, f.occupation, f.education, f.height_cm, f.gender, f.pronouns,
         f.languages, f.lifestyle_attributes, f.music_top_artists, f.shared_artist_ids, f.shared_interest_count,
         x.score, x.reasons, x.sec
    from _sugg x cross join lateral public.get_profile_card(x.target) f
   order by x.ord < 1000 desc, x.score desc;
end $$;

-- Allowance left today and when it resets (midnight, database time zone).
create or replace function public.suggestion_status()
returns table (daily_limit int, shown_today int, remaining int, resets_at timestamptz)
language sql stable security definer set search_path = public as $$
  select c.daily_limit, coalesce(d.shown, 0), greatest(c.daily_limit - coalesce(d.shown, 0), 0),
         (current_date + 1)::timestamptz
    from public.recommendation_config c
    left join public.recommendation_daily d on d.user_id = auth.uid() and d.day = current_date;
$$;

-- -----------------------------------------------------------------------------
-- 6. Discover also respects the preferences
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
     and public.prefs_match(me.id, p.id)
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

-- -----------------------------------------------------------------------------
-- 7. Retention
-- -----------------------------------------------------------------------------
create or replace function public.purge_recommendations()
returns void language sql security definer set search_path = public as $$
  delete from public.recommendation_history where shown_at < now() - interval '90 days';
  delete from public.recommendation_daily where day < current_date - 30;
$$;

revoke all on function public.prefs_match(uuid, uuid), public.suggestion_score(uuid, uuid, jsonb),
  public.get_suggestions(text, int, uuid[]), public.suggestion_status(), public.purge_recommendations(),
  public.admin_set_recommendation_config(jsonb, int, int), public.get_feed(int)
  from public, anon;
grant execute on function public.get_suggestions(text, int, uuid[]), public.suggestion_status(),
  public.admin_set_recommendation_config(jsonb, int, int), public.get_feed(int) to authenticated;
grant execute on function public.purge_recommendations() to service_role;
-- prefs_match / suggestion_score run inside the definer functions only.
