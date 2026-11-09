# Review and Moderation Workflow

## Review model

- Required: overall rating 1–5 (accessible labels: แย่ / ต่ำกว่าที่คาด / พอใช้ / ดี / ยอดเยี่ยม).
- Optional: one purpose (study, work, meeting, relax, other), up to 3 tags from the controlled taxonomy, comment ≤ 500 chars, up to 3 photos.
- **One current review per user per venue** (`UNIQUE(venue_id, user_id)`). Each verified visit that is submitted creates an immutable `review_revisions` row; `reviews.current_revision_id` points to the latest. Lists show only the current revision → no duplicate cards.
- Updating requires a **new** verified visit (a verification can be consumed once).
- Publication is immediate after server validation (no routine pre-approval). Review photos stay `pending` and are visible only to the author/Admin until approved.
- Drafts: if publishing fails (network, expired/consumed verification), the draft is saved locally (`local_drafts`) and restored next time; the UI says "not published". Expired/consumed verification → the composer requires a fresh verification.

## Venue submission workflow (mandatory Admin approval)

1. Registered user → Add Place: Apple Maps search *or* map pin; name, category, address required; description/website/phone/note/photos optional.
2. `create_venue_submission` → row in `venue_submissions` (`pending_review`). Never written to `venues`.
   - Exact provider match → `already_listed` + link to the existing venue (no queue entry).
   - Nearby/similar approved venues are returned as duplicate hints.
3. Submitter sees status and Admin feedback in **Profile › สถานที่ที่ฉันแนะนำ**; can withdraw, or edit & resubmit when `needs_changes`.
4. Admin queue (Profile › คิวตรวจสอบของทีมงาน, visible only when `get_my_capabilities.is_admin`): map, details, submitter stats (no phone), photos, duplicate candidates, history.
   - **Approve** → one transaction: re-check provider ref and likely duplicates (≥ 0.6 name similarity within 50 m → requires explicit "approve anyway"), insert venue, provider ref, photo links, set status, audit row, analytics event.
   - **Reject** / **Request changes** (reason required, shown to submitter) / **Mark duplicate** (links the canonical venue).
5. Only after approval does the venue appear in search and accept reviews.

## Post-publication moderation

- Registered users flag reviews (spam, offensive, not a real visit, wrong venue, privacy, other); cannot flag their own.
- Admin "รีวิวที่ถูกรายงาน" tab: dismiss (keep), hide, remove — reason required; open flags are resolved and an audit row is written.
- Hidden/removed reviews are excluded from lists and from rating summaries/tag counts.
- Business Owners cannot edit, delete or hide reviews.

## Audit

`public.moderation_actions` (append-only; UPDATE/DELETE raise). Written only inside Admin RPCs: actor, action, target, previous/new status, reason, metadata, timestamp. Admins can read it via RLS.

## Implementation status

| Item | Status |
|---|---|
| SQL RPCs + constraints | Implemented; SQL tests written, **not executed** |
| Same rules in Demo backend | Implemented, **Tested** (Swift Testing, 21 rule tests) |
| iOS composer, add place, my submissions, admin queue/detail | Implemented; verified manually in the iPhone 17 simulator (Demo backend) |
| Review photo approval UI for Admins | **Planned** (RPCs `admin_list_pending_review_media` / `admin_set_review_media_status` exist) |
