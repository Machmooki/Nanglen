-- Nanglen — 2026-11-18 detail update.
--   1. Remote config: every limit the app UI needs comes from private.app_settings via get_public_config().
--   2. Review photos: post-moderation (visible immediately, Admin can still reject), up to 5 per review,
--      no practical tag limit (= size of the tag catalog).
--   3. Submitters can list and remove their own submission photos while an Admin asks for changes.
-- Additive: safe on a database that already has every earlier migration.

-- ---------------------------------------------------------------------------
-- 1. Settings (edit values later in Table editor → private.app_settings, or SQL; apps pick them up on next launch)
-- ---------------------------------------------------------------------------
insert into private.app_settings (key, value, description) values
    ('filter_distance_min_m',     '500',   'Explore filter: smallest distance on the slider (m)'),
    ('filter_distance_max_m',     '20000', 'Explore filter: largest distance on the slider (m). search_venues accepts up to 50000'),
    ('filter_distance_step_m',    '500',   'Explore filter: slider step (m)'),
    ('filter_distance_default_m', '3000',  'Explore filter: default distance (m), also used by Reset'),
    ('filter_rating_step',        '0.5',   'Explore filter: minimum-rating step (0.5 = half stars, 1 = whole stars)'),
    ('review_media_auto_approve', '1',     '1 = review photos are public right away (post-moderation, Admin can reject later); 0 = held until an Admin approves')
on conflict (key) do nothing;

update private.app_settings set value = '5', updated_at = now()
where key = 'review_max_photos';

-- "Pick up to 3" is gone: a reviewer may choose every active tag.
update private.app_settings
set value = to_jsonb(greatest((select count(*) from public.review_tags where is_active), 1)), updated_at = now()
where key = 'review_max_tags';

-- review_media.display_order was capped at 0..2 (3 photos). Allow up to 10 so the limit lives in settings only.
alter table public.review_media drop constraint if exists review_media_display_order_check;
alter table public.review_media add constraint review_media_display_order_check check (display_order between 0 and 9);

-- ---------------------------------------------------------------------------
-- 2. Public config: everything the client UI needs. The server stays authoritative for every check.
-- ---------------------------------------------------------------------------
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
        'filter_distance_min_m', private.setting_numeric('filter_distance_min_m'),
        'filter_distance_max_m', private.setting_numeric('filter_distance_max_m'),
        'filter_distance_step_m', private.setting_numeric('filter_distance_step_m'),
        'filter_distance_default_m', private.setting_numeric('filter_distance_default_m'),
        'filter_rating_step', private.setting_numeric('filter_rating_step'));
$$;

-- Note: search_venues clamps p_radius_m to 100 m–50 km. That already covers filter_distance_max_m (20 km), and the
-- wider bound is still needed for map-area searches, so search_venues is intentionally left unchanged.

-- ---------------------------------------------------------------------------
-- 3. Review photos: post-moderation
-- ---------------------------------------------------------------------------
create or replace function public.attach_review_media(
    p_revision_id uuid, p_storage_path text, p_mime_type text, p_byte_size integer,
    p_width integer default null, p_height integer default null)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_uid    uuid := private.require_registered();
    v_count  integer;
    v_id     uuid;
    v_status public.media_status := case when coalesce(private.setting_numeric('review_media_auto_approve'), 0) = 1
                                         then 'approved' else 'pending' end;
begin
    if not exists (
        select 1 from public.review_revisions rv join public.reviews r on r.id = rv.review_id
        where rv.id = p_revision_id and rv.user_id = v_uid and r.current_revision_id = rv.id) then
        raise exception 'revision_not_found' using errcode = 'P0002';
    end if;
    if not private.valid_media_path(p_storage_path, v_uid, p_revision_id) then
        raise exception 'invalid_storage_path' using errcode = '22023';
    end if;
    if p_byte_size is null or p_byte_size <= 0 or p_byte_size > private.setting_numeric('media_max_bytes') then
        raise exception 'file_too_large' using errcode = '22023';
    end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'review-media' and o.name = p_storage_path) then
        raise exception 'object_not_uploaded' using errcode = 'P0002';
    end if;
    select count(*) into v_count from public.review_media m where m.revision_id = p_revision_id;
    if v_count >= private.setting_numeric('review_max_photos') then
        raise exception 'too_many_photos' using errcode = '22023';
    end if;
    insert into public.review_media (revision_id, uploaded_by, storage_path, mime_type, byte_size, width, height, display_order, status)
    values (p_revision_id, v_uid, p_storage_path, p_mime_type, p_byte_size, p_width, p_height, v_count, v_status)
    on conflict (storage_path) do nothing
    returning id into v_id;
    if v_id is null then
        select m.id into v_id from public.review_media m where m.storage_path = p_storage_path and m.uploaded_by = v_uid;
    end if;
    return v_id;
end;
$$;

-- Photos stuck in 'pending' (there was no in-app approval screen) become visible now.
-- Admins can still hide any of them with admin_set_review_media_status(..., 'rejected').
update public.review_media set status = 'approved'
where status = 'pending'
  and coalesce(private.setting_numeric('review_media_auto_approve'), 0) = 1;

-- ---------------------------------------------------------------------------
-- 4. Submission photos while an Admin asks for changes
-- ---------------------------------------------------------------------------

-- The caller's own photos for one of their submissions (any status: it is their own data).
create function public.list_my_submission_media(p_submission_id uuid)
returns table (media_id uuid, storage_path text, display_order smallint, status public.media_status, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_uid uuid := auth.uid();
begin
    if v_uid is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    if not exists (select 1 from public.venue_submissions s where s.id = p_submission_id and s.submitted_by = v_uid) then
        raise exception 'submission_not_found' using errcode = 'P0002';
    end if;
    return query
    select m.id, m.storage_path, m.display_order, m.status, m.created_at
    from public.venue_submission_media m
    where m.submission_id = p_submission_id
    order by m.display_order, m.created_at;
end;
$$;

-- Removes one photo from the caller's submission while it is in needs_changes, then renumbers display_order.
-- Returns the storage path; the client deletes the object through the Storage API (policy
-- "submission media: owner deletes while submission is open"). Direct deletes from storage.objects are blocked.
create function public.remove_submission_media(p_media_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_uid    uuid := private.require_registered();
    v_sub    uuid;
    v_status public.submission_status;
    v_path   text;
begin
    select m.submission_id, s.status, m.storage_path into v_sub, v_status, v_path
    from public.venue_submission_media m
    join public.venue_submissions s on s.id = m.submission_id
    where m.id = p_media_id and s.submitted_by = v_uid
    for update of m, s;
    if not found then
        raise exception 'media_not_found' using errcode = 'P0002';
    end if;
    if v_status <> 'needs_changes' then
        raise exception 'invalid_status_transition' using errcode = '55000';
    end if;

    delete from public.venue_submission_media where id = p_media_id;

    with ordered as (
        select m.id, (row_number() over (order by m.display_order, m.created_at) - 1)::smallint as position
        from public.venue_submission_media m
        where m.submission_id = v_sub
    )
    update public.venue_submission_media m
    set display_order = o.position
    from ordered o
    where m.id = o.id and m.display_order <> o.position;

    return v_path;
end;
$$;

revoke all on function public.list_my_submission_media(uuid) from public, anon;
revoke all on function public.remove_submission_media(uuid) from public, anon;
grant execute on function public.list_my_submission_media(uuid) to authenticated;
grant execute on function public.remove_submission_media(uuid) to authenticated;
