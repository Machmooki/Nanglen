-- Nanglen v2 — 0002: core tables, constraints, indexes, invariants.

-- ---------------------------------------------------------------------------
-- Profiles (public-safe fields only; credentials/phone stay in auth.users)
-- ---------------------------------------------------------------------------
create table public.profiles (
    id           uuid primary key references auth.users (id) on delete cascade,
    display_name text not null default 'ผู้ใช้ Nanglen'
                 check (char_length(btrim(display_name)) between 1 and 40),
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);
create trigger profiles_touch before update on public.profiles
    for each row execute function private.touch_updated_at();

-- Every auth user (anonymous or permanent) gets a profile row.
create function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
    return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
    for each row execute function private.handle_new_auth_user();

-- ---------------------------------------------------------------------------
-- Business foundation (minimal; Phase 2 adds tools)
-- ---------------------------------------------------------------------------
create table public.business_accounts (
    id          uuid primary key default gen_random_uuid(),
    name        text not null check (char_length(btrim(name)) between 1 and 120),
    status      public.business_status not null default 'active',
    created_by  uuid references auth.users (id) on delete set null,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);
create trigger business_accounts_touch before update on public.business_accounts
    for each row execute function private.touch_updated_at();

create table public.business_memberships (
    id           uuid primary key default gen_random_uuid(),
    business_id  uuid not null references public.business_accounts (id) on delete cascade,
    user_id      uuid not null references auth.users (id) on delete cascade,
    role         public.membership_role not null,
    status       public.membership_status not null default 'active',
    approved_by  uuid references auth.users (id) on delete set null,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now(),
    unique (business_id, user_id)
);
create index business_memberships_user_status_idx on public.business_memberships (user_id, status);
create index business_memberships_business_status_idx on public.business_memberships (business_id, status);
create trigger business_memberships_touch before update on public.business_memberships
    for each row execute function private.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Canonical venues — approved, public Nanglen places.
-- `location` is the single source of truth; latitude/longitude are generated from it.
-- ---------------------------------------------------------------------------
create table public.venues (
    id                  uuid primary key default gen_random_uuid(),
    name                text not null check (char_length(btrim(name)) between 1 and 120),
    normalized_name     text generated always as (private.normalize_name(name)) stored,
    description         text check (description is null or char_length(description) <= 1000),
    category            public.venue_category not null,
    formatted_address   text check (formatted_address is null or char_length(formatted_address) <= 300),
    location            extensions.geography(point, 4326) not null,
    latitude            double precision generated always as (extensions.st_y(location::extensions.geometry)) stored,
    longitude           double precision generated always as (extensions.st_x(location::extensions.geometry)) stored,
    -- Official details: shown only with a known source.
    website_url         text check (website_url is null or website_url ~* '^https?://'),
    phone_number        text check (phone_number is null or char_length(phone_number) <= 32),
    details_source      text check (details_source in ('community_submission', 'admin_curated', 'business_verified')),
    status              public.venue_status not null default 'active',
    provenance          public.venue_provenance not null,
    source_submission_id uuid,
    business_id         uuid references public.business_accounts (id) on delete set null,
    created_by          uuid references auth.users (id) on delete set null,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now()
);
create index venues_location_gix on public.venues using gist (location);
create index venues_status_category_idx on public.venues (status, category);
create index venues_normalized_name_trgm on public.venues using gin (normalized_name extensions.gin_trgm_ops);
create trigger venues_touch before update on public.venues
    for each row execute function private.touch_updated_at();

create table public.venue_provider_refs (
    id                uuid primary key default gen_random_uuid(),
    venue_id          uuid not null references public.venues (id) on delete cascade,
    provider          text not null check (provider in ('apple_maps', 'curated', 'other')),
    external_place_id text not null check (char_length(external_place_id) between 1 and 512),
    created_at        timestamptz not null default now(),
    unique (provider, external_place_id)
);
create index venue_provider_refs_venue_idx on public.venue_provider_refs (venue_id);

