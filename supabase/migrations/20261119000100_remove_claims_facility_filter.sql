-- Nanglen — 2026-11-19:
--   1. Claim Ownership is removed from the product: claim RPCs, the venue_claims table and its setting are dropped.
--      Business accounts / memberships stay (existing members keep access; Admins can still manage them with SQL).
--   2. "Good for" (facility) filters: no more "pick up to 3" — a search may use every active tag.
-- Irreversible for claim data: every row in public.venue_claims is deleted with the table.

-- ---------------------------------------------------------------------------
-- 1. Remove Claim Ownership
-- ---------------------------------------------------------------------------
drop function if exists public.request_venue_claim(uuid, uuid, text, public.membership_role, text, text);
drop function if exists public.admin_list_venue_claims(public.claim_status, integer);
drop function if exists public.admin_decide_venue_claim(uuid, boolean, text);

drop policy if exists venue_claims_owner_read on public.venue_claims;
drop table if exists public.venue_claims;
drop type if exists public.claim_status;

delete from private.app_settings where key = 'claims_max_open';

-- ---------------------------------------------------------------------------
-- 2. Facility ("Good for") filters: allow every active tag in one search
-- ---------------------------------------------------------------------------
update private.app_settings
set value = to_jsonb(greatest((select count(*) from public.review_tags where is_active), 1)),
    description = 'Maximum tag filters per search (= size of the active tag catalog: no practical limit)',
    updated_at = now()
where key = 'filter_max_tags';

-- The app reads this to size the "Good for" chips. get_public_config() is otherwise unchanged from 20261118000100.
create or replace function public.get_public_config()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select jsonb_build_object(
        'visit_radius_m', private.setting_numeric('visit_radius_m'),
        'visit_max_accuracy_m', private.setting_numeric('visit_max_accuracy_m'),
        'visit_max_location_age_s', private.setting_numeric('visit_max_location_age_s'),
        'review_body_max_chars', private.setting_numeric('review_body_max_chars'),
        'review_max_tags', private.setting_numeric('review_max_tags'),
        'review_max_photos', private.setting_numeric('review_max_photos'),
        'review_media_auto_approve', coalesce(private.setting_numeric('review_media_auto_approve'), 0) = 1,
        'submission_max_photos', private.setting_numeric('submission_max_photos'),
        'media_max_bytes', private.setting_numeric('media_max_bytes'),
        'filter_max_tags', private.setting_numeric('filter_max_tags'),
        'filter_distance_min_m', private.setting_numeric('filter_distance_min_m'),
        'filter_distance_max_m', private.setting_numeric('filter_distance_max_m'),
        'filter_distance_step_m', private.setting_numeric('filter_distance_step_m'),
        'filter_distance_default_m', private.setting_numeric('filter_distance_default_m'),
        'filter_rating_step', private.setting_numeric('filter_rating_step'));
$$;
