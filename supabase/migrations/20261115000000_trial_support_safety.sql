-- migration-id: 20261115000000_trial_support_safety
-- description: Discovery preferences in setup (prefs_set_at), 7-day free trial (168 h, once per
--   phone/email, new accounts only, starts when setup finishes), in-app notifications, support
--   tickets, safety reports with moderation decisions/history/restrictions, consented evidence
--   storage, and end-to-end encrypted chat photos.
-- tables: public.profiles (new column), public.reports (new columns, wider reason list),
--   public.app_private_settings, public.user_trials, public.trial_claims, public.user_notifications,
--   public.user_restrictions, public.moderation_actions, public.report_evidence,
--   public.support_tickets, public.support_ticket_events (new); storage buckets chat_images,
--   report_evidence, support_attachments (new)
-- columns-added: profiles.prefs_set_at (timestamptz, nullable); reports.report_no, reports.content_ref,
--   reports.decision, reports.decided_by, reports.decided_at (nullable)
-- backward-compat: Additive. Existing RPC signatures unchanged; access checks now also accept an
--   active trial; old report reasons and statuses remain valid. Older app versions keep working.
-- recovery: No existing rows are modified or removed (new nullable columns only). New tables can be
--   ignored; replaced functions keep their previous behaviour for every existing user.
-- user-data: optional (discovery_prefs)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Discovery preferences chosen during setup
-- -----------------------------------------------------------------------------
alter table public.profiles add column if not exists prefs_set_at timestamptz;

create or replace function public.tg_profiles_prefs_set() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.pref_age_min, new.pref_age_max, new.pref_genders) is distinct from (old.pref_age_min, old.pref_age_max, old.pref_genders)
     or new.prefs_set_at is distinct from old.prefs_set_at then
    new.prefs_set_at := now();
  end if;
  return new;
end $$;
drop trigger if exists profiles_prefs_set on public.profiles;
create trigger profiles_prefs_set before update on public.profiles
  for each row execute function public.tg_profiles_prefs_set();

-- Clients may confirm their (unchanged) preferences; the trigger stamps the time.
grant update (prefs_set_at) on public.profiles to authenticated;

