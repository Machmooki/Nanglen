# Database Design

Source: `supabase/migrations/2026110900*_*.sql` (ordered, additive). Status legend: **Implemented** = written in a migration; **Tested** = covered by `supabase/tests/database/01_security_and_workflows.test.sql` **(written, not yet executed — no local Postgres/Docker was available)**.

## Schemas

| Schema | Exposed via Data API | Contents |
|---|---|---|
| `public` | yes (only this one) | Catalog, reviews, submissions, favorites, claims, audit, views, RPCs |
| `private` | no | `app_settings`, `admin_users`, `visit_challenges`, `visit_verifications`, `analytics_events`, helper functions |
| `extensions` | no | `postgis`, `pg_trgm`, `pgcrypto` |

## Core tables

| Table | Purpose | Key constraints |
|---|---|---|
| `profiles` | Public-safe display name, 1:1 with `auth.users` (trigger creates row for every auth user, anonymous included) | PK = `auth.users.id`, name 1–40 chars |
| `venues` | **Approved canonical venues only** | `location geography(Point,4326)` is the single source of truth; `latitude/longitude` are *generated* from it; `normalized_name` generated; GiST on location; trigram GIN on name; status enum |
| `venue_provider_refs` | External IDs (Apple Maps, curated) | `UNIQUE(provider, external_place_id)` |
| `venue_submissions` | User-proposed places awaiting Admin | `UNIQUE(submitted_by, client_request_id)` (idempotency); CHECKs: duplicate ⇒ `duplicate_of_venue_id`, approved ⇒ `approved_venue_id`, rejected/needs_changes/duplicate ⇒ `decision_reason` |
| `venue_submission_media`, `venue_media` | Storage object references (pending vs. published) | MIME allowlist, ≤ 5 MB, unique path |
| `review_tags` | Controlled taxonomy (10 tags, TH/EN labels) | slug regex |
| `reviews` | One current review per user per venue | `UNIQUE(venue_id, user_id)`; `current_revision_id` FK deferrable |
| `review_revisions` | Immutable revision per verified visit | `UNIQUE(visit_verification_id)` (a verification is used once); `UNIQUE(user_id, idempotency_key)`; rating 1–5; body ≤ 500; UPDATE blocked by trigger |
| `review_revision_tags` | Normalized tag assignments | ≤ 3 per revision enforced by trigger *and* RPC |
| `review_media` | Review photos (pending until Admin approves) | display_order 0–2 |
| `review_flags` | User reports | `UNIQUE(review_id, flagged_by)` |
| `favorites` | Guest or Registered saved venues | PK `(user_id, venue_id)`; `user_id DEFAULT auth.uid()` |
| `business_accounts`, `business_memberships` | Scoped Business Owner capability | membership `UNIQUE(business_id,user_id)`, role/status enums |
| `venue_claims` | Claim requests | one open claim per (venue, user) partial unique index; reject ⇒ reason |
| `venue_change_requests` | Phase-2 owner proposals | JSON ≤ 8 KB |
| `moderation_actions` | **Append-only** audit | UPDATE/DELETE blocked by trigger; inserts only from SECURITY DEFINER functions |
| `private.visit_challenges` | One-time, 120 s, user+venue bound | consumed by first evaluation |
| `private.visit_verifications` | Outcome + coarse buckets only (no coordinates) | `UNIQUE(challenge_id)`; consumable only if `status = verified` |
| `private.app_settings` | Tunable thresholds (radius 100 m, accuracy 50 m, age 60 s, TTLs, rate limits, ranking prior) | read via `private.setting_numeric` |

## Views

- `venue_rating_summaries` — count, average (2 dp), distribution, last review — over the **current revision of published reviews** only. Venues with no reviews have no row → callers get `NULL`, never `0.0`.
- `venue_tag_counts` — tag frequency over current published revisions.

Both are `security_invoker = true`.

## RPC contract (public)

| Function | Caller | Notes |
|---|---|---|
| `search_venues(query, lat, lng, radius, category, min_rating, sort, limit, offset)` | anon, authenticated | Approved & open venues only; limit ≤ 50, offset ≤ 500; relevance + Bayesian + distance (see PERFORMANCE_STRATEGY.md) |
| `get_venue_cards(ids[], lat, lng)` | anon, authenticated | ≤ 100 ids |
| `get_venue(id)` | anon, authenticated | detail + tags + photos + caller's own review + `is_favorite` / `is_managed_by_me` |
| `list_venue_reviews(id, sort, limit, offset)` | anon, authenticated | display name only, `is_mine`, approved photo paths |
| `match_provider_refs(provider, ids[])` | anon, authenticated | maps Apple Maps IDs → canonical IDs |
| `get_public_config()`, `list_review_tags()` | anon, authenticated | |
| `get_my_capabilities()` | authenticated | server-derived roles; never trust local flags |
| `issue_visit_challenge`, `verify_visit`, `submit_review`, `attach_review_media`, `flag_review` | authenticated (Registered enforced) | see LOCATION_VERIFICATION_DESIGN.md |
| `create_venue_submission`, `resubmit_venue_submission`, `withdraw_venue_submission`, `attach_submission_media` | authenticated (Registered enforced; withdraw = owner) | |
| `request_venue_claim`, `update_my_display_name` | authenticated (Registered) | |
| `admin_*` (12 functions) | authenticated, but each calls `private.require_admin()` | all write `moderation_actions` in the same transaction |
| `log_event(name, venue_id, props)` | anon, authenticated | allowlisted names, identity/coordinate keys stripped |

## Status machines

```
venue_submissions: pending_review ──admin──▶ approved | rejected | duplicate | needs_changes
                   needs_changes ──submitter resubmit──▶ pending_review (revision+1)
                   pending_review | needs_changes ──submitter──▶ withdrawn
reviews:           published ⇄ hidden (admin) ; published|hidden ──admin──▶ removed (terminal)
venue_claims:      pending_review ──admin──▶ approved (creates business + membership) | rejected
```

## Seed data

`supabase/seed.sql` (dev only): 8 fictional venues marked "(ตัวอย่าง)" with name/category/location/address and `curated` provider refs. Reference tags live in migration `…0700_reference_data.sql` because they are required in every environment.
