-- Nanglen v2 — 0006: RLS, least-privilege grants, function EXECUTE grants, Storage policies.
-- Supabase grants broad default privileges to anon/authenticated on public objects; we revoke them and
-- re-grant explicitly. RLS is enabled on every public table.

-- ---------------------------------------------------------------------------
-- 1. Start from zero
-- ---------------------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
revoke all on all tables in schema private from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;

-- Future objects created by the migration role do not silently become public either.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on functions from public, anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema private revoke all on tables from public, anon, authenticated;
alter default privileges in schema private revoke all on functions from public, anon, authenticated;

grant usage on schema private to anon;  -- only so RLS/storage policies may call granted helpers

-- ---------------------------------------------------------------------------
-- 2. Enable RLS everywhere in public
-- ---------------------------------------------------------------------------
alter table public.profiles               enable row level security;
alter table public.business_accounts      enable row level security;
alter table public.business_memberships   enable row level security;
alter table public.venues                 enable row level security;
alter table public.venue_provider_refs    enable row level security;
alter table public.venue_submissions      enable row level security;
alter table public.venue_submission_media enable row level security;
alter table public.venue_media            enable row level security;
alter table public.review_tags            enable row level security;
alter table public.reviews                enable row level security;
alter table public.review_revisions       enable row level security;
alter table public.review_revision_tags   enable row level security;
alter table public.review_media           enable row level security;
alter table public.review_flags           enable row level security;
alter table public.favorites              enable row level security;
alter table public.venue_claims           enable row level security;
alter table public.venue_change_requests  enable row level security;
alter table public.moderation_actions     enable row level security;
-- private.* tables are not exposed through the Data API and have no grants; enable RLS anyway (defence in depth).
alter table private.app_settings          enable row level security;
alter table private.admin_users           enable row level security;
alter table private.visit_challenges      enable row level security;
alter table private.visit_verifications   enable row level security;
alter table private.analytics_events      enable row level security;

-- ---------------------------------------------------------------------------
-- 3. Helper functions callable from policies
-- ---------------------------------------------------------------------------
grant execute on function private.is_registered(uuid)            to anon, authenticated;
grant execute on function private.is_admin(uuid)                 to anon, authenticated;
grant execute on function private.can_manage_venue(uuid, uuid)   to authenticated;
grant execute on function private.normalize_name(text)           to anon, authenticated;

