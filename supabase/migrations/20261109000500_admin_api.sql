-- Nanglen v2 — 0005: Admin moderation API. Every function calls private.require_admin() and writes
-- an append-only moderation_actions row in the same transaction.

create function public.admin_list_venue_submissions(
    p_status public.submission_status default 'pending_review',
    p_limit  integer default 50,
    p_offset integer default 0)
returns table (
    id uuid, name text, category public.venue_category, formatted_address text,
    latitude double precision, longitude double precision, status public.submission_status,
    revision integer, submitted_at timestamptz, submitter_name text,
    media_count integer, duplicate_candidate_count integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    perform private.require_admin();
    return query
    select s.id, s.name, s.category, s.formatted_address, s.latitude, s.longitude, s.status, s.revision, s.submitted_at,
           p.display_name,
           (select count(*)::integer from public.venue_submission_media m where m.submission_id = s.id),
           jsonb_array_length(private.duplicate_candidates(s.name, s.location, s.provider, s.external_place_id))
    from public.venue_submissions s
    join public.profiles p on p.id = s.submitted_by
    where s.status = p_status
    order by s.submitted_at asc nulls last, s.id
    limit least(greatest(coalesce(p_limit, 50), 1), 100) offset least(greatest(coalesce(p_offset, 0), 0), 1000);
end;
$$;

create function public.admin_get_venue_submission(p_submission_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_result jsonb;
begin
    perform private.require_admin();
    select jsonb_build_object(
        'id', s.id, 'name', s.name, 'category', s.category, 'formatted_address', s.formatted_address,
        'latitude', s.latitude, 'longitude', s.longitude, 'provider', s.provider, 'external_place_id', s.external_place_id,
        'description', s.description, 'website_url', s.website_url, 'phone_number', s.phone_number,
        'submitter_note', s.submitter_note, 'status', s.status, 'revision', s.revision,
        'decision_reason', s.decision_reason, 'submitted_at', s.submitted_at, 'created_at', s.created_at,
        'duplicate_of_venue_id', s.duplicate_of_venue_id, 'approved_venue_id', s.approved_venue_id,
        -- Submitter context without phone/auth identifiers.
        'submitter', jsonb_build_object(
            'display_name', p.display_name,
            'total_submissions', (select count(*) from public.venue_submissions x where x.submitted_by = s.submitted_by),
            'approved_submissions', (select count(*) from public.venue_submissions x where x.submitted_by = s.submitted_by and x.status = 'approved')),
        'media', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'storage_path', m.storage_path, 'status', m.status) order by m.display_order)
                           from public.venue_submission_media m where m.submission_id = s.id), '[]'::jsonb),
        'duplicate_candidates', private.duplicate_candidates(s.name, s.location, s.provider, s.external_place_id, 10),
        'history', coalesce((select jsonb_agg(jsonb_build_object('action', a.action, 'reason', a.reason, 'created_at', a.created_at) order by a.created_at desc)
                             from public.moderation_actions a where a.target_type = 'venue_submission' and a.target_id = s.id), '[]'::jsonb)
    ) into v_result
    from public.venue_submissions s
    join public.profiles p on p.id = s.submitted_by
    where s.id = p_submission_id;
    if v_result is null then
        raise exception 'submission_not_found' using errcode = 'P0002';
    end if;
    return v_result;
end;
$$;

-- Approve: one transaction creates the canonical venue, provider ref and photo links, updates the
-- submission and writes the audit event. Any failure rolls back everything.
create function public.admin_approve_venue_submission(
    p_submission_id uuid,
    p_note          text default null,
    p_force         boolean default false)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_admin  uuid := private.require_admin();
    v_sub    public.venue_submissions;
    v_venue  uuid;
    v_likely jsonb;
