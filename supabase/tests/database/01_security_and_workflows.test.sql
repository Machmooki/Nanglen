-- pgTAP suite: run with `supabase test db` (local stack, isolated test users, rolled back at the end).
-- Covers Product Rules invariants: Guest limits, Admin-only approval, one-time visit verification,
-- one current review per user/venue with revisions, RLS isolation, immutable audit.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select * from no_plan();

-- ---------------------------------------------------------------------------
-- Fixtures (as postgres)
-- ---------------------------------------------------------------------------
insert into auth.users (id, aud, role, phone, phone_confirmed_at, is_anonymous, created_at, updated_at) values
    ('10000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', null,          null,  true,  now(), now()), -- guest
    ('10000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', '66810000002', now(), false, now(), now()), -- registered R1
    ('10000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', '66810000003', now(), false, now(), now()), -- registered R2
    ('10000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', '66810000004', now(), false, now(), now()), -- admin
    ('10000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', null,          null,  false, now(), now()); -- permanent, phone NOT confirmed
select private.grant_admin('10000000-0000-4000-8000-000000000004', 'pgtap');

insert into public.venues (id, name, category, formatted_address, location, provenance) values
    ('20000000-0000-4000-8000-000000000001', 'Test Reading Room', 'library', 'Bangkok',
     extensions.st_setsrid(extensions.st_makepoint(100.5300, 13.7400), 4326)::extensions.geography, 'curated_import'),
    ('20000000-0000-4000-8000-000000000002', 'Empty Cafe', 'cafe', 'Bangkok',
     extensions.st_setsrid(extensions.st_makepoint(100.5400, 13.7500), 4326)::extensions.geography, 'curated_import');

create temp table t (k text primary key, v jsonb);
grant all on t to authenticated, anon;

create function pg_temp.login(p_uid uuid, p_anon boolean default false) returns text language sql as $$
    select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'is_anonymous', p_anon)::text, true);
$$;

-- ---------------------------------------------------------------------------
-- Structural security
-- ---------------------------------------------------------------------------
select is((select count(*) from pg_tables where schemaname = 'public' and not rowsecurity), 0::bigint,
          'RLS is enabled on every public table');
select is((select count(*) from information_schema.role_table_grants
           where table_schema = 'private' and grantee in ('anon', 'authenticated')), 0::bigint,
          'No private table is granted to API roles');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prosecdef and not exists (
               select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')), 0::bigint,
          'Every SECURITY DEFINER function in public pins search_path');
select ok(not has_function_privilege('authenticated', 'private.grant_admin(uuid, text, text)', 'execute'),
          'API roles cannot grant Admin');

-- ---------------------------------------------------------------------------
-- Guest (anonymous auth user)
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.login('10000000-0000-4000-8000-000000000001', true);

select ok((select count(*) from public.search_venues(p_query => 'reading room')) = 1, 'Guest can search approved venues');
select lives_ok($$ insert into public.favorites (venue_id) values ('20000000-0000-4000-8000-000000000001') $$, 'Guest can save a favorite');
select throws_ok($$ select public.issue_visit_challenge('20000000-0000-4000-8000-000000000001') $$,
                 '42501', 'registration_required', 'Guest cannot start a review');
select throws_ok($$ select public.create_venue_submission(gen_random_uuid(), 'Guest Place', 'cafe', 'x', 13.7, 100.5) $$,
                 '42501', 'registration_required', 'Guest cannot submit a place');
select throws_ok($$ insert into public.favorites (user_id, venue_id) values ('10000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002') $$,
                 '42501', null, 'Cannot insert a favorite for another user');
select throws_ok($$ select visit_verification_id from public.review_revisions $$, '42501', null,
                 'Verification ids are not readable through the API');
select throws_ok($$ select user_id from public.reviews $$, '42501', null, 'Reviewer auth ids are not readable');

-- Permanent but phone-unverified user is not Registered.
select pg_temp.login('10000000-0000-4000-8000-000000000005', false);
select throws_ok($$ select public.issue_visit_challenge('20000000-0000-4000-8000-000000000001') $$,
                 '42501', 'registration_required', 'Unverified phone cannot review');

-- ---------------------------------------------------------------------------
-- Venue submission → mandatory Admin approval
-- ---------------------------------------------------------------------------
select pg_temp.login('10000000-0000-4000-8000-000000000002');
insert into t values ('sub1', public.create_venue_submission('30000000-0000-4000-8000-000000000001', 'Brand New Study Loft', 'study_space',
                                                             'Siam, Bangkok', 13.7450, 100.5330, 'apple_maps', 'I1234ABCD'));
