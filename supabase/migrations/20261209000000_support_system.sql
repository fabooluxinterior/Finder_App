-- migration-id: 20261209000000_support_system
-- description: Complete Help & Support. (1) Tickets get the full status set (new, open, assigned, in progress, waiting
--   for user, escalated, resolved, closed), a priority, an assignee, app/device details, the linked chatbot conversation,
--   a rating and reopen support; staff get internal notes and the actions to assign, escalate and change priority.
--   (2) A chatbot whose answers, keywords, quick replies, welcome and fallback messages are stored in the database and
--   edited by admins, so changes reach the app at once; its conversations are kept. (3) In-app notifications can no
--   longer be duplicated (dedupe_key). (4) Two more report categories (threats, privacy violation) and a priority
--   for serious reports. Nothing is deleted or rewritten; older app versions keep working.
-- tables: public.support_ticket_notes, public.support_bot_settings, public.support_bot_replies,
--   public.support_bot_conversations (new); public.support_tickets, public.user_notifications (columns added)
-- columns-added: support_tickets.priority/assigned_to/app_version/device_info/bot_conversation_id/rating/rating_comment/rated_at/
--   resolved_at/closed_at/reopened_count, user_notifications.dedupe_key
-- backward-compat: Additive. The status/category/reason checks are widened (every old value stays valid). Existing
--   functions keep their signatures; submit_support_ticket, reply_to_ticket and mod_set_ticket_status still work.
-- recovery: drop the new functions and tables; the added columns can stay unused; restore the old check lists if needed.
-- user-data: none changed
-- =============================================================================

-- ---------------------------------------------------------------- tickets ----
alter table public.support_tickets drop constraint if exists support_tickets_status_check;
alter table public.support_tickets add constraint support_tickets_status_check
  check (status in ('new', 'open', 'assigned', 'in_progress', 'waiting_for_user', 'escalated', 'resolved', 'closed'));
alter table public.support_tickets drop constraint if exists support_tickets_category_check;
alter table public.support_tickets add constraint support_tickets_category_check
  check (category in ('account', 'profile', 'discovery', 'chat', 'subscription', 'privacy', 'safety', 'technical', 'other'));

alter table public.support_tickets
  add column if not exists priority text not null default 'normal' check (priority in ('low', 'normal', 'high', 'urgent')),
  add column if not exists assigned_to uuid references auth.users (id) on delete set null,
  add column if not exists app_version text check (app_version is null or char_length(app_version) <= 40),
  add column if not exists device_info text check (device_info is null or char_length(device_info) <= 120),
  add column if not exists bot_conversation_id uuid,
  add column if not exists rating smallint check (rating is null or rating between 1 and 5),
  add column if not exists rating_comment text check (rating_comment is null or char_length(rating_comment) <= 500),
  add column if not exists rated_at timestamptz,
  add column if not exists resolved_at timestamptz,
  add column if not exists closed_at timestamptz,
  add column if not exists reopened_count int not null default 0;
create index if not exists support_tickets_status_idx on public.support_tickets (status, priority, updated_at desc);