-- ---------------------------------------------------------------------------
-- Venue submissions — never visible through public venue queries.
-- ---------------------------------------------------------------------------
create table public.venue_submissions (
    id                     uuid primary key default gen_random_uuid(),
    submitted_by           uuid not null references auth.users (id) on delete cascade,
    client_request_id      uuid not null,
    name                   text not null check (char_length(btrim(name)) between 1 and 120),
    normalized_name        text generated always as (private.normalize_name(name)) stored,
    category               public.venue_category not null,
    formatted_address      text check (formatted_address is null or char_length(formatted_address) <= 300),
    location               extensions.geography(point, 4326) not null,
    latitude               double precision generated always as (extensions.st_y(location::extensions.geometry)) stored,
    longitude              double precision generated always as (extensions.st_x(location::extensions.geometry)) stored,
    provider               text check (provider in ('apple_maps', 'other')),
    external_place_id      text check (external_place_id is null or char_length(external_place_id) <= 512),
    description            text check (description is null or char_length(description) <= 1000),
    website_url            text check (website_url is null or website_url ~* '^https?://'),
    phone_number           text check (phone_number is null or char_length(phone_number) <= 32),
    submitter_note         text check (submitter_note is null or char_length(submitter_note) <= 500),
    status                 public.submission_status not null default 'pending_review',
    revision               integer not null default 1 check (revision >= 1),
    duplicate_of_venue_id  uuid references public.venues (id) on delete set null,
    approved_venue_id      uuid references public.venues (id) on delete set null,
    reviewed_by            uuid references auth.users (id) on delete set null,
    reviewed_at            timestamptz,
    decision_reason        text check (decision_reason is null or char_length(decision_reason) <= 1000),
    submitted_at           timestamptz,
    created_at             timestamptz not null default now(),
    updated_at             timestamptz not null default now(),
    unique (submitted_by, client_request_id),
    check ((provider is null) = (external_place_id is null)),
    check (status <> 'duplicate' or duplicate_of_venue_id is not null),
    check (status <> 'approved' or approved_venue_id is not null),
    check (status not in ('rejected', 'needs_changes', 'duplicate') or decision_reason is not null)
);
create index venue_submissions_owner_idx on public.venue_submissions (submitted_by, created_at desc);
create index venue_submissions_queue_idx on public.venue_submissions (submitted_at) where status = 'pending_review';
create index venue_submissions_location_gix on public.venue_submissions using gist (location);
create trigger venue_submissions_touch before update on public.venue_submissions
    for each row execute function private.touch_updated_at();

alter table public.venues
    add constraint venues_source_submission_fk
    foreign key (source_submission_id) references public.venue_submissions (id) on delete set null;

create table public.venue_submission_media (
    id             uuid primary key default gen_random_uuid(),
    submission_id  uuid not null references public.venue_submissions (id) on delete cascade,
    uploaded_by    uuid not null references auth.users (id) on delete cascade,
    storage_path   text not null unique,
    mime_type      text not null check (mime_type in ('image/jpeg', 'image/png', 'image/heic', 'image/webp')),
    byte_size      integer not null check (byte_size > 0 and byte_size <= 5242880),
    width          integer check (width is null or width between 1 and 8000),
    height         integer check (height is null or height between 1 and 8000),
    display_order  smallint not null default 0 check (display_order between 0 and 9),
    status         public.media_status not null default 'pending',
    created_at     timestamptz not null default now()
);
create index venue_submission_media_submission_idx on public.venue_submission_media (submission_id);

-- Approved venue photos (copied references from approved submissions, or curated).
create table public.venue_media (
    id            uuid primary key default gen_random_uuid(),
    venue_id      uuid not null references public.venues (id) on delete cascade,
    bucket_id     text not null check (bucket_id in ('venue-submission-media')),
    storage_path  text not null,
    source        text not null check (source in ('submission', 'admin_curated', 'business')),
    display_order smallint not null default 0,
    created_at    timestamptz not null default now(),
    unique (bucket_id, storage_path)
);
create index venue_media_venue_idx on public.venue_media (venue_id, display_order);