select is((select v->>'status' from t where k = 'sub1'), 'pending_review', 'Submission enters pending_review');
select is((select v->>'submission_id' from t where k = 'sub1'),
          (public.create_venue_submission('30000000-0000-4000-8000-000000000001', 'Brand New Study Loft', 'study_space',
                                          'Siam, Bangkok', 13.7450, 100.5330, 'apple_maps', 'I1234ABCD'))->>'submission_id',
          'Submission creation is idempotent per client_request_id');
select is((select count(*) from public.search_venues(p_query => 'brand new study loft')), 0::bigint,
          'Pending submission never appears in public search');
select throws_ok($$ select public.admin_approve_venue_submission(((select v->>'submission_id' from t where k = 'sub1'))::uuid) $$,
                 '42501', 'admin_required', 'Submitter cannot approve own submission');
select throws_ok($$ update public.venue_submissions set status = 'approved' $$, '42501', null,
                 'Clients cannot update submission status directly');

select pg_temp.login('10000000-0000-4000-8000-000000000003');
select is((select count(*) from public.venue_submissions), 0::bigint, 'Another user cannot see the submission');
select throws_ok($$ select public.withdraw_venue_submission(((select v->>'submission_id' from t where k = 'sub1'))::uuid) $$,
                 '55000', 'invalid_status_transition', 'Another user cannot withdraw the submission');

select pg_temp.login('10000000-0000-4000-8000-000000000004');
insert into t values ('appr', public.admin_approve_venue_submission(((select v->>'submission_id' from t where k = 'sub1'))::uuid, 'Checked on map'));
select is((select count(*) from public.search_venues(p_query => 'brand new study loft')), 1::bigint,
          'Approved submission becomes a public venue');
select throws_ok($$ select public.admin_approve_venue_submission(((select v->>'submission_id' from t where k = 'sub1'))::uuid) $$,
                 '55000', 'invalid_status_transition', 'A submission cannot be approved twice');
select is((select count(*) from public.moderation_actions where action = 'submission_approved'), 1::bigint,
          'Approval wrote an audit event');

-- Exact provider match links to the existing venue instead of queuing.
select pg_temp.login('10000000-0000-4000-8000-000000000003');
select is((public.create_venue_submission(gen_random_uuid(), 'Study Loft again', 'study_space', null, 13.7450, 100.5330, 'apple_maps', 'I1234ABCD'))->>'status',
          'already_listed', 'Exact provider duplicate links to the existing venue');

-- needs_changes → resubmit → duplicate path
insert into t values ('sub2', public.create_venue_submission(gen_random_uuid(), 'Reading Room Copy', 'library', 'Bangkok', 13.74001, 100.53001));
select pg_temp.login('10000000-0000-4000-8000-000000000004');
select throws_ok($$ select public.admin_request_submission_changes(((select v->>'submission_id' from t where k = 'sub2'))::uuid, '') $$,
                 '22023', 'reason_required', 'Requesting changes needs a reason');
select lives_ok($$ select public.admin_request_submission_changes(((select v->>'submission_id' from t where k = 'sub2'))::uuid, 'Pin looks off') $$,
                'Admin can request changes');
select pg_temp.login('10000000-0000-4000-8000-000000000003');
select is((public.resubmit_venue_submission(((select v->>'submission_id' from t where k = 'sub2'))::uuid, 'Reading Room Copy', 'library', 'Bangkok', 13.74001, 100.53001))->>'status',
          'pending_review', 'Submitter can resubmit after needs_changes');
select pg_temp.login('10000000-0000-4000-8000-000000000004');
select is((public.admin_mark_submission_duplicate(((select v->>'submission_id' from t where k = 'sub2'))::uuid, '20000000-0000-4000-8000-000000000001'))->>'status',
          'duplicate', 'Admin can mark a duplicate and link the canonical venue');

-- ---------------------------------------------------------------------------
-- Visit verification
-- ---------------------------------------------------------------------------
select pg_temp.login('10000000-0000-4000-8000-000000000002');
insert into t values ('ch1', public.issue_visit_challenge('20000000-0000-4000-8000-000000000001'));
select is((public.verify_visit(((select v->>'challenge_id' from t where k = 'ch1'))::uuid, 13.7500, 100.5300, 10, now()))->>'status',
          'too_far', 'Out-of-radius reading is rejected');
select throws_ok($$ select public.verify_visit(((select v->>'challenge_id' from t where k = 'ch1'))::uuid, 13.7400, 100.5300, 10, now()) $$,
                 '55000', 'challenge_consumed', 'A challenge cannot be replayed');

insert into t values ('ch2', public.issue_visit_challenge('20000000-0000-4000-8000-000000000001'));
select is((public.verify_visit(((select v->>'challenge_id' from t where k = 'ch2'))::uuid, 13.7400, 100.5300, 80, now()))->>'status',
          'inaccurate', 'Inaccurate reading is rejected');
