-- migration-id: 20261118000000_contact_email
-- description: The email address is collected for account and support notifications only. It is NOT
--   verified and is not used to sign in. Stored in its own private table (never in a public profile
--   field, never shown to other users); existing confirmed emails are copied across so nobody is
--   asked again. Support tickets pick the contact email first.
-- tables: public.user_contacts (new); public.profile_requirements ('email' detection changes)
-- columns-added: none on existing tables
-- backward-compat: Additive. Older app versions never call the new RPCs. requirement_missing and the
--   two support functions are replaced with the same signatures; their earlier behaviour is kept
--   (the account's own auth email is still the fallback).
-- recovery: Nothing existing is modified or removed. user_contacts can be ignored or dropped later
--   with owner approval; the backfill only copies emails that already exist in auth.users.
-- user-data: optional (email)
-- =============================================================================

create table if not exists public.user_contacts (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  email      text not null check (char_length(email) <= 254 and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  updated_at timestamptz not null default now()
);
alter table public.user_contacts enable row level security;
-- No policies and no direct privileges: only the functions below (and the service role) touch it.
revoke all on public.user_contacts from anon, authenticated;

-- Copy emails people already have (additive; never overwrites a stored contact email).
insert into public.user_contacts (user_id, email)
select u.id, lower(btrim(to_jsonb(u) ->> 'email'))
  from auth.users u
 where coalesce(btrim(to_jsonb(u) ->> 'email'), '') <> ''
   and lower(btrim(to_jsonb(u) ->> 'email')) ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
   and char_length(btrim(to_jsonb(u) ->> 'email')) <= 254
on conflict (user_id) do nothing;

create or replace function public.set_contact_email(p_email text)
returns void language plpgsql security definer set search_path = public as $$
declare v text := lower(btrim(coalesce(p_email, '')));
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if char_length(v) > 254 or v !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Enter a valid email address' using errcode = '22023';
  end if;
  perform public.enforce_rate_limit('contact_email', 10, interval '1 hour');
  insert into public.user_contacts (user_id, email) values (auth.uid(), v)
  on conflict (user_id) do update set email = excluded.email, updated_at = now();
end $$;

create or replace function public.my_contact_email()
returns text language sql stable security definer set search_path = public as $$
  select c.email from public.user_contacts c where c.user_id = auth.uid();
$$;

-- requirement_missing: earlier keys unchanged; 'email' now means "no contact email stored".
create or replace function public.requirement_missing(p_key text, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case p_key
    when 'occupation' then coalesce(btrim(p.occupation), '') = ''
    when 'discovery_prefs' then p.prefs_set_at is null and cardinality(p.pref_genders) = 0
                                and p.pref_age_min = 18 and p.pref_age_max = 60
    when 'email' then not exists (select 1 from public.user_contacts c where c.user_id = p.id)
    else false
  end
  from public.profiles p where p.id = p_user;
$$;

update public.profile_requirements
   set description = 'Add an email so we can send you account and support notifications. It is never shown to anyone.'
 where key = 'email';

-- Support tickets: reply-to comes from the contact email first, then the account's own email.
create or replace function public.submit_support_ticket(p_category text, p_subject text, p_description text,
  p_attachment_path text default null)
returns table (id uuid, ticket_no text) language plpgsql security definer set search_path = public as $$
declare v_no text; v_id uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  perform public.enforce_rate_limit('support_ticket', 5, interval '1 day');
  if p_attachment_path is not null and split_part(p_attachment_path, '/', 1) <> auth.uid()::text then
    raise exception 'Invalid attachment' using errcode = '22023';
  end if;
  loop
    v_no := public.new_ref('VB');
    exit when not exists (select 1 from public.support_tickets t where t.ticket_no = v_no);
  end loop;
  insert into public.support_tickets (ticket_no, user_id, email, category, subject, description, attachment_path)
  values (v_no, auth.uid(),
          coalesce((select c.email from public.user_contacts c where c.user_id = auth.uid()),
                   (select to_jsonb(u) ->> 'email' from auth.users u where u.id = auth.uid())),
          p_category, btrim(p_subject), btrim(p_description), p_attachment_path)
  returning support_tickets.id into v_id;
  insert into public.support_ticket_events (ticket_id, status, actor_id) values (v_id, 'new', auth.uid());
  return query select v_id, v_no;
end $$;

create or replace function public.my_support_email()
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select c.email from public.user_contacts c where c.user_id = auth.uid()),
                  (select to_jsonb(u) ->> 'email' from auth.users u where u.id = auth.uid()));
$$;

revoke all on function public.set_contact_email(text), public.my_contact_email() from public, anon;
grant execute on function public.set_contact_email(text), public.my_contact_email() to authenticated;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261118000000_contact_email',
        'Email collected for notifications only (not verified), stored privately; existing emails copied; support tickets use it',
        array['public.user_contacts', 'public.profile_requirements'], array[]::text[])
on conflict (migration_id) do nothing;
