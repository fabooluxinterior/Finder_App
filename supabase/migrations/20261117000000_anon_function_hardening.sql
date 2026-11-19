-- migration-id: 20261117000000_anon_function_hardening
-- description: Hosted Supabase grants EXECUTE on every new public function to the signed-out (anon)
--   role by default. Earlier migrations revoked it per function; this closes the remaining nine and
--   changes the default so future functions are not open to signed-out callers.
-- tables: none
-- columns-added: none
-- backward-compat: Additive hardening. The app only calls these functions while signed in (the
--   authenticated role keeps its EXECUTE); trigger functions are unaffected because trigger
--   privileges are checked when the trigger is created, not when it fires.
-- recovery: grant execute on function public.<name> to anon;  (not needed by any app version)
-- user-data: none
-- =============================================================================

revoke execute on function public.can_upload_evidence(text) from anon;
revoke execute on function public.mod_review_media(uuid, boolean) from anon;
revoke execute on function public.my_staff_role() from anon;
revoke execute on function public.tg_dob_locked() from anon;
revoke execute on function public.tg_profiles_age() from anon;
revoke execute on function public.tg_profiles_builder() from anon;
revoke execute on function public.tg_profiles_photos_after() from anon;
revoke execute on function public.tg_profiles_standards() from anon;
revoke execute on function public.tg_swipes_intro_guard() from anon;

-- Future functions created by the migration role start closed to signed-out callers.
alter default privileges for role postgres in schema public revoke execute on functions from anon;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261117000000_anon_function_hardening',
        'Revoke EXECUTE from the signed-out role on nine functions; closed by default for new functions',
        array[]::text[], array[]::text[])
on conflict (migration_id) do nothing;
