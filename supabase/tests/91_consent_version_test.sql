\set ON_ERROR_STOP 1
-- Re-consent after a policy bump: the setup acknowledgement ('community_standards') must not hold the
-- accepted version back, a missing policy still means "not accepted", and agreeing again moves it forward.
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid from generate_series(1,4) i;

create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000'||u, 'aal', 'aal1')::text, false); $$;
grant execute on all functions in schema pg_temp to authenticated;

-- 01: all four policies at 2026-11-19, setup acknowledgement still at 2026-11-18 (the reported case)
insert into public.user_consents (user_id, policy_type, policy_version)
select '00000000-0000-0000-0000-000000000001', t, '2026-11-19' from unnest(array['terms','privacy','community_guidelines','age_18_plus']) t;
insert into public.user_consents (user_id, policy_type, policy_version)
values ('00000000-0000-0000-0000-000000000001', 'community_standards', '2026-11-18');
-- 02: only three of the four policies
insert into public.user_consents (user_id, policy_type, policy_version)
select '00000000-0000-0000-0000-000000000002', t, '2026-11-19' from unnest(array['terms','privacy','community_guidelines']) t;
-- 03: all four, but accepted at an older version
insert into public.user_consents (user_id, policy_type, policy_version)
select '00000000-0000-0000-0000-000000000003', t, '2026-11-15' from unnest(array['terms','privacy','community_guidelines','age_18_plus']) t;
-- 04: only the setup acknowledgement
insert into public.user_consents (user_id, policy_type, policy_version)
values ('00000000-0000-0000-0000-000000000004', 'community_standards', '2026-11-19');

set role authenticated;
select pg_temp.as_user('01');
select pg_temp.expect(public.accepted_policy_version() = '2026-11-19', 'an older setup acknowledgement no longer holds the version back');
select pg_temp.as_user('02');
select pg_temp.expect(public.accepted_policy_version() is null, 'a missing policy still means not accepted');
select pg_temp.as_user('03');
select pg_temp.expect(public.accepted_policy_version() = '2026-11-15', 'accepted at an older version reports that version');
select public.record_consent('2026-11-19');
select pg_temp.expect(public.accepted_policy_version() = '2026-11-19', 'agreeing again moves it forward (even though the setup row stays old)');
select pg_temp.as_user('04');
select pg_temp.expect(public.accepted_policy_version() is null, 'the setup acknowledgement alone is not consent to the policies');
select pg_temp.as_user('01');
select pg_temp.expect((select count(*) from public.user_consents where user_id = auth.uid()) = 5, 'no consent rows were changed');
