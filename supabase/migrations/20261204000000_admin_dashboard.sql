-- migration-id: 20261204000000_admin_dashboard
-- description: Backend for the web admin dashboard. Adds account deactivation and a 30-day removal window as new
--   nullable columns, and staff-only functions: overview, user search and detail, direct actions without a report
--   (warn, restrict, suspend, ban, deactivate, reactivate, remove, cancel removal), unsuspend, list of suspended
--   accounts, audit log and staff management. Moderators can warn, restrict, suspend and unsuspend; only admins can
--   ban, remove and manage staff. Every action is written to moderation_actions and access_audit_log.
-- tables: none created (columns added to public.profiles)
-- columns-added: profiles.deactivated_at, profiles.removal_due_at, profiles.deactivation_reason
-- backward-compat: Additive. Existing functions keep their signatures. active_restriction() additionally reports
--   'suspended' for a deactivated profile, so existing gates (requests, messages, discovery) apply with no app change.
-- recovery: drop the mod_*/admin_* functions added here; the three nullable columns can stay unused.
-- user-data: none changed. "Remove" only marks an account (hidden at once, 30-day recovery); nothing is deleted here.
-- =============================================================================

alter table public.profiles
  add column if not exists deactivated_at timestamptz,
  add column if not exists removal_due_at timestamptz,
  add column if not exists deactivation_reason text;

-- Deactivated or removal-pending accounts behave like a suspension everywhere the app already checks.
create or replace function public.active_restriction(p_uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select r.kind from public.user_restrictions r
      where r.user_id = p_uid and r.lifted_at is null and (r.until is null or r.until > now())
        and r.kind <> 'warning'
      order by case r.kind when 'banned' then 0 when 'suspended' then 1 else 2 end
      limit 1),
    (select 'suspended' from public.profiles p where p.id = p_uid and p.deactivated_at is not null));
$$;

create or replace function public.my_restriction()
returns table (kind text, reason text, until timestamptz)
language sql stable security definer set search_path = public as $$
  select * from (
    select r.kind, r.reason, r.until from public.user_restrictions r
     where r.user_id = auth.uid() and r.lifted_at is null and (r.until is null or r.until > now())
    union all
    select 'suspended', coalesce(p.deactivation_reason, 'Your account is deactivated.'), p.removal_due_at
      from public.profiles p where p.id = auth.uid() and p.deactivated_at is not null
  ) x
  order by case x.kind when 'banned' then 0 when 'suspended' then 1 when 'restricted' then 2 else 3 end
  limit 1;
$$;

