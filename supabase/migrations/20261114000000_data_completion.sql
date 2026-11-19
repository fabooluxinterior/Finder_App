-- migration-id: 20261114000000_data_completion
-- description: Data-preservation tooling and the profile-update system: schema change log,
--   data snapshot for before/after checks, a registry of profile details introduced after
--   launch (asked only of users who are missing them), integration status for the admin app.
--   First registered detail: Profession (profiles.occupation), optional.
-- tables: public.schema_change_log (new), public.profile_requirements (new),
--   public.user_requirement_status (new), public.integration_status (new)
-- columns-added: none on existing tables
-- backward-compat: Additive only. No existing table, column, row or RPC is changed; older app
--   versions keep working and simply don't call the new RPCs.
-- recovery: Nothing to restore: no existing data is modified. The new tables can be ignored.
-- user-data: optional (occupation)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Schema change log (shown in the admin app)
-- -----------------------------------------------------------------------------
create table if not exists public.schema_change_log (
  migration_id  text primary key,
  description   text not null,
  tables        text[] not null default '{}',
  columns_added text[] not null default '{}',
  status        text not null default 'applied' check (status in ('applied', 'failed', 'rolled_forward')),
  error         text,
  applied_at    timestamptz not null default now()
);
alter table public.schema_change_log enable row level security;
-- No policies: read through admin_schema_status().

-- Earlier migrations (metadata only; applied_at = when this row was recorded).
insert into public.schema_change_log (migration_id, description, tables) values
  ('20261107000000_init_finder', 'Initial schema: profiles, requests, messages, RLS, storage, realtime',
   array['public.profiles', 'public.profile_private', 'public.swipes_and_requests', 'public.messages']),
  ('20261108000000_security', 'E2EE keys and envelopes, encrypted media, blocks, reports, staff, audit, rate limits',
   array['public.devices', 'public.message_envelopes', 'public.media_objects', 'public.blocks', 'public.reports', 'public.staff_roles']),
  ('20261109000000_subscription_model', 'Free requests; requests inbox and messaging need Fast-Track',
   array['public.swipes_and_requests']),
  ('20261110000000_compliance', 'Consents, date of birth, selfie verification, open profiles',
   array['public.user_consents', 'public.profile_dob', 'public.verification_requests', 'public.profiles']),
  ('20261111000000_profile_builder', 'Photo slots, identity and lifestyle, prompts, completion score, onboarding, Spotify',
   array['public.profiles', 'public.prompt_catalog', 'public.music_accounts', 'public.music_oauth_states']),
  ('20261112000000_music_tracks', 'Spotify top tracks and recently played',
   array['public.music_accounts', 'public.profiles']),
  ('20261113000000_suggestions', 'Suggestions, discovery preferences, recommendation limits and history',
   array['public.recommendation_config', 'public.interest_catalog', 'public.recommendation_history', 'public.recommendation_daily']),
  ('20261113000001_lock_internal_functions', 'Revoke client access to internal and service-only functions', '{}')
on conflict (migration_id) do nothing;

-- -----------------------------------------------------------------------------
-- 2. Data snapshot: row counts + key checksums (before/after a migration)
-- -----------------------------------------------------------------------------
create or replace function public.data_snapshot()
returns table (table_name text, row_count bigint, key_checksum text)
language plpgsql stable security definer set search_path = public as $$
declare r record;
begin
  for r in select * from (values
      ('profiles', 'id::text'), ('profile_private', 'id::text'), ('profile_dob', 'user_id::text'),
      ('swipes_and_requests', 'id::text'), ('messages', 'id::text'),
      ('message_envelopes', 'message_id::text || recipient_device_id::text'),
      ('media_objects', 'id::text'), ('user_consents', 'id::text'), ('music_accounts', 'user_id::text'),
      ('blocks', 'blocker_id::text || blocked_id::text'), ('reports', 'id::text'),
      ('verification_requests', 'id::text'), ('devices', 'id::text'), ('staff_roles', 'user_id::text'),
      ('profiles_premium', null)) t(name, keyexpr)
  loop
    table_name := r.name;
    if r.name = 'profiles_premium' then
      -- Subscription status lives on profiles.is_premium.
      execute 'select count(*), md5(coalesce(string_agg(id::text, '','' order by id), '''')) from public.profiles where is_premium'
        into row_count, key_checksum;
    elsif to_regclass('public.' || r.name) is null then
      continue;
    else
      execute format('select count(*), md5(coalesce(string_agg(%s, '','' order by %s), '''')) from public.%I',
                     r.keyexpr, r.keyexpr, r.name)
        into row_count, key_checksum;
    end if;
    return next;
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- 3. Profile details introduced after launch
-- -----------------------------------------------------------------------------
create table if not exists public.profile_requirements (
  key               text primary key check (key ~ '^[a-z][a-z0-9_]{1,40}$'),
  label             text not null check (char_length(label) between 2 and 60),
  description       text not null check (char_length(description) between 5 and 300),
  form              text not null default 'basics',          -- which editor section opens
  level             text not null default 'optional' check (level in ('optional', 'feature', 'required')),
  gated_feature     text,                                    -- only this feature waits for it
  introduced_by     text not null,                           -- migration id
  active            boolean not null default true,
  affected_at_intro int,                                     -- users missing it when introduced
  reminder_sent_at  timestamptz,                             -- admin "send reminder"
  created_at        timestamptz not null default now(),
  check (level <> 'feature' or gated_feature is not null)
);
alter table public.profile_requirements enable row level security;
drop policy if exists profile_requirements_read on public.profile_requirements;
create policy profile_requirements_read on public.profile_requirements
  for select to authenticated using (active);