insert into t values ('ch3', public.issue_visit_challenge('20000000-0000-4000-8000-000000000001'));
select is((public.verify_visit(((select v->>'challenge_id' from t where k = 'ch3'))::uuid, 13.7400, 100.5300, 10, now() - interval '5 minutes'))->>'status',
          'stale', 'Stale reading is rejected');
insert into t values ('ch4', public.issue_visit_challenge('20000000-0000-4000-8000-000000000001'));
select is((public.verify_visit(((select v->>'challenge_id' from t where k = 'ch4'))::uuid, 13.7400, 100.5300, -1, now()))->>'status',
          'invalid', 'Negative accuracy is invalid');

select pg_temp.login('10000000-0000-4000-8000-000000000003');
select throws_ok($$ select public.verify_visit(((select v->>'challenge_id' from t where k = 'ch1'))::uuid, 13.74, 100.53, 10, now()) $$,
                 'P0002', 'challenge_not_found', 'A challenge is bound to its user');

select pg_temp.login('10000000-0000-4000-8000-000000000002');
insert into t values ('ch5', public.issue_visit_challenge('20000000-0000-4000-8000-000000000001'));
insert into t values ('vv5', public.verify_visit(((select v->>'challenge_id' from t where k = 'ch5'))::uuid, 13.74030, 100.53010, 12, now()));
select is((select v->>'status' from t where k = 'vv5'), 'verified', 'In-radius, fresh, accurate reading is verified');
select ok((select (v->>'verification_id') is not null from t where k = 'vv5'), 'Verified result carries a one-time verification id');

-- ---------------------------------------------------------------------------
-- Reviews
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.submit_review('20000000-0000-4000-8000-000000000001', ((select v->>'verification_id' from t where k = 'vv5'))::uuid,
                                               5, null, array['quiet','good_wifi','power_outlets','study_friendly'], null, gen_random_uuid()) $$,
                 '22023', 'too_many_tags', 'More than three tags is rejected');
select throws_ok($$ select public.submit_review('20000000-0000-4000-8000-000000000001', ((select v->>'verification_id' from t where k = 'vv5'))::uuid,
                                               5, null, '{}', repeat('a', 501), gen_random_uuid()) $$,
                 '22001', 'body_too_long', 'Comments over 500 characters are rejected');
select throws_ok($$ select public.submit_review('20000000-0000-4000-8000-000000000002', ((select v->>'verification_id' from t where k = 'vv5'))::uuid,
                                               5, null, '{}', null, gen_random_uuid()) $$,
                 '42501', 'verification_invalid', 'A verification is bound to its venue');

insert into t values ('rv1', public.submit_review('20000000-0000-4000-8000-000000000001', ((select v->>'verification_id' from t where k = 'vv5'))::uuid,
                                                  4, 'study', array['quiet','study_friendly'], 'Calm and bright', '40000000-0000-4000-8000-000000000001'));
select is((select (v->>'revision_number')::int from t where k = 'rv1'), 1, 'First review creates revision 1');
select is((public.submit_review('20000000-0000-4000-8000-000000000001', ((select v->>'verification_id' from t where k = 'vv5'))::uuid,
                                4, 'study', array['quiet','study_friendly'], 'Calm and bright', '40000000-0000-4000-8000-000000000001'))->>'replayed',
          'true', 'Same idempotency key replays without a duplicate');
select throws_ok($$ select public.submit_review('20000000-0000-4000-8000-000000000001', ((select v->>'verification_id' from t where k = 'vv5'))::uuid,
                                               2, null, '{}', null, gen_random_uuid()) $$,
                 '55000', 'verification_consumed', 'A verification cannot be reused');

select pg_temp.login('10000000-0000-4000-8000-000000000003');
select throws_ok($$ select public.submit_review('20000000-0000-4000-8000-000000000001', ((select v->>'verification_id' from t where k = 'vv5'))::uuid,
                                               1, null, '{}', null, gen_random_uuid()) $$,
                 '42501', 'verification_invalid', 'Another user cannot use my verification');

-- Revisit → new revision, still one current review
select pg_temp.login('10000000-0000-4000-8000-000000000002');
insert into t values ('ch6', public.issue_visit_challenge('20000000-0000-4000-8000-000000000001'));
insert into t values ('vv6', public.verify_visit(((select v->>'challenge_id' from t where k = 'ch6'))::uuid, 13.7400, 100.5300, 5, now()));
insert into t values ('rv2', public.submit_review('20000000-0000-4000-8000-000000000001', ((select v->>'verification_id' from t where k = 'vv6'))::uuid,
                                                  2, 'work', '{}', 'Got noisy', gen_random_uuid()));
