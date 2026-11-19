\set ON_ERROR_STOP 1
-- 7-day trial, discovery preferences requirement, notifications, support
-- tickets, safety reports with staff decisions, restrictions, evidence and
-- chat-photo storage rules.
-- 01 A: new account (trial)   02 B: new account   03 C: account from before
-- the trial launched          04 D: admin (MFA)    05 E: free, B's match
-- 06 F: same email as A (re-created account)
alter table auth.users add column if not exists email text;
insert into auth.users (id, email) select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid,
  case i when 1 then 'asha@example.com' when 6 then 'ASHA@example.com ' else 'user'||i||'@example.com' end
  from generate_series(1,6) i;
insert into public.profile_dob (user_id, dob) select id, date '1998-01-01' from auth.users;
insert into public.profiles (id, full_name, age, city, bio, gender, interest_tags)
select ('00000000-0000-0000-0000-0000000000'||lpad(i::text,2,'0'))::uuid, 'User '||i, 26, 'Kochi',
       'Rain, books and chai.', case when i % 2 = 0 then 'man' else 'woman' end,
       '{Photography,Chai,Football,Poetry,Chess}'::text[]
  from generate_series(1,6) i;
update public.profiles set created_at = '2025-01-01' where id = '00000000-0000-0000-0000-000000000003';
update public.profiles set is_onboarded = true,
  photo_urls = array[gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text]
 where id <> '00000000-0000-0000-0000-000000000001';
-- A is still in setup with everything filled in.
update public.profiles set standards_acknowledged_at = now(),
  photo_urls = array[gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text, gen_random_uuid()::text],
  prompts = '[{"prompt_id":"p1","answer":"Filter coffee at four"},{"prompt_id":"p2","answer":"Pineapple on pizza is fine"}]'
 where id = '00000000-0000-0000-0000-000000000001';
insert into public.staff_roles (user_id, role) values ('00000000-0000-0000-0000-000000000004', 'admin');

create or replace function pg_temp.expect_fail(sql text, label text) returns text language plpgsql as $$
begin execute sql; raise exception 'EXPECTED FAILURE DID NOT HAPPEN: %', label;
exception when others then if sqlerrm like 'EXPECTED FAILURE%' then raise; end if; return 'ok (blocked): ' || label || ' -> ' || sqlerrm; end $$;
create or replace function pg_temp.expect(cond boolean, label text) returns text language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'CHECK FAILED: %', label; end if; return 'ok: ' || label; end $$;
create or replace function pg_temp.as_user(u text, aal text default 'aal1') returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000'||u, false),
         set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000'||u, 'aal', aal)::text, false); $$;
grant execute on all functions in schema pg_temp to authenticated;

-- A message that must survive trial expiry.
insert into public.messages (id, sender_id, receiver_id, client_msg_id)
values ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', gen_random_uuid());

set role authenticated;

-- ------------------------------------------------------------ trial starts with setup
select pg_temp.as_user('01');
select pg_temp.expect((select plan from public.my_access_status()) = 'free', 'free before setup');
select public.complete_onboarding();
select pg_temp.expect((select plan = 'trial' and trial_ends_at - trial_started_at = interval '168 hours'
                         from public.my_access_status()), 'setup finished: 168-hour trial');
select pg_temp.expect((select count(*) from public.user_notifications where kind = 'trial_started') = 1, 'trial-started notice');
select pg_temp.expect_fail($$insert into public.user_trials (user_id, ends_at) values (auth.uid(), now() + interval '999 days')$$, 'client extends trial');
select pg_temp.expect_fail($$update public.user_trials set ends_at = now() + interval '30 days'$$, 'client edits trial');
select pg_temp.expect_fail($$select public.start_trial_if_eligible(auth.uid())$$, 'client starts a trial itself');
select pg_temp.expect_fail($$select * from public.trial_claims$$, 'client reads claims');

