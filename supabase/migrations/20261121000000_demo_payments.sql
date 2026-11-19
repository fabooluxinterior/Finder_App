-- migration-id: 20261121000000_demo_payments
-- description: A server-controlled "demo payment" mode for closed testing: while the private setting
--   payments_demo_until (a date) is today or later, a signed-in user can activate Fast-Track for 30 days
--   without paying. Nothing is charged, the app cannot grant itself access (the server decides), and the
--   mode turns itself off after the date. Real payments (RevenueCat / Google Play) are untouched.
-- tables: none (two functions added; uses public.app_private_settings and public.security_events)
-- columns-added: none
-- backward-compat: Additive. New functions only; existing RPCs, the RevenueCat webhook and the premium
--   flags behave as before. Older app versions never call the new functions.
-- recovery: drop function public.demo_activate_fast_track(), public.payments_mode(); users keep their
--   normal is_premium / premium_expires_at values (a demo plan simply expires after 30 days).
-- user-data: none
-- =============================================================================

-- 'demo' while payments_demo_until is today or later (UTC), otherwise 'live'.
create or replace function public.payments_mode()
returns text language sql stable security definer set search_path = public as $$
  select case
    when (select value from public.app_private_settings where key = 'payments_demo_until') ~ '^\d{4}-\d{2}-\d{2}$'
     and (select value from public.app_private_settings where key = 'payments_demo_until')::date >= (now() at time zone 'utc')::date
    then 'demo' else 'live' end;
$$;

-- Activates Fast-Track for 30 days for the caller. Only in demo mode; never lowers a longer paid plan.
create or replace function public.demo_activate_fast_track()
returns timestamptz language plpgsql security definer set search_path = public as $$
declare v_until timestamptz := now() + interval '30 days';
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if public.payments_mode() <> 'demo' then
    raise exception 'Demo payments are off' using errcode = '42501', hint = 'DEMO_PAYMENTS_OFF';
  end if;
  perform public.enforce_rate_limit('demo_fast_track', 5, interval '1 day');
  update public.profiles
     set is_premium = true,
         premium_expires_at = case when is_premium and (premium_expires_at is null or premium_expires_at > v_until)
                                   then premium_expires_at else v_until end
   where id = auth.uid();
  if not found then raise exception 'Create your profile first' using errcode = 'P0002'; end if;
  perform public.log_security_event('demo_fast_track_activated', 'info', '{}'::jsonb, auth.uid());
  return v_until;
end $$;

revoke all on function public.payments_mode(), public.demo_activate_fast_track() from public, anon;
grant execute on function public.payments_mode(), public.demo_activate_fast_track() to authenticated;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261121000000_demo_payments',
        'Server-controlled demo payment mode for closed testing (30-day Fast-Track, no charge, expires by date)',
        array['public.profiles', 'public.app_private_settings'], array[]::text[])
on conflict (migration_id) do nothing;
