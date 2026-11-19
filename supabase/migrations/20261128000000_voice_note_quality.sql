-- migration-id: 20261128000000_voice_note_quality
-- description: Voice notes were recorded at 32 kbps / 22 kHz so they would fit the 192 KB storage cap, and sounded
--   thin and broken. New recordings use 64 kbps / 44.1 kHz mono AAC (about 360 KB for the full 45 seconds), so the
--   cap for the voice_notes bucket is raised to 512 KB. Existing voice notes are untouched and still play.
-- tables: none (one storage bucket setting changed)
-- columns-added: none
-- backward-compat: The larger cap only allows larger files; older app versions keep uploading their smaller ones.
-- recovery: update storage.buckets set file_size_limit = 196608 where id = 'voice_notes';
-- user-data: none
-- =============================================================================

update storage.buckets set file_size_limit = 524288 where id = 'voice_notes';

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261128000000_voice_note_quality',
        'Voice note storage cap raised to 512 KB for clearer 64 kbps / 44.1 kHz recordings',
        array['storage.buckets'], array[]::text[])
on conflict (migration_id) do nothing;