create table if not exists public.support_ticket_notes (
  id         bigint generated always as identity primary key,
  ticket_id  uuid not null references public.support_tickets (id) on delete cascade,
  author_id  uuid not null references auth.users (id),
  body       text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
alter table public.support_ticket_notes enable row level security;
revoke all on public.support_ticket_notes from anon, authenticated;

-- ---------------------------------------------------------- notifications ----
alter table public.user_notifications add column if not exists dedupe_key text;
create unique index if not exists user_notifications_dedupe_idx on public.user_notifications (user_id, dedupe_key) where dedupe_key is not null;

-- ------------------------------------------------------------------ chatbot ----
create table if not exists public.support_bot_settings (
  id              boolean primary key default true check (id),
  enabled         boolean not null default true,
  welcome         text not null default 'Hi! Welcome to Vouby Support. How can we help you today?' check (char_length(welcome) <= 500),
  fallback        text not null default 'Sorry, I didn’t quite get that. Could you rephrase it, or raise a support ticket and our team will help?' check (char_length(fallback) <= 500),
  resolved_prompt text not null default 'Did that solve your issue?' check (char_length(resolved_prompt) <= 200),
  ticket_prompt   text not null default 'I’m sorry that didn’t help. You can raise a support ticket and our team will look into it.' check (char_length(ticket_prompt) <= 500),
  quick_replies   jsonb not null default '[]' check (jsonb_typeof(quick_replies) = 'array'),
  updated_at      timestamptz not null default now()
);
insert into public.support_bot_settings (id, quick_replies) values (true,
  '["Account & Login","Profile & Verification","Matches & Likes","Chat & Messages","Payments & Subscription","Safety & Reporting","Technical Issues"]')
on conflict (id) do nothing;
alter table public.support_bot_settings enable row level security;
revoke all on public.support_bot_settings from anon, authenticated;

create table if not exists public.support_bot_replies (
  id         uuid primary key default gen_random_uuid(),
  category   text not null check (category in ('account', 'profile', 'discovery', 'chat', 'subscription', 'safety', 'technical', 'other')),
  title      text not null check (char_length(btrim(title)) between 3 and 160),
  keywords   text[] not null default '{}',
  answer     text not null check (char_length(btrim(answer)) between 3 and 2000),
  active     boolean not null default true,
  sort       int not null default 0,
  updated_at timestamptz not null default now()
);
create index if not exists support_bot_replies_idx on public.support_bot_replies (category, sort) where active;
alter table public.support_bot_replies enable row level security;
revoke all on public.support_bot_replies from anon, authenticated;

create table if not exists public.support_bot_conversations (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  messages   jsonb not null default '[]' check (jsonb_typeof(messages) = 'array'),
  ticket_id  uuid,
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists support_bot_conversations_user_idx on public.support_bot_conversations (user_id, updated_at desc);
alter table public.support_bot_conversations enable row level security;
revoke all on public.support_bot_conversations from anon, authenticated;

-- Default answers (admins can change, add and remove them from the dashboard).
insert into public.support_bot_replies (category, title, keywords, answer, sort)
select * from (values
 ('account', 'How do I log in?', array['login','log in','sign in','otp','code','phone number','cant login','can''t login','not receiving'],
  'Vouby uses your mobile number. Enter your number and we send a 6-digit code by SMS. If the code doesn’t arrive, wait a minute and tap Resend, check the number, and make sure your phone has network. Codes expire after a few minutes.', 10),
 ('account', 'I forgot my password', array['password','forgot','reset password','pass word'],
  'Vouby has no password. You sign in with a code sent to your mobile number, so there is nothing to reset. Enter your number on the sign-in screen to get a new code.', 20),
 ('account', 'How do I delete my account?', array['delete account','delete my account','remove account','close account','deactivate'],
  'Go to You → Privacy & security → Delete account. This permanently deletes your profile, photos and messages and cannot be undone. If you only want a break, you can simply stop using the app, or ask us for help with a support ticket.', 30),
 ('account', 'My account is suspended or restricted', array['suspended','banned','restricted','blocked account','account locked','locked'],
  'If your account was limited after a report, the reason is shown in the app. Our team reviews every case. If you think it was a mistake, raise a support ticket and explain what happened; a person will review it.', 40),
 ('profile', 'How do I edit my profile?', array['edit profile','change photo','change bio','update profile','change name','profile photo','add photo'],
  'Open the You tab and tap your profile card to edit your photos, bio, interests and details. Changes save when you tap Save.', 10),
 ('profile', 'How does verification work?', array['verify','verification','verified','blue tick','tick','selfie'],
  'Open You → Get verified and take a live selfie copying the pose shown. Our team compares it with your profile photo, usually within a day. Your selfie is never shown on your profile and is deleted 30 days after review. Gallery photos are not accepted.', 20),
 ('profile', 'My verification was rejected', array['rejected','verification failed','not verified','selfie rejected'],
  'Make sure your face is clearly visible, in good light, and that your profile photo shows you. Then try again from You → Get verified. If it keeps failing, raise a support ticket.', 30),
 ('discovery', 'How do matches and requests work?', array['match','matches','request','follow','like','likes','accept','connect'],
  'Send a request from someone’s profile or Discover. When they accept, you are connected and chat opens. You can see who requested you in Requests. Sending and answering requests is part of Fast-Track (included during your free trial).', 10),
 ('discovery', 'Why am I not seeing many people?', array['no profiles','not seeing','few people','nobody','discovery','preferences','filter'],
  'Discover follows your Discovery preferences (who you want to see and the age range) and also who wants to see you. Widen the age range or choose Everyone in You → Discovery preferences. New people join every day.', 20),
 ('chat', 'Why can’t I send messages?', array['cannot send','can''t send','message not sending','unable to message','chat locked','messaging'],
  'You can message once a request is accepted, and messaging is part of Fast-Track (included in your free trial). If your plan or trial has ended, you can still read your chats but need Fast-Track to send. Check your connection too.', 10),
 ('chat', 'What do the ticks mean?', array['tick','ticks','read','delivered','seen','receipt'],
  'One grey tick: sent. Two grey ticks: delivered to their phone. Two blue ticks: read. Tap and hold one of your messages and choose Message info to see the exact times.', 20),
 ('chat', 'Can I edit, delete or schedule messages?', array['edit message','delete message','schedule','scheduled','disappearing','unsend'],
  'Yes. Tap and hold a message to edit it (text) or delete it for everyone. Hold the send button to schedule a message for later, and open the chat menu (⋮) for Scheduled messages and Disappearing messages.', 30),
 ('chat', 'How do I block or unblock someone?', array['block','unblock','blocked users','blocked'],
  'Open the chat or profile menu and choose Block. To unblock, go to You → People → Blocked users. Unblocking does not bring back an old connection; you would send a new request.', 40),
 ('subscription', 'What is Fast-Track and how much is it?', array['fast track','fast-track','premium','price','cost','plan','subscription','subscribe'],
  'Fast-Track lets you send and answer requests and chat. It is ₹79 a month. New accounts get a free 7-day trial, and nothing is charged automatically.', 10),
 ('subscription', 'My payment failed or was charged twice', array['payment','paid','charged','refund','double charge','deducted','failed payment','money'],
  'We’re sorry about that. Please raise a support ticket with the date, amount and how you paid. A person will check it with you. Refunds for Google Play purchases are also handled by Google Play.', 20),
 ('subscription', 'How do I cancel my subscription?', array['cancel','cancel subscription','stop subscription','unsubscribe'],
  'If you subscribed through Google Play, open Play Store → Payments & subscriptions → Subscriptions → Vouby and cancel there. You keep access until the period ends.', 30),
 ('safety', 'How do I report someone?', array['report','fake profile','fake','scam','fraud','harass','harassment','abuse','threat','impersonat','inappropriate','underage','under 18','privacy'],
  'Open their profile or chat menu and choose Report, then pick the reason (fake profile, harassment, scam, impersonation, inappropriate content, threats, underage or privacy). Your identity is never shown to them. A person reviews every report, and serious ones are looked at first.', 10),
 ('safety', 'Staying safe', array['safe','safety','unsafe','scammer','money','send money','bank','meet'],
  'Never send money, share OTPs or bank details, or click unknown links. Meet in public places and tell a friend. If something feels wrong, block and report the person.', 20),
 ('technical', 'The app is slow or not working', array['slow','crash','crashing','bug','not working','freeze','stuck','error','loading','update'],
  'Please update to the latest version, restart the app and check your internet connection. If photos or chats still don’t load, raise a support ticket and tell us what you see.', 10),
 ('technical', 'I’m not getting notifications', array['notification','notifications','alerts','push','not notified'],
  'Check that notifications are allowed for Vouby in your phone settings and that Popup notifications is on in You. Battery-saver modes can also block them.', 20),
 ('technical', 'Spotify won’t connect', array['spotify','music','connect spotify','artists'],
  'Tap Connect Spotify in your profile. If Spotify refuses access, you can instead pick your favourite artists and songs without logging in. Still stuck? Raise a support ticket.', 30)
) as v(category, title, keywords, answer, sort)
where not exists (select 1 from public.support_bot_replies);

-- ------------------------------------------------------------ chatbot RPCs ----
create or replace function public.support_bot_config()
returns jsonb language sql stable security definer set search_path = public as $$
  select to_jsonb(s) - 'id' from public.support_bot_settings s where auth.uid() is not null;
$$;

-- Questions and answers for the Help home (search + categories).
create or replace function public.support_faqs(p_category text default null, p_q text default null)
returns table (id uuid, category text, title text, answer text)
language sql stable security definer set search_path = public as $$
  select r.id, r.category, r.title, r.answer from public.support_bot_replies r
   where auth.uid() is not null and r.active
     and (p_category is null or r.category = p_category)
     and (nullif(btrim(coalesce(p_q, '')), '') is null
          or r.title ilike '%' || replace(replace(btrim(p_q), '%', ''), '_', '') || '%'
          or r.answer ilike '%' || replace(replace(btrim(p_q), '%', ''), '_', '') || '%'
          or exists (select 1 from unnest(r.keywords) k where lower(btrim(p_q)) like '%' || lower(k) || '%'))
   order by r.category, r.sort, r.title limit 60;
$$;

-- Best answer for what the person typed: keyword hits weigh most, then shared words with the question.
create or replace function public.support_bot_answer(p_text text, p_category text default null)
returns table (id uuid, category text, title text, answer text, score int, related jsonb)
language plpgsql stable security definer set search_path = public as $$
declare v_text text := lower(btrim(coalesce(p_text, '')));
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if char_length(v_text) < 2 then return; end if;
  return query
  with words as (select distinct w from regexp_split_to_table(regexp_replace(v_text, '[^a-z0-9 ]', ' ', 'g'), '\s+') w where char_length(w) >= 4),
  scored as (
    select r.id, r.category, r.title, r.answer,
           (select coalesce(sum(case when position(lower(k) in v_text) > 0 then (case when k like '% %' then 4 else 3 end) else 0 end), 0)
              from unnest(r.keywords) k)::int
           + (select count(*)::int from words w where position(w.w in lower(r.title)) > 0)
           + case when p_category is not null and r.category = p_category then 1 else 0 end as score
      from public.support_bot_replies r where r.active),
  ranked as (select s.*, row_number() over (order by s.score desc, s.title) rn from scored s where s.score >= 1)
  select top.id, top.category, top.title, top.answer, top.score,
         coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'title', o.title) order by o.rn)
                     from ranked o where o.rn between 2 and 4 and o.id <> top.id), '[]')
    from ranked top where top.rn = 1 and top.score >= 3;
