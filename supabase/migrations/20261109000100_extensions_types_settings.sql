-- Nanglen v2 — 0001: extensions, schemas, enum types, central settings, helper functions.
-- Ordered, additive migrations. Safe on an empty database. No data is destroyed.

-- PostGIS and pg_trgm live in the dedicated `extensions` schema (Supabase guidance),
-- so their tables/functions are not exposed through the public Data API.
create schema if not exists extensions;
create extension if not exists postgis with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists pgcrypto with schema extensions;

-- `private` holds tables and helpers that must never be reachable through PostgREST.
-- Only `public` is in the API's exposed schemas.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;
-- (authenticated needs USAGE only so RLS policies may call private helper functions.
--  No private table is granted to authenticated.)

-- ---------------------------------------------------------------------------
-- Controlled vocabularies
-- ---------------------------------------------------------------------------
create type public.venue_category as enum ('cafe', 'library', 'coworking', 'study_space', 'other');
create type public.venue_status as enum ('active', 'temporarily_closed', 'permanently_closed', 'archived');
create type public.venue_provenance as enum ('curated_import', 'community_submission', 'business_claim');
create type public.submission_status as enum ('draft', 'pending_review', 'needs_changes', 'approved', 'rejected', 'duplicate', 'withdrawn');
create type public.review_status as enum ('published', 'hidden', 'removed');
create type public.visit_purpose as enum ('study', 'work', 'meeting', 'relax', 'other');
create type public.verification_status as enum ('verified', 'too_far', 'inaccurate', 'stale', 'invalid');
create type public.media_status as enum ('pending', 'approved', 'rejected');
create type public.flag_reason as enum ('spam', 'offensive', 'not_a_real_visit', 'wrong_venue', 'privacy', 'other');
create type public.flag_status as enum ('open', 'actioned', 'dismissed');
create type public.business_status as enum ('active', 'suspended');
create type public.membership_role as enum ('owner', 'manager', 'editor');
create type public.membership_status as enum ('active', 'suspended', 'revoked');
create type public.claim_status as enum ('pending_review', 'approved', 'rejected', 'withdrawn');
create type public.change_request_status as enum ('pending_review', 'approved', 'rejected', 'withdrawn');

-- ---------------------------------------------------------------------------
-- Central, tunable product thresholds (Product Rules §5, §8). Not hardcoded in functions.
-- ---------------------------------------------------------------------------
create table private.app_settings (
    key         text primary key,
    value       jsonb not null,
    description text not null,
    updated_at  timestamptz not null default now()
);

insert into private.app_settings (key, value, description) values
    ('visit_radius_m',            '100',  'Max distance (m) between submitted reading and venue for a verified visit'),
    ('visit_max_accuracy_m',      '50',   'Max horizontalAccuracy (m) accepted; negative values are always invalid'),
    ('visit_max_location_age_s',  '60',   'Max age (s) of the location reading at verification time'),
    ('visit_clock_skew_s',        '5',    'Tolerated device/server clock skew (s)'),
    ('visit_challenge_ttl_s',     '120',  'Lifetime (s) of a one-time visit challenge'),
    ('visit_verification_ttl_s',  '900',  'Time (s) a successful verification may be used to submit a review'),
    ('visit_challenges_per_10min','10',   'Rate limit: challenges a user may request per 10 minutes'),
    ('review_body_max_chars',     '500',  'Max review comment length'),
    ('review_max_tags',           '3',    'Max experience tags per review revision'),
    ('review_max_photos',         '3',    'Max photos per review revision'),
    ('submission_max_photos',     '5',    'Max photos per venue submission'),
    ('submission_max_open',       '10',   'Max pending/needs_changes submissions per user'),
    ('media_max_bytes',           '5242880', 'Max upload size (bytes) for images'),
    ('rank_prior_mean',           '3.5',  'Bayesian prior mean rating used for discovery ranking'),
    ('rank_prior_weight',         '5',    'Bayesian prior weight (pseudo-review count)'),
    ('duplicate_radius_m',        '150',  'Radius (m) used to find duplicate candidates'),
    ('business_min_cohort',       '5',    'Minimum distinct contributors before granular business analytics');

create function private.setting_numeric(p_key text)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
    select (value #>> '{}')::numeric from private.app_settings where key = p_key;
$$;

-- ---------------------------------------------------------------------------
-- Identity helpers. Identity is always derived from the verified JWT (auth.uid()).
-- ---------------------------------------------------------------------------

-- Normalized name used for search and duplicate detection (immutable → usable in generated columns).
create function private.normalize_name(p_name text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
    select btrim(regexp_replace(regexp_replace(lower(coalesce(p_name, '')), '[^[:alnum:][:space:]]+', ' ', 'g'), '\s+', ' ', 'g'));
$$;

-- Admin assignments: private, written only by the service role / SQL editor via private.grant_admin().
create table private.admin_users (
    user_id    uuid primary key references auth.users (id) on delete cascade,
    granted_by text not null,
    granted_at timestamptz not null default now(),
    revoked_at timestamptz,
    note       text
);

-- A Registered User is a permanent (non-anonymous) auth user with a confirmed phone (launch policy).
create function private.is_registered(p_user uuid default auth.uid())
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
          and u.phone_confirmed_at is not null
    );
$$;

-- Admin = active admin_users row AND registered. Revocation (revoked_at) takes effect immediately
-- because this is evaluated on every call (no long-lived claim).
create function private.is_admin(p_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select p_user is not null
       and exists (select 1 from private.admin_users a where a.user_id = p_user and a.revoked_at is null)
       and private.is_registered(p_user);
$$;

-- Active business membership for a venue (scoped Business Owner capability).
-- Defined after business tables in 0002 (placeholder signature declared there).

create function private.require_registered()
returns uuid
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
    if not private.is_registered(v_uid) then
        raise exception 'registration_required' using errcode = '42501',
            hint = 'Link and verify a phone number before contributing.';
    end if;
    return v_uid;
end;
$$;

create function private.require_admin()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_uid uuid := auth.uid();
begin
    if v_uid is null or not private.is_admin(v_uid) then
        raise exception 'admin_required' using errcode = '42501';
    end if;
    return v_uid;
end;
$$;

-- Trusted, server-side-only admin grant. Not executable by API roles.
create function private.grant_admin(p_user uuid, p_granted_by text, p_note text default null)
returns void
language sql
security definer
set search_path = ''
as $$
    insert into private.admin_users (user_id, granted_by, note)
    values (p_user, p_granted_by, p_note)
    on conflict (user_id) do update set revoked_at = null, granted_by = excluded.granted_by, granted_at = now(), note = excluded.note;
$$;

create function private.revoke_admin(p_user uuid)
returns void
language sql
security definer
set search_path = ''
as $$
    update private.admin_users set revoked_at = now() where user_id = p_user and revoked_at is null;
$$;

create function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

-- Coarse buckets: we keep buckets, never raw user coordinates.
create function private.distance_bucket(p_meters double precision)
returns text
language sql
immutable
set search_path = ''
as $$
    select case
        when p_meters is null then 'unknown'
        when p_meters <= 25 then '0-25'
        when p_meters <= 50 then '25-50'
        when p_meters <= 100 then '50-100'
        when p_meters <= 250 then '100-250'
        else '250+'
    end;
$$;

create function private.accuracy_bucket(p_meters double precision)
returns text
language sql
immutable
set search_path = ''
as $$
    select case
        when p_meters is null or p_meters < 0 then 'invalid'
        when p_meters <= 10 then '0-10'
        when p_meters <= 25 then '10-25'
        when p_meters <= 50 then '25-50'
        else '50+'
    end;
$$;
