-- migration-id: 20261124000000_message_push_trigger
-- description: Notification-bar alerts for new chat messages when the app is closed. After a message row is
--   stored, the database asks the push-message edge function (via pg_net) to notify the receiver's phones.
--   Messages are end-to-end encrypted, so the notification only says who wrote. It does nothing until the
--   private settings push_webhook_url and push_webhook_secret exist, and a failure here can never block a send.
-- tables: none (one trigger and its function added; uses public.app_private_settings)
-- columns-added: none
-- backward-compat: Additive. send_message() and all tables are unchanged; older app versions work as before.
-- recovery: drop trigger messages_push_notify on public.messages; drop function public.notify_new_message();
-- user-data: none
-- =============================================================================

do $$ begin
  create extension if not exists pg_net with schema extensions;
exception when others then
  raise notice 'pg_net is not available here; message push stays off (%)', sqlerrm;
end $$;

create or replace function public.notify_new_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_url text; v_secret text;
begin
  begin
    if to_regproc('net.http_post') is null then return new; end if;
    select value into v_url from public.app_private_settings where key = 'push_webhook_url';
    select value into v_secret from public.app_private_settings where key = 'push_webhook_secret';
    if coalesce(v_url, '') = '' or coalesce(v_secret, '') = '' then return new; end if;
    perform net.http_post(
      url := v_url,
      body := jsonb_build_object('message_id', new.id),
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
      timeout_milliseconds := 5000);
  exception when others then
    null; -- notifying is best effort: sending a message must never fail because of it
  end;
  return new;
end $$;
revoke all on function public.notify_new_message() from public, anon, authenticated;

drop trigger if exists messages_push_notify on public.messages;
create trigger messages_push_notify after insert on public.messages
  for each row execute function public.notify_new_message();

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261124000000_message_push_trigger',
        'Trigger asks the push-message function to notify the receiver''s phones about a new chat message (no content)',
        array['public.messages'], array[]::text[])
on conflict (migration_id) do nothing;
