# Business Owner Model

> **2026-11-19: the in-app Claim Ownership flow was removed** (app UI, Admin claims tab, `request_venue_claim`, `admin_list_venue_claims`, `admin_decide_venue_claim`, table `venue_claims`, setting `claims_max_open`; migration `20261119000100_remove_claims_facility_filter.sql`). `business_accounts` / `business_memberships` remain: existing members keep scoped access, and new memberships can only be created by an Admin with SQL. The sections below describe the original design.

## MVP (implemented)

- Business Owner is **not** a self-selected role. A Registered user submits a claim from Venue Detail ("เป็นเจ้าของที่นี่? ขอยืนยันความเป็นเจ้าของ") with business name, role (owner/manager/editor), contact and evidence notes.
- `request_venue_claim` creates `venue_claims (pending_review)`; one open claim per user per venue; idempotent per `client_request_id`.
- Admin approves/rejects in the queue (`admin_decide_venue_claim`, reason required on reject). Approval, in one transaction: create `business_accounts` if the venue has none, link `venues.business_id`, upsert an **active** `business_memberships` row, audit event.
- `private.can_manage_venue(venue, user)` = active membership in an active business that manages that venue, and Registered. Scope is per venue/business — tested.
- Profile shows memberships ("ธุรกิจที่ฉันดูแล") and claim statuses only when the server reports them; Venue Detail shows "คุณเป็นผู้ดูแลสถานที่นี้".
- Owners cannot modify or delete reviews; no access to reviewer identity or location evidence.

## Foundations ready for Phase 2

- `venue_change_requests` (JSON proposals, Admin decision) — table + RLS; RPCs **Planned**.
- Multiple venues per business, multiple members with roles — schema supports it.
- Aggregate analytics with a minimum cohort (`business_min_cohort = 5` setting) — **Planned**.
- Public owner responses, sponsored placements (clearly labelled, never in organic rank) — **Planned**.

## Rules that must not change

Payment or ownership never affects organic ranking (`search_venues` has no business/sponsored term), never suppresses reviews, never exposes user-level data.
