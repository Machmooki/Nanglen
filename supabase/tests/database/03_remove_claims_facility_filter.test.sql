-- pgTAP: 2026-11-19 — Claim Ownership removed; facility ("Good for") filters have no 3-tag limit.
-- Run with `supabase test db`. Everything is rolled back at the end.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select * from no_plan();

select ok(to_regclass('public.venue_claims') is null, 'venue_claims table is gone');
select ok(to_regtype('public.claim_status') is null, 'claim_status type is gone');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('request_venue_claim', 'admin_list_venue_claims', 'admin_decide_venue_claim')),
          0::bigint, 'Claim RPCs are gone');
select is((select count(*) from private.app_settings where key = 'claims_max_open'), 0::bigint, 'Claim setting is gone');

select is(private.setting_numeric('filter_max_tags'), (select count(*)::numeric from public.review_tags where is_active),
          'Facility filter limit equals the active tag catalog');
set local role anon;
select is(((public.get_public_config())->>'filter_max_tags')::numeric, (select count(*)::numeric from public.review_tags where is_active),
          'Config sends the facility filter limit');
select lives_ok($$ select * from public.search_venues(p_tags => array['study_friendly', 'work_friendly', 'quiet', 'good_wifi',
                                                                    'power_outlets', 'comfortable_seating', 'good_lighting',
                                                                    'good_value', 'lively']) $$,
                'Searching with every "Good for" tag is allowed');
reset role;

select * from finish();
rollback;
