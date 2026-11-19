-- migration-id: 20261116000000_email_after_phone
-- description: Sign-up is by mobile number; an email address is added and confirmed afterwards.
--   Registers 'email' as an optional profile detail so existing phone-only accounts get the
--   "small update" prompt (never blocked), and lets the app ask whether the signed-in account
--   has a confirmed email.
-- tables: public.profile_requirements (one new row)
-- columns-added: none
-- backward-compat: Additive. Email sign-in keeps working for accounts that already use it; the
--   email itself stays in auth.users (managed by Supabase Auth) and is never copied to a public table.
-- recovery: Nothing existing is modified. Set profile_requirements.active = false for 'email' to stop
--   the prompt; the replaced requirement_missing keeps every earlier case unchanged.
-- user-data: optional (email)
-- =============================================================================

-- True when the account has a confirmed email in Supabase Auth.
create or replace function public.has_confirmed_email(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select nullif(btrim(coalesce(to_jsonb(u) ->> 'email', '')), '') is not null
       and (not (to_jsonb(u) ? 'email_confirmed_at') or (to_jsonb(u) ->> 'email_confirmed_at') is not null)
      from auth.users u where u.id = p_user), false);
$$;

-- requirement_missing: previous keys unchanged + email.
create or replace function public.requirement_missing(p_key text, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case p_key
    when 'occupation' then coalesce(btrim(p.occupation), '') = ''
    when 'discovery_prefs' then p.prefs_set_at is null and cardinality(p.pref_genders) = 0
                                and p.pref_age_min = 18 and p.pref_age_max = 60
    when 'email' then not public.has_confirmed_email(p.id)
    else false
  end
  from public.profiles p where p.id = p_user;
$$;

-- The signed-in user's own status only (no address is returned).
create or replace function public.my_email_status()
returns boolean language sql stable security definer set search_path = public as $$
  select public.has_confirmed_email(auth.uid());
$$;

insert into public.profile_requirements (key, label, description, form, level, introduced_by)
values ('email', 'Email address', 'Add an email so we can reach you about your account and support tickets.',
        'email', 'optional', '20261116000000_email_after_phone')
on conflict (key) do nothing;
update public.profile_requirements r
   set affected_at_intro = (select count(*) from public.profiles p
                             where p.is_onboarded and public.requirement_missing('email', p.id))
 where r.key = 'email' and r.affected_at_intro is null;

revoke all on function public.has_confirmed_email(uuid) from public, anon, authenticated;
revoke all on function public.my_email_status() from public, anon;
grant execute on function public.my_email_status() to authenticated;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261116000000_email_after_phone',
        'Mobile sign-up, email added and confirmed afterwards; optional email detail for existing accounts',
        array['public.profile_requirements'], array[]::text[])
on conflict (migration_id) do nothing;
