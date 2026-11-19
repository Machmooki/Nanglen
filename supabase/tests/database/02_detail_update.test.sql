-- pgTAP: 2026-11-18 detail update — public config, review photo limits, submission photo removal.
-- Run with `supabase test db`. Everything is rolled back at the end.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select * from no_plan();

-- ---------------------------------------------------------------------------
-- Fixtures (as postgres)
-- ---------------------------------------------------------------------------
insert into auth.users (id, aud, role, email, email_confirmed_at, is_anonymous, created_at, updated_at) values
    ('11000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', null,               null,  true,  now(), now()), -- guest
    ('11000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'own@example.test', now(), false, now(), now()), -- owner
    ('11000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'oth@example.test', now(), false, now(), now()), -- other user
    ('11000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'adm@example.test', now(), false, now(), now()); -- admin
select private.grant_admin('11000000-0000-4000-8000-000000000004', 'pgtap');

create temp table t (k text primary key, v jsonb);
grant all on t to authenticated, anon;

create function pg_temp.login(p_uid uuid, p_anon boolean default false) returns text language sql as $$
    select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'is_anonymous', p_anon)::text, true);
$$;

-- ---------------------------------------------------------------------------
-- Settings and public config
-- ---------------------------------------------------------------------------
select is(private.setting_numeric('review_max_photos'), 5::numeric, 'Reviews accept up to 5 photos');
select is(private.setting_numeric('review_max_tags'), (select count(*)::numeric from public.review_tags where is_active),
          'Tag limit equals the size of the active tag catalog');
select is((select count(*) from public.review_media where status = 'pending'), 0::bigint,
          'No review photo is left waiting for approval while auto-approve is on');
select ok((select pg_get_constraintdef(c.oid) like '%9%' from pg_constraint c where c.conname = 'review_media_display_order_check'),
          'review_media.display_order allows more than 3 photos');

set local role anon;
select is((public.get_public_config())->>'filter_distance_max_m', '20000', 'Config exposes the distance slider maximum');
select is((public.get_public_config())->>'filter_distance_default_m', '3000', 'Config exposes the default distance');
select is((public.get_public_config())->>'filter_rating_step', '0.5', 'Config exposes the rating step');
select is((public.get_public_config())->>'review_media_auto_approve', 'true', 'Config says review photos are post-moderated');
select is((public.get_public_config())->>'review_max_photos', '5', 'Config exposes the review photo limit');
select ok(not has_function_privilege('anon', 'public.remove_submission_media(uuid)', 'execute'), 'Anonymous API role cannot remove submission photos');
select ok(not has_function_privilege('anon', 'public.list_my_submission_media(uuid)', 'execute'), 'Anonymous API role cannot list submission photos');
reset role;

-- ---------------------------------------------------------------------------
-- Submission photos (rows inserted directly; uploads are covered by Storage policies)
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.login('11000000-0000-4000-8000-000000000002');
insert into t values ('sub', public.create_venue_submission(gen_random_uuid(), 'Photo Edit Cafe', 'cafe', 'Bangkok', 13.7600, 100.5600));
reset role;

insert into public.venue_submission_media (id, submission_id, uploaded_by, storage_path, mime_type, byte_size, display_order)
select ('40000000-0000-4000-8000-00000000000' || n)::uuid, (select (v->>'submission_id')::uuid from t where k = 'sub'),
       '11000000-0000-4000-8000-000000000002',
       (select v->>'submission_id' from t where k = 'sub') || '/' || gen_random_uuid() || '.jpg', 'image/jpeg', 1000, n - 1
from generate_series(1, 3) as n;

set local role authenticated;

-- Owner can list; others cannot.
select pg_temp.login('11000000-0000-4000-8000-000000000002');
select is((select count(*) from public.list_my_submission_media(((select v->>'submission_id' from t where k = 'sub'))::uuid)), 3::bigint,
          'Owner lists their submission photos');
select pg_temp.login('11000000-0000-4000-8000-000000000003');
select throws_ok($$ select * from public.list_my_submission_media(((select v->>'submission_id' from t where k = 'sub'))::uuid) $$,
                 'P0002', 'submission_not_found', 'Another user cannot list the photos');

-- Removal only while needs_changes.
select pg_temp.login('11000000-0000-4000-8000-000000000002');
select throws_ok($$ select public.remove_submission_media('40000000-0000-4000-8000-000000000002') $$,
                 '55000', 'invalid_status_transition', 'Owner cannot remove photos while the submission is pending review');

select pg_temp.login('11000000-0000-4000-8000-000000000004');
select lives_ok($$ select public.admin_request_submission_changes(((select v->>'submission_id' from t where k = 'sub'))::uuid, 'Add a clearer photo') $$,
                'Admin asks for changes');

select pg_temp.login('11000000-0000-4000-8000-000000000001', true);
select throws_ok($$ select public.remove_submission_media('40000000-0000-4000-8000-000000000002') $$,
                 '42501', 'registration_required', 'Guest cannot remove photos');

select pg_temp.login('11000000-0000-4000-8000-000000000003');
select throws_ok($$ select public.remove_submission_media('40000000-0000-4000-8000-000000000002') $$,
                 'P0002', 'media_not_found', 'Another user cannot remove the photo');

select pg_temp.login('11000000-0000-4000-8000-000000000002');
select ok(public.remove_submission_media('40000000-0000-4000-8000-000000000002') like '%.jpg',
          'Owner removes a photo during needs_changes and gets the storage path back');
select is((select array_agg(display_order::int order by display_order)
           from public.list_my_submission_media(((select v->>'submission_id' from t where k = 'sub'))::uuid)),
          array[0, 1], 'Remaining photos are renumbered without gaps');
select throws_ok($$ select public.remove_submission_media('40000000-0000-4000-8000-000000000002') $$,
                 'P0002', 'media_not_found', 'A removed photo cannot be removed twice');

select is((public.resubmit_venue_submission(((select v->>'submission_id' from t where k = 'sub'))::uuid, 'Photo Edit Cafe', 'cafe', 'Bangkok', 13.7600, 100.5600))->>'status',
          'pending_review', 'Owner resubmits after editing photos');
select throws_ok($$ select public.remove_submission_media('40000000-0000-4000-8000-000000000001') $$,
                 '55000', 'invalid_status_transition', 'Photos are locked again once resubmitted');

select * from finish();
rollback;
