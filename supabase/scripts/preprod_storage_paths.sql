-- Pre-production: READ-ONLY list of Storage objects tied to demo venues / test users.
-- Run BEFORE preprod_cleanup.sql (the rows that reference these files are deleted by that script).
--   supabase db query --remote --read-only -f supabase/scripts/preprod_storage_paths.sql --output-format json > supabase/scripts/.preprod_paths.json
-- Then: deno run --allow-env --allow-net --allow-read supabase/scripts/preprod_storage_cleanup.ts supabase/scripts/.preprod_paths.json
-- Keep test_emails in sync with preprod_counts.sql / preprod_cleanup.sql.
with
test_emails(pattern) as (values ('%@demo.nanglen.app'), ('%@example.test'), ('%@example.com')),
demo_venues as (
    select v.id from public.venues v
    where v.id::text like '00000000-0000-4000-8000-0000000000__'
       or v.name ilike '%(Demo)' or v.name like '%(ตัวอย่าง)'
       or exists (select 1 from public.venue_provider_refs r
                  where r.venue_id = v.id and r.provider = 'curated' and r.external_place_id like 'seed:%')
),
test_users as (select u.id from auth.users u where exists (select 1 from test_emails t where u.email ilike t.pattern)),
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
paths(bucket, name) as (
    select 'venue-submission-media', m.storage_path from public.venue_media m where m.venue_id in (select id from demo_venues)
    union select 'venue-submission-media', m.storage_path from public.venue_submission_media m where m.submission_id in (select id from demo_submissions)
    union select 'review-media', m.storage_path from public.review_media m where m.revision_id in (select id from demo_revisions)
    union select 'avatars', p.avatar_path from public.profiles p where p.id in (select id from test_users) and p.avatar_path is not null
    union select o.bucket_id, o.name from storage.objects o
          where o.bucket_id in ('venue-submission-media', 'review-media', 'avatars') and o.owner_id in (select id::text from test_users)
)
-- Only objects that really exist (a row may point to a file that was never uploaded).
select p.bucket, p.name
from paths p
join storage.objects o on o.bucket_id = p.bucket and o.name = p.name
order by p.bucket, p.name;