select is((select (v->>'revision_number')::int from t where k = 'rv2'), 2, 'Verified revisit creates revision 2');
select is((select count(*) from public.list_venue_reviews('20000000-0000-4000-8000-000000000001')), 1::bigint,
          'Only one current review card per user and venue');
select is((public.get_venue('20000000-0000-4000-8000-000000000001'))->>'average_rating', '2.00',
          'Summary uses the current revision');

-- Expired verification
insert into t values ('ch7', public.issue_visit_challenge('20000000-0000-4000-8000-000000000001'));
insert into t values ('vv7', public.verify_visit(((select v->>'challenge_id' from t where k = 'ch7'))::uuid, 13.7400, 100.5300, 5, now()));
reset role;
update private.visit_verifications set expires_at = now() - interval '1 second'
where id = ((select v->>'verification_id' from t where k = 'vv7'))::uuid;
set local role authenticated;
select pg_temp.login('10000000-0000-4000-8000-000000000002');
select throws_ok($$ select public.submit_review('20000000-0000-4000-8000-000000000001', ((select v->>'verification_id' from t where k = 'vv7'))::uuid,
                                               3, null, '{}', null, gen_random_uuid()) $$,
                 '55000', 'verification_expired', 'An expired verification cannot publish');

-- No reviews → null rating, never 0
select ok((public.get_venue('20000000-0000-4000-8000-000000000002'))->'average_rating' = 'null'::jsonb,
          'Venue without reviews has a null average');

-- ---------------------------------------------------------------------------
-- Moderation
-- ---------------------------------------------------------------------------
select pg_temp.login('10000000-0000-4000-8000-000000000003');
select lives_ok($$ select public.flag_review(((select v->>'review_id' from t where k = 'rv1'))::uuid, 'spam', 'test') $$, 'Registered user can flag a review');
select throws_ok($$ select public.admin_moderate_review(((select v->>'review_id' from t where k = 'rv1'))::uuid, 'hidden', 'x') $$,
                 '42501', 'admin_required', 'Non-admin cannot moderate');
select pg_temp.login('10000000-0000-4000-8000-000000000004');
select lives_ok($$ select public.admin_moderate_review(((select v->>'review_id' from t where k = 'rv1'))::uuid, 'hidden', 'Spam confirmed') $$, 'Admin can hide a review');
select is((select count(*) from public.list_venue_reviews('20000000-0000-4000-8000-000000000001')), 0::bigint, 'Hidden review is not listed');
select ok((public.get_venue('20000000-0000-4000-8000-000000000001'))->'average_rating' = 'null'::jsonb, 'Hidden review is excluded from the summary');
select throws_ok($$ insert into public.moderation_actions (actor_id, action, target_type, target_id) values (auth.uid(), 'review_hidden', 'review', gen_random_uuid()) $$,
                 '42501', null, 'Audit rows cannot be inserted through the API');
reset role;
select throws_ok($$ update public.moderation_actions set reason = 'tampered' $$, '42501', null, 'Audit rows are append-only even for the owner role');

-- ---------------------------------------------------------------------------
-- Favorites isolation and business scope
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.login('10000000-0000-4000-8000-000000000003');
delete from public.favorites where venue_id = '20000000-0000-4000-8000-000000000001';
reset role;
select is((select count(*) from public.favorites where user_id = '10000000-0000-4000-8000-000000000001'), 1::bigint,
          'Another user cannot delete my favorite');

set local role authenticated;
select pg_temp.login('10000000-0000-4000-8000-000000000003');
insert into t values ('cl1', public.request_venue_claim(gen_random_uuid(), '20000000-0000-4000-8000-000000000002', 'Empty Cafe Co.'));
select ok(not private.can_manage_venue('20000000-0000-4000-8000-000000000002'), 'A pending claim grants nothing');
select pg_temp.login('10000000-0000-4000-8000-000000000004');
select is((public.admin_decide_venue_claim(((select v->>'claim_id' from t where k = 'cl1'))::uuid, true, 'Verified by phone'))->>'status',
          'approved', 'Admin approves a claim');
select ok(private.can_manage_venue('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000003'),
          'Approved claimant manages the venue');
select ok(not private.can_manage_venue('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002'),
          'Other users do not manage the venue');
select ok(not private.can_manage_venue('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000003'),
          'Membership is scoped to the business venues');

-- Admin revocation is immediate
reset role;
select private.revoke_admin('10000000-0000-4000-8000-000000000004');
set local role authenticated;
select pg_temp.login('10000000-0000-4000-8000-000000000004');
select throws_ok($$ select * from public.admin_list_venue_submissions() $$, '42501', 'admin_required', 'Revoked Admin loses access immediately');

select * from finish();
rollback;
