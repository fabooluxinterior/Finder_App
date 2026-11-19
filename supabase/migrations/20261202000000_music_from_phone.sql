-- migration-id: 20261202000000_music_from_phone
-- description: Spotify can now be connected straight from the phone (PKCE, no server secret). The phone keeps the
--   Spotify tokens; the server only stores the imported lists. One new function saves them, reusing the same
--   validation (normalize_artists / normalize_tracks) as the server flow, so only safe fields are kept.
-- tables: none (one function added over public.music_accounts)
-- columns-added: none
-- backward-compat: Additive. The server flow (music-connect/music-sync) and every existing function are unchanged.
-- recovery: drop function public.store_my_music(jsonb, jsonb, jsonb, text);
-- user-data: none changed
-- =============================================================================

create or replace function public.store_my_music(p_artists jsonb, p_tracks jsonb, p_recent jsonb, p_scopes text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  perform public.enforce_rate_limit('store_my_music', 30, interval '1 hour');
  if p_artists is not null and jsonb_typeof(p_artists) <> 'array'
     or p_tracks is not null and jsonb_typeof(p_tracks) <> 'array'
     or p_recent is not null and jsonb_typeof(p_recent) <> 'array' then
    raise exception 'Invalid list' using errcode = '22023';
  end if;
  -- No token is stored here: the phone keeps it. Tokens from the server flow are left untouched.
  perform public.service_music_store_v2(auth.uid(), null, null, coalesce(p_artists, '[]'), coalesce(p_tracks, '[]'),
                                        p_recent, p_scopes);
end $$;
revoke all on function public.store_my_music(jsonb, jsonb, jsonb, text) from public, anon;
grant execute on function public.store_my_music(jsonb, jsonb, jsonb, text) to authenticated;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261202000000_music_from_phone',
        'Save the Spotify import made on the phone (no server secret needed)',
        array['public.music_accounts'], array[]::text[])
on conflict (migration_id) do nothing;
