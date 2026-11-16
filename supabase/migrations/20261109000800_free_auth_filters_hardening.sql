-- Nanglen v2 — 0008: free sign-in (verified email), easier filters, security hardening.
-- Additive: safe to apply on a database that already has 0001–0007.

-- ---------------------------------------------------------------------------
-- 1. Settings
-- ---------------------------------------------------------------------------
insert into private.app_settings (key, value, description) values
    ('registered_via_email',  '1', '1 = a confirmed email makes a user Registered (free; needs SMTP)'),
    ('registered_via_phone',  '0', '1 = a confirmed phone makes a user Registered (SMS is billed)'),
    ('filter_min_tag_votes',  '1', 'Minimum visitors who chose a tag before a venue matches that tag filter'),
    ('filter_max_tags',       '5', 'Maximum tag filters per search'),
    ('claims_max_open',       '5', 'Max pending venue claims per user')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Registered = permanent user with a confirmed identity allowed by settings.
--    Launch default: confirmed email (OTP). Phone can be re-enabled without a migration.
-- ---------------------------------------------------------------------------
create or replace function private.is_registered(p_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from auth.users u
        where u.id = p_user
          and coalesce(u.is_anonymous, false) = false
          and ((u.email_confirmed_at is not null and private.setting_numeric('registered_via_email') = 1)
               or (u.phone_confirmed_at is not null and private.setting_numeric('registered_via_phone') = 1))
    );
$$;

-- ---------------------------------------------------------------------------
-- 3. Display names: no control/invisible characters, no staff impersonation.
-- ---------------------------------------------------------------------------
alter table public.profiles alter column display_name set default 'Nanglen user';
update public.profiles set display_name = 'Nanglen user' where display_name = 'ผู้ใช้ Nanglen';

create function private.clean_text(p text)
returns text
language sql
immutable
set search_path = ''
as $$
    -- Strips control, zero-width and bidi-override characters, collapses whitespace.
    select btrim(regexp_replace(
        regexp_replace(coalesce(p, ''), '[[:cntrl:]​-‏‪-‮⁠-⁩﻿]', '', 'g'),
        '\s+', ' ', 'g'));
$$;

