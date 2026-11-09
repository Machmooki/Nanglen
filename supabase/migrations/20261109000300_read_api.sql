-- Nanglen v2 — 0003: read API (views + stable RPCs). Public data only; bounded result sets.

-- Rating summary over the CURRENT revision of PUBLISHED reviews. Venues without reviews have no row,
-- so callers LEFT JOIN and get NULL (never 0.0).
create view public.venue_rating_summaries
with (security_invoker = true) as
select
    r.venue_id,
    count(*)::integer                                  as review_count,
    round(avg(rv.rating)::numeric, 2)                  as average_rating,
    sum(rv.rating)::integer                            as rating_sum,
    count(*) filter (where rv.rating = 1)::integer     as rating_1,
    count(*) filter (where rv.rating = 2)::integer     as rating_2,
    count(*) filter (where rv.rating = 3)::integer     as rating_3,
    count(*) filter (where rv.rating = 4)::integer     as rating_4,
    count(*) filter (where rv.rating = 5)::integer     as rating_5,
    max(rv.created_at)                                 as last_review_at
from public.reviews r
join public.review_revisions rv on rv.id = r.current_revision_id
where r.status = 'published'
group by r.venue_id;

create view public.venue_tag_counts
with (security_invoker = true) as
select r.venue_id, t.tag_slug, count(*)::integer as tag_count
from public.reviews r
join public.review_revision_tags t on t.revision_id = r.current_revision_id
where r.status = 'published'
group by r.venue_id, t.tag_slug;

-- Bayesian (confidence-aware) rating used for ranking only; the UI shows the plain average.
create function private.bayesian_rating(p_sum numeric, p_count integer)
returns double precision
language sql
stable
security definer
set search_path = ''
as $$
    select ((private.setting_numeric('rank_prior_weight') * private.setting_numeric('rank_prior_mean'))
            + coalesce(p_sum, 0))::double precision
         / (private.setting_numeric('rank_prior_weight') + coalesce(p_count, 0))::double precision;
$$;

create function private.top_tags(p_venue uuid, p_limit integer default 3)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce(array_agg(tag_slug order by tag_count desc, tag_slug), '{}')
    from (
        select t.tag_slug, count(*) as tag_count
        from public.reviews r
        join public.review_revision_tags t on t.revision_id = r.current_revision_id
        join public.review_tags rt on rt.slug = t.tag_slug and rt.is_active
        where r.venue_id = p_venue and r.status = 'published'
        group by t.tag_slug
        order by count(*) desc, t.tag_slug
        limit p_limit
    ) s;
$$;

