-- =============================================================================
-- Compliance & trust
--   * Open profiles: every signed-in user (not blocked) sees the full
--     profile, gallery and interests. Contact details never: the DB rejects
--     phone numbers, @handles and links in names, bios and interests, and
--     location is district-level only.
--   * Consent records (terms, privacy, community guidelines, 18+).
--   * Date of birth: private, locked once set, age computed server-side,
--     18+ enforced.
--   * Selfie verification with staff review; selfies purged 30 days after
--     review.
--   * "Appears under 18" reports hide a profile from discovery until a
--     moderator reviews it.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Open profiles, no contact details, no exact location
-- -----------------------------------------------------------------------------
-- Contact-info guard, extended with "my insta is …"-style phrases (an
-- explicit separator is required so "I love Instagram photography" passes).
-- Mirrors ContactSanitizer in the app.
create or replace function public.contains_contact_info(p_text text)
returns boolean
language sql
immutable
as $$
  select coalesce(p_text, '') ~* (
       '(\+?\d[\d\s\-().]{7,}\d)'
    || '|(^|[^[:alnum:]_])@[a-z0-9_.]{2,}'
    || '|((https?://|www\.)\S+)'
    || '|([a-z0-9-]+\.(com|in|net|org|io|me|co|app|link|ly|gg|xyz)(/\S*)?([^[:alnum:]]|$))'
    || '|(\y(insta(gram)?|snap(chat)?|whats ?app|telegram|ig)\y\s*(id|handle|is|:|-)\s*:?\s*[a-z0-9_.]{3,})'
  );
$$;

drop policy if exists profile_private_select on public.profile_private;
create policy profile_private_select on public.profile_private
  for select to authenticated
  using (id = auth.uid() or not public.is_blocked(auth.uid(), id));

alter table public.profiles drop constraint if exists profiles_name_clean;
alter table public.profiles add constraint profiles_name_clean check (not public.contains_contact_info(full_name));
-- District / city names only: letters, spaces, dots and hyphens (no street
-- addresses, pin codes or coordinates).
alter table public.profiles drop constraint if exists profiles_city_district;
alter table public.profiles add constraint profiles_city_district check (city ~ '^[A-Za-z][A-Za-z .-]{1,39}$');
alter table public.profile_private drop constraint if exists profile_private_interests_clean;
alter table public.profile_private add constraint profile_private_interests_clean
  check (not public.contains_contact_info(array_to_string(interests, ' ')));

-- Trust & moderation flags, written only by server functions.
alter table public.profiles add column if not exists is_verified boolean not null default false;
alter table public.profiles add column if not exists hidden_pending_review boolean not null default false;

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert to authenticated
  with check (id = auth.uid() and is_premium = false and avatar_urls = '{}'
              and is_verified = false and hidden_pending_review = false);

-- Age comes from the date of birth now; clients can't edit it.
revoke update on public.profiles from authenticated;
grant update (full_name, city, bio) on public.profiles to authenticated;

-- Media: gallery photos are visible to every signed-in user who isn't
-- blocked; verification selfies only to their owner (staff view them
-- through the audited media-function path).
alter table public.media_objects drop constraint if exists media_objects_kind_check;
alter table public.media_objects add constraint media_objects_kind_check check (kind in ('primary', 'gallery', 'selfie'));

create or replace function public.can_view_media(p_viewer uuid, p_media uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.media_objects m
     where m.id = p_media and m.status <> 'deleted'
       and not public.is_blocked(p_viewer, m.owner_id)
       and (
         m.owner_id = p_viewer
         or (m.status = 'approved' and m.kind in ('primary', 'gallery'))
       ));
$$;

