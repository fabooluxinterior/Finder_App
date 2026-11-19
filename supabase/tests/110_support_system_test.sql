\set ON_ERROR_STOP 1
-- 01 user, 02 other user, 03 moderator, 04 admin.
alter table auth.users add column if not exists email text;
insert into auth.users (id, email) select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid, 'u'||i||'@example.com' from generate_series(1,4) i;
insert into public.profile_dob (user_id, dob) select id, date '1998-01-01' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, gender) select id, 'User '||right(id::text,2), 25, 'Kochi', '', 'man' from auth.users;
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

-- ---------------------------------------------------------------- chatbot ----
select pg_temp.as_user('01');
select pg_temp.expect((select (public.support_bot_config() ->> 'welcome') like 'Hi! Welcome to Vouby Support%'), 'welcome message is served from the database');
select pg_temp.expect((select count(*) from public.support_faqs()) >= 15, 'default FAQs exist');
select pg_temp.expect((select count(*) from public.support_faqs('subscription', null)) >= 3, 'FAQs by category');
select pg_temp.expect((select count(*) from public.support_faqs(null, 'password')) >= 1, 'FAQ search');
select pg_temp.expect((select title from public.support_bot_answer('I forgot my password, how to reset it?')) = 'I forgot my password', 'keyword match: forgotten password');
select pg_temp.expect((select title from public.support_bot_answer('how can i delete my account')) = 'How do I delete my account?', 'keyword match: account deletion');
select pg_temp.expect((select count(*) from public.support_bot_answer('xqzv blorp')) = 0, 'no match when it does not understand');
select pg_temp.expect((select jsonb_array_length(related) >= 1 from public.support_bot_answer('payment failed, money deducted')), 'related questions are suggested');

create temporary table c1 as select public.support_bot_save(null, '[{"mine":true,"text":"hi"},{"mine":false,"text":"Hi! Welcome to Vouby Support."}]') as id;
grant select on c1 to authenticated;
select pg_temp.expect((select jsonb_array_length(messages) = 2 from public.support_bot_last()), 'conversation is kept');
select public.support_bot_save((select id from c1), '[{"mine":true,"text":"hi"},{"mine":false,"text":"a"},{"mine":true,"text":"b"}]');
select pg_temp.expect((select jsonb_array_length(messages) = 3 from public.support_bot_last()), 'conversation is updated, not duplicated');
select pg_temp.as_user('02');
select pg_temp.expect((select count(*) from public.support_bot_last()) = 0, 'conversations are private');
select pg_temp.expect_fail($$select public.admin_bot_overview()$$, 'a user cannot manage the chatbot');
select pg_temp.expect_fail($$select * from public.mod_ticket_counts()$$, 'a user cannot read ticket counts');

-- ---------------------------------------------------------------- tickets ----
select pg_temp.as_user('01');
create temporary table t1 as select * from public.submit_support_ticket_v2('chat', 'Messages not sending', 'My messages do not send since morning', 'high', '1.0.74', 'Android 14, Pixel 7', (select id from c1));
grant select on t1 to authenticated;
select pg_temp.expect((select ticket_no ~ '^VB-' from t1), 'unique ticket id');
select pg_temp.expect((select priority = 'high' and app_version = '1.0.74' and device_info like 'Android%' and bot_conversation_id is not null from public.support_tickets where id = (select id from t1)), 'priority, app version, device and the chatbot conversation are stored');
select pg_temp.expect((select count(*) from public.user_notifications where kind = 'ticket_created') = 1, 'submission notification');
select pg_temp.expect((select count(*) from public.my_ticket_thread((select id from t1))) = 1, 'conversation starts with the description');
create temporary table t2 as select * from public.submit_support_ticket_v2('safety', 'Someone scared me', 'A person keeps threatening me in chat', 'low', null, null, null);
grant select on t2 to authenticated;
select pg_temp.expect((select priority = 'high' from public.support_tickets where id = (select id from t2)), 'safety tickets are never low priority');

-- Staff.
select pg_temp.as_user('03', 'aal2');
select pg_temp.expect((select (public.mod_ticket_counts() ->> 'total')::int = 2 and (public.mod_ticket_counts() ->> 'new')::int = 2), 'dashboard counts');
select pg_temp.expect((select count(*) from public.mod_list_tickets_v3('all', 'chat')) = 1, 'filter by category');
select pg_temp.expect((select count(*) from public.mod_list_tickets_v3('all', null, 'high')) = 2, 'filter by priority');
select pg_temp.expect((select count(*) from public.mod_list_tickets_v3('all', null, null, 'User 01')) = 2, 'search by username');
select pg_temp.expect((select count(*) from public.mod_list_tickets_v3('all', null, null, (select ticket_no from t1))) = 1, 'search by ticket id');
select pg_temp.expect((select jsonb_array_length(public.mod_ticket_detail((select id from t1)) -> 'bot') = 3), 'staff can read the chatbot conversation on the ticket');
select public.mod_add_ticket_note((select id from t1), 'Checked: account has chat access.');
select pg_temp.expect((select jsonb_array_length(public.mod_ticket_detail((select id from t1)) -> 'notes') = 1), 'internal note stored');
select public.mod_assign_ticket((select id from t1), '00000000-0000-0000-0000-000000000004');
select pg_temp.expect((public.mod_ticket_detail((select id from t1)) -> 'ticket' ->> 'status') = 'assigned' and (public.mod_ticket_detail((select id from t1)) ->> 'assignee') = 'u4@example.com', 'assignment');
select pg_temp.expect_fail($$select public.mod_assign_ticket((select id from t1), '00000000-0000-0000-0000-000000000002')$$, 'only staff can be assigned');
select public.mod_set_ticket_priority((select id from t1), 'urgent');
select public.mod_set_ticket_status_v2((select id from t1), 'in_progress', 'Looking into it');
select public.mod_set_ticket_status_v2((select id from t1), 'in_progress', 'Looking into it');
select public.mod_reply_ticket((select id from t1), 'Could you tell us your phone model?');
select public.mod_escalate_ticket((select id from t2), 'Threats: needs an admin');
select pg_temp.expect((public.mod_ticket_detail((select id from t2)) -> 'ticket' ->> 'status') = 'escalated' and (public.mod_ticket_detail((select id from t2)) -> 'ticket' ->> 'priority') = 'high', 'escalation');
select pg_temp.expect_fail($$select public.mod_set_ticket_status_v2((select id from t1), 'weird', null)$$, 'invalid status refused');

