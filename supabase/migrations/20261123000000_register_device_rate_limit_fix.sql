-- migration-id: 20261123000000_register_device_rate_limit_fix
-- description: register_device() counted every call against its 5-per-hour limit, including calls from a
--   phone that is already registered (the app calls it each time chat starts). After a few app restarts or
--   reinstalls the limit tripped and every message failed with "something went wrong" until the next hour.
--   Now only the creation of a NEW device counts; re-registering a known device is free.
-- tables: none (function replaced)
-- columns-added: none
-- backward-compat: Same signature, same return value and errors (MFA_REQUIRED, DEVICE_LIMIT, RATE_LIMIT);
--   older app versions keep working and stop being locked out.
-- recovery: Re-create the previous body from 20261108000000_security.sql if ever needed.
-- user-data: none
-- =============================================================================

create or replace function public.register_device(p_curve25519 text, p_ed25519 text, p_label text, p_platform text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_active int;
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  if not public.mfa_satisfied() then
    raise exception 'Verify with your authenticator app to add a device' using errcode = '42501', hint = 'MFA_REQUIRED';
  end if;

  -- Already registered: just note it was seen (not rate limited).
  select id into v_id from public.devices where user_id = auth.uid() and curve25519 = p_curve25519 and revoked_at is null;
  if found then
    update public.devices set last_seen_at = now() where id = v_id;
    return v_id;
  end if;

  perform public.enforce_rate_limit('register_device', 5, interval '1 hour');
  select count(*) into v_active from public.devices where user_id = auth.uid() and revoked_at is null;
  if v_active >= 5 then
    raise exception 'Device limit reached. Remove a device first.' using errcode = 'P0001', hint = 'DEVICE_LIMIT';
  end if;

  insert into public.devices (user_id, curve25519, ed25519, label, platform)
  values (auth.uid(), p_curve25519, p_ed25519, left(coalesce(p_label, 'Device'), 60), p_platform)
  returning id into v_id;
  perform public.log_security_event('device_added', case when v_active > 0 then 'warning' else 'info' end,
    jsonb_build_object('device_id', v_id, 'platform', p_platform));
  return v_id;
end $$;

insert into public.schema_change_log (migration_id, description, tables, columns_added)
values ('20261123000000_register_device_rate_limit_fix',
        'Re-registering a known device no longer counts against the hourly limit (chat failed after several app restarts)',
        array['public.devices'], array[]::text[])
on conflict (migration_id) do nothing;