create or replace function public.mod_pending_media()
returns table (id uuid, owner_id uuid, kind text, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return query select m.id, m.owner_id, m.kind, m.created_at from public.media_objects m
                where m.status = 'pending' and m.kind <> 'selfie' order by m.created_at limit 100;
end $$;

-- -----------------------------------------------------------------------------
-- 2. Consent records
-- -----------------------------------------------------------------------------
create table if not exists public.user_consents (
  id             bigint generated always as identity primary key,
  user_id        uuid not null references auth.users (id) on delete cascade,
  policy_type    text not null check (policy_type in ('terms', 'privacy', 'community_guidelines', 'age_18_plus')),
  policy_version text not null check (policy_version ~ '^\d{4}-\d{2}-\d{2}$'),
  accepted_at    timestamptz not null default now(),
  unique (user_id, policy_type, policy_version)
);
alter table public.user_consents enable row level security;
drop policy if exists user_consents_own on public.user_consents;
create policy user_consents_own on public.user_consents for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on public.user_consents from authenticated, anon;

-- Records acceptance of all current policies (and the 18+ declaration).
create or replace function public.record_consent(p_version text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_version !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Invalid policy version' using errcode = '22023'; end if;
  insert into public.user_consents (user_id, policy_type, policy_version)
  select auth.uid(), t, p_version from unnest(array['terms', 'privacy', 'community_guidelines', 'age_18_plus']) t
  on conflict (user_id, policy_type, policy_version) do nothing;
end $$;

-- The oldest "latest accepted" version across the four policies; null if
-- any policy was never accepted. The app compares it with POLICY_VERSION.
create or replace function public.accepted_policy_version()
returns text language sql stable security definer set search_path = public as $$
  select case when count(distinct policy_type) < 4 then null else min(v) end
    from (select policy_type, max(policy_version) v from public.user_consents
           where user_id = auth.uid() group by policy_type) t;
$$;

-- -----------------------------------------------------------------------------
-- 3. Date of birth (private, locked, 18+)
-- -----------------------------------------------------------------------------
create table if not exists public.profile_dob (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  dob        date not null,
  created_at timestamptz not null default now()
);
alter table public.profile_dob enable row level security;
drop policy if exists profile_dob_own on public.profile_dob;
create policy profile_dob_own on public.profile_dob for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on public.profile_dob from authenticated, anon;

-- Locked once set — for everyone, including the service role. A genuine
-- correction requires a deliberate migration/ops procedure.
create or replace function public.tg_dob_locked() returns trigger language plpgsql as $$
begin
  raise exception 'Date of birth can''t be changed' using errcode = '42501', hint = 'DOB_LOCKED';
end $$;
drop trigger if exists profile_dob_locked on public.profile_dob;
create trigger profile_dob_locked before update on public.profile_dob
  for each row execute function public.tg_dob_locked();

create or replace function public.age_from_dob(p_dob date)
returns int language sql stable as $$
  select extract(year from age(current_date, p_dob))::int;
$$;

create or replace function public.set_dob(p_dob date)
returns int language plpgsql security definer set search_path = public as $$
declare v_age int;
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if exists (select 1 from public.profile_dob where user_id = auth.uid()) then
    raise exception 'Date of birth can''t be changed' using errcode = '42501', hint = 'DOB_LOCKED';
  end if;
  v_age := public.age_from_dob(p_dob);
  if p_dob > current_date or v_age > 100 then
    raise exception 'Enter a valid date of birth' using errcode = '22023';
  end if;
  if v_age < 18 then
    perform public.log_security_event('underage_dob_rejected', 'warning', '{}');
    raise exception 'Finder is only for people aged 18 and over' using errcode = 'P0001', hint = 'UNDER_18';
  end if;
  insert into public.profile_dob (user_id, dob) values (auth.uid(), p_dob);
  -- Existing profiles switch to the server-computed age.
  update public.profiles set age = v_age where id = auth.uid();
  return v_age;
end $$;

create or replace function public.has_dob()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profile_dob where user_id = auth.uid());
$$;

-- New profiles need a DOB first; their age is always computed from it.
create or replace function public.tg_profiles_age() returns trigger language plpgsql security definer set search_path = public as $$
declare v_dob date;
begin
  select dob into v_dob from public.profile_dob where user_id = new.id;
  if v_dob is null then
    raise exception 'Add your date of birth first' using errcode = 'P0001', hint = 'DOB_REQUIRED';
  end if;
  new.age := public.age_from_dob(v_dob);
  return new;
end $$;
drop trigger if exists profiles_age_from_dob on public.profiles;
create trigger profiles_age_from_dob before insert on public.profiles
  for each row execute function public.tg_profiles_age();

-- -----------------------------------------------------------------------------
-- 4. "Appears under 18" reports hide the profile until reviewed
-- -----------------------------------------------------------------------------
create or replace function public.submit_report(p_reported uuid, p_reason text, p_details text, p_evidence jsonb, p_block boolean default true)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform public.enforce_rate_limit('report', 10, interval '1 day');
  if p_evidence is not null and (jsonb_typeof(p_evidence) <> 'array' or jsonb_array_length(p_evidence) > 20
                                 or octet_length(p_evidence::text) > 200000) then
    raise exception 'Evidence too large' using errcode = '22023';
  end if;
  insert into public.reports (reporter_id, reported_id, reason, details, evidence, evidence_consent_at)
  values (auth.uid(), p_reported, p_reason, p_details, p_evidence, case when p_evidence is null then null else now() end)
  returning id into v_id;
  if p_reason = 'underage' then
    update public.profiles set hidden_pending_review = true where id = p_reported;
    perform public.log_security_event('underage_report', 'critical', jsonb_build_object('report', v_id, 'reported', p_reported));
  end if;
  if p_block then perform public.block_user(p_reported); end if;
  return v_id;
end $$;

create or replace function public.mod_resolve_report(p_report uuid, p_status text, p_resolution text)
returns void language plpgsql security definer set search_path = public as $$
declare r public.reports;
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  if p_status not in ('actioned', 'dismissed') then raise exception 'Invalid status' using errcode = '22023'; end if;
  update public.reports set status = p_status, resolution = p_resolution, resolved_at = now(), resolved_by = auth.uid()
   where id = p_report returning * into r;
  -- Under-18 reports: dismissed -> visible again (unless another one is still
  -- open); actioned -> stays hidden (the moderator removes the account).
  if r.reason = 'underage' and p_status = 'dismissed' and not exists (
       select 1 from public.reports x where x.reported_id = r.reported_id and x.reason = 'underage'
          and x.status in ('open', 'reviewing')) then
    update public.profiles set hidden_pending_review = false where id = r.reported_id;
  end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason)
  values (auth.uid(), 'resolve_report:' || p_status, 'report', p_report::text, p_resolution);