-- ---------------------------------------------------------------------------
-- Review tag catalog (controlled taxonomy)
-- ---------------------------------------------------------------------------
create table public.review_tags (
    slug        text primary key check (slug ~ '^[a-z][a-z_]{1,39}$'),
    label_th    text not null,
    label_en    text not null,
    tag_group   text not null check (tag_group in ('activity', 'environment', 'amenity', 'value')),
    sort_order  smallint not null default 0,
    is_active   boolean not null default true
);

-- ---------------------------------------------------------------------------
-- Visit verification (private: only reachable via RPC)
-- ---------------------------------------------------------------------------
create table private.visit_challenges (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid not null references auth.users (id) on delete cascade,
    venue_id     uuid not null references public.venues (id) on delete cascade,
    issued_at    timestamptz not null default now(),
    expires_at   timestamptz not null,
    consumed_at  timestamptz,
    check (expires_at > issued_at)
);
create index visit_challenges_user_issued_idx on private.visit_challenges (user_id, issued_at desc);

create table private.visit_verifications (
    id                   uuid primary key default gen_random_uuid(),
    challenge_id         uuid not null unique references private.visit_challenges (id) on delete cascade,
    user_id              uuid not null references auth.users (id) on delete cascade,
    venue_id             uuid not null references public.venues (id) on delete cascade,
    status               public.verification_status not null,
    method               text not null default 'gps' check (method in ('gps', 'qr', 'nfc')),
    distance_bucket      text not null,
    accuracy_bucket      text not null,
    integrity_status     text not null default 'not_checked' check (integrity_status in ('not_checked', 'app_attest_valid', 'app_attest_failed')),
    verified_at          timestamptz not null default now(),
    expires_at           timestamptz not null,
    consumed_at          timestamptz,
    check (consumed_at is null or status = 'verified')
);
create index visit_verifications_user_idx on private.visit_verifications (user_id, verified_at desc);

-- ---------------------------------------------------------------------------
-- Reviews and immutable revisions
-- ---------------------------------------------------------------------------
create table public.reviews (
    id                   uuid primary key default gen_random_uuid(),
    venue_id             uuid not null references public.venues (id) on delete cascade,
    user_id              uuid not null references auth.users (id) on delete cascade,
    current_revision_id  uuid,
    status               public.review_status not null default 'published',
    created_at           timestamptz not null default now(),
    updated_at           timestamptz not null default now(),
    unique (venue_id, user_id)
);
create index reviews_venue_updated_idx on public.reviews (venue_id, updated_at desc) where status = 'published';
create index reviews_user_idx on public.reviews (user_id, updated_at desc);
create trigger reviews_touch before update on public.reviews
    for each row execute function private.touch_updated_at();

create table public.review_revisions (
    id                     uuid primary key default gen_random_uuid(),
    review_id              uuid not null references public.reviews (id) on delete cascade,
    user_id                uuid not null references auth.users (id) on delete cascade,
    revision_number        integer not null check (revision_number >= 1),
    visit_verification_id  uuid not null unique references private.visit_verifications (id),
    rating                 smallint not null check (rating between 1 and 5),
    visit_purpose          public.visit_purpose,
    body                   text check (body is null or char_length(body) <= 500),
    idempotency_key        uuid not null,
    created_at             timestamptz not null default now(),
    unique (review_id, revision_number),
    unique (user_id, idempotency_key)
);
create index review_revisions_review_idx on public.review_revisions (review_id, revision_number desc);

alter table public.reviews
    add constraint reviews_current_revision_fk
    foreign key (current_revision_id) references public.review_revisions (id)
    deferrable initially deferred;