-- Status label used by the dashboard.
create or replace function public.account_status(p_uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select case
    when p.removal_due_at is not null then 'removal_pending'
    when public.active_restriction(p.id) = 'banned' then 'banned'
    when p.deactivated_at is not null then 'deactivated'
    when public.active_restriction(p.id) = 'suspended' then 'suspended'
    when public.active_restriction(p.id) = 'restricted' then 'restricted'
    else 'active' end
  from public.profiles p where p.id = p_uid;
$$;

-- ---------------------------------------------------------------- overview --
create or replace function public.mod_overview()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return jsonb_build_object(
    'open_reports', (select count(*) from public.reports where status in ('open', 'reviewing')),
    'suspended', (select count(*) from public.profiles p where public.account_status(p.id) in ('suspended', 'deactivated')),
    'restricted', (select count(*) from public.profiles p where public.account_status(p.id) = 'restricted'),
    'banned', (select count(*) from public.profiles p where public.account_status(p.id) = 'banned'),
    'removal_pending', (select count(*) from public.profiles where removal_due_at is not null),
    'open_tickets', (select count(*) from public.support_tickets where status in ('open', 'in_progress')),
    'users_total', (select count(*) from public.profiles),
    'users_today', (select count(*) from public.profiles where created_at >= date_trunc('day', now())),
    'actions_today', (select count(*) from public.moderation_actions where created_at >= date_trunc('day', now())));
end $$;

-- ------------------------------------------------------------------- users --
create or replace function public.mod_user_search(p_q text default null, p_status text default null,
                                                  p_limit int default 30, p_offset int default 0)
returns table (id uuid, full_name text, age smallint, city text, gender text, is_verified boolean,
               created_at timestamptz, status text, reports_against bigint)
language plpgsql stable security definer set search_path = public as $$
declare v_q text := nullif(btrim(coalesce(p_q, '')), '');
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return query
  select p.id, p.full_name, p.age, p.city, p.gender, p.is_verified, p.created_at, public.account_status(p.id),
         (select count(*) from public.reports r where r.reported_id = p.id)
    from public.profiles p left join auth.users u on u.id = p.id
   where (v_q is null
          or p.full_name ilike '%' || replace(replace(v_q, '%', ''), '_', '') || '%'
          or p.id::text = v_q
          or u.email ilike v_q || '%'
          or regexp_replace(coalesce(u.phone, ''), '\D', '', 'g') like '%' || nullif(regexp_replace(v_q, '\D', '', 'g'), '') || '%')
     and (p_status is null or p_status = 'all' or public.account_status(p.id) = p_status)
   order by p.created_at desc
   limit least(greatest(coalesce(p_limit, 30), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end $$;

create or replace function public.mod_user_detail(p_user uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason)
  values (auth.uid(), 'view_user', 'user', p_user::text, 'dashboard user detail');
  select jsonb_build_object(
    'id', p.id, 'full_name', p.full_name, 'age', p.age, 'city', p.city, 'gender', p.gender, 'bio', p.bio,
    'is_verified', p.is_verified, 'is_onboarded', p.is_onboarded, 'created_at', p.created_at,
    'photo_count', cardinality(p.photo_urls), 'photo_ids', to_jsonb(p.photo_urls),
    'email', u.email, 'phone', u.phone,
    'status', public.account_status(p.id),
    'deactivated_at', p.deactivated_at, 'deactivation_reason', p.deactivation_reason, 'removal_due_at', p.removal_due_at,
    'history', public.mod_user_history(p.id),
    'reports', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'report_no', r.report_no, 'reason', r.reason,
         'status', r.status, 'decision', r.decision, 'created_at', r.created_at, 'role', 'against') order by r.created_at desc)
         from public.reports r where r.reported_id = p.id), '[]'))
    into v
    from public.profiles p left join auth.users u on u.id = p.id where p.id = p_user;
  if v is null then raise exception 'User not found' using errcode = 'P0002'; end if;
  return v;
end $$;

