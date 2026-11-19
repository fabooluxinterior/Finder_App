-- migration-id: 20261203000000_suggestions_respect_preferences
-- description: Suggestions replayed people already shown earlier today even after the viewer changed Discovery
--   preferences (e.g. switched to Men and still saw women). The replay step now applies the same preference rule
--   (prefs_match) as new candidates. Same signature and result columns as before.
-- tables: none (one function replaced)
-- columns-added: none
-- backward-compat: Additive in behaviour only: fewer stale suggestions. Signature unchanged; older apps keep working.
-- recovery: re-apply the previous definition of public.get_suggestions from 20261113000000_suggestions.sql
-- user-data: none changed
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_suggestions(p_section text DEFAULT 'main'::text, p_limit integer DEFAULT 10, p_exclude uuid[] DEFAULT '{}'::uuid[])
 RETURNS TABLE(id uuid, full_name text, age smallint, city text, bio text, primary_photo text, is_premium boolean, is_verified boolean, photo_count integer, photo_urls text[], prompts jsonb, interest_tags text[], occupation text, education text, height_cm integer, gender text, pronouns text, languages text[], lifestyle_attributes jsonb, music_top_artists jsonb, shared_artist_ids text[], shared_interest_count integer, compatibility integer, reasons jsonb, section text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
     and public.prefs_match(v_me, p.id)
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
end $function$;

revoke all on function public.get_suggestions(text, int, uuid[]) from public, anon;
grant execute on function public.get_suggestions(text, int, uuid[]) to authenticated;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261203000000_suggestions_respect_preferences',
        'Suggestions apply Discovery preferences to people shown earlier today as well',
        array['public.recommendation_history'], array[]::text[])
on conflict (migration_id) do nothing;