end $$;

-- Feed: hide profiles pending an under-18 review; return verification and
-- photo count.
drop function if exists public.get_feed(int);
create function public.get_feed(p_limit int default 20)
returns table (id uuid, full_name text, age smallint, city text, bio text, primary_photo text,
               is_premium boolean, is_verified boolean, photo_count int)
language sql stable security definer set search_path = public as $$
  with me as (select p.id, lower(p.city) as city from public.profiles p where p.id = auth.uid())
  select p.id, p.full_name, p.age, p.city, p.bio, p.avatar_urls[1], public.is_premium(p.id), p.is_verified,
         1 + coalesce((select cardinality(pp.gallery_urls) from public.profile_private pp where pp.id = p.id), 0)
    from public.profiles p, me
   where p.id <> me.id
     and not p.hidden_pending_review
     and not public.is_blocked(me.id, p.id)
     and cardinality(p.avatar_urls) > 0
     and not exists (
       select 1 from public.swipes_and_requests s
        where s.sender_id = me.id and s.receiver_id = p.id
          and not (s.action = 'pass' and s.created_at < now() - interval '7 days'))
     and not exists (
       select 1 from public.swipes_and_requests s
        where s.sender_id = p.id and s.receiver_id = me.id and s.action in ('accepted', 'rejected'))
   order by
     (public.is_premium(p.id) and lower(p.city) = me.city) desc,
     (lower(p.city) = me.city) desc,
     exists (select 1 from public.swipes_and_requests s
              where s.sender_id = p.id and s.receiver_id = me.id and s.action = 'follow_requested') desc,
     p.created_at desc
   limit least(greatest(p_limit, 1), 50);