reset role;
select pg_temp.expect(not public.start_trial_if_eligible('00000000-0000-0000-0000-000000000001'), 'no second trial');
select pg_temp.expect(not public.start_trial_if_eligible('00000000-0000-0000-0000-000000000006'), 'same email on a new account: no trial');
select pg_temp.expect(not public.start_trial_if_eligible('00000000-0000-0000-0000-000000000003'), 'accounts from before launch: no trial');
select pg_temp.expect(public.start_trial_if_eligible('00000000-0000-0000-0000-000000000002'), 'other new account: trial');
set role authenticated;

-- ------------------------------------------------------------ trial unlocks requests
select pg_temp.as_user('03');
select public.swipe_profile('00000000-0000-0000-0000-000000000001', 'follow_requested');
select pg_temp.as_user('01');
select pg_temp.expect((select count(*) from public.swipes_and_requests where receiver_id = auth.uid() and action = 'follow_requested') = 1,
  'trial user sees received requests');
select public.respond_to_request((select id from public.swipes_and_requests where sender_id = '00000000-0000-0000-0000-000000000003'), true);
select 'ok: trial user accepts a request';
select pg_temp.as_user('05');
select public.swipe_profile('00000000-0000-0000-0000-000000000003', 'follow_requested');
select pg_temp.as_user('03');
select pg_temp.expect((select count(*) from public.swipes_and_requests where receiver_id = auth.uid() and action = 'follow_requested') = 0,
  'free user still can''t see requests');
select pg_temp.expect_fail($$select public.respond_to_request((select id from public.swipes_and_requests where sender_id = '00000000-0000-0000-0000-000000000005'), true)$$, 'free user accepts');

-- ------------------------------------------------------------ expiry keeps everything
reset role;
update public.user_trials set started_at = now() - interval '169 hours', ends_at = now() - interval '1 hour'
 where user_id = '00000000-0000-0000-0000-000000000001';
select public.service_trial_reminders();
set role authenticated;
select pg_temp.as_user('01');
select pg_temp.expect((select plan = 'free' and notice = 'trial_ended' from public.my_access_status()), 'trial ended notice');
select pg_temp.expect((select count(*) from public.user_notifications where kind = 'trial_ended') = 1, 'trial-ended reminder sent');
select pg_temp.expect((select count(*) from public.swipes_and_requests where receiver_id = auth.uid() and action = 'follow_requested') = 0,
  'after expiry: requests locked again');
reset role;
select pg_temp.expect(exists (select 1 from public.messages where id = '20000000-0000-0000-0000-000000000001'), 'messages kept after expiry');
select pg_temp.expect(exists (select 1 from public.swipes_and_requests where sender_id = '00000000-0000-0000-0000-000000000003'
                                and action = 'accepted'), 'connections kept after expiry');
update public.user_trials set started_at = now() - interval '150 hours', ends_at = now() + interval '18 hours'
 where user_id = '00000000-0000-0000-0000-000000000002';
select public.service_trial_reminders();
select pg_temp.expect((select count(*) from public.user_notifications where user_id = '00000000-0000-0000-0000-000000000002'
                         and kind = 'trial_24h') = 1, '24-hour reminder');
select public.service_trial_reminders();
select pg_temp.expect((select count(*) from public.user_notifications where user_id = '00000000-0000-0000-0000-000000000002'
                         and kind = 'trial_24h') = 1, 'reminder sent once');
update public.profiles set is_premium = true where id = '00000000-0000-0000-0000-000000000001';
set role authenticated;
select pg_temp.as_user('01');
select pg_temp.expect((select plan = 'fast_track' and notice is null from public.my_access_status()), 'subscribing restores access');
reset role;
update public.profiles set is_premium = false where id = '00000000-0000-0000-0000-000000000001';
set role authenticated;

-- ------------------------------------------------------------ discovery preferences
select pg_temp.as_user('05');
select pg_temp.expect(exists (select 1 from public.my_profile_updates() where key = 'discovery_prefs'), 'existing user asked who they''d like to meet');
update public.profiles set pref_genders = '{woman}', pref_age_min = 21, pref_age_max = 35 where id = auth.uid();
select pg_temp.expect(not exists (select 1 from public.my_profile_updates() where key = 'discovery_prefs'), 'answered once, not asked again');
select pg_temp.expect((select prefs_set_at is not null from public.profiles where id = auth.uid()), 'time recorded by the server');
select pg_temp.expect_fail($$update public.profiles set pref_age_min = 17 where id = auth.uid()$$, 'minimum age below 18');

