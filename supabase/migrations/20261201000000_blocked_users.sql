-- migration-id: 20261201000000_blocked_users
-- description: A "Blocked users" area. Lists the people you blocked and lets you unblock them. Unblocking only
--   removes the block row. The old connection and chat stay gone (blocking already ended them), so two people who
--   unblock each other start again with a new request.
-- tables: none (two functions added over public.blocks)
-- columns-added: none
-- backward-compat: Additive. block_user(), unmatch() and every table are unchanged; older app versions keep working.
-- recovery: drop function public.my_blocked_users(); drop function public.unblock_user(uuid);
-- user-data: none changed
-- =============================================================================

create or replace function public.my_blocked_users()
returns table (user_id uuid, full_name text, city text, blocked_at timestamptz)
language sql stable security definer set search_path = public as $$
  select b.blocked_id, p.full_name, p.city, b.created_at
    from public.blocks b join public.profiles p on p.id = b.blocked_id
   where b.blocker_id = auth.uid()
   order by b.created_at desc;
$$;
revoke all on function public.my_blocked_users() from public, anon;
grant execute on function public.my_blocked_users() to authenticated;

create or replace function public.unblock_user(p_peer uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  perform public.enforce_rate_limit('unblock_user', 30, interval '1 hour');
  delete from public.blocks where blocker_id = auth.uid() and blocked_id = p_peer;
  perform public.log_security_event('unblock', 'info', jsonb_build_object('target', p_peer));
end $$;
revoke all on function public.unblock_user(uuid) from public, anon;
grant execute on function public.unblock_user(uuid) to authenticated;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261201000000_blocked_users',
        'Blocked users list and unblock (the old connection is not restored)',
        array['public.blocks'], array[]::text[])
on conflict (migration_id) do nothing;
