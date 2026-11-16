# Security and RLS

Implemented in `supabase/migrations/20261109000600_rls_grants_storage.sql`. SQL tests written in `supabase/tests/database/01_security_and_workflows.test.sql` — **not executed in this environment**.

## Principles

1. Identity always comes from the verified JWT (`auth.uid()`); no RPC accepts `user_id`, `is_admin`, `is_verified` or a moderation status from the client.
2. **Guest = authenticated anonymous user** (`auth.users.is_anonymous = true`), not the `anon` API role. **Registered** = non-anonymous with a confirmed identity allowed by settings: confirmed **email** by default (`registered_via_email = 1`); phone only if `registered_via_phone = 1` (`private.is_registered`). **Admin** = active row in `private.admin_users` *and* Registered, evaluated per call so revocation is immediate. **Business Owner** = active membership in an active business linked to the venue (`private.can_manage_venue`).
3. Supabase's default broad grants are **revoked** on all `public`/`private` tables and functions, then re-granted per object (tables, columns, and `EXECUTE`). Default privileges are also revoked for future objects.
4. RLS is enabled on every table (also in `private`, defence in depth).
5. Every `SECURITY DEFINER` function pins `search_path = ''` and fully qualifies names; a pgTAP test asserts this for all public definer functions.
6. Multi-step privileged workflows (approval, review submission, claim approval) run in one function = one transaction.

## Role × capability matrix

| Object / action | anon (no session) | Guest | Registered | Business Owner | Admin |
|---|---|---|---|---|---|
| Search/browse approved venues, reviews (RPC) | ✓ | ✓ | ✓ | ✓ | ✓ |
| `favorites` own rows (select/insert/delete) | – | ✓ | ✓ | ✓ | ✓ |
| `issue_visit_challenge` / `verify_visit` / `submit_review` | – | ✗ `registration_required` | ✓ | ✓ | ✓ |
| `create_venue_submission`, `request_venue_claim`, `flag_review` | – | ✗ | ✓ | ✓ | ✓ |
| Read own submissions / claims / memberships | – | own (none) | own | own | own (+ queues via RPC) |
| Read `venue_change_requests` | – | – | own | own business venues | via RPC |
| `admin_*` RPCs | – | ✗ `admin_required` | ✗ | ✗ | ✓ |
| Read `moderation_actions` | – | – | – | – | ✓ |
| Insert/update/delete `moderation_actions` | – | – | – | – | ✗ (append-only, definer functions only) |
| Direct writes to `venues`, `reviews`, `review_revisions`, `venue_submissions` | ✗ | ✗ | ✗ | ✗ | ✗ (RPC only) |
| `private.grant_admin` | ✗ | ✗ | ✗ | ✗ | ✗ — service role / SQL editor only |

## Column-level privacy

`reviews.user_id`, `review_revisions.user_id`, `visit_verification_id`, `idempotency_key`, `review_media.uploaded_by`, `venue_submissions.submitted_by/reviewed_by`, `business_memberships.approved_by` are **not granted** to API roles. Review lists expose only `display_name` and `is_mine`. Phone numbers stay in `auth.users`.

## Storage

Buckets (private, 5 MiB, `image/jpeg|png|heic|webp`) declared in `supabase/config.toml`: `venue-submission-media`, `review-media`.

| Policy | Rule |
|---|---|
| Upload submission photo | path `<auth.uid()>/<submission id>/<file>`; Registered; submission owned by caller and `pending_review|needs_changes`; extension allowlist |
| Read submission photo | owner folder, Admin, or path linked from an approved `venue_media` row |
| Upload review photo | path `<auth.uid()>/<revision id>/<file>`; Registered; revision is the caller's current revision |
| Read review photo | owner, Admin, or media `approved` on a published current revision |
| Delete | owner while pending |

The `attach_*_media` RPCs re-validate path shape, size and object existence before inserting metadata. Clients read via short-lived signed URLs.

## Hardening added in migration 0008 (free-auth release)

| Risk | Fix |
|---|---|
| SMS cost / SIM-farm abuse | Registered = verified email (free OTP). Phone switch kept in `app_settings`. Supabase rate limits + Turnstile CAPTCHA on anonymous sign-up and OTP. |
| OTP brute force | 6-digit code, 10-minute expiry, Supabase `token_verifications` rate limit; app accepts codes only via Supabase `verifyOTP`. |
| Account takeover by "linking" someone else's email | Linking an email that already has an account fails (`email_exists`); the app offers an explicit **Sign in** instead and never merges accounts. Sign-in uses `shouldCreateUser: false`. |
| Uploader id leaked through photo URLs | Storage paths are now `<submission or revision id>/<random>.jpg`; ownership is checked through the parent row (`owns_submission`, `owns_revision`). |
| Photo GPS/EXIF leaks home location | App re-renders every image to JPEG before upload, so EXIF/GPS is dropped (unit test checks no GPS dictionary). |
| Fake staff names / invisible-character spoofing | `update_my_display_name` strips control, zero-width and bidi characters and rejects names containing admin/moderator/nanglen/official/support/staff (and Thai equivalents) for non-admins. |
| Analytics spam / free-text PII | `log_event` now requires a session (no `anon`) and keeps only allowlisted keys with small scalar values. |
| Claim spam | Max 5 open claims per user (`claims_max_open`). |
| Filter abuse | `search_venues` validates tags against the catalog (≤ 5), rating 1–5, sort values; text ≤ 100 chars. |
| Unsafe links in user-submitted data | App opens only `http(s)` URLs without credentials; DB already requires `^https?://`. |
| Right to delete (App Store 5.1.1(v), PDPA) | `delete-account` Edge Function: identifies the caller from their JWT, removes their Storage files, deletes the auth user (cascades). Active Admins are blocked (revoke first). The service-role key stays in the function. |
| Contact data exposure | `get_my_capabilities` returns only a masked email (`m•••@gmail.com`); emails never appear in reviews, queues or claims. |

## Known limitations / follow-ups

- GPS can be spoofed; see LOCATION_VERIFICATION_DESIGN.md. App Attest is **Planned**.
- Anonymous sign-up and OTP abuse: enable Turnstile CAPTCHA and keep rate limits in the dashboard — **Requires external configuration**. The app does not yet send a CAPTCHA token; add the Turnstile iOS widget before turning CAPTCHA on, or sign-ups will fail.
- Disposable-email signups are possible; monitor and add a blocklist hook if abused.
- `log_event` has no per-user rate limit (identity is intentionally not stored); add an edge rate limiter if abused.
- Thailand PDPA review is required before commercial launch (not legal advice).
