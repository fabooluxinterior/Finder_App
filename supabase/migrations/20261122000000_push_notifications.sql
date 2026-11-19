-- migration-id: 20261122000000_push_notifications
-- description: Dashboard-to-phone popup notifications. Phones register a push token; an admin (staff with
--   two-step verification) sends a custom message to everyone, to free users, to trial/Fast-Track users or to
--   one user. Each send is logged and also lands in the user's in-app notification list.
-- tables: public.push_devices, public.push_campaigns (new). public.user_notifications gets new rows only.
-- columns-added: none (new tables only)
-- backward-compat: Additive. Existing tables, RPCs and policies are unchanged; older app versions never call
--   the new functions and simply do not receive popups.
-- recovery: drop function public.register_push_token(text, text), public.unregister_push_token(text),
--   public.mod_push_prepare(text, text, text, text), public.push_campaign_tokens(uuid, text, int),
--   public.push_campaign_finish(uuid, int, int), public.mod_list_push_campaigns(); drop table
--   public.push_campaigns, public.push_devices. Nothing else depends on them.
-- user-data: push tokens (device addresses) only; users can remove theirs at any time.
-- =============================================================================

create table if not exists public.push_devices (
  token        text primary key check (char_length(token) between 20 and 4096),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  platform     text not null default 'android' check (platform in ('android', 'ios', 'web')),
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index if not exists push_devices_user_idx on public.push_devices (user_id);
alter table public.push_devices enable row level security;   -- no policies: only the functions below touch it
revoke all on public.push_devices from anon, authenticated;

create table if not exists public.push_campaigns (
  id          uuid primary key default gen_random_uuid(),
  sent_by     uuid references auth.users (id) on delete set null,
  title       text not null check (char_length(title) between 1 and 65),
  body        text not null check (char_length(body) between 1 and 240),
  audience    text not null check (audience in ('all', 'free', 'plan', 'user')),
  target_user uuid,
  recipients  int not null default 0,
  delivered   int not null default 0,
  failed      int not null default 0,
  created_at  timestamptz not null default now()
);
alter table public.push_campaigns enable row level security;
revoke all on public.push_campaigns from anon, authenticated;

-- A phone registers (or refreshes) its own token. A token follows whoever signed in last.
create or replace function public.register_push_token(p_token text, p_platform text default 'android')
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_token is null or char_length(p_token) not between 20 and 4096 then
    raise exception 'Invalid token' using errcode = '22023';
  end if;
  perform public.enforce_rate_limit('push_register', 30, interval '1 day');
  insert into public.push_devices (token, user_id, platform)
  values (p_token, auth.uid(), case when p_platform in ('android', 'ios', 'web') then p_platform else 'android' end)
  on conflict (token) do update set user_id = auth.uid(), last_seen_at = now();
  -- at most 5 phones per account: the oldest are dropped
  delete from public.push_devices d
   where d.user_id = auth.uid()
     and d.token in (select token from public.push_devices where user_id = auth.uid()
                      order by last_seen_at desc offset 5);
end $$;

create or replace function public.unregister_push_token(p_token text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  delete from public.push_devices where token = p_token and user_id = auth.uid();
end $$;

-- Who a campaign reaches. Internal: no direct grants.
create or replace function public.push_audience_users(p_audience text, p_user uuid)
returns table (user_id uuid) language sql stable security definer set search_path = public as $$
  select p.id from public.profiles p
   where p.is_onboarded
     and case p_audience
           when 'all'  then true
           when 'free' then not public.has_fast_track(p.id)
           when 'plan' then public.has_fast_track(p.id)
           when 'user' then p.id = p_user
           else false end;
$$;
revoke all on function public.push_audience_users(text, uuid) from public, anon, authenticated;

-- Admin only (with two-step verification). Records the send, adds the message to each recipient's in-app
-- notification list, and returns the campaign id. The edge function then pushes to the phones.
create or replace function public.mod_push_prepare(p_title text, p_body text, p_audience text, p_phone text default null)
returns table (campaign_id uuid, recipients int, devices int) language plpgsql security definer set search_path = public as $$
declare v_user uuid; v_id uuid; v_n int; v_d int; v_digits text;
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  p_title := btrim(coalesce(p_title, '')); p_body := btrim(coalesce(p_body, ''));
  if char_length(p_title) not between 1 and 65 then raise exception 'Title must be 1-65 characters' using errcode = '22023'; end if;
  if char_length(p_body) not between 1 and 240 then raise exception 'Message must be 1-240 characters' using errcode = '22023'; end if;
  if p_audience not in ('all', 'free', 'plan', 'user') then raise exception 'Unknown audience' using errcode = '22023'; end if;
  perform public.enforce_rate_limit('push_send', 20, interval '1 day');

  if p_audience = 'user' then
    v_digits := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
    if char_length(v_digits) < 10 then raise exception 'Enter the user''s mobile number' using errcode = '22023'; end if;
    select u.id into v_user from auth.users u
     where right(regexp_replace(coalesce(to_jsonb(u)->>'phone', ''), '\D', '', 'g'), 10) = right(v_digits, 10) limit 1;
    if v_user is null then raise exception 'No user with that mobile number' using errcode = 'P0002'; end if;
  end if;

  insert into public.push_campaigns (sent_by, title, body, audience, target_user)
  values (auth.uid(), p_title, p_body, p_audience, v_user) returning id into v_id;

  insert into public.user_notifications (user_id, kind, title, body)
  select a.user_id, 'announcement', p_title, p_body from public.push_audience_users(p_audience, v_user) a;
  get diagnostics v_n = row_count;

  select count(*) into v_d from public.push_devices d
   where d.user_id in (select a.user_id from public.push_audience_users(p_audience, v_user) a);
  update public.push_campaigns set recipients = v_n where id = v_id;
  perform public.log_security_event('push_campaign_sent', 'info',
    jsonb_build_object('campaign', v_id, 'audience', p_audience, 'recipients', v_n), auth.uid());
  return query select v_id, v_n, v_d;
end $$;

-- Service role only: a page of device tokens for a campaign.
create or replace function public.push_campaign_tokens(p_campaign uuid, p_after text default '', p_limit int default 500)
returns table (token text) language sql stable security definer set search_path = public as $$
  select d.token from public.push_campaigns c
    join public.push_audience_users(c.audience, c.target_user) a on true
    join public.push_devices d on d.user_id = a.user_id
   where c.id = p_campaign and d.token > coalesce(p_after, '')
   order by d.token limit least(greatest(p_limit, 1), 1000);
$$;

create or replace function public.push_campaign_finish(p_campaign uuid, p_delivered int, p_failed int)
returns void language sql security definer set search_path = public as $$
  update public.push_campaigns set delivered = greatest(p_delivered, 0), failed = greatest(p_failed, 0) where id = p_campaign;
$$;

create or replace function public.mod_list_push_campaigns()
returns setof public.push_campaigns language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return query select * from public.push_campaigns order by created_at desc limit 50;
end $$;

revoke all on function public.register_push_token(text, text), public.unregister_push_token(text),
  public.mod_push_prepare(text, text, text, text), public.push_campaign_tokens(uuid, text, int),
  public.push_campaign_finish(uuid, int, int), public.mod_list_push_campaigns() from public, anon;
grant execute on function public.register_push_token(text, text), public.unregister_push_token(text),
  public.mod_push_prepare(text, text, text, text), public.mod_list_push_campaigns() to authenticated;
revoke execute on function public.push_campaign_tokens(uuid, text, int), public.push_campaign_finish(uuid, int, int) from authenticated;
grant execute on function public.push_campaign_tokens(uuid, text, int), public.push_campaign_finish(uuid, int, int) to service_role;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261122000000_push_notifications',
        'Push notifications: device tokens, admin-sent campaigns (all/free/plan/one user) with log and in-app copy',
        array['public.push_devices', 'public.push_campaigns', 'public.user_notifications'], array[]::text[])
on conflict (migration_id) do nothing;
