\set ON_ERROR_STOP 1
-- Admin dashboard: 01,02 = users; 03 = moderator; 04 = admin.
alter table auth.users add column if not exists email text;
alter table auth.users add column if not exists phone text;
insert into auth.users (id, email) select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid, 'u'||i||'@example.com' from generate_series(1,4) i;
insert into public.profile_dob (user_id, dob) select id, date '1998-01-01' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, gender)
select id, 'User '||right(id::text,2), 25, 'Kochi', '', 'man' from auth.users;
update public.profiles set is_onboarded = true,
  photo_urls = array[gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text];
insert into public.staff_roles (user_id, role) values ('00000000-0000-0000-0000-000000000003', 'moderator'), ('00000000-0000-0000-0000-000000000004', 'admin');
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.expect_fail(sql text, label text) returns text language plpgsql as $$
begin execute sql; raise exception 'EXPECTED FAILURE DID NOT HAPPEN: %', label;
exception when others then if sqlerrm like 'EXPECTED FAILURE%' then raise; end if; return 'ok (blocked): ' || label; end $$;
create or replace function pg_temp.as_user(u text, aal text default 'aal1') returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000'||u, 'aal', aal)::text, false); $$;
grant execute on all functions in schema pg_temp to authenticated;
set role authenticated;

-- Normal users and staff without two-step verification are refused.
select pg_temp.as_user('01');
select pg_temp.expect_fail($$select public.mod_overview()$$, 'user cannot open the overview');
select pg_temp.expect_fail($$select * from public.mod_user_search()$$, 'user cannot search users');
select pg_temp.expect_fail($$select public.mod_apply_action('00000000-0000-0000-0000-000000000002', 'suspended', 'no right', 3)$$, 'user cannot suspend');
select pg_temp.as_user('03', 'aal1');
select pg_temp.expect_fail($$select public.mod_overview()$$, 'moderator without 2-step is refused');

-- Moderator.
select pg_temp.as_user('03', 'aal2');
select pg_temp.expect((select (public.mod_overview() ->> 'users_total')::int = 4), 'overview counts users');
select pg_temp.expect((select count(*) from public.mod_user_search('user 02')) = 1, 'search by name');
select pg_temp.expect((select count(*) from public.mod_user_search('u2@example.com')) = 1, 'search by email');
select pg_temp.expect_fail($$select public.mod_apply_action('00000000-0000-0000-0000-000000000002', 'suspended', '', 3)$$, 'note required');
select pg_temp.expect_fail($$select public.mod_apply_action('00000000-0000-0000-0000-000000000002', 'banned', 'bad actor', null)$$, 'moderator cannot ban');
select pg_temp.expect_fail($$select public.mod_apply_action('00000000-0000-0000-0000-000000000002', 'remove', 'bad actor', null)$$, 'moderator cannot remove');
select pg_temp.expect_fail($$select public.mod_apply_action('00000000-0000-0000-0000-000000000004', 'suspended', 'try admin', 3)$$, 'moderator cannot act on an admin');
select pg_temp.expect((select public.mod_apply_action('00000000-0000-0000-0000-000000000002', 'suspended', 'Harassment in chats', 7)) = 'suspended', 'suspend returns the new status');
select pg_temp.expect((select count(*) from public.mod_list_restricted('suspended')) = 1, 'listed as suspended');
select pg_temp.expect((select (public.mod_user_detail('00000000-0000-0000-0000-000000000002') ->> 'status') = 'suspended'), 'detail shows status');
select pg_temp.as_user('01');
select pg_temp.expect((select count(*) from public.get_feed(50) where id = '00000000-0000-0000-0000-000000000002') = 0, 'suspended user is hidden from discovery');
select pg_temp.as_user('03', 'aal2');
select pg_temp.expect((select public.mod_unsuspend_user('00000000-0000-0000-0000-000000000002', 'Appeal accepted')) = 'active', 'unsuspend makes the account active');
select pg_temp.expect((select count(*) from public.mod_list_restricted('all')) = 0, 'nothing left in the list');
select pg_temp.as_user('01');
select pg_temp.expect((select count(*) from public.get_feed(50) where id = '00000000-0000-0000-0000-000000000002') = 1, 'visible in discovery again');
select pg_temp.as_user('03', 'aal2');

-- Deactivate / reactivate.
select pg_temp.expect((select public.mod_apply_action('00000000-0000-0000-0000-000000000002', 'deactivate', 'Requested by the user', null)) = 'deactivated', 'deactivate');
select pg_temp.expect((select public.mod_unsuspend_user('00000000-0000-0000-0000-000000000002', 'Back on request')) = 'active', 'reactivate with unsuspend');

-- Admin only: ban, remove, staff.
select pg_temp.expect_fail($$select * from public.admin_list_staff()$$, 'moderator cannot list staff');
select pg_temp.as_user('04', 'aal2');
select pg_temp.expect((select public.mod_apply_action('00000000-0000-0000-0000-000000000002', 'banned', 'Repeated abuse', null)) = 'banned', 'admin bans');
select pg_temp.as_user('03', 'aal2');
select pg_temp.expect_fail($$select public.mod_unsuspend_user('00000000-0000-0000-0000-000000000002', 'trying')$$, 'moderator cannot lift a ban');
select pg_temp.as_user('04', 'aal2');
select pg_temp.expect((select public.mod_unsuspend_user('00000000-0000-0000-0000-000000000002', 'Ban overturned')) = 'active', 'admin lifts the ban');
select pg_temp.expect((select public.mod_apply_action('00000000-0000-0000-0000-000000000001', 'remove', 'Account removal requested', null)) = 'removal_pending', 'remove starts the 30-day window');
select pg_temp.expect((select removal_due_at > now() + interval '29 days' from public.profiles where id = '00000000-0000-0000-0000-000000000001'), 'due in 30 days');
select pg_temp.expect((select count(*) = 1 from public.profiles where id = '00000000-0000-0000-0000-000000000001'), 'nothing deleted');
select pg_temp.as_user('03', 'aal2');
select pg_temp.expect_fail($$select public.mod_unsuspend_user('00000000-0000-0000-0000-000000000001', 'x y z')$$, 'moderator cannot cancel a removal');
select pg_temp.as_user('04', 'aal2');
select pg_temp.expect((select public.mod_apply_action('00000000-0000-0000-0000-000000000001', 'cancel_removal', 'Changed their mind')) = 'active', 'admin cancels the removal');

select pg_temp.expect((select count(*) from public.mod_audit_log(100, 0) where action like 'user_%') >= 6, 'every action is in the audit log');
select pg_temp.expect_fail($$select public.admin_set_staff('u4@example.com', null)$$, 'admin cannot change own role');
select public.admin_set_staff('u1@example.com', 'moderator');
select pg_temp.expect((select count(*) from public.admin_list_staff()) = 3, 'staff list has three people');
select public.admin_set_staff('u1@example.com', null);
select pg_temp.expect((select count(*) from public.admin_list_staff()) = 2, 'staff removed');
-- A suspended user's own view.
select pg_temp.as_user('04', 'aal2');
select public.mod_apply_action('00000000-0000-0000-0000-000000000002', 'suspended', 'Test suspension', 1);
select pg_temp.as_user('02');
select pg_temp.expect((select kind from public.my_restriction()) = 'suspended', 'the user sees the suspension');