begin
    select * into v_sub from public.venue_submissions s where s.id = p_submission_id for update;
    if not found then
        raise exception 'submission_not_found' using errcode = 'P0002';
    end if;
    if v_sub.status <> 'pending_review' then
        raise exception 'invalid_status_transition' using errcode = '55000';
    end if;

    -- Re-check duplicates at decision time.
    if v_sub.external_place_id is not null and exists (
        select 1 from public.venue_provider_refs r where r.provider = v_sub.provider and r.external_place_id = v_sub.external_place_id) then
        raise exception 'provider_ref_exists' using errcode = '23505', hint = 'Mark the submission as duplicate instead.';
    end if;
    select coalesce(jsonb_agg(c), '[]'::jsonb) into v_likely
    from jsonb_array_elements(private.duplicate_candidates(v_sub.name, v_sub.location, v_sub.provider, v_sub.external_place_id, 10)) c
    where (c->>'name_similarity')::numeric >= 0.6 and (c->>'distance_m')::numeric <= 50;
    if jsonb_array_length(v_likely) > 0 and not coalesce(p_force, false) then
        raise exception 'likely_duplicate' using errcode = '23505', detail = v_likely::text;
    end if;

    insert into public.venues (name, description, category, formatted_address, location, website_url, phone_number,
                               details_source, provenance, source_submission_id, created_by)
    values (v_sub.name, v_sub.description, v_sub.category, v_sub.formatted_address, v_sub.location,
            v_sub.website_url, v_sub.phone_number,
            case when v_sub.website_url is not null or v_sub.phone_number is not null then 'community_submission' end,
            'community_submission', v_sub.id, v_admin)
    returning id into v_venue;

    if v_sub.external_place_id is not null then
        insert into public.venue_provider_refs (venue_id, provider, external_place_id)
        values (v_venue, v_sub.provider, v_sub.external_place_id);
    end if;

    update public.venue_submission_media set status = 'approved' where submission_id = v_sub.id and status = 'pending';
    insert into public.venue_media (venue_id, bucket_id, storage_path, source, display_order)
    select v_venue, 'venue-submission-media', m.storage_path, 'submission', m.display_order
    from public.venue_submission_media m where m.submission_id = v_sub.id and m.status = 'approved';

    update public.venue_submissions
    set status = 'approved', approved_venue_id = v_venue, reviewed_by = v_admin, reviewed_at = now(),
        decision_reason = nullif(btrim(coalesce(p_note, '')), '')
    where id = v_sub.id;

    perform private.audit(v_admin, 'submission_approved', 'venue_submission', v_sub.id, v_sub.status::text, 'approved',
                          nullif(btrim(coalesce(p_note, '')), ''), jsonb_build_object('venue_id', v_venue, 'forced', coalesce(p_force, false)));
    insert into private.analytics_events (event_name, venue_id) values ('venue_submission_approved', v_venue);

    return jsonb_build_object('venue_id', v_venue, 'submission_id', v_sub.id, 'status', 'approved');
end;
$$;