end $$;

-- Conversations are kept so the person can come back to them, and staff can see them on a ticket.
create or replace function public.support_bot_save(p_session uuid, p_messages jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  perform public.enforce_rate_limit('support_bot_save', 300, interval '1 hour');
  if jsonb_typeof(p_messages) <> 'array' then raise exception 'Invalid conversation' using errcode = '22023'; end if;
  if jsonb_array_length(p_messages) > 200 then
    p_messages := (select coalesce(jsonb_agg(x), '[]') from (select x from jsonb_array_elements(p_messages) with ordinality t(x, n) order by n desc limit 200) q);
  end if;
  update public.support_bot_conversations set messages = p_messages, updated_at = now()
   where id = p_session and user_id = auth.uid() returning id into v_id;
  if v_id is null then
    insert into public.support_bot_conversations (user_id, messages) values (auth.uid(), p_messages) returning id into v_id;
  end if;
  return v_id;
end $$;

create or replace function public.support_bot_last()
returns table (id uuid, messages jsonb, ticket_id uuid, updated_at timestamptz)
language sql stable security definer set search_path = public as $$
  select c.id, c.messages, c.ticket_id, c.updated_at from public.support_bot_conversations c
   where c.user_id = auth.uid() and c.updated_at > now() - interval '24 hours' and c.ticket_id is null
   order by c.updated_at desc limit 1;
$$;

-- ------------------------------------------------------------- ticket RPCs ----
create or replace function public.submit_support_ticket_v2(
  p_category text, p_subject text, p_description text, p_priority text default 'normal',
  p_app_version text default null, p_device_info text default null, p_bot_conversation uuid default null)
returns table (id uuid, ticket_no text) language plpgsql security definer set search_path = public as $$
declare v_no text; v_id uuid; v_pri text := case when p_priority in ('low', 'normal', 'high', 'urgent') then p_priority else 'normal' end;
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  perform public.enforce_rate_limit('support_ticket', 8, interval '1 day');
  loop
    v_no := public.new_ref('VB');
    exit when not exists (select 1 from public.support_tickets t where t.ticket_no = v_no);
  end loop;
  -- Safety tickets are looked at first, whatever priority was chosen.
  if p_category = 'safety' and v_pri in ('low', 'normal') then v_pri := 'high'; end if;
  insert into public.support_tickets (ticket_no, user_id, email, category, subject, description, priority, app_version, device_info, bot_conversation_id)
  values (v_no, auth.uid(), (select to_jsonb(u) ->> 'email' from auth.users u where u.id = auth.uid()),
          p_category, btrim(p_subject), btrim(p_description), v_pri, left(p_app_version, 40), left(p_device_info, 120),
          (select c.id from public.support_bot_conversations c where c.id = p_bot_conversation and c.user_id = auth.uid()))
  returning support_tickets.id into v_id;
  update public.support_bot_conversations c set ticket_id = v_id where c.id = p_bot_conversation and c.user_id = auth.uid();
  insert into public.support_ticket_events (ticket_id, status, actor_id) values (v_id, 'new', auth.uid());
  insert into public.user_notifications (user_id, kind, title, body, dedupe_key)
  values (auth.uid(), 'ticket_created', 'Ticket ' || v_no || ' received', 'Thanks, we have your request. A person will reply here.', 'ticket:' || v_id || ':created')
  on conflict do nothing;
  return query select v_id, v_no;
end $$;

create or replace function public.reopen_ticket(p_ticket uuid)
returns void language plpgsql security definer set search_path = public as $$
declare t public.support_tickets;
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  select * into t from public.support_tickets where id = p_ticket and user_id = auth.uid();
  if t.id is null then raise exception 'Ticket not found' using errcode = 'P0002'; end if;
  if not (t.status = 'resolved' or (t.status = 'closed' and coalesce(t.closed_at, t.updated_at) > now() - interval '14 days')) then
    raise exception 'This ticket can’t be reopened. Please raise a new one.' using errcode = '22023';
  end if;
  update public.support_tickets set status = 'open', reopened_count = reopened_count + 1, updated_at = now(), resolved_at = null, closed_at = null where id = p_ticket;
  insert into public.support_ticket_events (ticket_id, status, note, actor_id) values (p_ticket, 'open', 'Reopened by the user', auth.uid());
end $$;

create or replace function public.rate_ticket(p_ticket uuid, p_rating int, p_comment text default null)
returns void language plpgsql security definer set search_path = public as $$
declare t public.support_tickets;
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'Rating must be 1 to 5' using errcode = '22023'; end if;
  select * into t from public.support_tickets where id = p_ticket and user_id = auth.uid();
  if t.id is null then raise exception 'Ticket not found' using errcode = 'P0002'; end if;
  if t.status not in ('resolved', 'closed') then raise exception 'You can rate once the ticket is resolved' using errcode = '22023'; end if;
  update public.support_tickets set rating = p_rating, rating_comment = left(nullif(btrim(coalesce(p_comment, '')), ''), 500), rated_at = now() where id = p_ticket;
end $$;

-- A person can only add to open conversations; a closed ticket has to be reopened first.
create or replace function public.reply_to_ticket(p_ticket uuid, p_body text)
returns void language plpgsql security definer set search_path = public as $$
declare t public.support_tickets; v_body text := btrim(coalesce(p_body, ''));
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  perform public.enforce_rate_limit('ticket_reply', 40, interval '1 day');
  if char_length(v_body) < 1 or char_length(v_body) > 2000 then raise exception 'Invalid message' using errcode = '22023'; end if;
  select * into t from public.support_tickets where id = p_ticket and user_id = auth.uid();
  if t.id is null then raise exception 'Ticket not found' using errcode = 'P0002'; end if;
  if t.status = 'closed' then raise exception 'This ticket is closed. Reopen it to add a message.' using errcode = '22023'; end if;
  insert into public.support_ticket_messages (ticket_id, from_staff, author_id, body) values (p_ticket, false, auth.uid(), v_body);
  if t.status in ('waiting_for_user', 'resolved') then
    update public.support_tickets set status = 'in_progress', updated_at = now() where id = p_ticket;
    insert into public.support_ticket_events (ticket_id, status, note, actor_id) values (p_ticket, 'in_progress', 'User replied', auth.uid());
  else
    update public.support_tickets set updated_at = now() where id = p_ticket;
  end if;
end $$;

-- ------------------------------------------------------------- staff RPCs ----
create or replace function public.mod_list_staff()
returns table (user_id uuid, email text, role text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return query select s.user_id, u.email::text, s.role from public.staff_roles s left join auth.users u on u.id = s.user_id order by s.role, u.email;
end $$;

create or replace function public.mod_ticket_counts()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return jsonb_build_object(
    'total', (select count(*) from public.support_tickets),
    'new', (select count(*) from public.support_tickets where status = 'new'),
    'open', (select count(*) from public.support_tickets where status in ('open', 'assigned')),
    'in_progress', (select count(*) from public.support_tickets where status = 'in_progress'),
    'waiting_for_user', (select count(*) from public.support_tickets where status = 'waiting_for_user'),
    'escalated', (select count(*) from public.support_tickets where status = 'escalated'),
    'resolved', (select count(*) from public.support_tickets where status = 'resolved'),
    'closed', (select count(*) from public.support_tickets where status = 'closed'));
end $$;

create or replace function public.mod_list_tickets_v3(
  p_status text default null, p_category text default null, p_priority text default null, p_q text default null, p_assigned uuid default null)
returns table (id uuid, ticket_no text, user_id uuid, user_name text, category text, subject text, status text, priority text,
               assigned_to uuid, assignee text, created_at timestamptz, updated_at timestamptz, messages bigint, rating smallint)
language plpgsql stable security definer set search_path = public as $$
declare v_q text := nullif(btrim(coalesce(p_q, '')), '');
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return query
  select t.id, t.ticket_no, t.user_id, p.full_name, t.category, t.subject, t.status, t.priority, t.assigned_to, a.email::text,
         t.created_at, t.updated_at, (select count(*) from public.support_ticket_messages m where m.ticket_id = t.id), t.rating
    from public.support_tickets t
    left join public.profiles p on p.id = t.user_id
    left join auth.users a on a.id = t.assigned_to
   where (p_status is null or p_status = 'all' or t.status = p_status
          or (p_status = 'open' and t.status in ('open', 'assigned'))
          or (p_status = 'active' and t.status not in ('resolved', 'closed')))
     and (p_category is null or p_category = 'all' or t.category = p_category)
     and (p_priority is null or p_priority = 'all' or t.priority = p_priority)
     and (p_assigned is null or t.assigned_to = p_assigned)
     and (v_q is null or t.ticket_no ilike '%' || replace(replace(v_q, '%', ''), '_', '') || '%'
          or p.full_name ilike '%' || replace(replace(v_q, '%', ''), '_', '') || '%' or t.user_id::text = v_q)
   order by case t.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end, t.updated_at desc
   limit 200;
end $$;

create or replace function public.mod_ticket_detail(p_ticket uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason)
  values (auth.uid(), 'view_ticket', 'support_ticket', p_ticket::text, 'dashboard');
  select jsonb_build_object(
    'ticket', to_jsonb(t) - 'attachment_path',
    'user', jsonb_build_object('id', t.user_id, 'name', p.full_name, 'email', t.email, 'city', p.city, 'joined', p.created_at,
                               'status', public.account_status(t.user_id)),
    'assignee', (select a.email::text from auth.users a where a.id = t.assigned_to),
    'thread', coalesce((select jsonb_agg(jsonb_build_object('from_staff', x.from_staff, 'body', x.body, 'at', x.at) order by x.at, x.n)
                          from (select 0 n, false from_staff, t.description body, t.created_at at
                                union all select m.id, m.from_staff, m.body, m.created_at from public.support_ticket_messages m where m.ticket_id = t.id) x), '[]'),
    'notes', coalesce((select jsonb_agg(jsonb_build_object('body', n.body, 'author', u.email::text, 'at', n.created_at) order by n.created_at)
                         from public.support_ticket_notes n left join auth.users u on u.id = n.author_id where n.ticket_id = t.id), '[]'),
    'history', coalesce((select jsonb_agg(jsonb_build_object('status', e.status, 'note', e.note, 'actor', u.email::text, 'at', e.created_at) order by e.created_at)
                           from public.support_ticket_events e left join auth.users u on u.id = e.actor_id where e.ticket_id = t.id), '[]'),
    'bot', (select c.messages from public.support_bot_conversations c where c.id = t.bot_conversation_id))
    into v
    from public.support_tickets t left join public.profiles p on p.id = t.user_id where t.id = p_ticket;
  if v is null then raise exception 'Ticket not found' using errcode = 'P0002'; end if;
  return v;
end $$;

create or replace function public.mod_add_ticket_note(p_ticket uuid, p_body text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_body, ''))) < 1 then raise exception 'Write a note first' using errcode = '22023'; end if;
  insert into public.support_ticket_notes (ticket_id, author_id, body) values (p_ticket, auth.uid(), btrim(p_body));
  update public.support_tickets set updated_at = now() where id = p_ticket;