create or replace function public.update_my_display_name(p_display_name text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_uid  uuid := private.require_registered();
    v_name text := private.clean_text(p_display_name);
begin
    if char_length(v_name) not between 2 and 40 then
        raise exception 'invalid_display_name' using errcode = '22023';
    end if;
    if not private.is_admin(v_uid)
       and lower(v_name) ~ '(admin|moderator|nanglen|official|support|staff|ผู้ดูแล|แอดมิน|ทีมงาน)' then
        raise exception 'reserved_display_name' using errcode = '22023';
    end if;
    update public.profiles set display_name = v_name where id = v_uid;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Media paths must not reveal the uploader's auth id.
--    New shape: '<submission or revision uuid>/<uuid>.<ext>'. Ownership is checked through the parent row.
--    (Objects uploaded with the old '<uid>/<parent>/…' shape are no longer accepted; none should exist yet.)
-- ---------------------------------------------------------------------------
create or replace function private.valid_media_path(p_path text, p_uid uuid, p_parent uuid)
returns boolean
language sql
immutable
set search_path = ''
as $$
    select p_path ~ ('^' || p_parent::text || '/[0-9a-f-]{36}\.(jpg|jpeg|png|heic|webp)$');
$$;

create function private.owns_submission(p_submission uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (select 1 from public.venue_submissions s where s.id = p_submission and s.submitted_by = auth.uid());
$$;

create function private.owns_revision(p_revision uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (select 1 from public.review_revisions rv where rv.id = p_revision and rv.user_id = auth.uid());
$$;

revoke all on function private.clean_text(text) from public, anon, authenticated;
-- anon needs EXECUTE too: the SELECT policies below call these for anon readers (they return false without a session).
grant execute on function private.owns_submission(uuid) to anon, authenticated;
grant execute on function private.owns_revision(uuid) to anon, authenticated;

drop policy if exists "submission media: registered owner uploads to own open submission" on storage.objects;
drop policy if exists "submission media: owner, admin, or approved venue photo" on storage.objects;
drop policy if exists "submission media: owner deletes while submission is open" on storage.objects;
drop policy if exists "review media: registered owner uploads to own current revision" on storage.objects;
drop policy if exists "review media: owner, admin, or approved and published" on storage.objects;
drop policy if exists "review media: owner deletes own pending upload" on storage.objects;

create policy "submission media: registered owner uploads to own open submission"
    on storage.objects for insert to authenticated
    with check (
        bucket_id = 'venue-submission-media'
        and array_length(storage.foldername(name), 1) = 1
        and private.is_registered()
        and private.owns_open_submission(private.safe_uuid((storage.foldername(name))[1]))
        and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'heic', 'webp')
    );

create policy "submission media: owner, admin, or approved venue photo"
    on storage.objects for select to anon, authenticated
    using (
        bucket_id = 'venue-submission-media'
        and (private.is_public_venue_media(bucket_id, name)
             or (select private.is_admin())
             or private.owns_submission(private.safe_uuid((storage.foldername(name))[1])))
    );

create policy "submission media: owner deletes while submission is open"
    on storage.objects for delete to authenticated
    using (
        bucket_id = 'venue-submission-media'
        and private.owns_open_submission(private.safe_uuid((storage.foldername(name))[1]))
    );

create policy "review media: registered owner uploads to own current revision"
    on storage.objects for insert to authenticated
    with check (
        bucket_id = 'review-media'
        and array_length(storage.foldername(name), 1) = 1
        and private.is_registered()
        and private.owns_current_revision(private.safe_uuid((storage.foldername(name))[1]))
        and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'heic', 'webp')
    );

create policy "review media: owner, admin, or approved and published"
    on storage.objects for select to anon, authenticated
    using (
        bucket_id = 'review-media'
        and (private.is_public_review_media(name)
             or (select private.is_admin())
             or private.owns_revision(private.safe_uuid((storage.foldername(name))[1])))
    );

create policy "review media: owner deletes own pending upload"
    on storage.objects for delete to authenticated
    using (
        bucket_id = 'review-media'
        and private.owns_revision(private.safe_uuid((storage.foldername(name))[1]))
        and not private.is_public_review_media(name)
    );

-- ---------------------------------------------------------------------------
-- 5. Analytics: signed-in sessions only (Guests are signed in), allowlisted keys only (no free text).
-- ---------------------------------------------------------------------------
revoke execute on function public.log_event(text, uuid, jsonb) from anon;

create or replace function public.log_event(p_event_name text, p_venue_id uuid default null, p_properties jsonb default '{}'::jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_props jsonb := '{}'::jsonb;
begin
    if auth.uid() is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    if p_event_name not in ('search', 'venue_detail_view', 'favorite_added', 'navigation_opened') then
        raise exception 'event_not_allowed' using errcode = '22023';
    end if;
    if p_properties is not null and jsonb_typeof(p_properties) = 'object' then
        select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) into v_props
        from jsonb_each(p_properties)
        where key in ('category', 'sort', 'has_query', 'result_count', 'filter_count')
          and jsonb_typeof(value) in ('string', 'number', 'boolean')
          and pg_column_size(value) <= 64;
    end if;
    insert into private.analytics_events (event_name, venue_id, properties) values (p_event_name, p_venue_id, v_props);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Claims: cap open claims per user (prevents claim spam across venues).
-- ---------------------------------------------------------------------------
create or replace function public.request_venue_claim(
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
    v_uid  uuid := private.require_registered();
    v_row  public.venue_claims;
    v_name text := private.clean_text(p_business_name);
begin
    select * into v_row from public.venue_claims c where c.requested_by = v_uid and c.client_request_id = p_client_request_id;
    if found then
        return jsonb_build_object('claim_id', v_row.id, 'status', v_row.status, 'replayed', true);
    end if;
    if not exists (select 1 from public.venues v where v.id = p_venue_id and v.status <> 'archived') then
        raise exception 'venue_not_found' using errcode = 'P0002';
    end if;
    if char_length(v_name) = 0 then
        raise exception 'name_required' using errcode = '22023';
    end if;
    if private.can_manage_venue(p_venue_id, v_uid) then
        raise exception 'already_manager' using errcode = '22023';
    end if;
    if (select count(*) from public.venue_claims c where c.requested_by = v_uid and c.status = 'pending_review')
       >= private.setting_numeric('claims_max_open') then
        raise exception 'rate_limited' using errcode = '53400';
    end if;
    insert into public.venue_claims (venue_id, requested_by, client_request_id, business_name, claimant_role, contact_note, evidence_note)
    values (p_venue_id, v_uid, p_client_request_id, v_name, coalesce(p_claimant_role, 'owner'),
            nullif(private.clean_text(p_contact_note), ''), nullif(private.clean_text(p_evidence_note), ''))
    returning * into v_row;
    return jsonb_build_object('claim_id', v_row.id, 'status', v_row.status, 'replayed', false);
exception
    when unique_violation then
        raise exception 'claim_already_pending' using errcode = '23505';
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Capabilities: add a masked contact hint for the Profile screen (never the full email/phone).
-- ---------------------------------------------------------------------------
create or replace function public.get_my_capabilities()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_uid   uuid := auth.uid();
    v_email text;
begin
    if v_uid is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    select case when u.email_confirmed_at is not null then u.email end into v_email from auth.users u where u.id = v_uid;
    return jsonb_build_object(
        'user_id', v_uid,
        'is_anonymous', coalesce((select u.is_anonymous from auth.users u where u.id = v_uid), true),
        'is_registered', private.is_registered(v_uid),
        'is_admin', private.is_admin(v_uid),
        'display_name', (select p.display_name from public.profiles p where p.id = v_uid),
        'contact_hint', case when v_email is null then null
                             else left(split_part(v_email, '@', 1), 1) || '•••@' || split_part(v_email, '@', 2) end,
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

-- ---------------------------------------------------------------------------
-- 8. search_venues v2: optional "good for" tag filters and "has reviews" toggle.
--    Tags are community impressions: a venue matches when at least `filter_min_tag_votes`
--    published current reviews chose that tag.
-- ---------------------------------------------------------------------------
drop function if exists public.search_venues(text, double precision, double precision, double precision, public.venue_category, numeric, text, integer, integer);

create function public.search_venues(
    p_query         text default null,
    p_latitude      double precision default null,
    p_longitude     double precision default null,
    p_radius_m      double precision default 5000,
    p_category      public.venue_category default null,
    p_min_rating    numeric default null,
    p_sort          text default 'relevance',
    p_limit         integer default 20,
    p_offset        integer default 0,
    p_tags          text[] default null,
    p_reviewed_only boolean default false
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
    v_q        text := nullif(private.normalize_name(p_query), '');
    v_origin   extensions.geography;
    v_radius   double precision := least(greatest(coalesce(p_radius_m, 5000), 100), 50000);
    v_limit    integer := least(greatest(coalesce(p_limit, 20), 1), 50);
    v_offset   integer := least(greatest(coalesce(p_offset, 0), 0), 500);
    v_tags     text[];
    v_minvotes integer := greatest(private.setting_numeric('filter_min_tag_votes')::integer, 1);
begin
    if p_sort is not null and p_sort not in ('relevance', 'distance', 'rating') then
        raise exception 'invalid_sort' using errcode = '22023';
    end if;
    if p_min_rating is not null and (p_min_rating < 1 or p_min_rating > 5) then
        raise exception 'invalid_rating' using errcode = '22023';
    end if;
    select coalesce(array_agg(distinct t), '{}') into v_tags from unnest(coalesce(p_tags, '{}')) t where t is not null;
    if cardinality(v_tags) > private.setting_numeric('filter_max_tags') then
        raise exception 'too_many_tags' using errcode = '22023';
    end if;
    if exists (select 1 from unnest(v_tags) t where not exists (select 1 from public.review_tags rt where rt.slug = t and rt.is_active)) then
        raise exception 'unknown_tag' using errcode = '22023';
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
          and (v_origin is null or v_q is not null or extensions.st_dwithin(v.location, v_origin, v_radius))
          and (v_q is null
               or strpos(v.normalized_name, v_q) > 0
               or extensions.similarity(v.normalized_name, v_q) >= 0.25
               or extensions.word_similarity(v_q, v.normalized_name) >= 0.4)
          and (p_min_rating is null or coalesce(s.average_rating, 0) >= p_min_rating)
          and (not coalesce(p_reviewed_only, false) or coalesce(s.review_count, 0) > 0)
          and (cardinality(v_tags) = 0 or not exists (
                select 1 from unnest(v_tags) wanted
                where (select count(*) from public.reviews r
                       join public.review_revision_tags rt on rt.revision_id = r.current_revision_id
                       where r.venue_id = v.id and r.status = 'published' and rt.tag_slug = wanted) < v_minvotes))
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

revoke all on function public.search_venues(text, double precision, double precision, double precision, public.venue_category, numeric, text, integer, integer, text[], boolean) from public;
grant execute on function public.search_venues(text, double precision, double precision, double precision, public.venue_category, numeric, text, integer, integer, text[], boolean) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 9. Re-assert: no PUBLIC execute on new helpers (explicit role grants above remain).
-- ---------------------------------------------------------------------------
revoke all on function private.owns_submission(uuid) from public;
revoke all on function private.owns_revision(uuid) from public;

-- ---------------------------------------------------------------------------
-- 10. Account deletion support (called only by the delete-account Edge Function with the service role).
-- ---------------------------------------------------------------------------
create function public.account_deletion_blocked(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    -- Active Admins must be revoked first so the immutable audit trail keeps a valid actor.
    select exists (select 1 from private.admin_users a where a.user_id = p_user and a.revoked_at is null);
$$;
revoke all on function public.account_deletion_blocked(uuid) from public, anon, authenticated;
grant execute on function public.account_deletion_blocked(uuid) to service_role;
