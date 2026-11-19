# Sync and Cache Strategy

Cloud is the source of truth. GRDB/SQLite (`Core/Database`, `Data/Local/LocalCache.swift`) is a bounded **read cache, per-user drafts, a photo outbox and small device state**. It is not a second database.

## Tables (migration `v3_production_hardening`)

| Table | Contents | Written when | TTL / invalidation |
|---|---|---|---|
| `cached_venues` | `VenueSummary` JSON (`payload_version`) + name/category/lat/lng columns, `cached_at`, `last_accessed_at` | after every successful search, card fetch, or detail fetch | Fresh for 15 min (`venueCacheFreshness`), never shown after 7 days (`venueCacheMaxAge`). At launch `prune()` deletes rows older than that, then keeps at most `venueCacheMaxEntries` (2000), least recently read first. |
| `cached_venue_details` | public part of `VenueDetail` (no `myReview`, `isFavorite`, `isManagedByMe`) | after every successful detail fetch | Same age rule; LRU cap `venueDetailCacheMaxEntries` (300). |
| `cached_favorites` | favorite venue ids per user | after a favorites refresh and after a confirmed toggle | replaced on every refresh; deleted at sign-out |
| `local_drafts` | per `(user_id, key)`: unsent review draft per venue; add-place draft | when publishing fails or the user leaves a non-empty form | deleted after a successful publish and at sign-out |
| `pending_uploads` | photos of an already-published review/submission whose upload failed offline; file in `Application Support/PendingUploads` | when a photo upload fails with a network error | retried by `PendingUploadService`; removed on success, permanent error, 5 failed tries, or sign-out |
| `app_kv` | device state, e.g. the last server config (`remote_config.v1`) | after `get_public_config()` | kept across "Clear cache" and sign-out (not personal) |

Every JSON payload has a `payload_version`. A row whose version doesn't match the app's, or that can't be decoded, is deleted when read (never silently skipped).

The v1 tables (`check_ins`, `venues`, `favorites`, `app_identity`) were dropped by v3. The `Database` and `PendingUploads` folders use the `completeUntilFirstUserAuthentication` file-protection class.

"Clear cache" in Profile deletes cached venues, details, favorites and drafts. It keeps `app_kv` and `pending_uploads`.

## Offline behaviour

| Feature | Offline |
|---|---|
| Explore / search | Cached cards are filtered and ranked locally (`VenueRanker`). A banner shows "ออฟไลน์ · ข้อมูลที่บันทึกไว้เมื่อ … อาจไม่เป็นปัจจุบัน". If the cache is empty, an error state with Retry is shown. |
| Saved | Cached favorite ids and cached cards, with an offline note |
| Venue detail | The cached public detail is shown with an offline banner (same wording as Explore). Reviews are not shown; writing a review and saving are disabled. No cache → error. |
| Favorite toggle | **Not queued.** The UI reverts and shows an error, so it never fakes success. (An outbox was intentionally not built for the MVP.) |
| Review publish | **Never offline.** The one-time verification and the transaction need the server. The draft is kept. If the review is published but a photo upload fails for a network reason, the photo goes to `pending_uploads` and is retried at launch, on return to the foreground and after sign-in (backoff 30 s × 2ⁿ, at most 5 tries; 4xx-type errors give up at once). |
| Venue submission | Not sent offline. The draft is kept and is never shown as submitted. |

## Identity continuity

Guest favorites belong to the anonymous auth user. Verifying an email keeps the same user id, so favorites and everything else stay attached (tested in the Demo backend). Losing the anonymous session before linking loses the guest data. Profile and Saved explain this.

## Not built (by design)

There is no multi-master sync and no background sync. When the network returns, the next screen load fetches fresh data. The only outbox is for photos of content the server already accepted; favorites are never queued.