-- ------------------------------------------------------------ support tickets
select pg_temp.as_user('01');
create temporary table t1 as select * from public.submit_support_ticket('subscription', 'Trial question', 'When does my free trial end exactly?');
select pg_temp.expect((select ticket_no ~ '^VB-[2-9A-Z]{6}$' from t1), 'ticket number generated');
select pg_temp.expect((select email = 'asha@example.com' from public.support_tickets where id = (select id from t1)), 'email prefilled by the server');
select pg_temp.expect((select count(*) from public.support_ticket_events) = 1, 'ticket history visible to owner');
select pg_temp.expect_fail($$select * from public.submit_support_ticket('subscription', 'x', 'too short')$$, 'invalid ticket');
select pg_temp.expect_fail($$select * from public.submit_support_ticket('account', 'Screenshot', 'Attached a screenshot here', '00000000-0000-0000-0000-000000000002/x.webp')$$, 'attachment from someone else''s folder');
select pg_temp.expect_fail($$update public.support_tickets set status = 'resolved'$$, 'user changes ticket status');
select pg_temp.as_user('02');
select pg_temp.expect((select count(*) from public.support_tickets) = 0, 'other users can''t see the ticket');
select pg_temp.expect_fail($$select public.mod_set_ticket_status((select id from t1), 'resolved')$$, 'non-staff changes status');
select pg_temp.as_user('04', 'aal2');
select public.mod_set_ticket_status((select id from t1), 'in_progress', 'Looking into it');
select pg_temp.expect((select count(*) from public.mod_list_tickets('open')) = 1, 'staff see open tickets');
select pg_temp.as_user('01');
select pg_temp.expect((select status from public.support_tickets) = 'in_progress', 'owner sees new status');
select pg_temp.expect((select count(*) from public.user_notifications where kind = 'ticket_in_progress') = 1, 'owner notified');
select count(*) from (select public.submit_support_ticket('other', 'Ticket ' || g, 'Testing the daily limit please') from generate_series(1,4) g) x;
select pg_temp.expect_fail($$select * from public.submit_support_ticket('other', 'One too many', 'Testing the daily limit please')$$, '6th ticket in a day');

-- ------------------------------------------------------------ reports and decisions
select pg_temp.as_user('02');
create temporary table r1 as select * from public.submit_report_v2('00000000-0000-0000-0000-000000000005', 'impersonation',
  'Uses my friend''s photos', 'msg:abc123', null, false);
select pg_temp.expect((select report_no ~ '^R-[2-9A-Z]{6}$' from r1), 'report number generated');
select pg_temp.expect_fail($$select * from public.submit_report_v2('00000000-0000-0000-0000-000000000005', 'not_a_reason', null, null, null, false)$$, 'unknown category');
select pg_temp.as_user('03');
select * from public.submit_report_v2('00000000-0000-0000-0000-000000000005', 'spam', 'Spam', null, null, false);
select pg_temp.as_user('06');
select * from public.submit_report_v2('00000000-0000-0000-0000-000000000005', 'scam', 'Asked for money', null, null, false);
reset role;
select pg_temp.expect((select count(*) from public.user_restrictions) = 0, 'three reports never restrict automatically');
select pg_temp.expect((select count(*) from public.reports where reported_id = '00000000-0000-0000-0000-000000000005' and status = 'open') = 3, 'reports wait for review');
set role authenticated;