end $$;

create or replace function public.mod_set_ticket_priority(p_ticket uuid, p_priority text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  if p_priority not in ('low', 'normal', 'high', 'urgent') then raise exception 'Invalid priority' using errcode = '22023'; end if;
  update public.support_tickets set priority = p_priority, updated_at = now() where id = p_ticket;
  insert into public.support_ticket_events (ticket_id, status, note, actor_id)
  select id, status, 'Priority: ' || p_priority, auth.uid() from public.support_tickets where id = p_ticket;
end $$;

create or replace function public.mod_assign_ticket(p_ticket uuid, p_admin uuid)
returns void language plpgsql security definer set search_path = public as $$
declare t public.support_tickets;
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  if p_admin is not null and not exists (select 1 from public.staff_roles where user_id = p_admin) then
    raise exception 'That person is not on the staff list' using errcode = '22023';
  end if;
  update public.support_tickets set assigned_to = p_admin, updated_at = now(),
         status = case when p_admin is not null and status in ('new', 'open') then 'assigned' else status end
   where id = p_ticket returning * into t;
  if t.id is null then raise exception 'Ticket not found' using errcode = 'P0002'; end if;
  insert into public.support_ticket_events (ticket_id, status, note, actor_id)
  values (p_ticket, t.status, case when p_admin is null then 'Unassigned' else 'Assigned' end, auth.uid());
end $$;

-- Status changes. The person is told about changes that matter to them, once per change.
create or replace function public.mod_set_ticket_status_v2(p_ticket uuid, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare t public.support_tickets; v_old text; v_event bigint;
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  if p_status not in ('new', 'open', 'assigned', 'in_progress', 'waiting_for_user', 'escalated', 'resolved', 'closed') then
    raise exception 'Invalid status' using errcode = '22023';
  end if;
  select status into v_old from public.support_tickets where id = p_ticket;
  if v_old is null then raise exception 'Ticket not found' using errcode = 'P0002'; end if;
  if v_old = p_status then return; end if;
  update public.support_tickets set status = p_status, updated_at = now(),
         resolved_at = case when p_status = 'resolved' then now() else resolved_at end,
         closed_at = case when p_status = 'closed' then now() else closed_at end,
         priority = case when p_status = 'escalated' and priority in ('low', 'normal') then 'high' else priority end
   where id = p_ticket returning * into t;
  insert into public.support_ticket_events (ticket_id, status, note, actor_id) values (p_ticket, p_status, p_note, auth.uid()) returning id into v_event;
  if t.user_id is not null and p_status in ('in_progress', 'waiting_for_user', 'resolved', 'closed') then
    insert into public.user_notifications (user_id, kind, title, body, dedupe_key)
    values (t.user_id, 'ticket_' || p_status,
            'Ticket ' || t.ticket_no || case p_status when 'in_progress' then ' is being looked at' when 'waiting_for_user' then ': we need more information'
                                                       when 'resolved' then ' was resolved' else ' was closed' end,
            coalesce(nullif(btrim(p_note), ''), case p_status when 'resolved' then 'You can reopen it or rate our support in My tickets.' else 'Open My tickets to see the details.' end),
            'ticket:' || p_ticket || ':event:' || v_event)
    on conflict do nothing;
  end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason)
  values (auth.uid(), 'ticket_status:' || p_status, 'support_ticket', p_ticket::text, left(p_note, 300));
end $$;

create or replace function public.mod_escalate_ticket(p_ticket uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.mod_set_ticket_status_v2(p_ticket, 'escalated', coalesce(nullif(btrim(p_note), ''), 'Escalated'));
end $$;

-- Replies now carry a dedupe key too (one notification per reply).
create or replace function public.mod_reply_ticket(p_ticket uuid, p_body text)
returns void language plpgsql security definer set search_path = public as $$
declare t public.support_tickets; v_body text := btrim(coalesce(p_body, '')); v_msg bigint;
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  if char_length(v_body) < 1 or char_length(v_body) > 2000 then raise exception 'Invalid message' using errcode = '22023'; end if;
  select * into t from public.support_tickets where id = p_ticket;
  if t.id is null then raise exception 'Ticket not found' using errcode = 'P0002'; end if;
  insert into public.support_ticket_messages (ticket_id, from_staff, author_id, body) values (p_ticket, true, auth.uid(), v_body) returning id into v_msg;
  update public.support_tickets set status = 'waiting_for_user', updated_at = now() where id = p_ticket and status not in ('resolved', 'closed');
  insert into public.support_ticket_events (ticket_id, status, note, actor_id) values (p_ticket, 'waiting_for_user', 'Team replied', auth.uid());
  if t.user_id is not null then
    insert into public.user_notifications (user_id, kind, title, body, dedupe_key)
    values (t.user_id, 'ticket_reply', 'Reply on ticket ' || t.ticket_no, left(v_body, 300), 'ticket:' || p_ticket || ':reply:' || v_msg)
    on conflict do nothing;
  end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason)
  values (auth.uid(), 'ticket_reply', 'support_ticket', p_ticket::text, null);
end $$;

-- ------------------------------------------------- admin: auto-reply management ----
create or replace function public.admin_bot_overview()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return jsonb_build_object(
    'settings', (select to_jsonb(s) - 'id' from public.support_bot_settings s),
    'replies', coalesce((select jsonb_agg(to_jsonb(r) order by r.category, r.sort, r.title) from public.support_bot_replies r), '[]'),
    'conversations', (select count(*) from public.support_bot_conversations));
end $$;

create or replace function public.admin_bot_set_settings(p_enabled boolean, p_welcome text, p_fallback text, p_resolved_prompt text, p_ticket_prompt text, p_quick_replies jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  if jsonb_typeof(p_quick_replies) <> 'array' or jsonb_array_length(p_quick_replies) > 12 then raise exception 'Invalid quick replies' using errcode = '22023'; end if;
  update public.support_bot_settings set enabled = p_enabled, welcome = btrim(p_welcome), fallback = btrim(p_fallback),
         resolved_prompt = btrim(p_resolved_prompt), ticket_prompt = btrim(p_ticket_prompt), quick_replies = p_quick_replies, updated_at = now()
   where id = true;
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason) values (auth.uid(), 'bot_settings', 'support_bot', 'settings', null);
end $$;

create or replace function public.admin_bot_upsert_reply(p_id uuid, p_category text, p_title text, p_keywords text[], p_answer text, p_active boolean, p_sort int)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  if cardinality(coalesce(p_keywords, '{}')) > 40 then raise exception 'Too many keywords' using errcode = '22023'; end if;
  if p_id is null then
    insert into public.support_bot_replies (category, title, keywords, answer, active, sort)
    values (p_category, btrim(p_title), coalesce(array(select lower(btrim(k)) from unnest(p_keywords) k where btrim(k) <> ''), '{}'), btrim(p_answer), coalesce(p_active, true), coalesce(p_sort, 0))
    returning id into v_id;
  else
    update public.support_bot_replies set category = p_category, title = btrim(p_title),
           keywords = coalesce(array(select lower(btrim(k)) from unnest(p_keywords) k where btrim(k) <> ''), '{}'),
           answer = btrim(p_answer), active = coalesce(p_active, true), sort = coalesce(p_sort, 0), updated_at = now()
     where id = p_id returning id into v_id;
    if v_id is null then raise exception 'Reply not found' using errcode = 'P0002'; end if;
  end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason) values (auth.uid(), 'bot_reply_saved', 'support_bot', v_id::text, left(p_title, 100));
  return v_id;
