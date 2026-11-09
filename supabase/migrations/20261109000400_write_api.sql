-- Nanglen v2 — 0004: trusted write API (SECURITY DEFINER, fixed search_path, identity from auth.uid()).
-- Every function validates its caller; no function accepts user_id / is_admin / is_verified / status from the client.

-- ---------------------------------------------------------------------------
-- Visit verification
-- ---------------------------------------------------------------------------
create function public.issue_visit_challenge(p_venue_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_uid       uuid := private.require_registered();
    v_challenge private.visit_challenges;
begin
    if not exists (select 1 from public.venues v where v.id = p_venue_id and v.status in ('active', 'temporarily_closed')) then
        raise exception 'venue_not_reviewable' using errcode = 'P0002';
    end if;
    if (select count(*) from private.visit_challenges c
        where c.user_id = v_uid and c.issued_at > now() - interval '10 minutes')
       >= private.setting_numeric('visit_challenges_per_10min') then
        raise exception 'rate_limited' using errcode = '53400';
    end if;

    insert into private.visit_challenges (user_id, venue_id, expires_at)
    values (v_uid, p_venue_id, now() + make_interval(secs => private.setting_numeric('visit_challenge_ttl_s')::double precision))
    returning * into v_challenge;

    return jsonb_build_object(
        'challenge_id', v_challenge.id,
        'issued_at', v_challenge.issued_at,
        'expires_at', v_challenge.expires_at,
        'radius_m', private.setting_numeric('visit_radius_m'),
        'max_accuracy_m', private.setting_numeric('visit_max_accuracy_m'),
        'max_location_age_s', private.setting_numeric('visit_max_location_age_s'));
end;
$$;

-- Evaluates ONE location reading against ONE challenge. The challenge is consumed by any evaluated
-- attempt (success or failure); a retry needs a new challenge. Raw coordinates are not stored.
create function public.verify_visit(
    p_challenge_id        uuid,
    p_latitude            double precision,
    p_longitude           double precision,
    p_horizontal_accuracy double precision,
    p_location_timestamp  timestamptz
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_uid       uuid := private.require_registered();
    v_challenge private.visit_challenges;
    v_venue     public.venues;
    v_status    public.verification_status;
    v_distance  double precision;
    v_skew      interval := make_interval(secs => private.setting_numeric('visit_clock_skew_s')::double precision);
    v_row       private.visit_verifications;
begin
    select * into v_challenge from private.visit_challenges c
    where c.id = p_challenge_id and c.user_id = v_uid
    for update;
    if not found then
        raise exception 'challenge_not_found' using errcode = 'P0002';
    end if;
    if v_challenge.consumed_at is not null then
        raise exception 'challenge_consumed' using errcode = '55000';
    end if;
    if v_challenge.expires_at <= now() then
        raise exception 'challenge_expired' using errcode = '55000';
    end if;

    update private.visit_challenges set consumed_at = now() where id = v_challenge.id;
    select * into v_venue from public.venues v where v.id = v_challenge.venue_id;

    if p_latitude is null or p_longitude is null or p_location_timestamp is null
       or p_latitude not between -90 and 90 or p_longitude not between -180 and 180
       or p_horizontal_accuracy is null or p_horizontal_accuracy < 0
       or v_venue.status not in ('active', 'temporarily_closed') then
        v_status := 'invalid';
    elsif p_location_timestamp > now() + v_skew then
        v_status := 'invalid';
    elsif p_location_timestamp < v_challenge.issued_at - v_skew
       or now() - p_location_timestamp > make_interval(secs => private.setting_numeric('visit_max_location_age_s')::double precision) then
        v_status := 'stale';
    elsif p_horizontal_accuracy > private.setting_numeric('visit_max_accuracy_m') then
        v_status := 'inaccurate';
    else
        v_distance := extensions.st_distance(
            v_venue.location,
            extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326)::extensions.geography);
        if v_distance > private.setting_numeric('visit_radius_m') then
            v_status := 'too_far';
        else
            v_status := 'verified';
        end if;
    end if;

    if v_distance is null and v_status in ('stale', 'inaccurate') and v_venue.id is not null
       and p_latitude between -90 and 90 and p_longitude between -180 and 180 then
        v_distance := extensions.st_distance(
            v_venue.location,
            extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326)::extensions.geography);
    end if;

    insert into private.visit_verifications (challenge_id, user_id, venue_id, status, distance_bucket, accuracy_bucket, expires_at)
    values (v_challenge.id, v_uid, v_challenge.venue_id, v_status,
            private.distance_bucket(v_distance), private.accuracy_bucket(p_horizontal_accuracy),
            now() + make_interval(secs => private.setting_numeric('visit_verification_ttl_s')::double precision))
    returning * into v_row;

    return jsonb_build_object(
        'verification_id', case when v_status = 'verified' then v_row.id end,
        'status', v_status,
        'distance_bucket', v_row.distance_bucket,
        'accuracy_bucket', v_row.accuracy_bucket,
        'expires_at', case when v_status = 'verified' then v_row.expires_at end);
