-- migration-id: 20261117000001_public_function_execute
-- description: Completes 20261117000000: nine functions were still callable by signed-out users through
--   PostgreSQL's built-in PUBLIC execute grant. Revokes PUBLIC and anon on them; signed-in users keep
--   (or are given explicitly) EXECUTE where the app calls them.
-- tables: none
-- columns-added: none
-- backward-compat: Additive hardening. The app only calls these while signed in; trigger functions are
--   unaffected (trigger privileges are checked when the trigger is created, not when it fires).
-- recovery: grant execute on function public.<name> to public;  (not needed by any app version)
-- user-data: none
-- =============================================================================

grant execute on function public.can_upload_evidence(text), public.mod_review_media(uuid, boolean),
  public.my_staff_role() to authenticated;

revoke execute on function public.can_upload_evidence(text), public.mod_review_media(uuid, boolean),
  public.my_staff_role(), public.tg_dob_locked(), public.tg_profiles_age(), public.tg_profiles_builder(),
  public.tg_profiles_photos_after(), public.tg_profiles_standards(), public.tg_swipes_intro_guard()
  from public, anon;

-- Functions created from now on start closed to everyone except the roles that are granted explicitly.
alter default privileges for role postgres in schema public revoke execute on functions from public;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261117000001_public_function_execute',
        'Revoke PUBLIC and anon EXECUTE on nine functions; new functions closed to PUBLIC by default',
        array[]::text[], array[]::text[])
on conflict (migration_id) do nothing;
