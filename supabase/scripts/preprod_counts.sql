-- Pre-production: READ-ONLY counts of demo/test data. Safe to run any time.
--   supabase db query --remote --read-only -f supabase/scripts/preprod_counts.sql
-- Test-user rule: emails @demo.nanglen.app, @example.test, @example.com (add more in test_emails below).
with
test_emails(pattern) as (values ('%@demo.nanglen.app'), ('%@example.test'), ('%@example.com')),
demo_venues as (
    select v.id from public.venues v
    where v.id::text like '00000000-0000-4000-8000-0000000000__'
       or v.name ilike '%(Demo)' or v.name like '%(ตัวอย่าง)'
       or exists (select 1 from public.venue_provider_refs r
                  where r.venue_id = v.id and r.provider = 'curated' and r.external_place_id like 'seed:%')
),
test_users as (
    select u.id from auth.users u
    where exists (select 1 from test_emails t where u.email ilike t.pattern)
),
data_users as (  -- any user who owns something
    select user_id as id from public.favorites
    union select user_id from public.reviews
    union select submitted_by from public.venue_submissions
    union select user_id from public.business_memberships
    union select user_id from private.admin_users
    union select actor_id from public.moderation_actions
    union select id from public.profiles where avatar_path is not null
),
empty_anon_users as (
    select u.id from auth.users u
    where coalesce(u.is_anonymous, false) and not exists (select 1 from data_users d where d.id = u.id)
),
demo_reviews as (
    select r.id from public.reviews r
    where r.venue_id in (select id from demo_venues) or r.user_id in (select id from test_users)
),
demo_revisions as (select rv.id from public.review_revisions rv where rv.review_id in (select id from demo_reviews)),
demo_submissions as (
    select s.id from public.venue_submissions s
    where s.submitted_by in (select id from test_users)
       or s.approved_venue_id in (select id from demo_venues)
       or s.duplicate_of_venue_id in (select id from demo_venues)
),
demo_paths(bucket, name) as (
    select 'venue-submission-media', m.storage_path from public.venue_media m where m.venue_id in (select id from demo_venues)
    union select 'venue-submission-media', m.storage_path from public.venue_submission_media m where m.submission_id in (select id from demo_submissions)
    union select 'review-media', m.storage_path from public.review_media m where m.revision_id in (select id from demo_revisions)
    union select 'avatars', p.avatar_path from public.profiles p where p.id in (select id from test_users) and p.avatar_path is not null
    union select o.bucket_id, o.name from storage.objects o
          where o.bucket_id in ('venue-submission-media', 'review-media', 'avatars') and o.owner_id in (select id::text from test_users)
)
select 'venues (demo)' as item, count(*) as n from demo_venues
union all select 'venues curated_import NOT matched as demo (check!)', count(*) from public.venues v
    where v.provenance = 'curated_import' and v.id not in (select id from demo_venues)
union all select 'venues total', count(*) from public.venues
union all select 'venue_provider_refs', count(*) from public.venue_provider_refs where venue_id in (select id from demo_venues)
union all select 'venue_media', count(*) from public.venue_media where venue_id in (select id from demo_venues)
union all select 'reviews (demo venue or test user)', count(*) from demo_reviews
union all select 'review_revisions', count(*) from demo_revisions
union all select 'review_revision_tags', count(*) from public.review_revision_tags where revision_id in (select id from demo_revisions)
union all select 'review_media', count(*) from public.review_media where revision_id in (select id from demo_revisions)
union all select 'review_flags', count(*) from public.review_flags where review_id in (select id from demo_reviews) or flagged_by in (select id from test_users)
union all select 'favorites', count(*) from public.favorites where venue_id in (select id from demo_venues) or user_id in (select id from test_users)
union all select 'venue_submissions (test user or linked to demo venue)', count(*) from demo_submissions
union all select 'venue_submissions approved/duplicate -> demo venue (blocks venue delete)', count(*) from public.venue_submissions
    where approved_venue_id in (select id from demo_venues) or duplicate_of_venue_id in (select id from demo_venues)
union all select 'venue_submission_media', count(*) from public.venue_submission_media where submission_id in (select id from demo_submissions)
union all select 'venue_change_requests', count(*) from public.venue_change_requests where venue_id in (select id from demo_venues) or requested_by in (select id from test_users)
union all select 'business_memberships (test users)', count(*) from public.business_memberships where user_id in (select id from test_users)
union all select 'visit_challenges', count(*) from private.visit_challenges where venue_id in (select id from demo_venues) or user_id in (select id from test_users)
union all select 'visit_verifications', count(*) from private.visit_verifications where venue_id in (select id from demo_venues) or user_id in (select id from test_users)
union all select 'venue_rating_summaries rows (view, auto-updates)', count(*) from public.venue_rating_summaries where venue_id in (select id from demo_venues)
union all select 'venue_tag_counts rows (view, auto-updates)', count(*) from public.venue_tag_counts where venue_id in (select id from demo_venues)
union all select 'analytics_events (demo venues)', count(*) from private.analytics_events where venue_id in (select id from demo_venues)
union all select 'moderation_actions by test users (append-only, kept)', count(*) from public.moderation_actions where actor_id in (select id from test_users)
union all select 'admin_users (test users)', count(*) from private.admin_users where user_id in (select id from test_users)
union all select 'auth.users test emails', count(*) from test_users
union all select 'auth.users anonymous with no data', count(*) from empty_anon_users
union all select 'auth.users anonymous total', count(*) from auth.users where coalesce(is_anonymous, false)
union all select 'auth.users registered total', count(*) from auth.users where not coalesce(is_anonymous, false)
union all select 'storage objects tied to demo/test: ' || b, count(distinct d.name)
    from (values ('venue-submission-media'), ('review-media'), ('avatars')) as bk(b)
    left join demo_paths d on d.bucket = bk.b group by b
union all select 'storage objects total: ' || bucket_id, count(*) from storage.objects
    where bucket_id in ('venue-submission-media', 'review-media', 'avatars') group by bucket_id;