$$;

-- -----------------------------------------------------------------------------
-- 5. Selfie verification
-- -----------------------------------------------------------------------------
create table if not exists public.verification_requests (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  media_id     uuid references public.media_objects (id) on delete set null,
  pose         text not null,
  status       text not null default 'awaiting_photo'
                 check (status in ('awaiting_photo', 'pending', 'approved', 'rejected', 'expired')),
  created_at   timestamptz not null default now(),
  submitted_at timestamptz,
  reviewed_by  uuid references auth.users (id),
  reviewed_at  timestamptz
);
create index if not exists verification_status_idx on public.verification_requests (status, submitted_at);
create index if not exists verification_user_idx on public.verification_requests (user_id, created_at desc);
alter table public.verification_requests enable row level security;
drop policy if exists verification_own on public.verification_requests;
create policy verification_own on public.verification_requests for select to authenticated using (user_id = auth.uid());
revoke all on public.verification_requests from authenticated, anon;
grant select (id, pose, status, created_at, submitted_at, reviewed_at) on public.verification_requests to authenticated;

-- Starts a verification with a server-chosen random pose (the client can't
-- pick an easy one or reuse an old photo: the selfie must arrive within
-- 15 minutes for this request).
create or replace function public.start_verification()
returns table (request_id uuid, pose text)
language plpgsql security definer set search_path = public as $$
declare
  v_poses text[] := array[
    'Touch your nose with your right index finger',
    'Give a thumbs up with your left hand',
    'Make a peace sign next to your right cheek',
    'Cover your left eye with your left hand',
    'Hold up three fingers next to your face',
    'Put your right hand on top of your head',
    'Touch your chin with two fingers',
    'Wave with your left hand, palm facing the camera'
  ];
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if exists (select 1 from public.profiles where id = auth.uid() and is_verified) then
    raise exception 'You''re already verified' using errcode = '22023';
  end if;
  if exists (select 1 from public.verification_requests where user_id = auth.uid() and status = 'pending') then
    raise exception 'Your verification is being reviewed' using errcode = 'P0001', hint = 'VERIFICATION_PENDING';
  end if;
  perform public.enforce_rate_limit('start_verification', 5, interval '1 day');
  update public.verification_requests set status = 'expired' where user_id = auth.uid() and status = 'awaiting_photo';
  request_id := gen_random_uuid();
  pose := v_poses[1 + floor(random() * array_length(v_poses, 1))::int];
  insert into public.verification_requests (id, user_id, pose) values (request_id, auth.uid(), pose);
  return next;
end $$;