create function private.decide_submission(
    p_submission_id uuid, p_new public.submission_status, p_reason text, p_duplicate_of uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_admin  uuid := private.require_admin();
    v_sub    public.venue_submissions;
    v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
    v_action text;
begin
    if v_reason is null then
        raise exception 'reason_required' using errcode = '22023';
    end if;
    select * into v_sub from public.venue_submissions s where s.id = p_submission_id for update;
    if not found then
        raise exception 'submission_not_found' using errcode = 'P0002';
    end if;
    if v_sub.status <> 'pending_review' then
        raise exception 'invalid_status_transition' using errcode = '55000';
    end if;
    if p_new = 'duplicate' and not exists (select 1 from public.venues v where v.id = p_duplicate_of and v.status <> 'archived') then
        raise exception 'venue_not_found' using errcode = 'P0002';
    end if;

    update public.venue_submissions
    set status = p_new, decision_reason = v_reason, reviewed_by = v_admin, reviewed_at = now(),
        duplicate_of_venue_id = case when p_new = 'duplicate' then p_duplicate_of else duplicate_of_venue_id end
    where id = v_sub.id;

    if p_new in ('rejected', 'duplicate') then
        update public.venue_submission_media set status = 'rejected' where submission_id = v_sub.id and status = 'pending';
    end if;

    v_action := case p_new when 'rejected' then 'submission_rejected'
                           when 'duplicate' then 'submission_duplicate'
                           when 'needs_changes' then 'submission_needs_changes' end;
    if v_action is null then
        raise exception 'invalid_status_transition' using errcode = '55000';
    end if;
    perform private.audit(v_admin, v_action, 'venue_submission', v_sub.id, v_sub.status::text, p_new::text, v_reason,
                          case when p_duplicate_of is not null then jsonb_build_object('duplicate_of_venue_id', p_duplicate_of) else '{}'::jsonb end);
    return jsonb_build_object('submission_id', v_sub.id, 'status', p_new);
end;
$$;

create function public.admin_reject_venue_submission(p_submission_id uuid, p_reason text)
returns jsonb language sql volatile security definer set search_path = ''
as $$ select private.decide_submission(p_submission_id, 'rejected', p_reason); $$;

create function public.admin_request_submission_changes(p_submission_id uuid, p_reason text)
returns jsonb language sql volatile security definer set search_path = ''
as $$ select private.decide_submission(p_submission_id, 'needs_changes', p_reason); $$;

create function public.admin_mark_submission_duplicate(p_submission_id uuid, p_venue_id uuid, p_reason text default 'ซ้ำกับสถานที่ที่มีอยู่แล้วใน Nanglen')
returns jsonb language sql volatile security definer set search_path = ''
as $$ select private.decide_submission(p_submission_id, 'duplicate', p_reason, p_venue_id); $$;

-- ---------------------------------------------------------------------------
-- Claims → business account + scoped membership
-- ---------------------------------------------------------------------------
create function public.admin_list_venue_claims(p_status public.claim_status default 'pending_review', p_limit integer default 50)
returns table (id uuid, venue_id uuid, venue_name text, business_name text, claimant_role public.membership_role,
               claimant_name text, contact_note text, evidence_note text, status public.claim_status, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    perform private.require_admin();
    return query
    select c.id, c.venue_id, v.name, c.business_name, c.claimant_role, p.display_name, c.contact_note, c.evidence_note, c.status, c.created_at
    from public.venue_claims c
    join public.venues v on v.id = c.venue_id
    join public.profiles p on p.id = c.requested_by
    where c.status = p_status
    order by c.created_at
    limit least(greatest(coalesce(p_limit, 50), 1), 100);
end;
$$;

create function public.admin_decide_venue_claim(p_claim_id uuid, p_approve boolean, p_reason text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_admin    uuid := private.require_admin();
    v_claim    public.venue_claims;
    v_business uuid;
    v_reason   text := nullif(btrim(coalesce(p_reason, '')), '');
begin
    select * into v_claim from public.venue_claims c where c.id = p_claim_id for update;
    if not found then
        raise exception 'claim_not_found' using errcode = 'P0002';
    end if;
    if v_claim.status <> 'pending_review' then
        raise exception 'invalid_status_transition' using errcode = '55000';
    end if;

    if not p_approve then
        if v_reason is null then
            raise exception 'reason_required' using errcode = '22023';
        end if;
        update public.venue_claims set status = 'rejected', reviewed_by = v_admin, reviewed_at = now(), decision_reason = v_reason where id = v_claim.id;
        perform private.audit(v_admin, 'claim_rejected', 'venue_claim', v_claim.id, 'pending_review', 'rejected', v_reason);
        return jsonb_build_object('claim_id', v_claim.id, 'status', 'rejected');
    end if;

    if not private.is_registered(v_claim.requested_by) then
        raise exception 'claimant_not_registered' using errcode = '42501';
    end if;
    select v.business_id into v_business from public.venues v where v.id = v_claim.venue_id for update;
    if v_business is null then
        insert into public.business_accounts (name, created_by) values (v_claim.business_name, v_claim.requested_by)
        returning id into v_business;
        update public.venues set business_id = v_business where id = v_claim.venue_id;
    end if;
    insert into public.business_memberships (business_id, user_id, role, status, approved_by)
    values (v_business, v_claim.requested_by, v_claim.claimant_role, 'active', v_admin)
    on conflict (business_id, user_id) do update set status = 'active', role = excluded.role, approved_by = excluded.approved_by;

    update public.venue_claims set status = 'approved', business_id = v_business, reviewed_by = v_admin, reviewed_at = now(), decision_reason = v_reason
    where id = v_claim.id;
    perform private.audit(v_admin, 'claim_approved', 'venue_claim', v_claim.id, 'pending_review', 'approved', v_reason,
                          jsonb_build_object('business_id', v_business, 'venue_id', v_claim.venue_id));
    return jsonb_build_object('claim_id', v_claim.id, 'status', 'approved', 'business_id', v_business);
end;
$$;

-- ---------------------------------------------------------------------------
-- Post-publication review moderation and media moderation
-- ---------------------------------------------------------------------------
create function public.admin_list_flagged_reviews(p_limit integer default 50)
returns table (review_id uuid, venue_id uuid, venue_name text, author_name text, rating smallint, body text,
               review_status public.review_status, open_flags integer, reasons text[], last_flagged_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    perform private.require_admin();
    return query
    select r.id, r.venue_id, v.name, p.display_name, rv.rating, rv.body, r.status,
           count(f.id)::integer, array_agg(distinct f.reason::text), max(f.created_at)
    from public.review_flags f
    join public.reviews r on r.id = f.review_id
    join public.review_revisions rv on rv.id = r.current_revision_id
    join public.venues v on v.id = r.venue_id
    join public.profiles p on p.id = r.user_id
    where f.status = 'open'
    group by r.id, r.venue_id, v.name, p.display_name, rv.rating, rv.body, r.status
    order by count(f.id) desc, max(f.created_at)
    limit least(greatest(coalesce(p_limit, 50), 1), 100);
end;
$$;

create function public.admin_moderate_review(p_review_id uuid, p_status public.review_status, p_reason text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_admin  uuid := private.require_admin();
    v_prev   public.review_status;
    v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
    v_action text;
begin
    if v_reason is null then
        raise exception 'reason_required' using errcode = '22023';
    end if;
    select r.status into v_prev from public.reviews r where r.id = p_review_id for update;
    if not found then
        raise exception 'review_not_found' using errcode = 'P0002';
    end if;
    if v_prev = 'removed' then
        raise exception 'invalid_status_transition' using errcode = '55000';
    end if;

    update public.reviews set status = p_status where id = p_review_id;
    update public.review_flags
    set status = case when p_status = 'published' then 'dismissed'::public.flag_status else 'actioned'::public.flag_status end,
        resolved_by = v_admin, resolved_at = now()
    where review_id = p_review_id and status = 'open';

    v_action := case
        when p_status = v_prev and p_status = 'published' then 'flag_dismissed'
        when p_status = 'published' then 'review_restored'
        when p_status = 'hidden' then 'review_hidden'
        else 'review_removed' end;
    perform private.audit(v_admin, v_action, 'review', p_review_id, v_prev::text, p_status::text, v_reason);
    return jsonb_build_object('review_id', p_review_id, 'status', p_status);
end;
$$;

create function public.admin_list_pending_review_media(p_limit integer default 50)
returns table (media_id uuid, review_id uuid, venue_name text, storage_path text, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    perform private.require_admin();
    return query
    select m.id, r.id, v.name, m.storage_path, m.created_at
    from public.review_media m
    join public.review_revisions rv on rv.id = m.revision_id
    join public.reviews r on r.id = rv.review_id
    join public.venues v on v.id = r.venue_id
    where m.status = 'pending'
    order by m.created_at
    limit least(greatest(coalesce(p_limit, 50), 1), 100);
end;
$$;

create function public.admin_set_review_media_status(p_media_id uuid, p_status public.media_status, p_reason text default null)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_admin uuid := private.require_admin();
    v_prev  public.media_status;
begin
    if p_status = 'pending' then
        raise exception 'invalid_status_transition' using errcode = '55000';
    end if;
    select m.status into v_prev from public.review_media m where m.id = p_media_id for update;
    if not found then
        raise exception 'media_not_found' using errcode = 'P0002';
    end if;
    update public.review_media set status = p_status where id = p_media_id;
    perform private.audit(v_admin, case when p_status = 'approved' then 'media_approved' else 'media_rejected' end,
                          'review_media', p_media_id, v_prev::text, p_status::text, nullif(btrim(coalesce(p_reason, '')), ''));
end;
$$;
