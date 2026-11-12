-- migration-id: 20261119000000_consent_version_fix
-- description: accepted_policy_version() counted the setup acknowledgement 'community_standards'
--   (written once, at the version current during setup, never refreshed by a re-consent), so after
--   any policy-version bump the oldest-version answer stayed old and the "We've updated our policies"
--   screen came back after every Agree. It now looks only at the four policies a re-consent records.
-- tables: none (function replaced)
-- columns-added: none
-- backward-compat: Same signature and return type, so every app version keeps working; the answer
--   is the same or newer than before, never older. No consent row is changed or removed.
-- recovery: Re-create the previous body from 20261110000000_compliance.sql if ever needed.
-- user-data: none
-- =============================================================================

create or replace function public.accepted_policy_version()
returns text language sql stable security definer set search_path = public as $$
  select case when count(distinct policy_type) < 4 then null else min(v) end
    from (select policy_type, max(policy_version) v from public.user_consents
           where user_id = auth.uid()
             and policy_type in ('terms', 'privacy', 'community_guidelines', 'age_18_plus')
           group by policy_type) t;
$$;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261119000000_consent_version_fix',
        'accepted_policy_version() ignores the setup acknowledgement so re-consent works after a policy bump',
        array['public.user_consents'], array[]::text[])
on conflict (migration_id) do nothing;
