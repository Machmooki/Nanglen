# Security and RLS

Implemented in `supabase/migrations/20261109000600_rls_grants_storage.sql`. SQL tests written in `supabase/tests/database/01_security_and_workflows.test.sql` — **not executed in this environment**.

## Principles

1. Identity always comes from the verified JWT (`auth.uid()`); no RPC accepts `user_id`, `is_admin`, `is_verified` or a moderation status from the client.
2. **Guest = authenticated anonymous user** (`auth.users.is_anonymous = true`), not the `anon` API role. **Registered** = non-anonymous with `phone_confirmed_at` (`private.is_registered`). **Admin** = active row in `private.admin_users` *and* Registered, evaluated per call so revocation is immediate. **Business Owner** = active membership in an active business linked to the venue (`private.can_manage_venue`).
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

## Known limitations / follow-ups

- GPS can be spoofed; see LOCATION_VERIFICATION_DESIGN.md. App Attest is **Planned**.
- Anonymous sign-up abuse: enable CAPTCHA (hCaptcha/Turnstile) and rate limits in the Supabase dashboard — **Requires external configuration**.
- `log_event` has no per-user rate limit (identity is intentionally not stored); add an edge rate limiter if abused.
- Thailand PDPA review is required before commercial launch (not legal advice).