-- Evidence: only the reporter, only on their own new report.
select pg_temp.as_user('02');
select public.add_report_evidence((select id from r1), 'image', 'msg:abc123', (select id from r1)::text || '/1.webp');
select 'ok: reporter adds selected evidence';
select pg_temp.expect_fail($$select public.add_report_evidence((select id from r1), 'image', null, 'other/1.webp')$$, 'evidence outside the report folder');
select pg_temp.expect_fail($$select * from public.report_evidence$$, 'users read evidence table');
insert into storage.objects (bucket_id, name) values ('report_evidence', (select id from r1)::text || '/1.webp');
select 'ok: reporter uploads evidence file';
select pg_temp.as_user('03');
select pg_temp.expect_fail($$select public.add_report_evidence((select id from r1), 'text', null, (select id from r1)::text || '/2.json')$$, 'evidence on someone else''s report');
select pg_temp.expect_fail($$insert into storage.objects (bucket_id, name) values ('report_evidence', (select id from r1)::text || '/x.webp')$$, 'upload to someone else''s report');
select pg_temp.expect_fail($$select * from public.mod_list_reports_v2('open')$$, 'non-staff lists reports');

-- Staff decisions (moderation history, false reports, restrictions).
select pg_temp.as_user('04', 'aal2');
select pg_temp.expect((select count(*) from public.mod_list_reports_v2('open')) = 3, 'staff see the reports');
select pg_temp.expect((select evidence_files = 1 from public.mod_list_reports_v2('open') where id = (select id from r1)), 'staff see evidence count');
select pg_temp.expect(public.mod_evidence_path((select e.id from public.mod_list_evidence((select id from r1)) e), 'review') like '%/1.webp',
  'staff open evidence (logged)');
select pg_temp.expect_fail($$select public.mod_decide_report((select id from r1), 'suspended', '')$$, 'decision without a note');
select public.mod_decide_report((select id from public.mod_list_reports_v2('open') where reason = 'spam'), 'false_report', 'Not spam; normal messages');
select public.mod_decide_report((select id from r1), 'suspended', 'Confirmed impersonation', 'suspended', 7);
select pg_temp.expect((select reporter_false_reports from public.mod_list_reports_v2('all') where reason = 'spam') = 1, 'false reports counted for the reporter');
select pg_temp.expect((public.mod_user_history('00000000-0000-0000-0000-000000000005') ->> 'reports_upheld')::int = 1, 'history: upheld report');
reset role;
select pg_temp.expect((select count(*) from public.moderation_actions) = 2, 'every decision recorded');
select pg_temp.expect(public.is_moderation_hidden('00000000-0000-0000-0000-000000000005'), 'suspended user hidden from discovery');
select pg_temp.expect(not public.prefs_match('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000005'), 'not matched in feed or suggestions');
set role authenticated;
select pg_temp.as_user('05');
select pg_temp.expect((select kind = 'suspended' and until > now() + interval '6 days' from public.my_restriction()), 'user sees their suspension');
select pg_temp.expect_fail($$select public.swipe_profile('00000000-0000-0000-0000-000000000003', 'follow_requested')$$, 'suspended user sends request');
select pg_temp.expect_fail($$select * from public.moderation_actions$$, 'users read moderation history');

-- ------------------------------------------------------------ chat photo storage
select pg_temp.as_user('02');
select pg_temp.expect_fail($$insert into storage.objects (bucket_id, name) values ('chat_images', '00000000-0000-0000-0000-000000000002_00000000-0000-0000-0000-000000000004/x.bin')$$, 'photo to a non-connection');
select pg_temp.as_user('03');
select pg_temp.expect_fail($$insert into storage.objects (bucket_id, name) values ('chat_images', '00000000-0000-0000-0000-000000000001_00000000-0000-0000-0000-000000000003/x.bin')$$, 'free user sends a photo');
reset role;
update public.profiles set is_premium = true where id = '00000000-0000-0000-0000-000000000003';
set role authenticated;
insert into storage.objects (bucket_id, name) values ('chat_images', '00000000-0000-0000-0000-000000000001_00000000-0000-0000-0000-000000000003/x.bin');
select 'ok: Fast-Track user sends a photo to a connection';
select pg_temp.as_user('01');
select pg_temp.expect((select count(*) from storage.objects where bucket_id = 'chat_images') = 1, 'the connection can download it');
select pg_temp.as_user('02');
select pg_temp.expect((select count(*) from storage.objects where bucket_id = 'chat_images') = 0, 'others can''t');