-- requirement_missing: previous keys + discovery_prefs. Users who already
-- changed their preferences from the defaults are never asked.
create or replace function public.requirement_missing(p_key text, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case p_key
    when 'occupation' then coalesce(btrim(p.occupation), '') = ''
    when 'discovery_prefs' then p.prefs_set_at is null and cardinality(p.pref_genders) = 0
                                and p.pref_age_min = 18 and p.pref_age_max = 60
    else false
  end
  from public.profiles p where p.id = p_user;
$$;

insert into public.profile_requirements (key, label, description, form, level, introduced_by)
values ('discovery_prefs', 'Who you’d like to meet', 'Choose who you’re interested in and an age range.',
        'discovery', 'optional', '20261115000000_trial_support_safety')
on conflict (key) do nothing;
update public.profile_requirements r
   set affected_at_intro = (select count(*) from public.profiles p
                             where p.is_onboarded and public.requirement_missing('discovery_prefs', p.id))
 where r.key = 'discovery_prefs' and r.affected_at_intro is null;

-- -----------------------------------------------------------------------------
-- 2. Free trial: exactly 168 hours, once per phone/email, new accounts only
-- -----------------------------------------------------------------------------
create table if not exists public.app_private_settings (
  key   text primary key,
  value text not null
);
alter table public.app_private_settings enable row level security;
revoke all on public.app_private_settings from anon, authenticated;
insert into public.app_private_settings (key, value) values
  ('trial_salt', replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')),
  ('trial_launch_at', now()::text)
on conflict (key) do nothing;

create table if not exists public.user_trials (
  user_id             uuid primary key references public.profiles (id) on delete cascade,
  started_at          timestamptz not null default now(),
  ends_at             timestamptz not null,
  reminded_24h_at     timestamptz,
  expired_notified_at timestamptz,
  notice_24h_seen_at  timestamptz,
  notice_end_seen_at  timestamptz,
  check (ends_at = started_at + interval '168 hours')
);
alter table public.user_trials enable row level security;
drop policy if exists user_trials_own on public.user_trials;
create policy user_trials_own on public.user_trials for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete, truncate on public.user_trials from anon, authenticated;

-- Survives account deletion on purpose (no foreign key): one trial per
-- phone/email. Holds a salted hash only, never the phone or email.
create table if not exists public.trial_claims (
  identity_hash text primary key,
  claimed_at    timestamptz not null default now()
);
alter table public.trial_claims enable row level security;
revoke all on public.trial_claims from anon, authenticated;

create or replace function public.trial_identity_hash(p_user uuid)
returns text language sql stable security definer set search_path = public as $$
  select encode(sha256(convert_to(
           (select value from public.app_private_settings where key = 'trial_salt') || ':' ||
           coalesce(nullif(regexp_replace(coalesce(to_jsonb(u) ->> 'phone', ''), '\D', '', 'g'), ''),
                    nullif(lower(btrim(coalesce(to_jsonb(u) ->> 'email', ''))), ''),
                    'user:' || u.id::text), 'UTF8')), 'hex')
    from auth.users u where u.id = p_user;
$$;

create or replace function public.trial_eligible(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.user_trials t where t.user_id = p_user)
     and not exists (select 1 from public.trial_claims c where c.identity_hash = public.trial_identity_hash(p_user))
     and coalesce((select not p.is_premium and p.premium_expires_at is null from public.profiles p where p.id = p_user), false)
     and coalesce(
           (select (to_jsonb(u) ->> 'created_at')::timestamptz from auth.users u where u.id = p_user),
           (select p.created_at from public.profiles p where p.id = p_user))
         >= (select value::timestamptz from public.app_private_settings where key = 'trial_launch_at');
$$;

create or replace function public.start_trial_if_eligible(p_user uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_now timestamptz := now();
begin
  if not public.trial_eligible(p_user) then return false; end if;
  insert into public.trial_claims (identity_hash) values (public.trial_identity_hash(p_user))
  on conflict (identity_hash) do nothing;
  if not found then return false; end if;
  insert into public.user_trials (user_id, started_at, ends_at)
  values (p_user, v_now, v_now + interval '168 hours');
  insert into public.user_notifications (user_id, kind, title, body)
  values (p_user, 'trial_started', 'Your 7-day free trial has started',
          'See who sent you requests and chat with your connections until '
          || to_char(v_now + interval '168 hours', 'DD Mon') || '. Nothing is charged automatically.');
  return true;
end $$;

create or replace function public.has_active_trial(p_uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_trials t where t.user_id = p_uid and now() < t.ends_at);
$$;

-- Paid Fast-Track OR an active trial. (The public Fast-Track badge and feed
-- ordering keep using paid is_premium only.)
create or replace function public.has_fast_track(p_uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_premium(p_uid) or public.has_active_trial(p_uid);
$$;

-- -----------------------------------------------------------------------------
-- 3. In-app notifications (trial reminders, ticket updates, moderation notices)
-- -----------------------------------------------------------------------------
create table if not exists public.user_notifications (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  kind       text not null,
  title      text not null check (char_length(title) <= 120),
  body       text not null check (char_length(body) <= 600),
  created_at timestamptz not null default now(),
  read_at    timestamptz
);
create index if not exists user_notifications_user_idx on public.user_notifications (user_id, created_at desc);
alter table public.user_notifications enable row level security;
drop policy if exists user_notifications_own on public.user_notifications;
create policy user_notifications_own on public.user_notifications for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete, truncate on public.user_notifications from anon, authenticated;

create or replace function public.mark_notifications_read()
returns void language sql security definer set search_path = public as $$
  update public.user_notifications set read_at = now() where user_id = auth.uid() and read_at is null;
$$;

-- What the app shows about access: plan, trial dates and any due notice.
create or replace function public.my_access_status()
returns table (plan text, premium boolean, trial_started_at timestamptz, trial_ends_at timestamptz,
               trial_used boolean, notice text)
language sql stable security definer set search_path = public as $$
  select case when public.is_premium(auth.uid()) then 'fast_track'
              when t.ends_at > now() then 'trial' else 'free' end,
         public.is_premium(auth.uid()),
         t.started_at, t.ends_at, t.user_id is not null,
         case when public.is_premium(auth.uid()) then null
              when t.ends_at > now() and t.ends_at - now() <= interval '24 hours' and t.notice_24h_seen_at is null
                then 'trial_24h'
              when t.ends_at <= now() and t.notice_end_seen_at is null then 'trial_ended'
         end
    from (select auth.uid() as uid) me
    left join public.user_trials t on t.user_id = me.uid
   where me.uid is not null;
$$;

create or replace function public.mark_access_notice_seen(p_kind text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_kind = 'trial_24h' then
    update public.user_trials set notice_24h_seen_at = now() where user_id = auth.uid();
  elsif p_kind = 'trial_ended' then
    update public.user_trials set notice_end_seen_at = now() where user_id = auth.uid();
  else
    raise exception 'Unknown notice' using errcode = '22023';
  end if;
end $$;

-- Scheduled (media-maintenance): reminders 24 h before and at expiry.
create or replace function public.service_trial_reminders()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_24 int; v_end int;
begin
  with due as (
    update public.user_trials t set reminded_24h_at = now()
     where t.reminded_24h_at is null and t.ends_at > now() and t.ends_at - now() <= interval '24 hours'
       and not public.is_premium(t.user_id)
    returning t.user_id, t.ends_at)
  insert into public.user_notifications (user_id, kind, title, body)
  select user_id, 'trial_24h', 'Your free trial ends in 24 hours',
         'Keep chatting with Fast-Track for ₹79/month. Nothing is charged automatically; your chats stay safe either way.'
    from due;
  get diagnostics v_24 = row_count;
  with ended as (
    update public.user_trials t set expired_notified_at = now()
     where t.expired_notified_at is null and t.ends_at <= now() and not public.is_premium(t.user_id)
    returning t.user_id)
  insert into public.user_notifications (user_id, kind, title, body)
  select user_id, 'trial_ended', 'Your free trial has ended',
         'Your matches and messages are kept. Get Fast-Track (₹79/month) to see requests and chat again.'
    from ended;
  get diagnostics v_end = row_count;
  return jsonb_build_object('reminded_24h', v_24, 'ended', v_end);
end $$;

-- -----------------------------------------------------------------------------
-- 4. Moderation restrictions (only ever created by a staff decision)
-- -----------------------------------------------------------------------------
create table if not exists public.user_restrictions (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  kind       text not null check (kind in ('warning', 'restricted', 'suspended', 'banned')),
  reason     text not null check (char_length(reason) between 3 and 500),
  report_id  uuid,
  until      timestamptz,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  lifted_at  timestamptz,
  lifted_by  uuid references auth.users (id)
);
create index if not exists user_restrictions_user_idx on public.user_restrictions (user_id);
alter table public.user_restrictions enable row level security;
drop policy if exists user_restrictions_own on public.user_restrictions;
create policy user_restrictions_own on public.user_restrictions for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete, truncate on public.user_restrictions from anon, authenticated;

-- Most severe active restriction (warnings don't limit anything).
create or replace function public.active_restriction(p_uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select r.kind from public.user_restrictions r
   where r.user_id = p_uid and r.lifted_at is null and (r.until is null or r.until > now())
     and r.kind <> 'warning'
   order by case r.kind when 'banned' then 0 when 'suspended' then 1 else 2 end
   limit 1;
$$;

create or replace function public.is_moderation_hidden(p_uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.active_restriction(p_uid) in ('suspended', 'banned'), false);
$$;

create or replace function public.my_restriction()
returns table (kind text, reason text, until timestamptz)
language sql stable security definer set search_path = public as $$
  select r.kind, r.reason, r.until from public.user_restrictions r
   where r.user_id = auth.uid() and r.lifted_at is null and (r.until is null or r.until > now())
   order by case r.kind when 'banned' then 0 when 'suspended' then 1 when 'restricted' then 2 else 3 end
   limit 1;
$$;

-- Discovery (feed and suggestions both use prefs_match): previous rule +
-- suspended/banned profiles aren't shown.
create or replace function public.prefs_match(p_a uuid, p_b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select a.age between b.pref_age_min and b.pref_age_max
     and b.age between a.pref_age_min and a.pref_age_max
     and (cardinality(a.pref_genders) = 0 or b.gender = any (a.pref_genders))
     and (cardinality(b.pref_genders) = 0 or a.gender = any (b.pref_genders))
     and not public.is_moderation_hidden(b.id)
    from public.profiles a, public.profiles b where a.id = p_a and b.id = p_b;
$$;

-- Restricted, suspended or banned accounts can't send requests.
create or replace function public.tg_swipes_restriction() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.action = 'follow_requested' and public.active_restriction(new.sender_id) is not null then
    raise exception 'Your account can’t send requests right now' using errcode = 'P0001', hint = 'ACCOUNT_RESTRICTED';
  end if;
  return new;
end $$;
drop trigger if exists swipes_restriction on public.swipes_and_requests;
create trigger swipes_restriction before insert on public.swipes_and_requests
  for each row execute function public.tg_swipes_restriction();

-- -----------------------------------------------------------------------------
-- 5. Access gates: trial counts as Fast-Track (same signatures and checks as
--    before, plus restrictions on messaging)
-- -----------------------------------------------------------------------------
create or replace function public.respond_to_request(p_request_id uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.has_fast_track(auth.uid()) then
    raise exception 'Seeing requests is part of Fast-Track' using errcode = 'P0001', hint = 'SUBSCRIPTION_REQUIRED';
  end if;
  update public.swipes_and_requests
     set action = case when p_accept then 'accepted'::public.swipe_action else 'rejected'::public.swipe_action end,
         responded_at = now()
   where id = p_request_id and receiver_id = auth.uid() and action = 'follow_requested';
  if not found then raise exception 'Request not found' using errcode = 'P0002'; end if;
end $$;

create or replace function public.send_message(p_receiver uuid, p_client_msg_id uuid, p_sender_device uuid, p_envelopes jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_bad int;
begin
  if not public.is_connected(auth.uid(), p_receiver) then
    perform public.log_security_event('send_denied', 'warning', jsonb_build_object('target', p_receiver));
    raise exception 'Chat unlocks once the follow request is accepted' using errcode = '42501';
  end if;
  if not exists (select 1 from public.devices where id = p_sender_device and user_id = auth.uid() and revoked_at is null) then
    raise exception 'Unknown sender device' using errcode = '42501';
  end if;
  if not public.has_fast_track(auth.uid()) then
    raise exception 'Messaging is part of Fast-Track' using errcode = 'P0001', hint = 'SUBSCRIPTION_REQUIRED';
  end if;
  if public.active_restriction(auth.uid()) is not null then
    raise exception 'Your account can’t send messages right now' using errcode = 'P0001', hint = 'ACCOUNT_RESTRICTED';
  end if;
  perform public.enforce_rate_limit('send_message', 40, interval '1 minute');
  if jsonb_array_length(p_envelopes) = 0 or jsonb_array_length(p_envelopes) > 12 then
    raise exception 'Invalid envelopes' using errcode = '22023';
  end if;

  select count(*) into v_bad from jsonb_array_elements(p_envelopes) e
   where not exists (select 1 from public.devices d
                      where d.id = (e ->> 'device_id')::uuid and d.revoked_at is null
                        and d.user_id in (auth.uid(), p_receiver));
  if v_bad > 0 then raise exception 'Envelope for unknown device' using errcode = '42501'; end if;

  insert into public.messages (sender_id, receiver_id, client_msg_id, sender_device_id)
  values (auth.uid(), p_receiver, p_client_msg_id, p_sender_device)
  on conflict (sender_id, client_msg_id) do nothing
  returning id into v_id;
  if v_id is null then  -- idempotent retry
    select id into v_id from public.messages where sender_id = auth.uid() and client_msg_id = p_client_msg_id;
    return v_id;
  end if;

  insert into public.message_envelopes (message_id, recipient_device_id, message_type, ciphertext)
  select v_id, (e ->> 'device_id')::uuid, (e ->> 'type')::smallint, e ->> 'ciphertext'
    from jsonb_array_elements(p_envelopes) e
   where (e ->> 'device_id')::uuid <> p_sender_device;
  return v_id;
end $$;

create or replace function public.claim_device_keys(p_user uuid, p_exclude uuid[] default '{}')
returns table (device_id uuid, curve25519 text, ed25519 text, key_id text, public_key text, signature text)
language plpgsql security definer set search_path = public as $$
declare d record; k record;
begin
  if p_user <> auth.uid() and not public.is_connected(auth.uid(), p_user) then
    perform public.log_security_event('key_claim_denied', 'warning', jsonb_build_object('target', p_user));
    raise exception 'Not connected' using errcode = '42501';
  end if;
  -- Keys of other people are only needed to send them messages: Fast-Track or trial.
  if p_user <> auth.uid() and not public.has_fast_track(auth.uid()) then
    raise exception 'Messaging is part of Fast-Track' using errcode = 'P0001', hint = 'SUBSCRIPTION_REQUIRED';
  end if;
  perform public.enforce_rate_limit('claim_keys', 120, interval '1 hour');

  for d in select * from public.devices x
            where x.user_id = p_user and x.revoked_at is null and not (x.id = any (p_exclude))
  loop
    select * into k from public.one_time_keys o
     where o.device_id = d.id and not o.is_fallback
     order by o.id limit 1 for update skip locked;
    if found then
      delete from public.one_time_keys where id = k.id;
    else
      select * into k from public.one_time_keys o where o.device_id = d.id and o.is_fallback limit 1;
      if not found then continue; end if;
    end if;
    device_id := d.id; curve25519 := d.curve25519; ed25519 := d.ed25519;
    key_id := k.key_id; public_key := k.public_key; signature := k.signature;
    return next;
  end loop;
end $$;

drop policy if exists swipes_select on public.swipes_and_requests;
create policy swipes_select on public.swipes_and_requests
  for select to authenticated
  using (
    sender_id = auth.uid()
    or (receiver_id = auth.uid()
        and (action <> 'follow_requested' or public.has_fast_track(auth.uid())))
  );

-- Setup finished -> profile goes live and, for eligible new accounts, the
-- 168-hour trial starts (same checks as before).
create or replace function public.complete_onboarding()
returns void language plpgsql security definer set search_path = public as $$
declare v_missing text[];
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  v_missing := public.onboarding_missing(auth.uid());
  if v_missing is null then raise exception 'Create your profile first' using errcode = 'P0002'; end if;
  if cardinality(v_missing) > 0 then
    raise exception 'Profile incomplete: %', array_to_string(v_missing, ', ')
      using errcode = 'P0001', hint = 'ONBOARDING_INCOMPLETE';
  end if;
  update public.profiles set is_onboarded = true, onboarding_stage = 8 where id = auth.uid();
  perform public.start_trial_if_eligible(auth.uid());
end $$;

-- -----------------------------------------------------------------------------
-- 6. Safety reports: categories, decisions, history, false-report tracking
-- -----------------------------------------------------------------------------
alter table public.reports drop constraint if exists reports_reason_check;
alter table public.reports add constraint reports_reason_check check (reason in (
  -- earlier values stay valid
  'sexual_content', 'harassment', 'spam_or_scam', 'fake_profile', 'underage', 'malicious_link', 'other',
  -- new categories
  'abusive_messages', 'inappropriate_images', 'spam', 'scam', 'impersonation', 'suspicious_behaviour'));

alter table public.reports add column if not exists report_no text;
alter table public.reports add column if not exists content_ref text check (content_ref is null or char_length(content_ref) <= 80);
alter table public.reports add column if not exists decision text check (decision is null or decision in (
  'review', 'verified', 'false_report', 'dismissed', 'warning_issued', 'restricted', 'suspended', 'banned',
  'content_removed', 'resolved'));
alter table public.reports add column if not exists decided_by uuid references auth.users (id);
alter table public.reports add column if not exists decided_at timestamptz;
create unique index if not exists reports_report_no_idx on public.reports (report_no) where report_no is not null;

create or replace function public.new_ref(p_prefix text)
returns text language sql volatile security definer set search_path = public as $$
  select p_prefix || '-' || string_agg(substr('23456789ABCDEFGHJKMNPQRSTUVWXYZ', 1 + floor(random() * 31)::int, 1), '')
    from generate_series(1, 6);
$$;

create or replace function public.tg_reports_number() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.report_no is null then
    loop
      new.report_no := public.new_ref('R');
      exit when not exists (select 1 from public.reports where report_no = new.report_no);
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists reports_number on public.reports;
create trigger reports_number before insert on public.reports
  for each row execute function public.tg_reports_number();

-- Moderation history: append-only.
create table if not exists public.moderation_actions (
  id          bigint generated always as identity primary key,
  report_id   uuid references public.reports (id) on delete set null,
  target_user uuid,
  actor_id    uuid not null references auth.users (id),
  decision    text not null,
  restriction text,
  until       timestamptz,
  note        text check (char_length(note) <= 1000),
  created_at  timestamptz not null default now()
);
create index if not exists moderation_actions_target_idx on public.moderation_actions (target_user, created_at desc);
alter table public.moderation_actions enable row level security;
revoke all on public.moderation_actions from anon, authenticated;
revoke update, delete, truncate on public.moderation_actions from service_role;

-- Report with a content reference (message/photo id) and the report number.
create or replace function public.submit_report_v2(p_reported uuid, p_reason text, p_details text,
  p_content_ref text, p_evidence jsonb, p_block boolean default true)
returns table (id uuid, report_no text) language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  v_id := public.submit_report(p_reported, p_reason, p_details, p_evidence, p_block);
  update public.reports r set content_ref = p_content_ref where r.id = v_id;
  return query select r.id, r.report_no from public.reports r where r.id = v_id;
end $$;

create or replace function public.mod_list_reports_v2(p_status text default 'open')
returns table (id uuid, report_no text, reporter_id uuid, reported_id uuid, reason text, details text,
               content_ref text, has_evidence boolean, evidence_files int, report_count bigint,
               reporter_false_reports bigint, created_at timestamptz, status text, decision text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return query
  select r.id, r.report_no, r.reporter_id, r.reported_id, r.reason, r.details, r.content_ref,
         r.evidence is not null, (select count(*)::int from public.report_evidence e where e.report_id = r.id),
         (select count(*) from public.reports x where x.reported_id = r.reported_id),
         (select count(*) from public.reports x where x.reporter_id = r.reporter_id and x.decision = 'false_report'),
         r.created_at, r.status, r.decision
    from public.reports r
   where (p_status = 'all' or r.status = p_status or (p_status = 'open' and r.status = 'reviewing'))
   order by r.created_at
   limit 200;
end $$;

-- A staff decision. Restrictions are never automatic: only this call creates them.
create or replace function public.mod_decide_report(p_report uuid, p_decision text, p_note text,
  p_restriction text default null, p_days int default null)
returns void language plpgsql security definer set search_path = public as $$
declare r public.reports; v_until timestamptz; v_status text;
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  if p_decision not in ('review', 'verified', 'false_report', 'dismissed', 'warning_issued', 'restricted',
                        'suspended', 'banned', 'content_removed', 'resolved') then
    raise exception 'Invalid decision' using errcode = '22023';
  end if;
  if p_restriction is not null and p_restriction not in ('warning', 'restricted', 'suspended', 'banned') then
    raise exception 'Invalid restriction' using errcode = '22023';
  end if;
  if p_restriction = 'banned' and not public.is_staff('admin') then
    raise exception 'Only admins can ban' using errcode = '42501';
  end if;
  if coalesce(btrim(p_note), '') = '' and p_decision <> 'review' then
    raise exception 'Add a note explaining the decision' using errcode = '22023';
  end if;
  v_status := case when p_decision = 'review' then 'reviewing'
                   when p_decision in ('false_report', 'dismissed') then 'dismissed'
                   else 'actioned' end;
  update public.reports set status = v_status, decision = p_decision, decided_by = auth.uid(), decided_at = now(),
         resolution = coalesce(p_note, resolution),
         resolved_at = case when v_status = 'reviewing' then null else now() end,
         resolved_by = case when v_status = 'reviewing' then null else auth.uid() end
   where id = p_report returning * into r;
  if r.id is null then raise exception 'Report not found' using errcode = 'P0002'; end if;

  if p_restriction is not null then
    v_until := case when p_days is null or p_restriction = 'banned' then null else now() + make_interval(days => p_days) end;
    insert into public.user_restrictions (user_id, kind, reason, report_id, until, created_by)
    values (r.reported_id, p_restriction, coalesce(nullif(btrim(p_note), ''), p_decision), r.id, v_until, auth.uid());
    insert into public.user_notifications (user_id, kind, title, body)
    values (r.reported_id, 'moderation_' || p_restriction,
            case p_restriction when 'warning' then 'A warning from Vouby safety'
                               when 'restricted' then 'Your account is limited'
                               when 'suspended' then 'Your account is suspended'
                               else 'Your account is banned' end,
            'This follows a review of a report against your account. Reason: '
            || left(coalesce(nullif(btrim(p_note), ''), p_decision), 300)
            || case when v_until is not null then ' Until ' || to_char(v_until, 'DD Mon YYYY') || '.' else '' end
            || ' You can contact support to appeal.');
  end if;

  -- Under-18 reports: same visibility rule as mod_resolve_report.
  if r.reason = 'underage' and v_status = 'dismissed' and not exists (
       select 1 from public.reports x where x.reported_id = r.reported_id and x.reason = 'underage'
          and x.status in ('open', 'reviewing')) then
    update public.profiles set hidden_pending_review = false where id = r.reported_id;
  end if;

  insert into public.moderation_actions (report_id, target_user, actor_id, decision, restriction, until, note)
  values (r.id, r.reported_id, auth.uid(), p_decision, p_restriction, v_until, p_note);
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason)
  values (auth.uid(), 'decide_report:' || p_decision, 'report', r.id::text, p_note);
end $$;

create or replace function public.mod_lift_restriction(p_restriction uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare v_user uuid;
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  update public.user_restrictions set lifted_at = now(), lifted_by = auth.uid()
   where id = p_restriction and lifted_at is null returning user_id into v_user;
  if v_user is null then raise exception 'Restriction not found' using errcode = 'P0002'; end if;
  insert into public.moderation_actions (target_user, actor_id, decision, note)
  values (v_user, auth.uid(), 'restriction_lifted', p_note);
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason)
  values (auth.uid(), 'lift_restriction', 'user', v_user::text, p_note);
end $$;

-- Everything staff need to judge a report fairly.
create or replace function public.mod_user_history(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return jsonb_build_object(
    'reports_against', (select count(*) from public.reports where reported_id = p_user),
    'reports_upheld', (select count(*) from public.reports where reported_id = p_user and status = 'actioned'),
    'reports_made', (select count(*) from public.reports where reporter_id = p_user),
    'false_reports_made', (select count(*) from public.reports where reporter_id = p_user and decision = 'false_report'),
    'restrictions', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'reason', r.reason,
        'until', r.until, 'created_at', r.created_at, 'lifted_at', r.lifted_at) order by r.created_at desc)
        from public.user_restrictions r where r.user_id = p_user), '[]'),
    'actions', coalesce((select jsonb_agg(jsonb_build_object('decision', a.decision, 'restriction', a.restriction,
        'note', a.note, 'created_at', a.created_at) order by a.created_at desc)
        from (select * from public.moderation_actions where target_user = p_user order by created_at desc limit 50) a), '[]'));
end $$;

-- -----------------------------------------------------------------------------
-- 7. Evidence: only what the reporter selected and confirmed
-- -----------------------------------------------------------------------------
create table if not exists public.report_evidence (
  id           uuid primary key default gen_random_uuid(),
  report_id    uuid not null references public.reports (id) on delete cascade,
  kind         text not null check (kind in ('text', 'image')),
  message_ref  text check (char_length(message_ref) <= 80),
  storage_path text not null,
  created_at   timestamptz not null default now()
);
alter table public.report_evidence enable row level security;
revoke all on public.report_evidence from anon, authenticated;

create or replace function public.add_report_evidence(p_report uuid, p_kind text, p_message_ref text, p_path text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not exists (select 1 from public.reports r where r.id = p_report and r.reporter_id = auth.uid()
                  and r.created_at > now() - interval '1 hour') then
    raise exception 'Evidence can only be added to your own new report' using errcode = '42501';
  end if;
  if p_path is null or split_part(p_path, '/', 1) <> p_report::text then
    raise exception 'Invalid evidence path' using errcode = '22023';
  end if;
  if (select count(*) from public.report_evidence where report_id = p_report) >= 10 then
    raise exception 'Too many evidence files' using errcode = '22023';
  end if;
  insert into public.report_evidence (report_id, kind, message_ref, storage_path)
  values (p_report, p_kind, p_message_ref, p_path) returning id into v_id;
  return v_id;
end $$;

-- Staff open evidence through the evidence-url function, which calls this
-- (logged) and then signs a 5-minute URL with the service key.
create or replace function public.mod_evidence_path(p_evidence uuid, p_reason text)
returns text language plpgsql security definer set search_path = public as $$
declare v_path text; v_report uuid;
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  select storage_path, report_id into v_path, v_report from public.report_evidence where id = p_evidence;
  if v_path is null then raise exception 'Evidence not found' using errcode = 'P0002'; end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason)
  values (auth.uid(), 'open_evidence', 'report', v_report::text, coalesce(p_reason, 'review'));
  return v_path;
end $$;

create or replace function public.mod_list_evidence(p_report uuid)
returns table (id uuid, kind text, message_ref text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return query select e.id, e.kind, e.message_ref, e.created_at from public.report_evidence e
                where e.report_id = p_report order by e.created_at;
end $$;

-- Retention: evidence files of reports closed more than 90 days ago.
create or replace function public.service_expired_evidence()
returns table (id uuid, storage_path text) language sql stable security definer set search_path = public as $$
  select e.id, e.storage_path from public.report_evidence e join public.reports r on r.id = e.report_id
   where r.status in ('actioned', 'dismissed') and r.resolved_at < now() - interval '90 days';
$$;
create or replace function public.service_forget_evidence(p_ids uuid[])
returns void language sql security definer set search_path = public as $$
  delete from public.report_evidence where id = any (p_ids);
$$;

-- -----------------------------------------------------------------------------
-- 8. Support tickets
-- -----------------------------------------------------------------------------
create table if not exists public.support_tickets (
  id              uuid primary key default gen_random_uuid(),
  ticket_no       text not null unique,
  user_id         uuid references public.profiles (id) on delete set null,
  email           text,
  category        text not null check (category in ('account', 'discovery', 'chat', 'subscription', 'privacy', 'safety', 'other')),
  subject         text not null check (char_length(btrim(subject)) between 3 and 120),
  description     text not null check (char_length(btrim(description)) between 10 and 4000),
  attachment_path text,
  status          text not null default 'new' check (status in ('new', 'in_progress', 'waiting_for_user', 'resolved', 'closed')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists support_tickets_user_idx on public.support_tickets (user_id, created_at desc);
alter table public.support_tickets enable row level security;
drop policy if exists support_tickets_own on public.support_tickets;
create policy support_tickets_own on public.support_tickets for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete, truncate on public.support_tickets from anon, authenticated;

create table if not exists public.support_ticket_events (
  id         bigint generated always as identity primary key,
  ticket_id  uuid not null references public.support_tickets (id) on delete cascade,
  status     text not null,
  note       text check (char_length(note) <= 1000),
  actor_id   uuid,
  created_at timestamptz not null default now()
);
alter table public.support_ticket_events enable row level security;
drop policy if exists support_ticket_events_own on public.support_ticket_events;
create policy support_ticket_events_own on public.support_ticket_events for select to authenticated
  using (exists (select 1 from public.support_tickets t where t.id = ticket_id and t.user_id = auth.uid()));
revoke insert, update, delete, truncate on public.support_ticket_events from anon, authenticated;

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
  values (v_no, auth.uid(), (select to_jsonb(u) ->> 'email' from auth.users u where u.id = auth.uid()),
          p_category, btrim(p_subject), btrim(p_description), p_attachment_path)
  returning support_tickets.id into v_id;
  insert into public.support_ticket_events (ticket_id, status, actor_id) values (v_id, 'new', auth.uid());
  return query select v_id, v_no;
end $$;

create or replace function public.my_support_email()
returns text language sql stable security definer set search_path = public as $$
  select to_jsonb(u) ->> 'email' from auth.users u where u.id = auth.uid();
$$;

create or replace function public.mod_list_tickets(p_status text default 'open')
returns setof public.support_tickets language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return query select * from public.support_tickets t
   where p_status = 'all' or t.status = p_status
      or (p_status = 'open' and t.status in ('new', 'in_progress', 'waiting_for_user'))
   order by t.created_at limit 200;
end $$;

create or replace function public.mod_set_ticket_status(p_ticket uuid, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare t public.support_tickets;
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  update public.support_tickets set status = p_status, updated_at = now() where id = p_ticket returning * into t;
  if t.id is null then raise exception 'Ticket not found' using errcode = 'P0002'; end if;
  insert into public.support_ticket_events (ticket_id, status, note, actor_id) values (p_ticket, p_status, p_note, auth.uid());
  if t.user_id is not null then
    insert into public.user_notifications (user_id, kind, title, body)
    values (t.user_id, 'ticket_' || p_status, 'Ticket ' || t.ticket_no || ': ' || replace(p_status, '_', ' '),
            coalesce(nullif(btrim(p_note), ''), 'Your support request was updated.'));
  end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason)
  values (auth.uid(), 'ticket_status:' || p_status, 'support_ticket', p_ticket::text, p_note);
end $$;

create or replace function public.mod_ticket_attachment_path(p_ticket uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_path text;
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  select attachment_path into v_path from public.support_tickets where id = p_ticket;
  if v_path is null then raise exception 'No attachment' using errcode = 'P0002'; end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id)
  values (auth.uid(), 'open_ticket_attachment', 'support_ticket', p_ticket::text);
  return v_path;
end $$;

-- -----------------------------------------------------------------------------
-- 9. Storage: chat photos (E2EE ciphertext), evidence, support screenshots
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('chat_images', 'chat_images', false, 409600, array['application/octet-stream']),
  ('report_evidence', 'report_evidence', false, 2097152, array['image/jpeg', 'image/png', 'image/webp', 'application/json']),
  ('support_attachments', 'support_attachments', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- chat_images/<uidA>_<uidB>/<file>.bin: the two connected people only;
-- sending also needs chat access (Fast-Track or trial).
drop policy if exists chat_images_read on storage.objects;
create policy chat_images_read on storage.objects for select to authenticated
  using (
    bucket_id = 'chat_images'
    and auth.uid()::text = any (string_to_array((storage.foldername(name))[1], '_'))
    and public.is_connected(
          (split_part((storage.foldername(name))[1], '_', 1))::uuid,
          (split_part((storage.foldername(name))[1], '_', 2))::uuid)
  );
drop policy if exists chat_images_write on storage.objects;
create policy chat_images_write on storage.objects for insert to authenticated
  with check (
    bucket_id = 'chat_images'
    and auth.uid()::text = any (string_to_array((storage.foldername(name))[1], '_'))
    and public.is_connected(
          (split_part((storage.foldername(name))[1], '_', 1))::uuid,
          (split_part((storage.foldername(name))[1], '_', 2))::uuid)
    and public.has_fast_track(auth.uid())
  );

-- report_evidence/<report id>/<file>: the reporter may upload to their own
-- report for one hour; nobody reads directly (staff get signed URLs).
create or replace function public.can_upload_evidence(p_folder text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.reports r
                  where r.id::text = p_folder and r.reporter_id = auth.uid()
                    and r.created_at > now() - interval '1 hour');
$$;
grant execute on function public.can_upload_evidence(text) to authenticated;

drop policy if exists report_evidence_write on storage.objects;
create policy report_evidence_write on storage.objects for insert to authenticated
  with check (bucket_id = 'report_evidence' and public.can_upload_evidence((storage.foldername(name))[1]));

-- support_attachments/<user id>/<file>: owner writes and reads own folder.
drop policy if exists support_attachments_write on storage.objects;
create policy support_attachments_write on storage.objects for insert to authenticated
  with check (bucket_id = 'support_attachments' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists support_attachments_read on storage.objects;
create policy support_attachments_read on storage.objects for select to authenticated
  using (bucket_id = 'support_attachments' and (storage.foldername(name))[1] = auth.uid()::text);

-- -----------------------------------------------------------------------------
-- 10. Privileges
-- -----------------------------------------------------------------------------
revoke all on function public.trial_identity_hash(uuid), public.trial_eligible(uuid),
  public.start_trial_if_eligible(uuid), public.service_trial_reminders(), public.service_expired_evidence(),
  public.service_forget_evidence(uuid[]), public.tg_profiles_prefs_set(), public.tg_swipes_restriction(),
  public.tg_reports_number(), public.new_ref(text), public.active_restriction(uuid),
  public.is_moderation_hidden(uuid), public.has_active_trial(uuid), public.has_fast_track(uuid)
  from public, anon, authenticated;
grant execute on function public.service_trial_reminders(), public.service_expired_evidence(),
  public.service_forget_evidence(uuid[]) to service_role;
-- Used inside RLS policies (like is_premium before it): returns only a boolean.
grant execute on function public.has_fast_track(uuid) to authenticated;
revoke all on function public.my_access_status(), public.mark_access_notice_seen(text),
  public.mark_notifications_read(), public.my_restriction(), public.submit_report_v2(uuid, text, text, text, jsonb, boolean),
  public.mod_list_reports_v2(text), public.mod_decide_report(uuid, text, text, text, int),
  public.mod_lift_restriction(uuid, text), public.mod_user_history(uuid),
  public.add_report_evidence(uuid, text, text, text), public.mod_evidence_path(uuid, text),
  public.mod_list_evidence(uuid), public.submit_support_ticket(text, text, text, text),
  public.my_support_email(), public.mod_list_tickets(text), public.mod_set_ticket_status(uuid, text, text),
  public.mod_ticket_attachment_path(uuid) from public, anon;
grant execute on function public.my_access_status(), public.mark_access_notice_seen(text),
  public.mark_notifications_read(), public.my_restriction(), public.submit_report_v2(uuid, text, text, text, jsonb, boolean),
  public.mod_list_reports_v2(text), public.mod_decide_report(uuid, text, text, text, int),
  public.mod_lift_restriction(uuid, text), public.mod_user_history(uuid),
  public.add_report_evidence(uuid, text, text, text), public.mod_evidence_path(uuid, text),
  public.mod_list_evidence(uuid), public.submit_support_ticket(text, text, text, text),
  public.my_support_email(), public.mod_list_tickets(text), public.mod_set_ticket_status(uuid, text, text),
  public.mod_ticket_attachment_path(uuid) to authenticated;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261115000000_trial_support_safety',
        'Discovery preferences in setup, 7-day trial, notifications, support tickets, moderation decisions and restrictions, evidence, chat photos',
        array['public.profiles', 'public.reports', 'public.user_trials', 'public.trial_claims', 'public.user_notifications',
              'public.user_restrictions', 'public.moderation_actions', 'public.report_evidence', 'public.support_tickets',
              'public.support_ticket_events', 'public.app_private_settings'],
        array['profiles.prefs_set_at', 'reports.report_no', 'reports.content_ref', 'reports.decision',
              'reports.decided_by', 'reports.decided_at'])
on conflict (migration_id) do nothing;
