-- migration-id: 20261125000000_matches_not_suggested
-- description: (1) Suggestions no longer re-show someone you are already connected with or who answered you
--   (the "shown earlier today" list skipped that check). (2) A profile you passed in Discovery can still be
--   suggested; requests and connections never are. (3) Requesting someone you are already connected with can
--   no longer create a second row (which showed as a duplicate chat card).
-- tables: none (two functions replaced)
-- columns-added: none
-- backward-compat: Same signatures and return values; older app versions keep working.
-- recovery: Re-create the previous bodies from 20261113000000_suggestions.sql and 20261120000000_pass_then_request_fix.sql.
-- user-data: none (existing rows are untouched)
-- =============================================================================

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
     and not exists (select 1 from public.swipes_and_requests s
                      where s.sender_id = p.id and s.receiver_id = v_me and s.action in ('accepted', 'rejected'))
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
         -- A profile passed in Discovery may still be suggested; requests and connections never are.
         and not exists (select 1 from public.swipes_and_requests s
                          where s.sender_id = v_me and s.receiver_id = p.id and s.action <> 'pass')
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

create or replace function public.swipe_profile(p_target uuid, p_action public.swipe_action)
returns text language plpgsql security definer set search_path = public as $$
declare v_me uuid := auth.uid(); v_reverse public.swipes_and_requests; v_existing public.swipe_action; v_new uuid;
begin
  if v_me is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_action not in ('pass', 'follow_requested') then
    raise exception 'Invalid swipe action' using errcode = '22023';
  end if;

  if p_action = 'pass' then
    -- A pass older than 7 days expires, so it can be made again.
    delete from public.swipes_and_requests
     where sender_id = v_me and receiver_id = p_target
       and action = 'pass' and created_at < now() - interval '7 days';
    insert into public.swipes_and_requests (sender_id, receiver_id, action)
    values (v_me, p_target, 'pass') on conflict (sender_id, receiver_id) do nothing;
    return 'passed';
  end if;

  -- Already connected (either direction): never create a second row, so the chat can't be duplicated.
  if exists (select 1 from public.swipes_and_requests s
              where s.action = 'accepted'
                and ((s.sender_id = v_me and s.receiver_id = p_target) or (s.sender_id = p_target and s.receiver_id = v_me))) then
    return 'matched';
  end if;

  -- Sending a request: changing your mind about your own earlier pass is allowed.
  delete from public.swipes_and_requests
   where sender_id = v_me and receiver_id = p_target and action = 'pass';

  -- They already asked me: that is a match.
  select * into v_reverse from public.swipes_and_requests
   where sender_id = p_target and receiver_id = v_me and action = 'follow_requested' for update;
  if found then
    update public.swipes_and_requests set action = 'accepted', responded_at = now() where id = v_reverse.id;
    return 'matched';
  end if;

  insert into public.swipes_and_requests (sender_id, receiver_id, action)
  values (v_me, p_target, 'follow_requested')
  on conflict (sender_id, receiver_id) do nothing
  returning id into v_new;
  if v_new is not null then return 'requested'; end if;

  -- Something already exists for this pair: report what is true.
  select action into v_existing from public.swipes_and_requests where sender_id = v_me and receiver_id = p_target;
  return case v_existing when 'follow_requested' then 'requested' when 'accepted' then 'matched' else 'passed' end;
end $$;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261125000000_matches_not_suggested',
        'Matches no longer reappear in Suggestions; Discovery passes may be suggested; no duplicate connection rows',
        array['public.swipes_and_requests'], array[]::text[])
on conflict (migration_id) do nothing;
