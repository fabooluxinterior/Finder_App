-- migration-id: 20261126000000_activity_notifications
-- description: Phone notifications that say what happened: a new request, a new connection, daily suggestions,
--   moderation notices, ticket updates and trial reminders (everything written to user_notifications is now also
--   pushed to the user's phones, except dashboard announcements, which are pushed by the dashboard itself).
--   Also schedules the daily jobs (trial reminders and the suggestion nudge) when pg_cron is available.
-- tables: none (triggers and functions added; user_notifications receives new rows only)
-- columns-added: none
-- backward-compat: Additive. No existing function, table or policy changes; older app versions show the new rows in
--   their notification list. Requests from people a user cannot see (free plan) never reveal the sender's name.
-- recovery: drop trigger swipes_notify on public.swipes_and_requests; drop trigger notifications_push on
--   public.user_notifications; drop functions notify_request_activity, notify_push_for_notification,
--   push_webhook_call, service_suggestion_nudges; select cron.unschedule('vouby-suggestion-nudge'),
--   cron.unschedule('vouby-trial-reminders') if scheduled.
-- user-data: none. Blocked people are never told they were blocked.
-- =============================================================================

-- One guarded place that calls the push-message function (best effort: never blocks the caller).
create or replace function public.push_webhook_call(p_body jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_url text; v_secret text;
begin
  begin
    if to_regproc('net.http_post') is null then return; end if;
    select value into v_url from public.app_private_settings where key = 'push_webhook_url';
    select value into v_secret from public.app_private_settings where key = 'push_webhook_secret';
    if coalesce(v_url, '') = '' or coalesce(v_secret, '') = '' then return; end if;
    perform net.http_post(url := v_url, body := p_body,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
      timeout_milliseconds := 5000);
  exception when others then null;
  end;
end $$;
revoke all on function public.push_webhook_call(jsonb) from public, anon, authenticated;

-- Everything in the in-app notification list is also pushed, except dashboard announcements (pushed by push-send).
create or replace function public.notify_push_for_notification()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.kind <> 'announcement' then
    perform public.push_webhook_call(jsonb_build_object('notification_id', new.id));
  end if;
  return new;
end $$;
revoke all on function public.notify_push_for_notification() from public, anon, authenticated;

drop trigger if exists notifications_push on public.user_notifications;
create trigger notifications_push after insert on public.user_notifications
  for each row execute function public.notify_push_for_notification();

-- Requests and connections.
create or replace function public.notify_request_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_name text;
begin
  begin
    if tg_op = 'INSERT' and new.action = 'follow_requested' then
      if public.is_blocked(new.sender_id, new.receiver_id) then return new; end if;
      select nullif(split_part(full_name, ' ', 1), '') into v_name from public.profiles where id = new.sender_id;
      if public.has_fast_track(new.receiver_id) then
        insert into public.user_notifications (user_id, kind, title, body)
        values (new.receiver_id, 'request', coalesce(v_name, 'Someone') || ' sent you a request',
                'Open Requests to accept or decline.');
      else
        -- Free plan: the server never reveals who asked.
        insert into public.user_notifications (user_id, kind, title, body)
        values (new.receiver_id, 'request', 'You have a new request',
                'Someone sent you a request. Fast-Track shows you who.');
      end if;
    elsif tg_op = 'UPDATE' and old.action = 'follow_requested' and new.action = 'accepted' then
      select nullif(split_part(full_name, ' ', 1), '') into v_name from public.profiles where id = new.receiver_id;
      insert into public.user_notifications (user_id, kind, title, body)
      values (new.sender_id, 'match', 'You''re connected with ' || coalesce(v_name, 'a new person'),
              'Say hello: your chat is open.');
    end if;
  exception when others then
    null; -- a notice must never make a request fail
  end;
  return new;
end $$;
revoke all on function public.notify_request_activity() from public, anon, authenticated;

drop trigger if exists swipes_notify on public.swipes_and_requests;
create trigger swipes_notify after insert or update on public.swipes_and_requests
  for each row execute function public.notify_request_activity();

-- Once a day: people who haven't opened Suggestions today hear that new ones are ready.
create or replace function public.service_suggestion_nudges()
returns int language plpgsql security definer set search_path = public as $$
declare v int;
begin
  insert into public.user_notifications (user_id, kind, title, body)
  select p.id, 'suggestions', 'New people to meet', 'Fresh suggestions are ready for you today.'
    from public.profiles p
   where p.is_onboarded and cardinality(p.photo_urls) >= 4 and not p.hidden_pending_review
     and not exists (select 1 from public.recommendation_daily d where d.user_id = p.id and d.day = current_date)
     and not exists (select 1 from public.user_notifications n
                      where n.user_id = p.id and n.kind = 'suggestions' and n.created_at > now() - interval '20 hours');
  get diagnostics v = row_count;
  return v;
end $$;
revoke all on function public.service_suggestion_nudges() from public, anon, authenticated;
grant execute on function public.service_suggestion_nudges() to service_role;

-- Daily jobs (18:00 India time for the suggestion nudge; trial reminders hourly).
do $$ begin
  create extension if not exists pg_cron with schema pg_catalog;
  perform cron.schedule('vouby-suggestion-nudge', '30 12 * * *', 'select public.service_suggestion_nudges()');
  perform cron.schedule('vouby-trial-reminders', '7 * * * *', 'select public.service_trial_reminders()');
exception when others then
  raise notice 'pg_cron is not available here (%); schedule service_suggestion_nudges() and service_trial_reminders() elsewhere', sqlerrm;
end $$;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261126000000_activity_notifications',
        'Push for requests, connections, suggestions, moderation and ticket notices; daily jobs',
        array['public.user_notifications', 'public.swipes_and_requests'], array[]::text[])
on conflict (migration_id) do nothing;