-- Revisions are immutable once written.
create function private.forbid_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    raise exception '% rows are append-only', tg_table_name using errcode = '42501';
end;
$$;
create trigger review_revisions_immutable before update on public.review_revisions
    for each row execute function private.forbid_mutation();

create table public.review_revision_tags (
    revision_id  uuid not null references public.review_revisions (id) on delete cascade,
    tag_slug     text not null references public.review_tags (slug),
    primary key (revision_id, tag_slug)
);
create index review_revision_tags_tag_idx on public.review_revision_tags (tag_slug);

-- Defence in depth: never more than 3 tags per revision, whatever the write path.
create function private.enforce_max_tags()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if (select count(*) from public.review_revision_tags where revision_id = new.revision_id)
       >= private.setting_numeric('review_max_tags') then
        raise exception 'too_many_tags' using errcode = '23514';
    end if;
    return new;
end;
$$;
create trigger review_revision_tags_max before insert on public.review_revision_tags
    for each row execute function private.enforce_max_tags();

create table public.review_media (
    id             uuid primary key default gen_random_uuid(),
    revision_id    uuid not null references public.review_revisions (id) on delete cascade,
    uploaded_by    uuid not null references auth.users (id) on delete cascade,
    storage_path   text not null unique,
    mime_type      text not null check (mime_type in ('image/jpeg', 'image/png', 'image/heic', 'image/webp')),
    byte_size      integer not null check (byte_size > 0 and byte_size <= 5242880),
    width          integer check (width is null or width between 1 and 8000),
    height         integer check (height is null or height between 1 and 8000),
    display_order  smallint not null default 0 check (display_order between 0 and 2),
    status         public.media_status not null default 'pending',
    created_at     timestamptz not null default now()
);
create index review_media_revision_idx on public.review_media (revision_id, display_order);
create index review_media_pending_idx on public.review_media (created_at) where status = 'pending';

create table public.review_flags (
    id           uuid primary key default gen_random_uuid(),
    review_id    uuid not null references public.reviews (id) on delete cascade,
    flagged_by   uuid not null references auth.users (id) on delete cascade,
    reason       public.flag_reason not null,
    note         text check (note is null or char_length(note) <= 300),
    status       public.flag_status not null default 'open',
    resolved_by  uuid references auth.users (id) on delete set null,
    resolved_at  timestamptz,
    created_at   timestamptz not null default now(),
    unique (review_id, flagged_by)
);
create index review_flags_open_idx on public.review_flags (created_at) where status = 'open';