select pg_temp.as_user('01');
select pg_temp.expect((select count(*) from public.user_notifications where kind = 'ticket_in_progress') = 1, 'a repeated status change does not notify twice');
select pg_temp.expect((select count(*) from public.user_notifications where kind = 'ticket_reply') = 1, 'reply notification');
select pg_temp.expect((select count(*) from public.user_notifications where kind = 'ticket_escalated') = 0, 'internal changes (assign, escalate) do not notify the user');
select public.reply_to_ticket((select id from t1), 'Pixel 7, Android 14');
select pg_temp.expect((select status = 'in_progress' from public.support_tickets where id = (select id from t1)), 'user reply puts it back in the queue');
select pg_temp.expect_fail($$select public.rate_ticket((select id from t1), 5, 'great')$$, 'cannot rate before it is resolved');

select pg_temp.as_user('03', 'aal2');
select public.mod_set_ticket_status_v2((select id from t1), 'resolved', 'Fixed by updating.');
select pg_temp.as_user('01');
select pg_temp.expect((select count(*) from public.user_notifications where kind = 'ticket_resolved') = 1, 'resolution notification');
select public.rate_ticket((select id from t1), 4, 'Quick help');
select pg_temp.expect((select rating = 4 from public.support_tickets where id = (select id from t1)), 'rating stored');
select public.reopen_ticket((select id from t1));
select pg_temp.expect((select status = 'open' and reopened_count = 1 from public.support_tickets where id = (select id from t1)), 'a resolved ticket can be reopened');
select pg_temp.expect_fail($$select public.reopen_ticket((select id from t1))$$, 'an open ticket cannot be "reopened"');
select pg_temp.as_user('03', 'aal2');
select public.mod_set_ticket_status_v2((select id from t1), 'closed', null);
select pg_temp.as_user('01');
select pg_temp.expect_fail($$select public.reply_to_ticket((select id from t1), 'one more thing')$$, 'a closed ticket needs reopening before a reply');
select pg_temp.as_user('02');
select pg_temp.expect_fail($$select public.reopen_ticket((select id from t1))$$, 'another user cannot reopen it');
select pg_temp.expect_fail($$select public.rate_ticket((select id from t1), 1, null)$$, 'another user cannot rate it');

-- ------------------------------------------------------ auto-reply management ----
select pg_temp.as_user('03', 'aal2');
select pg_temp.expect_fail($$select public.admin_bot_overview()$$, 'a moderator cannot edit the chatbot');
select pg_temp.as_user('04', 'aal2');
create temporary table r1 as select public.admin_bot_upsert_reply(null, 'technical', 'Dark mode', array['Dark Mode', 'night theme'], 'Vouby follows your phone theme.', true, 5) as id;
grant select on r1 to authenticated;
select pg_temp.as_user('01');
select pg_temp.expect((select title from public.support_bot_answer('how do i turn on night theme')) = 'Dark mode', 'a new reply reaches the chatbot at once');
select pg_temp.as_user('04', 'aal2');
select public.admin_bot_upsert_reply((select id from r1), 'technical', 'Dark mode', array['night theme'], 'Updated answer.', false, 5);
select pg_temp.as_user('01');
select pg_temp.expect((select count(*) from public.support_bot_answer('how do i turn on night theme')) = 0, 'a disabled reply is no longer used');
select pg_temp.as_user('04', 'aal2');
select public.admin_bot_set_settings(true, 'Hello from Vouby', 'Please rephrase.', 'Solved?', 'Raise a ticket.', '["Account & Login"]');
select pg_temp.as_user('01');
select pg_temp.expect((select public.support_bot_config() ->> 'welcome') = 'Hello from Vouby', 'changed welcome message reaches the app');
select pg_temp.as_user('04', 'aal2');
select public.admin_bot_delete_reply((select id from r1));
select pg_temp.expect((select count(*) from public.admin_bot_conversations()) >= 1, 'admins can view chatbot conversations');
reset role;
select pg_temp.expect((select count(*) from public.access_audit_log where action like 'bot_%') >= 3, 'chatbot changes are audited');

-- ------------------------------------------------------------------ reports ----
select pg_temp.expect(public.report_priority('underage') = 'urgent' and public.report_priority('threats') = 'urgent' and public.report_priority('harassment') = 'high' and public.report_priority('other') = 'normal', 'serious reports rank first');
insert into public.reports (reporter_id, reported_id, reason) values ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'threats'), ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'privacy_violation');
select pg_temp.expect((select count(*) from public.reports where status = 'open') = 2, 'serious reports stay open for a person to review');