end $$;

create or replace function public.admin_bot_delete_reply(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  delete from public.support_bot_replies where id = p_id;
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason) values (auth.uid(), 'bot_reply_deleted', 'support_bot', p_id::text, null);
end $$;

create or replace function public.admin_bot_conversations(p_limit int default 30, p_offset int default 0)
returns table (id uuid, user_name text, ticket_no text, updated_at timestamptz, message_count int, messages jsonb)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff('admin') then raise exception 'Forbidden' using errcode = '42501'; end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason) values (auth.uid(), 'view_bot_conversations', 'support_bot', 'list', null);
  return query
  select c.id, p.full_name, t.ticket_no, c.updated_at, jsonb_array_length(c.messages), c.messages
    from public.support_bot_conversations c left join public.profiles p on p.id = c.user_id left join public.support_tickets t on t.id = c.ticket_id
   order by c.updated_at desc limit least(greatest(coalesce(p_limit, 30), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end $$;

-- ---------------------------------------------------- reports: categories + priority ----
alter table public.reports drop constraint if exists reports_reason_check;
alter table public.reports add constraint reports_reason_check
  check (reason in ('sexual_content', 'harassment', 'spam_or_scam', 'fake_profile', 'underage', 'malicious_link', 'other', 'abusive_messages',
                    'inappropriate_images', 'spam', 'scam', 'impersonation', 'suspicious_behaviour', 'threats', 'privacy_violation'));

-- Serious reports are reviewed first, by a person. Nothing here ever resolves a report.
create or replace function public.report_priority(p_reason text)
returns text language sql immutable as $$
  select case when p_reason in ('underage', 'threats') then 'urgent'
              when p_reason in ('harassment', 'abusive_messages', 'scam', 'spam_or_scam', 'impersonation', 'privacy_violation', 'sexual_content', 'inappropriate_images', 'malicious_link') then 'high'
              else 'normal' end;
$$;

revoke all on function public.support_bot_config(), public.support_faqs(text, text), public.support_bot_answer(text, text), public.support_bot_save(uuid, jsonb),
  public.support_bot_last(), public.submit_support_ticket_v2(text, text, text, text, text, text, uuid), public.reopen_ticket(uuid), public.rate_ticket(uuid, int, text),
  public.reply_to_ticket(uuid, text), public.mod_list_staff(), public.mod_ticket_counts(), public.mod_list_tickets_v3(text, text, text, text, uuid),
  public.mod_ticket_detail(uuid), public.mod_add_ticket_note(uuid, text), public.mod_set_ticket_priority(uuid, text), public.mod_assign_ticket(uuid, uuid),
  public.mod_set_ticket_status_v2(uuid, text, text), public.mod_escalate_ticket(uuid, text), public.mod_reply_ticket(uuid, text),
  public.admin_bot_overview(), public.admin_bot_set_settings(boolean, text, text, text, text, jsonb),
  public.admin_bot_upsert_reply(uuid, text, text, text[], text, boolean, int), public.admin_bot_delete_reply(uuid), public.admin_bot_conversations(int, int),
  public.report_priority(text) from public, anon;
grant execute on function public.support_bot_config(), public.support_faqs(text, text), public.support_bot_answer(text, text), public.support_bot_save(uuid, jsonb),
  public.support_bot_last(), public.submit_support_ticket_v2(text, text, text, text, text, text, uuid), public.reopen_ticket(uuid), public.rate_ticket(uuid, int, text),
  public.reply_to_ticket(uuid, text), public.mod_list_staff(), public.mod_ticket_counts(), public.mod_list_tickets_v3(text, text, text, text, uuid),
  public.mod_ticket_detail(uuid), public.mod_add_ticket_note(uuid, text), public.mod_set_ticket_priority(uuid, text), public.mod_assign_ticket(uuid, uuid),
  public.mod_set_ticket_status_v2(uuid, text, text), public.mod_escalate_ticket(uuid, text), public.mod_reply_ticket(uuid, text),
  public.admin_bot_overview(), public.admin_bot_set_settings(boolean, text, text, text, text, jsonb),
  public.admin_bot_upsert_reply(uuid, text, text, text[], text, boolean, int), public.admin_bot_delete_reply(uuid), public.admin_bot_conversations(int, int),
  public.report_priority(text) to authenticated;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261209000000_support_system', 'Help & Support: statuses, priority, assignment, notes, ratings, admin-managed chatbot, notification dedupe, report priority',
        array['public.support_tickets', 'public.support_ticket_notes', 'public.support_bot_settings', 'public.support_bot_replies', 'public.support_bot_conversations', 'public.user_notifications'],
        array['support_tickets.priority', 'support_tickets.assigned_to', 'user_notifications.dedupe_key'])
on conflict (migration_id) do nothing;