-- Prompt state per user (never profile data).
create table if not exists public.user_requirement_status (
  user_id          uuid not null references public.profiles (id) on delete cascade,
  key              text not null references public.profile_requirements (key) on delete cascade,
  last_prompted_at timestamptz,
  dismissed_at     timestamptz,
  completed_at     timestamptz,
  primary key (user_id, key)
);
alter table public.user_requirement_status enable row level security;
drop policy if exists user_requirement_status_own on public.user_requirement_status;
create policy user_requirement_status_own on public.user_requirement_status
  for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete, truncate on public.user_requirement_status from anon, authenticated;

-- Is <key> missing for <user>? Each migration that registers a key adds its
-- line here (create or replace, copying the previous body).
create or replace function public.requirement_missing(p_key text, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case p_key
    when 'occupation' then coalesce(btrim(p.occupation), '') = ''
    else false
  end
  from public.profiles p where p.id = p_user;
$$;

-- The signed-in user's missing details. show_prompt is false while the user
-- has dismissed an optional item or was prompted in the last 7 days (unless
-- staff sent a reminder since).
create or replace function public.my_profile_updates()
returns table (key text, label text, description text, form text, level text,
               gated_feature text, show_prompt boolean)
language sql stable security definer set search_path = public as $$
  select r.key, r.label, r.description, r.form, r.level, r.gated_feature,
         (s.dismissed_at is null or r.level <> 'optional')
         and (s.last_prompted_at is null
              or s.last_prompted_at < now() - interval '7 days'
              or (r.reminder_sent_at is not null and s.last_prompted_at < r.reminder_sent_at))
    from public.profile_requirements r
    left join public.user_requirement_status s on s.user_id = auth.uid() and s.key = r.key
   where auth.uid() is not null and r.active
     and coalesce(public.requirement_missing(r.key, auth.uid()), false)
   order by case r.level when 'required' then 0 when 'feature' then 1 else 2 end, r.created_at;
$$;

create or replace function public.mark_profile_update_seen(p_key text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if not exists (select 1 from public.profile_requirements where key = p_key and active) then
    raise exception 'Unknown profile update' using errcode = '22023';
  end if;
  insert into public.user_requirement_status (user_id, key, last_prompted_at)
  values (auth.uid(), p_key, now())
  on conflict (user_id, key) do update set last_prompted_at = excluded.last_prompted_at;
end $$;

create or replace function public.dismiss_profile_update(p_key text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if not exists (select 1 from public.profile_requirements where key = p_key and active and level = 'optional') then
    raise exception 'This detail can''t be skipped' using errcode = '22023';
  end if;
  insert into public.user_requirement_status (user_id, key, last_prompted_at, dismissed_at)
  values (auth.uid(), p_key, now(), now())
  on conflict (user_id, key) do update set dismissed_at = now(), last_prompted_at = now();
end $$;

-- Feature gating helper: call at the top of a feature's RPC when a detail
-- registered with level 'feature' is needed. Never locks the account.
create or replace function public.require_profile_details(p_feature text)
returns void language plpgsql stable security definer set search_path = public as $$
declare v_missing text;
begin
  select string_agg(r.label, ', ') into v_missing
    from public.profile_requirements r
   where r.active and r.gated_feature = p_feature
     and coalesce(public.requirement_missing(r.key, auth.uid()), false);
  if v_missing is not null then
    raise exception 'Add % to use this feature', v_missing using errcode = 'P0001', hint = 'PROFILE_UPDATE_REQUIRED';
  end if;
end $$;

-- Records completion when a saved profile no longer misses a prompted detail.
-- Touches only the status rows of that user.
create or replace function public.tg_profiles_requirements() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.user_requirement_status s set completed_at = now()
   where s.user_id = new.id and s.completed_at is null
     and not coalesce(public.requirement_missing(s.key, new.id), true);
  return null;
end $$;
drop trigger if exists profiles_requirements on public.profiles;
create trigger profiles_requirements after update on public.profiles
  for each row execute function public.tg_profiles_requirements();

-- First registered detail: Profession. Already a column; optional; existing
-- values are untouched and users who have one are never asked.
insert into public.profile_requirements (key, label, description, form, level, introduced_by)
values ('occupation', 'Profession', 'Add what you do so people have more to talk about.', 'basics', 'optional',
        '20261114000000_data_completion')
on conflict (key) do nothing;
update public.profile_requirements r
   set affected_at_intro = (select count(*) from public.profiles p
                             where p.is_onboarded and coalesce(btrim(p.occupation), '') = '')
 where r.key = 'occupation' and r.affected_at_intro is null;

-- -----------------------------------------------------------------------------
-- 4. Integration status (written by the admin-config-status edge function;
--    never holds secret values)
-- -----------------------------------------------------------------------------
create table if not exists public.integration_status (
  service       text primary key,
  configured    boolean not null default false,
  missing       text[] not null default '{}',
  valid         boolean,
  message       text check (char_length(message) <= 300),
  checked_at    timestamptz not null default now(),
  validated_at  timestamptz
);
alter table public.integration_status enable row level security;
-- No policies: read through admin_integration_status().

-- -----------------------------------------------------------------------------
-- 5. Admin RPCs (staff admins only; every call re-checks the role)
-- -----------------------------------------------------------------------------
create or replace function public.admin_schema_status()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_log jsonb; v_cli jsonb;
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(l) order by l.migration_id), '[]') into v_log from public.schema_change_log l;
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'select coalesce(jsonb_agg(version order by version), ''[]'') from supabase_migrations.schema_migrations' into v_cli;
  end if;
  return jsonb_build_object('change_log', v_log, 'applied_versions', v_cli);
end $$;

create or replace function public.admin_data_snapshot()
returns table (table_name text, row_count bigint, key_checksum text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return query select * from public.data_snapshot();
end $$;

create or replace function public.admin_requirement_stats()
returns table (key text, label text, level text, gated_feature text, introduced_by text, active boolean,
               created_at timestamptz, reminder_sent_at timestamptz, affected_at_intro int,
               users_total bigint, pending bigint, completed bigint, dismissed bigint, prompted bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return query
  select r.key, r.label, r.level, r.gated_feature, r.introduced_by, r.active, r.created_at,
         r.reminder_sent_at, r.affected_at_intro,
         m.total, m.pending, m.total - m.pending,
         (select count(*) from public.user_requirement_status s
           where s.key = r.key and s.dismissed_at is not null and s.completed_at is null),
         (select count(*) from public.user_requirement_status s where s.key = r.key)
    from public.profile_requirements r
    cross join lateral (
      select count(*) as total,
             count(*) filter (where coalesce(public.requirement_missing(r.key, p.id), false)) as pending
        from public.profiles p where p.is_onboarded) m
   order by r.created_at;
end $$;

-- "Send reminder": users still missing the detail see the prompt again on
-- their next visit (dismissed optional items stay dismissed).
create or replace function public.admin_remind_requirement(p_key text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  update public.profile_requirements set reminder_sent_at = now() where key = p_key;
  if not found then raise exception 'Unknown profile update' using errcode = '22023'; end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id)
  values (auth.uid(), 'remind_profile_update', 'profile_requirement', p_key);
end $$;

create or replace function public.admin_integration_status()
returns setof public.integration_status
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return query select * from public.integration_status order by service;
end $$;

create or replace function public.service_record_integration(
  p_service text, p_configured boolean, p_missing text[], p_valid boolean, p_message text, p_validated boolean)
returns void language sql security definer set search_path = public as $$
  insert into public.integration_status (service, configured, missing, valid, message, checked_at, validated_at)
  values (p_service, p_configured, coalesce(p_missing, '{}'), p_valid, left(p_message, 300), now(),
          case when p_validated then now() end)
  on conflict (service) do update set
    configured = excluded.configured, missing = excluded.missing, checked_at = now(),
    valid = case when p_validated then excluded.valid else integration_status.valid end,
    message = case when p_validated then excluded.message else integration_status.message end,
    validated_at = case when p_validated then now() else integration_status.validated_at end;
$$;

-- -----------------------------------------------------------------------------
-- 6. Privileges
-- -----------------------------------------------------------------------------
revoke all on public.schema_change_log, public.integration_status from anon, authenticated;
revoke all on function public.data_snapshot(), public.requirement_missing(text, uuid),
  public.service_record_integration(text, boolean, text[], boolean, text, boolean),
  public.tg_profiles_requirements() from public, anon, authenticated;
grant execute on function public.data_snapshot(),
  public.service_record_integration(text, boolean, text[], boolean, text, boolean) to service_role;
revoke all on function public.my_profile_updates(), public.mark_profile_update_seen(text),
  public.dismiss_profile_update(text), public.require_profile_details(text),
  public.admin_schema_status(), public.admin_data_snapshot(), public.admin_requirement_stats(),
  public.admin_remind_requirement(text), public.admin_integration_status() from public, anon;
grant execute on function public.my_profile_updates(), public.mark_profile_update_seen(text),
  public.dismiss_profile_update(text), public.admin_schema_status(), public.admin_data_snapshot(),
  public.admin_requirement_stats(), public.admin_remind_requirement(text),
  public.admin_integration_status() to authenticated;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261114000000_data_completion',
        'Data-preservation tooling, profile-update prompts (first: Profession), integration status for admin',
        array['public.schema_change_log', 'public.profile_requirements', 'public.user_requirement_status',
              'public.integration_status'],
        '{}')
on conflict (migration_id) do nothing;
