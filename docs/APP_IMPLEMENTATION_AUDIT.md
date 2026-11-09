# App Implementation Audit

**Date:** 2026-11-09 · Written before the v2 refactor (Product Rules v1 + App Development Prompt v2).

## What exists and is preserved

| Keep | Why |
|---|---|
| UIKit scene lifecycle, `Main.storyboard` tab bar (Explore / Saved / Profile), `AppContainer` DI, `AppContainerConfigurable` | Matches the required architecture. |
| Design system (`Core/DesignSystem`: colors in asset catalog, rounded Dynamic Type scale, spacing, Liquid Glass button styles, `EmptyStateView`, `SectionHeaderView`, `StatusPillView`) | Good quality; reused and extended. |
| `LocationManager` (When-In-Use, one-shot, 15 s timeout, never at launch) | Correct permission behavior; extended to report `horizontalAccuracy` and timestamp for verification. |
| `MapKitPlaceSearchProvider`, `MapCoordinator` (directions) | Reused only for **external candidates** (Add Place prefill, provider-ID matching) and directions. |
| Explore layout (search bar first, chips, filter button, list/map toggle, "search this area"), `CategoryChipCell`, `PlaceCardCell.xib` | Re-bound to approved venues and rating summaries. |
| GRDB | Kept as the local **cache** (v2 migration). |
| Signing, bundle id, deployment targets | Unchanged. |

## What conflicts with the product rules and is replaced

| Old | Replacement |
|---|---|
| `Features/CheckIn/*`, `CheckInService`, `CheckInVerifier`, `CheckInRepository`, `Domain/Models/CheckIn.swift` (crowd/noise/seat) | `Features/ReviewComposer` + `VisitVerificationService` (server challenge → server verification → `submit_review` RPC). |
| `ConditionAggregator`, `RecommendationService` (crowd/noise weights), `SpotFilterEngine`, `ScoreBadgeView`, `ConditionRowView` | `VenueRanker` (relevance + Bayesian rating + distance), rating label (`4.6 · 28 รีวิว` / `ยังไม่มีรีวิว`), community tag pills. |
| Filter sheet (crowd/noise/Wi‑Fi/power/budget) | Filter sheet (sort, distance, minimum rating). |
| Every MapKit result becomes a "venue" | Explore lists **approved canonical venues** only; MapKit candidates appear only in Add Place, clearly labelled "not yet on Nanglen". |
| Local `guest_id` identity | Supabase anonymous auth user (Demo backend in dev); phone OTP link keeps the same user id. |
| SQLite primary store | Cloud authoritative; GRDB cache with freshness labels; local review/submission drafts only. |

## New features required

Venue Detail (reviews, tags, save, directions, write review, claim), Review Composer with location verification states, Add Place (MapKit search or pin) → `venue_submissions`, My Submissions (status + admin feedback), Phone link (OTP), Admin moderation queue (approve / reject / duplicate / needs changes, audited), Business claim request + status.

## Migration plan

1. Add Supabase SDK; introduce `NanglenBackend` remote data source protocols with `SupabaseBackend` and `DemoBackend`.
2. GRDB v2 migration: archive legacy tables (rename, no data loss), create cache tables.
3. Remove obsolete check-in code paths and storyboard scenes in the same change so no conflicting behavior remains.
4. Rebuild storyboard scenes for the new flows; add tests; build with `xcodebuild`.
