-- migration-id: 20261129000000_tags_accept_accents
-- description: Interests and languages only accepted plain A-Z letters, but the app's own interest list contains
--   "Cafés". Picking it made the whole interests step fail on the server, so "Continue" appeared to do nothing.
--   valid_tag_list() now accepts any letter (accented included). Length, duplicate and no-digits/links rules are
--   unchanged, and contact details are still rejected. Only the function body changes; no row is touched and every
--   value that was valid before is still valid.
-- tables: none (function replaced)
-- columns-added: none
-- backward-compat: Strictly wider than before; older app versions keep working and can now save "Cafés" too.
-- recovery: re-create the function with the previous pattern '^[A-Za-z][A-Za-z &''/-]*$' (see 20261111000000_profile_builder.sql).
-- user-data: none
-- =============================================================================

create or replace function public.valid_tag_list(p text[], p_max_len int)
returns boolean language sql immutable as $$
  select not exists (select 1 from unnest(p) t
                      where char_length(t) not between 2 and p_max_len or t !~ '^[[:alpha:]][[:alpha:] &''/-]*$')
     and cardinality(p) = (select count(distinct lower(t)) from unnest(p) t);
$$;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261129000000_tags_accept_accents',
        'Interest and language tags accept accented letters (fixes "Cafés" failing to save)',
        array[]::text[], array[]::text[])
on conflict (migration_id) do nothing;
