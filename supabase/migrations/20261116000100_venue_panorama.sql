-- 360° panoramas for venue detail.
-- A venue can have one or more equirectangular (2:1) 360° photos stored in the same bucket as venue photos.
-- They are added by the Nanglen team or a verified owner (same moderation path as venue photos) and marked
-- with kind = 'panorama_360'. They are excluded from the normal photo gallery and from the cover photo.

alter table public.venue_media
    add column if not exists kind text not null default 'photo'
    check (kind in ('photo', 'panorama_360'));

-- Cover photo: only regular photos, never a panorama.
create or replace function private.cover_path(p_venue uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
    select storage_path from public.venue_media
    where venue_id = p_venue and kind = 'photo'
    order by display_order, created_at limit 1;
$$;

-- Venue detail: same as before, plus `panorama_path`; `photo_paths` lists regular photos only.
create or replace function public.get_venue(p_venue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_uid    uuid := auth.uid();
    v_result jsonb;
begin
    select jsonb_build_object(
        'id', v.id,
        'name', v.name,
        'description', v.description,
        'category', v.category,
        'formatted_address', v.formatted_address,
        'latitude', v.latitude,
        'longitude', v.longitude,
        'status', v.status,
        'website_url', case when v.details_source is not null then v.website_url end,
        'phone_number', case when v.details_source is not null then v.phone_number end,
        'details_source', v.details_source,
        'apple_maps_id', (select r.external_place_id from public.venue_provider_refs r where r.venue_id = v.id and r.provider = 'apple_maps' limit 1),
        'review_count', coalesce(s.review_count, 0),
        'average_rating', s.average_rating,
        'rating_distribution', case when s.venue_id is null then null else jsonb_build_array(s.rating_1, s.rating_2, s.rating_3, s.rating_4, s.rating_5) end,
        'last_review_at', s.last_review_at,
        'tags', coalesce((select jsonb_agg(jsonb_build_object('slug', tc.tag_slug, 'count', tc.tag_count) order by tc.tag_count desc, tc.tag_slug)
                          from public.venue_tag_counts tc join public.review_tags rt on rt.slug = tc.tag_slug and rt.is_active
                          where tc.venue_id = v.id), '[]'::jsonb),
        'photo_paths', coalesce((select jsonb_agg(m.storage_path order by m.display_order, m.created_at) from public.venue_media m where m.venue_id = v.id and m.kind = 'photo'), '[]'::jsonb),
        'panorama_path', (select m.storage_path from public.venue_media m where m.venue_id = v.id and m.kind = 'panorama_360' order by m.display_order, m.created_at limit 1),
        'is_favorite', v_uid is not null and exists (select 1 from public.favorites f where f.user_id = v_uid and f.venue_id = v.id),
        'is_managed_by_me', v_uid is not null and private.can_manage_venue(v.id, v_uid),
        'my_review', (
            select jsonb_build_object(
                'review_id', r.id, 'status', r.status, 'rating', rv.rating, 'visit_purpose', rv.visit_purpose,
                'body', rv.body, 'revision_number', rv.revision_number, 'updated_at', rv.created_at,
                'tags', coalesce((select jsonb_agg(t.tag_slug order by t.tag_slug) from public.review_revision_tags t where t.revision_id = rv.id), '[]'::jsonb))
            from public.reviews r join public.review_revisions rv on rv.id = r.current_revision_id
            where r.venue_id = v.id and r.user_id = v_uid)
    )
    into v_result
    from public.venues v
    left join public.venue_rating_summaries s on s.venue_id = v.id
    where v.id = p_venue_id and v.status <> 'archived';

    if v_result is null then
        raise exception 'venue_not_found' using errcode = 'P0002';
    end if;
    return v_result;
end;
$$;