-- Direct actions (no report needed). A note is always required.
create or replace function public.mod_apply_action(p_user uuid, p_action text, p_note text, p_days int default null)
returns text language plpgsql security definer set search_path = public as $$
declare v_note text := btrim(coalesce(p_note, '')); v_until timestamptz;
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  if p_action not in ('warning', 'restricted', 'suspended', 'banned', 'deactivate', 'reactivate', 'remove', 'cancel_removal') then
    raise exception 'Invalid action' using errcode = '22023';
  end if;
  if p_action in ('banned', 'remove', 'cancel_removal') and not public.is_staff('admin') then
    raise exception 'Only admins can do this' using errcode = '42501';
  end if;
  if char_length(v_note) < 3 then raise exception 'Add a note explaining the action' using errcode = '22023'; end if;
  if p_user = auth.uid() then raise exception 'You can''t act on your own account' using errcode = '22023'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'User not found' using errcode = 'P0002'; end if;
  if exists (select 1 from public.staff_roles where user_id = p_user) and not public.is_staff('admin') then
    raise exception 'Only admins can act on staff accounts' using errcode = '42501';
  end if;

  if p_action in ('warning', 'restricted', 'suspended', 'banned') then
    v_until := case when p_days is null or p_action = 'banned' then null else now() + make_interval(days => p_days) end;
    insert into public.user_restrictions (user_id, kind, reason, until, created_by)
    values (p_user, p_action, left(v_note, 500), v_until, auth.uid());
    insert into public.user_notifications (user_id, kind, title, body)
    values (p_user, 'moderation_' || p_action,
            case p_action when 'warning' then 'A warning from Vouby safety' when 'restricted' then 'Your account is limited'
                          when 'suspended' then 'Your account is suspended' else 'Your account is banned' end,
            'Reason: ' || left(v_note, 300));
  elsif p_action = 'deactivate' then
    update public.profiles set deactivated_at = coalesce(deactivated_at, now()), deactivation_reason = left(v_note, 500) where id = p_user;
    insert into public.user_notifications (user_id, kind, title, body)
    values (p_user, 'moderation_deactivated', 'Your account is deactivated', 'Reason: ' || left(v_note, 300));
  elsif p_action = 'reactivate' then
    update public.profiles set deactivated_at = null, deactivation_reason = null where id = p_user and removal_due_at is null;
    insert into public.user_notifications (user_id, kind, title, body)
    values (p_user, 'moderation_reactivated', 'Your account is active again', 'You can use Vouby as before.');
  elsif p_action = 'remove' then
    update public.profiles set deactivated_at = coalesce(deactivated_at, now()), removal_due_at = now() + interval '30 days',
           deactivation_reason = left(v_note, 500) where id = p_user;
  else -- cancel_removal
    update public.profiles set removal_due_at = null, deactivated_at = null, deactivation_reason = null where id = p_user;
    insert into public.user_notifications (user_id, kind, title, body)
    values (p_user, 'moderation_reactivated', 'Your account is active again', 'You can use Vouby as before.');
  end if;

  insert into public.moderation_actions (target_user, actor_id, decision, restriction, until, note)
  values (p_user, auth.uid(), 'direct_' || p_action,
          case when p_action in ('warning', 'restricted', 'suspended', 'banned') then p_action end, v_until, v_note);
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason)
  values (auth.uid(), 'user_' || p_action, 'user', p_user::text, left(v_note, 500));
  return public.account_status(p_user);
end $$;

-- Unsuspend: lifts every active restriction (not warnings) and reactivates a deactivated account.
-- A pending removal needs an admin (cancel_removal).
create or replace function public.mod_unsuspend_user(p_user uuid, p_note text)
returns text language plpgsql security definer set search_path = public as $$
declare v_note text := btrim(coalesce(p_note, ''));
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  if char_length(v_note) < 3 then raise exception 'Add a note explaining the action' using errcode = '22023'; end if;
  if exists (select 1 from public.user_restrictions where user_id = p_user and kind = 'banned' and lifted_at is null)
     and not public.is_staff('admin') then
    raise exception 'Only admins can lift a ban' using errcode = '42501';
  end if;
  if exists (select 1 from public.profiles where id = p_user and removal_due_at is not null) then
    raise exception 'Removal is pending: an admin must cancel it first' using errcode = '22023';
  end if;
  update public.user_restrictions set lifted_at = now(), lifted_by = auth.uid()
   where user_id = p_user and lifted_at is null and kind <> 'warning';
  update public.profiles set deactivated_at = null, deactivation_reason = null where id = p_user;
  insert into public.user_notifications (user_id, kind, title, body)
  values (p_user, 'moderation_reactivated', 'Your account is active again', 'You can use Vouby as before.');
  insert into public.moderation_actions (target_user, actor_id, decision, note)
  values (p_user, auth.uid(), 'unsuspended', v_note);
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason)
  values (auth.uid(), 'user_unsuspend', 'user', p_user::text, left(v_note, 500));
  return public.account_status(p_user);
end $$;

