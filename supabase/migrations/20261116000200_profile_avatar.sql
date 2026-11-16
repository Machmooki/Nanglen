-- Profile photos (avatars).
--
-- Storage: private bucket 'avatars'. Object names are '<random uuid>.<ext>' at the bucket root, so a path never
-- reveals the auth user id. Ownership comes from storage.objects.owner_id (set by Storage to the uploader).
-- Flow: the app uploads the file, then calls set_my_avatar(path). The RPC checks the caller uploaded that object,
-- stores the path on the profile and returns the previous path so the app can delete the old file.

-- ---------------------------------------------------------------------------
-- 1. Bucket (also declared in supabase/config.toml for local dev)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Column
-- ---------------------------------------------------------------------------
alter table public.profiles
    add column if not exists avatar_path text
    check (avatar_path is null or avatar_path ~ '^[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$');

create unique index if not exists profiles_avatar_path_key on public.profiles (avatar_path) where avatar_path is not null;

-- ---------------------------------------------------------------------------
-- 3. Helpers + RPCs
-- ---------------------------------------------------------------------------
create function private.is_profile_avatar(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (select 1 from public.profiles p where p.avatar_path = p_name);
$$;
grant execute on function private.is_profile_avatar(text) to anon, authenticated;

-- Sets the caller's profile photo to an object they just uploaded. Returns {"previous_path": text|null}.
create function public.set_my_avatar(p_storage_path text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_uid      uuid := private.require_registered();
    v_previous text;
begin
    if p_storage_path is null or p_storage_path !~ '^[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$' then
        raise exception 'invalid_storage_path' using errcode = '22023';
    end if;
    if not exists (select 1 from storage.objects o
                   where o.bucket_id = 'avatars' and o.name = p_storage_path and o.owner_id = v_uid::text) then
        raise exception 'invalid_storage_path' using errcode = '22023';
    end if;
    select p.avatar_path into v_previous from public.profiles p where p.id = v_uid for update;
    update public.profiles set avatar_path = p_storage_path where id = v_uid;
    return jsonb_build_object('previous_path', nullif(v_previous, p_storage_path));
end;
$$;

-- Removes the caller's profile photo. Returns {"previous_path": text|null} for the app to delete.
create function public.clear_my_avatar()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_uid      uuid := private.require_registered();
    v_previous text;
begin
    select p.avatar_path into v_previous from public.profiles p where p.id = v_uid for update;
    update public.profiles set avatar_path = null where id = v_uid;
    return jsonb_build_object('previous_path', v_previous);
end;
$$;

revoke all on function public.set_my_avatar(text) from public, anon;
revoke all on function public.clear_my_avatar() from public, anon;
grant execute on function public.set_my_avatar(text) to authenticated;
grant execute on function public.clear_my_avatar() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Storage policies
-- ---------------------------------------------------------------------------
create policy "avatars: registered user uploads own photo"
    on storage.objects for insert to authenticated
    with check (
        bucket_id = 'avatars'
        and array_length(storage.foldername(name), 1) is null
        and name ~ '^[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$'
        and private.is_registered()
    );

-- Readable by the uploader, and by everyone once it is someone's current profile photo
-- (so it can appear next to that person's reviews later).
create policy "avatars: owner or in-use profile photo"
    on storage.objects for select to anon, authenticated
    using (
        bucket_id = 'avatars'
        and (owner_id = (select auth.uid())::text or private.is_profile_avatar(name))
    );

create policy "avatars: owner deletes own photo"
    on storage.objects for delete to authenticated
    using (bucket_id = 'avatars' and owner_id = (select auth.uid())::text);

-- ---------------------------------------------------------------------------
-- 5. Capabilities now include avatar_path
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
        'avatar_path', (select p.avatar_path from public.profiles p where p.id = v_uid),
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