create function private.safe_uuid(p_text text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
begin
    return p_text::uuid;
exception when others then
    return null;
end;
$$;
grant execute on function private.safe_uuid(text) to anon, authenticated;

create function private.is_current_public_revision(p_revision uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (select 1 from public.reviews r where r.current_revision_id = p_revision and r.status = 'published');
$$;
grant execute on function private.is_current_public_revision(uuid) to anon, authenticated;

create function private.owns_open_submission(p_submission uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (select 1 from public.venue_submissions s
                   where s.id = p_submission and s.submitted_by = auth.uid() and s.status in ('pending_review', 'needs_changes'));
$$;
grant execute on function private.owns_open_submission(uuid) to authenticated;

create function private.owns_current_revision(p_revision uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (select 1 from public.review_revisions rv join public.reviews r on r.id = rv.review_id
                   where rv.id = p_revision and rv.user_id = auth.uid() and r.current_revision_id = rv.id);
$$;
grant execute on function private.owns_current_revision(uuid) to authenticated;

create function private.is_public_venue_media(p_bucket text, p_path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (select 1 from public.venue_media m join public.venues v on v.id = m.venue_id and v.status <> 'archived'
                   where m.bucket_id = p_bucket and m.storage_path = p_path);
$$;
grant execute on function private.is_public_venue_media(text, text) to anon, authenticated;

create function private.is_public_review_media(p_path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (select 1 from public.review_media m
                   join public.reviews r on r.current_revision_id = m.revision_id and r.status = 'published'
                   where m.storage_path = p_path and m.status = 'approved');
$$;
grant execute on function private.is_public_review_media(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Table grants (column-level where identity columns must stay private) + policies
-- ---------------------------------------------------------------------------

-- Venues: public catalog (archived hidden). No client writes.
grant select on public.venues to anon, authenticated;
create policy venues_public_read on public.venues for select to anon, authenticated
    using (status <> 'archived');

grant select on public.venue_provider_refs to anon, authenticated;
create policy venue_provider_refs_public_read on public.venue_provider_refs for select to anon, authenticated
    using (exists (select 1 from public.venues v where v.id = venue_id and v.status <> 'archived'));

grant select on public.venue_media to anon, authenticated;
create policy venue_media_public_read on public.venue_media for select to anon, authenticated
    using (exists (select 1 from public.venues v where v.id = venue_id and v.status <> 'archived'));

grant select on public.review_tags to anon, authenticated;
create policy review_tags_public_read on public.review_tags for select to anon, authenticated using (is_active);

-- Reviews: published are public; author and Admin can also see hidden ones. user_id is NOT granted.
grant select (id, venue_id, current_revision_id, status, created_at, updated_at) on public.reviews to anon, authenticated;
create policy reviews_read on public.reviews for select to anon, authenticated
    using (status = 'published' or user_id = (select auth.uid()) or (select private.is_admin()));

-- Revisions: only the current revision of a published review is public; history is visible to its author/Admin.
-- visit_verification_id, idempotency_key and user_id are NOT granted.
grant select (id, review_id, revision_number, rating, visit_purpose, body, created_at) on public.review_revisions to anon, authenticated;
create policy review_revisions_read on public.review_revisions for select to anon, authenticated
    using (private.is_current_public_revision(id) or user_id = (select auth.uid()) or (select private.is_admin()));

grant select on public.review_revision_tags to anon, authenticated;
create policy review_revision_tags_read on public.review_revision_tags for select to anon, authenticated
    using (private.is_current_public_revision(revision_id)
           or exists (select 1 from public.review_revisions rv where rv.id = revision_id and rv.user_id = (select auth.uid())));

grant select (id, revision_id, storage_path, mime_type, width, height, display_order, status, created_at) on public.review_media to anon, authenticated;
create policy review_media_read on public.review_media for select to anon, authenticated
    using ((status = 'approved' and private.is_current_public_revision(revision_id))
           or uploaded_by = (select auth.uid()) or (select private.is_admin()));

-- Views are security_invoker: callers need SELECT on the view; base-table RLS + column grants apply.
grant select on public.venue_rating_summaries to anon, authenticated;
grant select on public.venue_tag_counts to anon, authenticated;

-- Profiles: owner-only read. Public display names are only exposed through review RPCs.
grant select (id, display_name, created_at) on public.profiles to authenticated;
create policy profiles_owner_read on public.profiles for select to authenticated using (id = (select auth.uid()));

-- Favorites: owner-only, Guests included (anonymous auth user). user_id defaults to auth.uid() and is checked.
grant select, insert, delete on public.favorites to authenticated;
create policy favorites_owner_read on public.favorites for select to authenticated using (user_id = (select auth.uid()));
create policy favorites_owner_insert on public.favorites for insert to authenticated
    with check (user_id = (select auth.uid())
                and exists (select 1 from public.venues v where v.id = venue_id and v.status <> 'archived'));
create policy favorites_owner_delete on public.favorites for delete to authenticated using (user_id = (select auth.uid()));

-- Submissions: submitter reads own rows; all writes go through RPCs. Reviewer identity not granted.
grant select (id, client_request_id, name, category, formatted_address, latitude, longitude, provider, external_place_id,
              description, website_url, phone_number, submitter_note, status, revision, duplicate_of_venue_id,
              approved_venue_id, reviewed_at, decision_reason, submitted_at, created_at, updated_at)
    on public.venue_submissions to authenticated;
create policy venue_submissions_owner_read on public.venue_submissions for select to authenticated
    using (submitted_by = (select auth.uid()));

grant select (id, submission_id, storage_path, mime_type, display_order, status, created_at) on public.venue_submission_media to authenticated;
create policy venue_submission_media_owner_read on public.venue_submission_media for select to authenticated
    using (uploaded_by = (select auth.uid()));

-- Flags: no direct access (RPC only).

-- Business: members see their own business and memberships.
grant select on public.business_accounts to authenticated;
create policy business_accounts_member_read on public.business_accounts for select to authenticated
    using (exists (select 1 from public.business_memberships m
                   where m.business_id = id and m.user_id = (select auth.uid()) and m.status = 'active'));

grant select (id, business_id, user_id, role, status, created_at) on public.business_memberships to authenticated;
create policy business_memberships_own_read on public.business_memberships for select to authenticated
    using (user_id = (select auth.uid()));

grant select (id, venue_id, client_request_id, business_name, claimant_role, contact_note, evidence_note, status,
              business_id, reviewed_at, decision_reason, created_at, updated_at)
    on public.venue_claims to authenticated;
create policy venue_claims_owner_read on public.venue_claims for select to authenticated
    using (requested_by = (select auth.uid()));

grant select on public.venue_change_requests to authenticated;
create policy venue_change_requests_member_read on public.venue_change_requests for select to authenticated
    using (requested_by = (select auth.uid()) or private.can_manage_venue(venue_id));

-- Audit: Admin read-only; nobody can insert/update/delete through the API.
grant select on public.moderation_actions to authenticated;
create policy moderation_actions_admin_read on public.moderation_actions for select to authenticated
    using ((select private.is_admin()));

-- ---------------------------------------------------------------------------
-- 5. RPC EXECUTE grants (explicit allowlist)
-- ---------------------------------------------------------------------------
-- Public browsing (anon key without session is allowed so browsing works even if anonymous sign-in fails).
grant execute on function public.search_venues(text, double precision, double precision, double precision, public.venue_category, numeric, text, integer, integer) to anon, authenticated;
grant execute on function public.get_venue_cards(uuid[], double precision, double precision) to anon, authenticated;
grant execute on function public.match_provider_refs(text, text[]) to anon, authenticated;
grant execute on function public.get_venue(uuid) to anon, authenticated;
grant execute on function public.list_venue_reviews(uuid, text, integer, integer) to anon, authenticated;
grant execute on function public.list_review_tags() to anon, authenticated;
grant execute on function public.get_public_config() to anon, authenticated;
grant execute on function public.log_event(text, uuid, jsonb) to anon, authenticated;

-- Signed-in (Guest or Registered). Functions themselves enforce Registered where required.
grant execute on function public.get_my_capabilities() to authenticated;
grant execute on function public.my_favorite_venue_ids() to authenticated;
grant execute on function public.issue_visit_challenge(uuid) to authenticated;
grant execute on function public.verify_visit(uuid, double precision, double precision, double precision, timestamptz) to authenticated;
grant execute on function public.submit_review(uuid, uuid, integer, public.visit_purpose, text[], text, uuid) to authenticated;
grant execute on function public.attach_review_media(uuid, text, text, integer, integer, integer) to authenticated;
grant execute on function public.flag_review(uuid, public.flag_reason, text) to authenticated;
grant execute on function public.create_venue_submission(uuid, text, public.venue_category, text, double precision, double precision, text, text, text, text, text, text) to authenticated;
grant execute on function public.resubmit_venue_submission(uuid, text, public.venue_category, text, double precision, double precision, text, text, text, text) to authenticated;
grant execute on function public.withdraw_venue_submission(uuid) to authenticated;
grant execute on function public.attach_submission_media(uuid, text, text, integer, integer, integer) to authenticated;
grant execute on function public.update_my_display_name(text) to authenticated;
grant execute on function public.request_venue_claim(uuid, uuid, text, public.membership_role, text, text) to authenticated;

-- Admin RPCs: granted to authenticated, but each one calls private.require_admin() first.
grant execute on function public.admin_list_venue_submissions(public.submission_status, integer, integer) to authenticated;
grant execute on function public.admin_get_venue_submission(uuid) to authenticated;
grant execute on function public.admin_approve_venue_submission(uuid, text, boolean) to authenticated;
grant execute on function public.admin_reject_venue_submission(uuid, text) to authenticated;
grant execute on function public.admin_request_submission_changes(uuid, text) to authenticated;
grant execute on function public.admin_mark_submission_duplicate(uuid, uuid, text) to authenticated;
grant execute on function public.admin_list_venue_claims(public.claim_status, integer) to authenticated;
grant execute on function public.admin_decide_venue_claim(uuid, boolean, text) to authenticated;
grant execute on function public.admin_list_flagged_reviews(integer) to authenticated;
grant execute on function public.admin_moderate_review(uuid, public.review_status, text) to authenticated;
grant execute on function public.admin_list_pending_review_media(integer) to authenticated;
grant execute on function public.admin_set_review_media_status(uuid, public.media_status, text) to authenticated;

-- private.grant_admin / revoke_admin: service_role / SQL editor only (no grant to API roles).

-- ---------------------------------------------------------------------------
-- 6. Storage policies (buckets are declared in supabase/config.toml / created via the Storage API).
--    Paths: '<auth.uid()>/<submission or revision uuid>/<uuid>.<ext>'. Both buckets are PRIVATE;
--    reads go through signed URLs which still require the SELECT policy below.
-- ---------------------------------------------------------------------------
create policy "submission media: registered owner uploads to own open submission"
    on storage.objects for insert to authenticated
    with check (
        bucket_id = 'venue-submission-media'
        and (storage.foldername(name))[1] = (select auth.uid())::text
        and private.is_registered()
        and private.owns_open_submission(private.safe_uuid((storage.foldername(name))[2]))
        and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'heic', 'webp')
    );

create policy "submission media: owner, admin, or approved venue photo"
    on storage.objects for select to anon, authenticated
    using (
        bucket_id = 'venue-submission-media'
        and ((storage.foldername(name))[1] = (select auth.uid())::text
             or (select private.is_admin())
             or private.is_public_venue_media(bucket_id, name))
    );

create policy "submission media: owner deletes while submission is open"
    on storage.objects for delete to authenticated
    using (
        bucket_id = 'venue-submission-media'
        and (storage.foldername(name))[1] = (select auth.uid())::text
        and private.owns_open_submission(private.safe_uuid((storage.foldername(name))[2]))
    );

create policy "review media: registered owner uploads to own current revision"
    on storage.objects for insert to authenticated
    with check (
        bucket_id = 'review-media'
        and (storage.foldername(name))[1] = (select auth.uid())::text
        and private.is_registered()
        and private.owns_current_revision(private.safe_uuid((storage.foldername(name))[2]))
        and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'heic', 'webp')
    );

create policy "review media: owner, admin, or approved and published"
    on storage.objects for select to anon, authenticated
    using (
        bucket_id = 'review-media'
        and ((storage.foldername(name))[1] = (select auth.uid())::text
             or (select private.is_admin())
             or private.is_public_review_media(name))
    );

create policy "review media: owner deletes own pending upload"
    on storage.objects for delete to authenticated
    using (
        bucket_id = 'review-media'
        and (storage.foldername(name))[1] = (select auth.uid())::text
        and not private.is_public_review_media(name)
    );