-- Everyone currently limited, with who did it and why.
create or replace function public.mod_list_restricted(p_kind text default null)
returns table (user_id uuid, full_name text, status text, kind text, reason text, since timestamptz, until timestamptz,
               by_email text, report_no text, removal_due_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return query
  select p.id, p.full_name, public.account_status(p.id), x.kind, x.reason, x.since, x.until, x.by_email, x.report_no, p.removal_due_at
    from public.profiles p
    left join lateral (
      select r.kind, r.reason, r.created_at as since, r.until, au.email::text as by_email, rp.report_no
        from public.user_restrictions r
        left join auth.users au on au.id = r.created_by
        left join public.reports rp on rp.id = r.report_id
       where r.user_id = p.id and r.lifted_at is null and (r.until is null or r.until > now()) and r.kind <> 'warning'
       order by case r.kind when 'banned' then 0 when 'suspended' then 1 else 2 end, r.created_at desc limit 1) x on true
   where public.account_status(p.id) <> 'active'
     and (p_kind is null or p_kind = 'all' or public.account_status(p.id) = p_kind)
   order by coalesce(x.since, p.deactivated_at) desc nulls last
   limit 200;
end $$;

-- ------------------------------------------------------------------- audit --
create or replace function public.mod_audit_log(p_limit int default 50, p_offset int default 0)
returns table (id bigint, created_at timestamptz, actor_email text, action text, target_type text, target_id text, reason text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return query
  select a.id, a.created_at, u.email::text, a.action, a.target_type, a.target_id, a.reason
    from public.access_audit_log a left join auth.users u on u.id = a.actor_id
   order by a.created_at desc
   limit least(greatest(coalesce(p_limit, 50), 1), 200) offset greatest(coalesce(p_offset, 0), 0);
end $$;

-- ------------------------------------------------------------------- staff --
create or replace function public.admin_list_staff()
returns table (user_id uuid, email text, role text, granted_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return query select s.user_id, u.email::text, s.role, s.granted_at
    from public.staff_roles s left join auth.users u on u.id = s.user_id order by s.granted_at;
end $$;

-- p_role: 'moderator', 'admin', or null to remove. The person must already have an account.
create or replace function public.admin_set_staff(p_email text, p_role text)
returns void language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  if p_role is not null and p_role not in ('moderator', 'admin') then raise exception 'Invalid role' using errcode = '22023'; end if;
  select id into v_id from auth.users where lower(email) = lower(btrim(p_email));
  if v_id is null then raise exception 'No account with that email' using errcode = 'P0002'; end if;
  if v_id = auth.uid() then raise exception 'You can''t change your own role' using errcode = '22023'; end if;
  if p_role is null then
    delete from public.staff_roles where user_id = v_id;
  else
    insert into public.staff_roles (user_id, role, granted_by) values (v_id, p_role, auth.uid())
    on conflict (user_id) do update set role = excluded.role, granted_by = excluded.granted_by;
  end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason)
  values (auth.uid(), 'staff_' || coalesce(p_role, 'removed'), 'user', v_id::text, 'staff role change');
end $$;

revoke all on function public.account_status(uuid), public.mod_overview(), public.mod_user_search(text, text, int, int),
  public.mod_user_detail(uuid), public.mod_apply_action(uuid, text, text, int), public.mod_unsuspend_user(uuid, text),
  public.mod_list_restricted(text), public.mod_audit_log(int, int), public.admin_list_staff(), public.admin_set_staff(text, text)
  from public, anon;
grant execute on function public.mod_overview(), public.mod_user_search(text, text, int, int), public.mod_user_detail(uuid),
  public.mod_apply_action(uuid, text, text, int), public.mod_unsuspend_user(uuid, text), public.mod_list_restricted(text),
  public.mod_audit_log(int, int), public.admin_list_staff(), public.admin_set_staff(text, text) to authenticated;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261204000000_admin_dashboard',
        'Admin dashboard backend: user search/detail, direct actions, unsuspend, restricted list, audit log, staff',
        array['public.profiles'], array['profiles.deactivated_at', 'profiles.removal_due_at', 'profiles.deactivation_reason'])
on conflict (migration_id) do nothing;
