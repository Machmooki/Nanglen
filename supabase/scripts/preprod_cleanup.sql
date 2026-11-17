-- =====================================================================================================
-- Pre-production cleanup: remove demo venues and test users from the REAL database.
-- NOT a migration. Never put this in supabase/migrations.
--
-- ⚠️  1. BACK UP FIRST:   supabase db dump --linked --data-only -f backup_preprod.sql
--                          (keep the file outside git; it contains user data)
-- ⚠️  2. STORAGE FIRST:   run preprod_storage_paths.sql + preprod_storage_cleanup.ts BEFORE this script,
--                          because the rows deleted here are what point to those files.
-- ⚠️  3. DRY RUN BY DEFAULT: the script ends with ROLLBACK. Read the "before" and "after" counts.
--                          Only when they look right, change the last line to COMMIT and run again.
--
--   supabase db query --remote -f supabase/scripts/preprod_cleanup.sql
--
-- What it relies on (verified against the live schema on 2026-11-16):
--   venues -> provider_refs, venue_media, reviews, favorites, claims, change_requests,
--             visit_challenges, visit_verifications : ON DELETE CASCADE
--   reviews -> review_revisions -> review_revision_tags, review_media : CASCADE; review_flags : CASCADE
--   venue_submissions.approved_venue_id / duplicate_of_venue_id : SET NULL — but a CHECK requires them for
--             status approved/duplicate, so those submissions are deleted BEFORE their venues (step 2).
--   auth.users -> profiles, favorites, reviews, submissions, claims, memberships, admin_users, visits : CASCADE
--   moderation_actions.actor_id : NO ACTION and the table is append-only → test users that appear in the
--             audit trail are NOT deleted (reported in the "skipped" row). The audit trail is never edited.
--   venue_rating_summaries / venue_tag_counts are plain views → nothing to refresh.
-- =====================================================================================================
begin;

-- Keep these rules in sync with preprod_counts.sql and preprod_storage_paths.sql.
create temp table _test_emails(pattern text) on commit drop;
insert into _test_emails values ('%@demo.nanglen.app'), ('%@example.test'), ('%@example.com');

create temp table _demo_venues on commit drop as
select v.id from public.venues v
where v.id::text like '00000000-0000-4000-8000-0000000000__'
   or v.name ilike '%(Demo)' or v.name like '%(ตัวอย่าง)'
   or exists (select 1 from public.venue_provider_refs r
              where r.venue_id = v.id and r.provider = 'curated' and r.external_place_id like 'seed:%');

create temp table _test_users on commit drop as
select u.id from auth.users u where exists (select 1 from _test_emails t where u.email ilike t.pattern);

create temp table _data_users on commit drop as
select user_id as id from public.favorites
union select user_id from public.reviews
union select submitted_by from public.venue_submissions
union select requested_by from public.venue_claims
union select user_id from public.business_memberships
union select user_id from private.admin_users
union select actor_id from public.moderation_actions
union select id from public.profiles where avatar_path is not null;

create temp table _empty_anon_users on commit drop as
select u.id from auth.users u
where coalesce(u.is_anonymous, false) and u.id not in (select id from _data_users);

create temp table _audited_test_users on commit drop as
select distinct a.actor_id as id from public.moderation_actions a where a.actor_id in (select id from _test_users);

create temp view _counts as
select 'venues (demo)' as item, (select count(*) from public.venues where id in (select id from _demo_venues)) as n
union all select 'reviews on demo venues or by test users', (select count(*) from public.reviews where venue_id in (select id from _demo_venues) or user_id in (select id from _test_users))
union all select 'favorites', (select count(*) from public.favorites where venue_id in (select id from _demo_venues) or user_id in (select id from _test_users))
union all select 'venue_submissions', (select count(*) from public.venue_submissions where submitted_by in (select id from _test_users) or approved_venue_id in (select id from _demo_venues) or duplicate_of_venue_id in (select id from _demo_venues))
union all select 'venue_claims', (select count(*) from public.venue_claims where venue_id in (select id from _demo_venues) or requested_by in (select id from _test_users))
union all select 'visit_verifications', (select count(*) from private.visit_verifications where venue_id in (select id from _demo_venues) or user_id in (select id from _test_users))
union all select 'analytics_events (demo venues)', (select count(*) from private.analytics_events where venue_id in (select id from _demo_venues))
union all select 'auth.users test (deletable)', (select count(*) from auth.users where id in (select id from _test_users) and id not in (select id from _audited_test_users))
union all select 'auth.users test SKIPPED (in audit trail)', (select count(*) from _audited_test_users)
union all select 'auth.users anonymous with no data', (select count(*) from auth.users where id in (select id from _empty_anon_users));

select 'BEFORE' as phase, * from _counts;

-- 1. Analytics rows for demo venues (no FK; delete explicitly).
delete from private.analytics_events where venue_id in (select id from _demo_venues);

-- 2. Submissions that point at demo venues or were made by test users (their media rows cascade).
--    Must run before step 3 because of the approved/duplicate CHECK constraints.
delete from public.venue_submissions
where submitted_by in (select id from _test_users)
   or approved_venue_id in (select id from _demo_venues)
   or duplicate_of_venue_id in (select id from _demo_venues);

-- 3. Demo venues (cascades: provider refs, venue media, reviews → revisions → tags/media/flags,
--    favorites, claims, change requests, visit challenges/verifications).
delete from public.venues where id in (select id from _demo_venues);

-- 4. Test users that are not part of the audit trail (cascades their remaining personal rows).
--    Their Storage files must already be gone (step ⚠️ 2).
delete from auth.users where id in (select id from _test_users) and id not in (select id from _audited_test_users);

-- 5. Anonymous users with no data at all (stale guest sessions).
delete from auth.users where id in (select id from _empty_anon_users);

select 'AFTER' as phase, * from _counts;   -- every row except "SKIPPED" must be 0

-- Change to COMMIT only after reviewing the BEFORE/AFTER output of a dry run.
rollback;
