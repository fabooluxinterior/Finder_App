-- migration-id: 20261120000000_pass_then_request_fix
-- description: swipe_profile() silently dropped a request when the sender had already passed on that person
--   in the last 7 days (the pass row occupies the unique (sender, receiver) pair, and the insert used
--   "on conflict do nothing") while still answering 'requested', so the app said "sent" and nothing was saved.
--   Now a request replaces the sender's own earlier pass (changing their mind), and when a request or an
--   answer already exists the true state is returned instead of a false 'requested'.
-- tables: none (function replaced)
-- columns-added: none
-- backward-compat: Same signature and return values ('passed' | 'requested' | 'matched'); older app
--   versions keep working and now actually save the request. Only the sender's OWN pass on that one
--   person is replaced; no one else's rows are touched.
-- recovery: Re-create the previous body from 20261109000000_subscription_model.sql if ever needed.
-- user-data: none
-- =============================================================================

create or replace function public.swipe_profile(p_target uuid, p_action public.swipe_action)
returns text language plpgsql security definer set search_path = public as $$
declare v_me uuid := auth.uid(); v_reverse public.swipes_and_requests; v_existing public.swipe_action; v_new uuid;
begin
  if v_me is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if p_action not in ('pass', 'follow_requested') then
    raise exception 'Invalid swipe action' using errcode = '22023';
  end if;

  if p_action = 'pass' then
    -- A pass older than 7 days expires, so it can be made again.
    delete from public.swipes_and_requests
     where sender_id = v_me and receiver_id = p_target
       and action = 'pass' and created_at < now() - interval '7 days';
    insert into public.swipes_and_requests (sender_id, receiver_id, action)
    values (v_me, p_target, 'pass') on conflict (sender_id, receiver_id) do nothing;
    return 'passed';
  end if;

  -- Sending a request: changing your mind about your own earlier pass is allowed.
  delete from public.swipes_and_requests
   where sender_id = v_me and receiver_id = p_target and action = 'pass';

  -- They already asked me: that is a match.
  select * into v_reverse from public.swipes_and_requests
   where sender_id = p_target and receiver_id = v_me and action = 'follow_requested' for update;
  if found then
    update public.swipes_and_requests set action = 'accepted', responded_at = now() where id = v_reverse.id;
    return 'matched';
  end if;

  insert into public.swipes_and_requests (sender_id, receiver_id, action)
  values (v_me, p_target, 'follow_requested')
  on conflict (sender_id, receiver_id) do nothing
  returning id into v_new;
  if v_new is not null then return 'requested'; end if;

  -- Something already exists for this pair: report what is true.
  select action into v_existing from public.swipes_and_requests where sender_id = v_me and receiver_id = p_target;
  return case v_existing when 'follow_requested' then 'requested' when 'accepted' then 'matched' else 'passed' end;
end $$;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261120000000_pass_then_request_fix',
        'A request now replaces the sender''s own earlier pass; swipe_profile reports the true state instead of a false requested',
        array['public.swipes_and_requests'], array[]::text[])
on conflict (migration_id) do nothing;
