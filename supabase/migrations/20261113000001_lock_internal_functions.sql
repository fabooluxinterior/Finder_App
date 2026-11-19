-- Supabase grants EXECUTE on new functions to `authenticated` by default.
-- These helpers are for edge functions (service role) or run inside other
-- SECURITY DEFINER functions only; signed-in clients must not call them.
revoke execute on function
  public.service_music_store(uuid, text, text, jsonb),
  public.service_music_store_v2(uuid, text, text, jsonb, jsonb, jsonb, text),
  public.service_music_reauth(uuid),
  public.refresh_public_music(uuid),
  public.normalize_artists(jsonb),
  public.normalize_tracks(jsonb, boolean),
  public.normalize_prompts(jsonb),
  public.onboarding_missing(uuid),
  public.purge_music_states(),
  public.prefs_match(uuid, uuid),
  public.suggestion_score(uuid, uuid, jsonb),
  public.purge_recommendations()
from authenticated, anon, public;

grant execute on function
  public.service_music_store(uuid, text, text, jsonb),
  public.service_music_store_v2(uuid, text, text, jsonb, jsonb, jsonb, text),
  public.service_music_reauth(uuid),
  public.refresh_public_music(uuid),
  public.normalize_artists(jsonb),
  public.normalize_tracks(jsonb, boolean),
  public.onboarding_missing(uuid),
  public.purge_music_states(),
  public.purge_recommendations()
to service_role;