-- Called by process-image (service role) after the selfie passed the upload
-- pipeline (validation, metadata strip, moderation, encryption).
create or replace function public.attach_verification_selfie(p_user uuid, p_request uuid, p_media uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.verification_requests
     set media_id = p_media, status = 'pending', submitted_at = now()
   where id = p_request and user_id = p_user and status = 'awaiting_photo'
     and created_at > now() - interval '15 minutes';
  if not found then raise exception 'Verification request expired. Start again.' using errcode = 'P0002'; end if;
end $$;

create or replace function public.my_verification_status()
returns text language sql stable security definer set search_path = public as $$
  select case
    when (select is_verified from public.profiles where id = auth.uid()) then 'approved'
    else coalesce((select status from public.verification_requests
                    where user_id = auth.uid() and status in ('pending', 'rejected')
                    order by created_at desc limit 1), 'none')
  end;
$$;

-- Staff review queue: selfie, pose and profile photo side by side.
create or replace function public.mod_verification_queue()
returns table (request_id uuid, user_id uuid, full_name text, pose text, selfie_media uuid, profile_media text, submitted_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then
    perform public.log_security_event('staff_access_denied', 'critical', '{"area":"verification_queue"}');
    raise exception 'Forbidden' using errcode = '42501';
  end if;
  return query
    select v.id, v.user_id, p.full_name, v.pose, v.media_id, p.avatar_urls[1], v.submitted_at
      from public.verification_requests v join public.profiles p on p.id = v.user_id
     where v.status = 'pending' and v.media_id is not null
     order by v.submitted_at limit 100;
end $$;

-- The only way is_verified changes.
create or replace function public.mod_review_verification(p_request uuid, p_approve boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v public.verification_requests;
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  update public.verification_requests
     set status = case when p_approve then 'approved' else 'rejected' end, reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_request and status = 'pending'
   returning * into v;
  if not found then raise exception 'Not pending' using errcode = 'P0002'; end if;
  if p_approve then update public.profiles set is_verified = true where id = v.user_id; end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id)
  values (auth.uid(), case when p_approve then 'approve_verification' else 'reject_verification' end, 'verification', p_request::text);
end $$;

-- -----------------------------------------------------------------------------
-- 6. Retention: + selfie purge 30 days after review, stale requests, ages
-- -----------------------------------------------------------------------------
create or replace function public.run_retention()
returns void language sql security definer set search_path = public as $$
  delete from public.rate_limits where window_start < now() - interval '1 day';
  delete from public.message_envelopes where created_at < now() - interval '30 days';
  update public.reports set evidence = null where resolved_at < now() - interval '90 days' and evidence is not null;
  delete from public.security_events where created_at < now() - interval '365 days';
  -- Verification selfies: unservable now, storage purged by media-maintenance.
  update public.media_objects set status = 'deleted'
   where kind = 'selfie' and status <> 'deleted'
     and id in (select media_id from public.verification_requests
                 where reviewed_at < now() - interval '30 days' and media_id is not null);
  update public.verification_requests set media_id = null
   where reviewed_at < now() - interval '30 days' and media_id is not null;
  update public.verification_requests set status = 'expired'
   where status = 'awaiting_photo' and created_at < now() - interval '1 day';
  -- Birthdays: keep the public age in step with the private DOB.
  update public.profiles p set age = public.age_from_dob(d.dob)
    from public.profile_dob d where d.user_id = p.id and p.age <> public.age_from_dob(d.dob);
$$;

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
revoke all on function public.record_consent(text), public.accepted_policy_version(), public.set_dob(date),
  public.has_dob(), public.start_verification(), public.my_verification_status(), public.mod_verification_queue(),
  public.mod_review_verification(uuid, boolean), public.attach_verification_selfie(uuid, uuid, uuid),
  public.get_feed(int), public.submit_report(uuid, text, text, jsonb, boolean),
  public.mod_resolve_report(uuid, text, text), public.run_retention(), public.can_view_media(uuid, uuid),
  public.mod_pending_media(), public.age_from_dob(date)
  from public, anon;
grant execute on function public.record_consent(text), public.accepted_policy_version(), public.set_dob(date),
  public.has_dob(), public.start_verification(), public.my_verification_status(), public.mod_verification_queue(),
  public.mod_review_verification(uuid, boolean), public.get_feed(int),
  public.submit_report(uuid, text, text, jsonb, boolean), public.mod_resolve_report(uuid, text, text),
  public.mod_pending_media(), public.age_from_dob(date)
  to authenticated;
revoke execute on function public.attach_verification_selfie(uuid, uuid, uuid), public.run_retention(),
  public.can_view_media(uuid, uuid) from authenticated;
grant execute on function public.attach_verification_selfie(uuid, uuid, uuid), public.run_retention(),
  public.can_view_media(uuid, uuid) to service_role;
