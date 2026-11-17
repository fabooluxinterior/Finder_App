-- migration-id: 20261205000000_support_thread
-- description: Support requests become a real two-way conversation. Adds a message thread per ticket: the person's
--   messages and the team's replies. Staff can list tickets with the person's name, read the thread and reply from the
--   web dashboard; a reply moves the ticket to "waiting for you" and notifies the person. People can add follow-up
--   messages from the Help chat. Existing tickets, statuses and notifications are unchanged.
-- tables: public.support_ticket_messages (new)
-- columns-added: none
-- backward-compat: Additive. submit_support_ticket, mod_list_tickets and mod_set_ticket_status keep their signatures.
-- recovery: drop function public.my_ticket_thread(uuid), public.reply_to_ticket(uuid, text),
--   public.mod_list_tickets_v2(text), public.mod_ticket_thread(uuid), public.mod_reply_ticket(uuid, text);
--   drop table public.support_ticket_messages;
-- user-data: none changed
-- =============================================================================

create table if not exists public.support_ticket_messages (
  id         bigint generated always as identity primary key,
  ticket_id  uuid not null references public.support_tickets (id) on delete cascade,
  from_staff boolean not null default false,
  author_id  uuid,
  body       text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists support_ticket_messages_ticket_idx on public.support_ticket_messages (ticket_id, created_at);
alter table public.support_ticket_messages enable row level security;
revoke all on public.support_ticket_messages from anon, authenticated;

-- The person's view: the first message is what they wrote when opening the ticket.
create or replace function public.my_ticket_thread(p_ticket uuid)
returns table (id bigint, from_staff boolean, body text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if not exists (select 1 from public.support_tickets t where t.id = p_ticket and t.user_id = auth.uid()) then
    raise exception 'Ticket not found' using errcode = 'P0002';
  end if;
  return query
  select 0::bigint, false, t.description, t.created_at from public.support_tickets t where t.id = p_ticket
  union all
  select m.id, m.from_staff, m.body, m.created_at from public.support_ticket_messages m where m.ticket_id = p_ticket
  order by 4, 1;
end $$;

create or replace function public.reply_to_ticket(p_ticket uuid, p_body text)
returns void language plpgsql security definer set search_path = public as $$
declare t public.support_tickets; v_body text := btrim(coalesce(p_body, ''));
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  perform public.enforce_rate_limit('ticket_reply', 40, interval '1 day');
  if char_length(v_body) < 1 or char_length(v_body) > 2000 then raise exception 'Invalid message' using errcode = '22023'; end if;
  select * into t from public.support_tickets where id = p_ticket and user_id = auth.uid();
  if t.id is null then raise exception 'Ticket not found' using errcode = 'P0002'; end if;
  insert into public.support_ticket_messages (ticket_id, from_staff, author_id, body) values (p_ticket, false, auth.uid(), v_body);
  -- A new message from the person puts the ticket back in the team's queue.
  if t.status in ('waiting_for_user', 'resolved', 'closed') then
    update public.support_tickets set status = 'in_progress', updated_at = now() where id = p_ticket;
    insert into public.support_ticket_events (ticket_id, status, note, actor_id) values (p_ticket, 'in_progress', 'User replied', auth.uid());
  else
    update public.support_tickets set updated_at = now() where id = p_ticket;
  end if;
end $$;

-- Staff: tickets with the person's name and the size of the conversation.
create or replace function public.mod_list_tickets_v2(p_status text default 'open')
returns table (id uuid, ticket_no text, user_id uuid, user_name text, email text, category text, subject text,
               description text, status text, created_at timestamptz, updated_at timestamptz, has_attachment boolean,
               messages bigint, last_from_staff boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  return query
  select t.id, t.ticket_no, t.user_id, p.full_name, t.email, t.category, t.subject, t.description, t.status,
         t.created_at, t.updated_at, t.attachment_path is not null,
         (select count(*) from public.support_ticket_messages m where m.ticket_id = t.id),
         coalesce((select m.from_staff from public.support_ticket_messages m where m.ticket_id = t.id order by m.created_at desc, m.id desc limit 1), false)
    from public.support_tickets t left join public.profiles p on p.id = t.user_id
   where p_status = 'all' or t.status = p_status
      or (p_status = 'open' and t.status in ('new', 'in_progress', 'waiting_for_user'))
   order by t.updated_at desc limit 200;
end $$;

create or replace function public.mod_ticket_thread(p_ticket uuid)
returns table (id bigint, from_staff boolean, body text, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason)
  values (auth.uid(), 'view_ticket', 'support_ticket', p_ticket::text, 'dashboard');
  return query
  select 0::bigint, false, t.description, t.created_at from public.support_tickets t where t.id = p_ticket
  union all
  select m.id, m.from_staff, m.body, m.created_at from public.support_ticket_messages m where m.ticket_id = p_ticket
  order by 4, 1;
end $$;

create or replace function public.mod_reply_ticket(p_ticket uuid, p_body text)
returns void language plpgsql security definer set search_path = public as $$
declare t public.support_tickets; v_body text := btrim(coalesce(p_body, ''));
begin
  if not public.is_staff('moderator') then raise exception 'Forbidden' using errcode = '42501'; end if;
  if char_length(v_body) < 1 or char_length(v_body) > 2000 then raise exception 'Invalid message' using errcode = '22023'; end if;
  select * into t from public.support_tickets where id = p_ticket;
  if t.id is null then raise exception 'Ticket not found' using errcode = 'P0002'; end if;
  insert into public.support_ticket_messages (ticket_id, from_staff, author_id, body) values (p_ticket, true, auth.uid(), v_body);
  update public.support_tickets set status = 'waiting_for_user', updated_at = now() where id = p_ticket;
  insert into public.support_ticket_events (ticket_id, status, note, actor_id) values (p_ticket, 'waiting_for_user', 'Team replied', auth.uid());
  if t.user_id is not null then
    insert into public.user_notifications (user_id, kind, title, body)
    values (t.user_id, 'ticket_reply', 'Reply on ticket ' || t.ticket_no, left(v_body, 300));
  end if;
  insert into public.access_audit_log (actor_id, action, target_type, target_id, reason)
  values (auth.uid(), 'ticket_reply', 'support_ticket', p_ticket::text, null);
end $$;

revoke all on function public.my_ticket_thread(uuid), public.reply_to_ticket(uuid, text), public.mod_list_tickets_v2(text),
  public.mod_ticket_thread(uuid), public.mod_reply_ticket(uuid, text) from public, anon;
grant execute on function public.my_ticket_thread(uuid), public.reply_to_ticket(uuid, text), public.mod_list_tickets_v2(text),
  public.mod_ticket_thread(uuid), public.mod_reply_ticket(uuid, text) to authenticated;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261205000000_support_thread', 'Support tickets as a two-way conversation (user follow-ups, staff replies)',
        array['public.support_ticket_messages'], array[]::text[])
on conflict (migration_id) do nothing;
