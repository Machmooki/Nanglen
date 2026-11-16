# Sync and Cache Strategy

Cloud is the source of truth. GRDB/SQLite (`Core/Database`, `Data/Local/LocalCache.swift`) is a bounded **read cache plus local drafts**. It is not a second database.

## Tables (migration `v2_cache_and_legacy_archive`)

| Table | Contents | Written when | TTL / invalidation |
|---|---|---|---|
| `cached_venues` | `VenueSummary` JSON + name/category/lat/lng columns | after every successful search, card fetch, or detail fetch | Considered fresh for 15 min (`venueCacheFreshness`). Never shown when older than 7 days (`venueCacheMaxAge`). Each fetch overwrites the row. "Clear cache" in Profile deletes everything. |
| `cached_favorites` | favorite venue ids per user | after a favorites refresh and after a confirmed toggle | replaced on every refresh; keyed by user id |
| `local_drafts` | unsent review draft per venue; add-place draft | when publishing fails or the user cancels a non-empty form | deleted after a successful publish |

The v1 tables (`check_ins`, `venues`, `favorites`, `app_identity`) are left in place, untouched and unused. Old crowd/noise reports are not converted into reviews.

## Offline behaviour

| Feature | Offline |
|---|---|
| Explore / search | Cached cards are filtered and ranked locally (`VenueRanker`). A banner shows "ออฟไลน์ · ข้อมูลที่บันทึกไว้เมื่อ … อาจไม่เป็นปัจจุบัน". If the cache is empty, an error state with Retry is shown. |
| Saved | Cached favorite ids and cached cards, with an offline note |
| Venue detail | Requires the network for reviews; shows an error |
| Favorite toggle | **Not queued.** The UI reverts and shows an error, so it never fakes success. (An outbox was intentionally not built for the MVP.) |
| Review publish | **Never offline.** The one-time verification and the transaction need the server. The draft is kept. |
| Venue submission | Not sent offline. The draft is kept and is never shown as submitted. |

## Identity continuity

Guest favorites belong to the anonymous auth user. Verifying an email keeps the same user id, so favorites and everything else stay attached (tested in the Demo backend). Losing the anonymous session before linking loses the guest data. Profile and Saved explain this.

## Not built (by design)

There is no multi-master sync and no background sync. When the network returns, the next screen load fetches fresh data.