create function private.cover_path(p_venue uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
    select storage_path from public.venue_media where venue_id = p_venue order by display_order, created_at limit 1;
$$;

-- ---------------------------------------------------------------------------
-- search_venues: approved canonical venues only. Ranking = relevance + Bayesian rating + distance.
-- p_sort: 'relevance' (default) | 'distance' | 'rating'
-- ---------------------------------------------------------------------------
create function public.search_venues(
    p_query       text default null,
    p_latitude    double precision default null,
    p_longitude   double precision default null,
    p_radius_m    double precision default 5000,
    p_category    public.venue_category default null,
    p_min_rating  numeric default null,
    p_sort        text default 'relevance',
    p_limit       integer default 20,
    p_offset      integer default 0
)
returns table (
    id                uuid,
    name              text,
    category          public.venue_category,
    formatted_address text,
    latitude          double precision,
    longitude         double precision,
    status            public.venue_status,
    review_count      integer,
    average_rating    numeric,
    top_tags          text[],
    cover_path        text,
    distance_m        double precision,
    rank_score        double precision
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_q       text := nullif(private.normalize_name(p_query), '');
    v_origin  extensions.geography;
    v_radius  double precision := least(greatest(coalesce(p_radius_m, 5000), 100), 50000);
    v_limit   integer := least(greatest(coalesce(p_limit, 20), 1), 50);
    v_offset  integer := least(greatest(coalesce(p_offset, 0), 0), 500);
begin
    if p_sort is not null and p_sort not in ('relevance', 'distance', 'rating') then
        raise exception 'invalid_sort' using errcode = '22023';
    end if;
    if p_latitude is not null and p_longitude is not null then
        if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
            raise exception 'invalid_coordinate' using errcode = '22023';
        end if;
        v_origin := extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326)::extensions.geography;
    end if;
    if v_q is not null and char_length(v_q) > 100 then
        v_q := left(v_q, 100);
    end if;

    return query
    with candidates as (
        select
            v.id, v.name, v.category, v.formatted_address, v.latitude, v.longitude, v.status,
            s.review_count, s.average_rating, s.rating_sum,
            case when v_origin is null then null else extensions.st_distance(v.location, v_origin) end as dist,
            case when v_q is null then null
                 else greatest(
                        extensions.similarity(v.normalized_name, v_q),
                        extensions.word_similarity(v_q, v.normalized_name),
                        case when v.normalized_name like v_q || '%' then 0.9
                             when strpos(v.normalized_name, v_q) > 0 then 0.7
                             else 0 end)
            end as rel
        from public.venues v
        left join public.venue_rating_summaries s on s.venue_id = v.id
        where v.status in ('active', 'temporarily_closed')
          and (p_category is null or v.category = p_category)
          -- Browsing is area-bounded; text search may look further but is still relevance-filtered.
          and (v_origin is null or v_q is not null or extensions.st_dwithin(v.location, v_origin, v_radius))
          and (v_q is null
               or strpos(v.normalized_name, v_q) > 0
               or extensions.similarity(v.normalized_name, v_q) >= 0.25
               or extensions.word_similarity(v_q, v.normalized_name) >= 0.4)
          and (p_min_rating is null or coalesce(s.average_rating, 0) >= p_min_rating)
    ),
    scored as (
        select c.*,
            private.bayesian_rating(c.rating_sum, coalesce(c.review_count, 0)) as bayes,
            case when c.dist is null then 0.5 else 1.0 / (1.0 + c.dist / 1000.0) end as dist_score
        from candidates c
    ),
    ranked as (
        select sc.*,
            case when sc.rel is null
                 then 0.55 * ((sc.bayes - 1) / 4.0) + 0.45 * sc.dist_score
                 else 0.50 * sc.rel + 0.25 * ((sc.bayes - 1) / 4.0) + 0.25 * sc.dist_score
            end as score
        from scored sc
    ),
    page as (
        select r.* from ranked r
        order by
            case when coalesce(p_sort, 'relevance') = 'relevance' then r.score end desc nulls last,
            case when p_sort = 'distance' then r.dist end asc nulls last,
            case when p_sort = 'rating' then r.bayes end desc nulls last,
            case when p_sort = 'rating' then r.review_count end desc nulls last,
            r.name asc, r.id asc
        limit v_limit offset v_offset
    )
    select p.id, p.name, p.category, p.formatted_address, p.latitude, p.longitude, p.status,
           coalesce(p.review_count, 0), p.average_rating,
           private.top_tags(p.id, 3), private.cover_path(p.id),
           p.dist, p.score
    from page p
    order by
        case when coalesce(p_sort, 'relevance') = 'relevance' then p.score end desc nulls last,
        case when p_sort = 'distance' then p.dist end asc nulls last,
        case when p_sort = 'rating' then p.bayes end desc nulls last,
        p.name asc, p.id asc;
end;
$$;

-- Compact cards for a known set of ids (favorites refresh, cache revalidation). Max 100 ids.
create function public.get_venue_cards(p_ids uuid[], p_latitude double precision default null, p_longitude double precision default null)
returns table (
    id uuid, name text, category public.venue_category, formatted_address text,
    latitude double precision, longitude double precision, status public.venue_status,
    review_count integer, average_rating numeric, top_tags text[], cover_path text, distance_m double precision
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_origin extensions.geography;
begin
    if coalesce(array_length(p_ids, 1), 0) > 100 then
        raise exception 'too_many_ids' using errcode = '22023';
    end if;
    if p_latitude is not null and p_longitude is not null then
        v_origin := extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326)::extensions.geography;
    end if;
    return query
    select v.id, v.name, v.category, v.formatted_address, v.latitude, v.longitude, v.status,
           coalesce(s.review_count, 0), s.average_rating,
           private.top_tags(v.id, 3), private.cover_path(v.id),
           case when v_origin is null then null else extensions.st_distance(v.location, v_origin) end
    from public.venues v
    left join public.venue_rating_summaries s on s.venue_id = v.id
    where v.id = any (p_ids) and v.status <> 'archived';
end;
$$;

-- Maps provider ids (e.g. Apple Maps identifiers from MapKit) to canonical venue ids.
create function public.match_provider_refs(p_provider text, p_external_ids text[])
returns table (external_place_id text, venue_id uuid)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    if coalesce(array_length(p_external_ids, 1), 0) > 100 then
        raise exception 'too_many_ids' using errcode = '22023';
    end if;
    return query
    select r.external_place_id, r.venue_id
    from public.venue_provider_refs r
    join public.venues v on v.id = r.venue_id and v.status <> 'archived'
    where r.provider = p_provider and r.external_place_id = any (p_external_ids);
end;
$$;

-- Venue detail. Includes the caller's own current review and capability hints (UI only; writes re-check).
create function public.get_venue(p_venue_id uuid)
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
        'photo_paths', coalesce((select jsonb_agg(m.storage_path order by m.display_order, m.created_at) from public.venue_media m where m.venue_id = v.id), '[]'::jsonb),
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

-- Published reviews for a venue (current revision only). Reviewer identity limited to display name.
-- p_sort: 'relevant' (informative + recent first) | 'recent'
create function public.list_venue_reviews(
    p_venue_id uuid,
    p_sort     text default 'relevant',
    p_limit    integer default 20,
    p_offset   integer default 0
)
returns table (
    review_id        uuid,
    author_name      text,
    rating           smallint,
    visit_purpose    public.visit_purpose,
    body             text,
    tags             text[],
    photo_paths      text[],
    revision_number  integer,
    updated_at       timestamptz,
    is_mine          boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_uid    uuid := auth.uid();
    v_limit  integer := least(greatest(coalesce(p_limit, 20), 1), 50);
    v_offset integer := least(greatest(coalesce(p_offset, 0), 0), 1000);
begin
    if p_sort not in ('relevant', 'recent') then
        raise exception 'invalid_sort' using errcode = '22023';
    end if;
    return query
    select r.id, p.display_name, rv.rating, rv.visit_purpose, rv.body,
           coalesce((select array_agg(t.tag_slug order by t.tag_slug) from public.review_revision_tags t where t.revision_id = rv.id), '{}'),
           coalesce((select array_agg(m.storage_path order by m.display_order) from public.review_media m where m.revision_id = rv.id and m.status = 'approved'), '{}'),
           rv.revision_number, rv.created_at,
           v_uid is not null and r.user_id = v_uid
    from public.reviews r
    join public.review_revisions rv on rv.id = r.current_revision_id
    join public.profiles p on p.id = r.user_id
    join public.venues v on v.id = r.venue_id and v.status <> 'archived'
    where r.venue_id = p_venue_id and r.status = 'published'
    order by
        case when p_sort = 'relevant'
             then (case when rv.body is not null then 2 else 0 end)
                + (select count(*) from public.review_revision_tags t where t.revision_id = rv.id) * 0.25
                - extract(epoch from (now() - rv.created_at)) / (86400.0 * 60)
        end desc nulls last,
        rv.created_at desc, r.id
    limit v_limit offset v_offset;
end;
$$;

create function public.list_review_tags()
returns table (slug text, label_th text, label_en text, tag_group text, sort_order smallint)
language sql
stable
security definer
set search_path = ''
as $$
    select slug, label_th, label_en, tag_group, sort_order from public.review_tags where is_active order by sort_order, slug;
$$;

-- Thresholds the client uses for UX pre-checks. The server decision remains authoritative.
create function public.get_public_config()
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
        'submission_max_photos', private.setting_numeric('submission_max_photos'),
        'media_max_bytes', private.setting_numeric('media_max_bytes'));
$$;

-- Server-derived capabilities. The client must never infer privileges from local state.
create function public.get_my_capabilities()
returns jsonb
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
    return jsonb_build_object(
        'user_id', v_uid,
        'is_anonymous', coalesce((select u.is_anonymous from auth.users u where u.id = v_uid), true),
        'is_registered', private.is_registered(v_uid),
        'is_admin', private.is_admin(v_uid),
        'display_name', (select p.display_name from public.profiles p where p.id = v_uid),
        'favorites_count', (select count(*) from public.favorites f where f.user_id = v_uid),
        'reviews_count', (select count(*) from public.reviews r where r.user_id = v_uid and r.status <> 'removed'),
        'open_submissions_count', (select count(*) from public.venue_submissions s where s.submitted_by = v_uid and s.status in ('pending_review', 'needs_changes')),
        'memberships', coalesce((
            select jsonb_agg(jsonb_build_object(
                'business_id', b.id, 'business_name', b.name, 'role', m.role,
                'venue_ids', coalesce((select jsonb_agg(v.id) from public.venues v where v.business_id = b.id), '[]'::jsonb)))
            from public.business_memberships m
            join public.business_accounts b on b.id = m.business_id and b.status = 'active'
            where m.user_id = v_uid and m.status = 'active' and private.is_registered(v_uid)), '[]'::jsonb)
    );
end;
$$;

create function public.my_favorite_venue_ids()
returns table (venue_id uuid, created_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
    select f.venue_id, f.created_at from public.favorites f where f.user_id = auth.uid() order by f.created_at desc limit 500;
$$;