end;
$$;

-- ---------------------------------------------------------------------------
-- Review submission: create the review or a new revision; consume the verification atomically.
-- ---------------------------------------------------------------------------
create function public.submit_review(
    p_venue_id         uuid,
    p_verification_id  uuid,
    p_rating           integer,
    p_visit_purpose    public.visit_purpose default null,
    p_tags             text[] default '{}',
    p_body             text default null,
    p_idempotency_key  uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_uid          uuid := private.require_registered();
    v_existing     public.review_revisions;
    v_verification private.visit_verifications;
    v_review       public.reviews;
    v_revision     public.review_revisions;
    v_body         text := nullif(btrim(coalesce(p_body, '')), '');
    v_tags         text[];
    v_number       integer;
    v_created      boolean;
begin
    if p_idempotency_key is null then
        raise exception 'idempotency_key_required' using errcode = '22023';
    end if;

    -- Idempotent replay: same key returns the original result without consuming anything else.
    select * into v_existing from public.review_revisions rv where rv.user_id = v_uid and rv.idempotency_key = p_idempotency_key;
    if found then
        select * into v_review from public.reviews r where r.id = v_existing.review_id;
        if v_review.venue_id <> p_venue_id then
            raise exception 'idempotency_conflict' using errcode = '23505';
        end if;
        return jsonb_build_object('review_id', v_review.id, 'revision_id', v_existing.id,
                                  'revision_number', v_existing.revision_number, 'status', v_review.status, 'replayed', true);
    end if;

    if p_rating is null or p_rating not between 1 and 5 then
        raise exception 'invalid_rating' using errcode = '22023';
    end if;
    if v_body is not null and char_length(v_body) > private.setting_numeric('review_body_max_chars') then
        raise exception 'body_too_long' using errcode = '22001';
    end if;
    select coalesce(array_agg(distinct t), '{}') into v_tags from unnest(coalesce(p_tags, '{}')) as t where t is not null;
    if coalesce(array_length(v_tags, 1), 0) > private.setting_numeric('review_max_tags') then
        raise exception 'too_many_tags' using errcode = '22023';
    end if;
    if exists (select 1 from unnest(v_tags) t where not exists (select 1 from public.review_tags rt where rt.slug = t and rt.is_active)) then
        raise exception 'unknown_tag' using errcode = '22023';
    end if;

    select * into v_verification from private.visit_verifications vv where vv.id = p_verification_id for update;
    if not found or v_verification.user_id <> v_uid or v_verification.venue_id <> p_venue_id then
        raise exception 'verification_invalid' using errcode = '42501';
    end if;
    if v_verification.status <> 'verified' then
        raise exception 'verification_invalid' using errcode = '42501';
    end if;
    if v_verification.consumed_at is not null then
        raise exception 'verification_consumed' using errcode = '55000';
    end if;
    if v_verification.expires_at <= now() then
        raise exception 'verification_expired' using errcode = '55000';
    end if;
    if not exists (select 1 from public.venues v where v.id = p_venue_id and v.status in ('active', 'temporarily_closed')) then
        raise exception 'venue_not_reviewable' using errcode = 'P0002';
    end if;

    -- One current review per (venue, user). The upsert locks the row for revision numbering.
    insert into public.reviews (venue_id, user_id) values (p_venue_id, v_uid)
    on conflict (venue_id, user_id) do update set updated_at = now()
    returning reviews.id, reviews.status, (reviews.xmax = 0) into v_review.id, v_review.status, v_created;
    if v_review.status = 'removed' then
        raise exception 'review_removed' using errcode = '42501';
    end if;

    select coalesce(max(rv.revision_number), 0) + 1 into v_number from public.review_revisions rv where rv.review_id = v_review.id;

    insert into public.review_revisions (review_id, user_id, revision_number, visit_verification_id, rating, visit_purpose, body, idempotency_key)
    values (v_review.id, v_uid, v_number, v_verification.id, p_rating::smallint, p_visit_purpose, v_body, p_idempotency_key)
    returning * into v_revision;

    insert into public.review_revision_tags (revision_id, tag_slug)
    select v_revision.id, t from unnest(v_tags) t;

    update public.reviews set current_revision_id = v_revision.id where id = v_review.id;
    update private.visit_verifications set consumed_at = now() where id = v_verification.id;

    insert into private.analytics_events (event_name, venue_id, properties)
    values ('review_submitted', p_venue_id, jsonb_build_object('revision', v_number, 'has_body', v_body is not null, 'tag_count', coalesce(array_length(v_tags, 1), 0)));

    return jsonb_build_object('review_id', v_review.id, 'revision_id', v_revision.id,
                              'revision_number', v_number, 'status', v_review.status, 'created', v_created, 'replayed', false);
end;
$$;

-- Storage path validation shared by media attach functions: '<uid>/<parent uuid>/<uuid>.<ext>'
create function private.valid_media_path(p_path text, p_uid uuid, p_parent uuid)
returns boolean
language sql
immutable
set search_path = ''
as $$
    select p_path ~ ('^' || p_uid::text || '/' || p_parent::text || '/[0-9a-f-]{36}\.(jpg|jpeg|png|heic|webp)$');
$$;

create function public.attach_review_media(
    p_revision_id uuid, p_storage_path text, p_mime_type text, p_byte_size integer,
    p_width integer default null, p_height integer default null)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_uid   uuid := private.require_registered();
    v_count integer;
    v_id    uuid;
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
    insert into public.review_media (revision_id, uploaded_by, storage_path, mime_type, byte_size, width, height, display_order)
    values (p_revision_id, v_uid, p_storage_path, p_mime_type, p_byte_size, p_width, p_height, v_count)
    on conflict (storage_path) do nothing
    returning id into v_id;
    if v_id is null then
        select m.id into v_id from public.review_media m where m.storage_path = p_storage_path and m.uploaded_by = v_uid;
    end if;
    return v_id;
end;
$$;

create function public.flag_review(p_review_id uuid, p_reason public.flag_reason, p_note text default null)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_uid uuid := private.require_registered();
begin
    if not exists (select 1 from public.reviews r where r.id = p_review_id and r.status = 'published') then
        raise exception 'review_not_found' using errcode = 'P0002';
    end if;
    if exists (select 1 from public.reviews r where r.id = p_review_id and r.user_id = v_uid) then
        raise exception 'cannot_flag_own_review' using errcode = '22023';
    end if;
    insert into public.review_flags (review_id, flagged_by, reason, note)
    values (p_review_id, v_uid, p_reason, nullif(left(btrim(coalesce(p_note, '')), 300), ''))
    on conflict (review_id, flagged_by) do nothing;
end;
$$;

-- ---------------------------------------------------------------------------
-- Venue submissions (never inserted into public.venues by users)
-- ---------------------------------------------------------------------------
create function private.duplicate_candidates(
    p_name text, p_location extensions.geography, p_provider text, p_external_id text, p_limit integer default 5)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce(jsonb_agg(c order by (c->>'score')::double precision desc), '[]'::jsonb)
    from (
        select jsonb_build_object(
            'venue_id', v.id, 'name', v.name, 'formatted_address', v.formatted_address, 'category', v.category,
            'distance_m', round(extensions.st_distance(v.location, p_location)::numeric, 1),
            'name_similarity', round(extensions.similarity(v.normalized_name, private.normalize_name(p_name))::numeric, 2),
            'provider_match', p_external_id is not null and exists (
                select 1 from public.venue_provider_refs r where r.venue_id = v.id and r.provider = p_provider and r.external_place_id = p_external_id),
            'score', extensions.similarity(v.normalized_name, private.normalize_name(p_name))
                     + greatest(0, 1 - extensions.st_distance(v.location, p_location) / private.setting_numeric('duplicate_radius_m')::double precision)
        ) as c
        from public.venues v
        where v.status <> 'archived'
          and (extensions.st_dwithin(v.location, p_location, private.setting_numeric('duplicate_radius_m')::double precision)
               or (p_external_id is not null and exists (
                    select 1 from public.venue_provider_refs r where r.venue_id = v.id and r.provider = p_provider and r.external_place_id = p_external_id)))
        order by extensions.similarity(v.normalized_name, private.normalize_name(p_name)) desc
        limit p_limit
    ) s;
$$;

create function private.validate_submission_fields(
    p_name text, p_latitude double precision, p_longitude double precision, p_website_url text)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
    if p_name is null or char_length(btrim(p_name)) = 0 then
        raise exception 'name_required' using errcode = '22023';
    end if;
    if p_latitude is null or p_longitude is null or p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
        raise exception 'invalid_coordinate' using errcode = '22023';
    end if;
    if p_website_url is not null and p_website_url !~* '^https?://' then
        raise exception 'invalid_website_url' using errcode = '22023';
    end if;
end;
$$;

create function public.create_venue_submission(
    p_client_request_id  uuid,
    p_name               text,
    p_category           public.venue_category,
    p_formatted_address  text,
    p_latitude           double precision,
    p_longitude          double precision,
    p_provider           text default null,
    p_external_place_id  text default null,
    p_description        text default null,
    p_website_url        text default null,
    p_phone_number       text default null,
    p_submitter_note     text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_uid       uuid := private.require_registered();
    v_row       public.venue_submissions;
    v_location  extensions.geography;
    v_existing  uuid;
    v_provider  text := case when nullif(btrim(coalesce(p_external_place_id, '')), '') is null then null else coalesce(p_provider, 'other') end;
    v_ext       text := nullif(btrim(coalesce(p_external_place_id, '')), '');
    v_website   text := nullif(btrim(coalesce(p_website_url, '')), '');
begin
    if p_client_request_id is null then
        raise exception 'idempotency_key_required' using errcode = '22023';
    end if;
    select * into v_row from public.venue_submissions s where s.submitted_by = v_uid and s.client_request_id = p_client_request_id;
    if found then
        return jsonb_build_object('submission_id', v_row.id, 'status', v_row.status, 'replayed', true,
                                  'duplicate_candidates', private.duplicate_candidates(v_row.name, v_row.location, v_row.provider, v_row.external_place_id));
    end if;

    perform private.validate_submission_fields(p_name, p_latitude, p_longitude, v_website);
    v_location := extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326)::extensions.geography;

    -- An exact provider match is certain: link the user to the existing approved venue instead of queuing.
    if v_ext is not null then
        select r.venue_id into v_existing from public.venue_provider_refs r
        join public.venues v on v.id = r.venue_id and v.status <> 'archived'
        where r.provider = v_provider and r.external_place_id = v_ext;
        if v_existing is not null then
            return jsonb_build_object('submission_id', null, 'status', 'already_listed', 'existing_venue_id', v_existing, 'replayed', false,
                                      'duplicate_candidates', '[]'::jsonb);
        end if;
    end if;

    if (select count(*) from public.venue_submissions s where s.submitted_by = v_uid and s.status in ('pending_review', 'needs_changes'))
       >= private.setting_numeric('submission_max_open') then
        raise exception 'too_many_open_submissions' using errcode = '53400';
    end if;

    insert into public.venue_submissions (
        submitted_by, client_request_id, name, category, formatted_address, location, provider, external_place_id,
        description, website_url, phone_number, submitter_note, status, submitted_at)
    values (
        v_uid, p_client_request_id, btrim(p_name), p_category, nullif(btrim(coalesce(p_formatted_address, '')), ''), v_location,
        v_provider, v_ext, nullif(btrim(coalesce(p_description, '')), ''), v_website,
        nullif(btrim(coalesce(p_phone_number, '')), ''), nullif(btrim(coalesce(p_submitter_note, '')), ''),
        'pending_review', now())
    returning * into v_row;

    insert into private.analytics_events (event_name, properties) values ('venue_submission_submitted', jsonb_build_object('category', p_category));

    return jsonb_build_object('submission_id', v_row.id, 'status', v_row.status, 'replayed', false,
                              'duplicate_candidates', private.duplicate_candidates(v_row.name, v_row.location, v_row.provider, v_row.external_place_id));
end;
$$;

create function public.resubmit_venue_submission(
    p_submission_id      uuid,
    p_name               text,
    p_category           public.venue_category,
    p_formatted_address  text,
    p_latitude           double precision,
    p_longitude          double precision,
    p_description        text default null,
    p_website_url        text default null,
    p_phone_number       text default null,
    p_submitter_note     text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_uid     uuid := private.require_registered();
    v_row     public.venue_submissions;
    v_website text := nullif(btrim(coalesce(p_website_url, '')), '');
begin
    select * into v_row from public.venue_submissions s where s.id = p_submission_id and s.submitted_by = v_uid for update;
    if not found then
        raise exception 'submission_not_found' using errcode = 'P0002';
    end if;
    if v_row.status <> 'needs_changes' then
        raise exception 'invalid_status_transition' using errcode = '55000';
    end if;
    perform private.validate_submission_fields(p_name, p_latitude, p_longitude, v_website);

    update public.venue_submissions set
        name = btrim(p_name), category = p_category,
        formatted_address = nullif(btrim(coalesce(p_formatted_address, '')), ''),
        location = extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326)::extensions.geography,
        description = nullif(btrim(coalesce(p_description, '')), ''), website_url = v_website,
        phone_number = nullif(btrim(coalesce(p_phone_number, '')), ''),
        submitter_note = nullif(btrim(coalesce(p_submitter_note, '')), ''),
        status = 'pending_review', revision = revision + 1, submitted_at = now(), decision_reason = null
    where id = v_row.id
    returning * into v_row;

    return jsonb_build_object('submission_id', v_row.id, 'status', v_row.status, 'revision', v_row.revision);
end;
$$;

create function public.withdraw_venue_submission(p_submission_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_uid uuid := auth.uid();
begin
    update public.venue_submissions s set status = 'withdrawn'
    where s.id = p_submission_id and s.submitted_by = v_uid and s.status in ('pending_review', 'needs_changes');
    if not found then
        raise exception 'invalid_status_transition' using errcode = '55000';
    end if;
end;
$$;

create function public.attach_submission_media(
    p_submission_id uuid, p_storage_path text, p_mime_type text, p_byte_size integer,
    p_width integer default null, p_height integer default null)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_uid   uuid := private.require_registered();
    v_count integer;
    v_id    uuid;
begin
    if not exists (select 1 from public.venue_submissions s
                   where s.id = p_submission_id and s.submitted_by = v_uid and s.status in ('pending_review', 'needs_changes')) then
        raise exception 'submission_not_found' using errcode = 'P0002';
    end if;
    if not private.valid_media_path(p_storage_path, v_uid, p_submission_id) then
        raise exception 'invalid_storage_path' using errcode = '22023';
    end if;
    if p_byte_size is null or p_byte_size <= 0 or p_byte_size > private.setting_numeric('media_max_bytes') then
        raise exception 'file_too_large' using errcode = '22023';
    end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'venue-submission-media' and o.name = p_storage_path) then
        raise exception 'object_not_uploaded' using errcode = 'P0002';
    end if;
    select count(*) into v_count from public.venue_submission_media m where m.submission_id = p_submission_id;
    if v_count >= private.setting_numeric('submission_max_photos') then
        raise exception 'too_many_photos' using errcode = '22023';
    end if;
    insert into public.venue_submission_media (submission_id, uploaded_by, storage_path, mime_type, byte_size, width, height, display_order)
    values (p_submission_id, v_uid, p_storage_path, p_mime_type, p_byte_size, p_width, p_height, v_count)
    on conflict (storage_path) do nothing
    returning id into v_id;
    return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Profiles, claims, analytics
-- ---------------------------------------------------------------------------
create function public.update_my_display_name(p_display_name text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_uid  uuid := private.require_registered();
    v_name text := btrim(coalesce(p_display_name, ''));
begin
    if char_length(v_name) not between 1 and 40 then
        raise exception 'invalid_display_name' using errcode = '22023';
    end if;
    update public.profiles set display_name = v_name where id = v_uid;
end;
$$;

create function public.request_venue_claim(
    p_client_request_id uuid,
    p_venue_id          uuid,
    p_business_name     text,
    p_claimant_role     public.membership_role default 'owner',
    p_contact_note      text default null,
    p_evidence_note     text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_uid uuid := private.require_registered();
    v_row public.venue_claims;
begin
    select * into v_row from public.venue_claims c where c.requested_by = v_uid and c.client_request_id = p_client_request_id;
    if found then
        return jsonb_build_object('claim_id', v_row.id, 'status', v_row.status, 'replayed', true);
    end if;
    if not exists (select 1 from public.venues v where v.id = p_venue_id and v.status <> 'archived') then
        raise exception 'venue_not_found' using errcode = 'P0002';
    end if;
    if private.can_manage_venue(p_venue_id, v_uid) then
        raise exception 'already_manager' using errcode = '22023';
    end if;
    insert into public.venue_claims (venue_id, requested_by, client_request_id, business_name, claimant_role, contact_note, evidence_note)
    values (p_venue_id, v_uid, p_client_request_id, btrim(p_business_name), coalesce(p_claimant_role, 'owner'),
            nullif(btrim(coalesce(p_contact_note, '')), ''), nullif(btrim(coalesce(p_evidence_note, '')), ''))
    returning * into v_row;
    return jsonb_build_object('claim_id', v_row.id, 'status', v_row.status, 'replayed', false);
exception
    when unique_violation then
        raise exception 'claim_already_pending' using errcode = '23505';
end;
$$;

-- Privacy-safe funnel events: allowlisted names, no identity, small payloads.
create function public.log_event(p_event_name text, p_venue_id uuid default null, p_properties jsonb default '{}'::jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
    if p_event_name not in ('search', 'venue_detail_view', 'favorite_added', 'navigation_opened') then
        raise exception 'event_not_allowed' using errcode = '22023';
    end if;
    insert into private.analytics_events (event_name, venue_id, properties)
    values (p_event_name, p_venue_id,
            case when p_properties is null or jsonb_typeof(p_properties) <> 'object' or pg_column_size(p_properties) > 1024
                 then '{}'::jsonb else p_properties - 'latitude' - 'longitude' - 'phone' - 'email' - 'user_id' end);
end;
$$;