-- ---------------------------------------------------------------------------
-- Favorites (Guest favorites belong to the anonymous auth user; linking keeps the uid)
-- ---------------------------------------------------------------------------
create table public.favorites (
    user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
    venue_id    uuid not null references public.venues (id) on delete cascade,
    created_at  timestamptz not null default now(),
    primary key (user_id, venue_id)
);
create index favorites_user_created_idx on public.favorites (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Venue claims and change requests
-- ---------------------------------------------------------------------------
create table public.venue_claims (
    id                 uuid primary key default gen_random_uuid(),
    venue_id           uuid not null references public.venues (id) on delete cascade,
    requested_by       uuid not null references auth.users (id) on delete cascade,
    client_request_id  uuid not null,
    business_name      text not null check (char_length(btrim(business_name)) between 1 and 120),
    claimant_role      public.membership_role not null default 'owner',
    contact_note       text check (contact_note is null or char_length(contact_note) <= 500),
    evidence_note      text check (evidence_note is null or char_length(evidence_note) <= 1000),
    status             public.claim_status not null default 'pending_review',
    business_id        uuid references public.business_accounts (id) on delete set null,
    reviewed_by        uuid references auth.users (id) on delete set null,
    reviewed_at        timestamptz,
    decision_reason    text check (decision_reason is null or char_length(decision_reason) <= 1000),
    created_at         timestamptz not null default now(),
    updated_at         timestamptz not null default now(),
    unique (requested_by, client_request_id),
    check (status <> 'rejected' or decision_reason is not null)
);
create unique index venue_claims_one_open_per_user on public.venue_claims (venue_id, requested_by) where status = 'pending_review';
create index venue_claims_queue_idx on public.venue_claims (created_at) where status = 'pending_review';
create trigger venue_claims_touch before update on public.venue_claims
    for each row execute function private.touch_updated_at();

create table public.venue_change_requests (
    id               uuid primary key default gen_random_uuid(),
    venue_id         uuid not null references public.venues (id) on delete cascade,
    business_id      uuid not null references public.business_accounts (id) on delete cascade,
    requested_by     uuid not null references auth.users (id) on delete cascade,
    proposed         jsonb not null check (jsonb_typeof(proposed) = 'object' and pg_column_size(proposed) <= 8192),
    status           public.change_request_status not null default 'pending_review',
    reviewed_by      uuid references auth.users (id) on delete set null,
    reviewed_at      timestamptz,
    decision_reason  text,
    created_at       timestamptz not null default now()
);
create index venue_change_requests_queue_idx on public.venue_change_requests (created_at) where status = 'pending_review';

-- Scoped Business Owner capability: active membership in an active business that manages the venue.
create function private.can_manage_venue(p_venue uuid, p_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.venues v
        join public.business_accounts b on b.id = v.business_id and b.status = 'active'
        join public.business_memberships m on m.business_id = b.id and m.status = 'active'
        where v.id = p_venue and m.user_id = p_user
    ) and private.is_registered(p_user);
$$;

-- ---------------------------------------------------------------------------
-- Immutable moderation audit trail
-- ---------------------------------------------------------------------------
create table public.moderation_actions (
    id               bigint generated always as identity primary key,
    actor_id         uuid not null references auth.users (id),
    action           text not null check (action in (
                        'submission_approved', 'submission_rejected', 'submission_duplicate', 'submission_needs_changes',
                        'review_hidden', 'review_restored', 'review_removed', 'flag_dismissed',
                        'media_approved', 'media_rejected',
                        'claim_approved', 'claim_rejected',
                        'change_request_approved', 'change_request_rejected')),
    target_type      text not null check (target_type in ('venue_submission', 'review', 'review_flag', 'review_media', 'venue_submission_media', 'venue_claim', 'venue_change_request')),
    target_id        uuid not null,
    previous_status  text,
    new_status       text,
    reason           text check (reason is null or char_length(reason) <= 1000),
    metadata         jsonb not null default '{}'::jsonb,
    created_at       timestamptz not null default now()
);
create index moderation_actions_target_idx on public.moderation_actions (target_type, target_id, created_at desc);
create index moderation_actions_actor_idx on public.moderation_actions (actor_id, created_at desc);
create trigger moderation_actions_no_update before update or delete on public.moderation_actions
    for each row execute function private.forbid_mutation();

create function private.audit(
    p_actor uuid, p_action text, p_target_type text, p_target uuid,
    p_prev text, p_new text, p_reason text, p_metadata jsonb default '{}'::jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
    insert into public.moderation_actions (actor_id, action, target_type, target_id, previous_status, new_status, reason, metadata)
    values (p_actor, p_action, p_target_type, p_target, p_prev, p_new, p_reason, coalesce(p_metadata, '{}'::jsonb));
$$;

-- ---------------------------------------------------------------------------
-- Minimal, privacy-safe product analytics (separate from transactional tables)
-- ---------------------------------------------------------------------------
create table private.analytics_events (
    id          bigint generated always as identity primary key,
    event_name  text not null check (event_name in (
                    'search', 'venue_detail_view', 'favorite_added', 'navigation_opened',
                    'review_submitted', 'venue_submission_submitted', 'venue_submission_approved')),
    venue_id    uuid,
    properties  jsonb not null default '{}'::jsonb check (pg_column_size(properties) <= 1024),
    created_at  timestamptz not null default now()
);
create index analytics_events_name_created_idx on private.analytics_events (event_name, created_at);
