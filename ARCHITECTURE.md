# Nanglen Architecture (v2)

Feature-based **MVVM + Repository + Service** on **UIKit + Storyboard**, with a cloud backend
(**Supabase: Auth + PostgreSQL/PostGIS + Storage**) and **GRDB** as a local cache.
Product rules: `../Docs/Product_Business_Rules_v1.md`. Backend decision: `docs/ARCHITECTURE_DECISION_RECORD.md`.

## Layers

```
ViewController (Storyboard outlets, rendering, input) ──▶ ViewModel (screen state, orchestration)
        ──▶ Service (business rules)            SessionService, VisitVerificationService,
                                                ReviewService, SubmissionService, VenueRanker, validators
        ──▶ Repository (remote + cache)         Venue/Favorite/Review/Submission/Business/AdminRepository
        ──▶ Remote data source protocols        AuthRemote, VenueRemote, FavoriteRemote, ReviewRemote,
                                                SubmissionRemote, BusinessRemote, AdminRemote (= NanglenBackend)
              ├─ SupabaseBackend   (supabase-swift 2.55.x: auth, rpc, storage)
              └─ DemoBackend       (in-process, same rules, JSON-persisted, labelled "Demo")
        ──▶ LocalCache (GRDB)    cached venue cards, favorite ids, drafts
Providers: LocationManager (CoreLocation one-shot), MapKitPlaceSearchProvider (candidates only), MapCoordinator
```

- ViewControllers and ViewModels never touch Supabase or SQL. `AppContainer` is the only place that wires implementations.
- Backend selection (`AppContainer.live()`): `Supabase.plist` or env vars → `SupabaseBackend`; otherwise `DemoBackend`. `-NanglenDemoBackend` forces Demo, `-NanglenResetData` resets the cache and demo data (UI tests).
- Swift 6, default MainActor isolation. Models are `nonisolated` value types.

## Storyboard

`Base.lproj/Main.storyboard` is generated from the previous storyboard and keeps the original tab bar, Explore, Saved and Profile scenes. It adds 14 scenes (navigation controllers + view controllers):

| Scene (storyboard ID) | Reached by |
|---|---|
| `VenueDetailViewController` | segue `showVenueDetail` from Explore / Saved; instantiated from Add Place / My Submissions |
| `FilterNavigationController` | `presentFilter` |
| `ReviewComposerNavigationController` | `presentReviewComposer` |
| `SignInNavigationController` | `presentSignIn` (Detail, Profile); instantiated from the composer and Add Place (email code: link, or sign in to an existing account) |
| `AddPlaceNavigationController` | `presentAddPlace` (Explore, Profile); instantiated from My Submissions |
| `ClaimNavigationController` | `presentClaim` |
| `MySubmissionsViewController` | `showMySubmissions` |
| `AdminQueueViewController` → `AdminSubmissionViewController` | `showAdminQueue` → `showAdminSubmission` |

Dynamic content (review cards, chips, tag pills, info rows, photo strips) is built in code with design-system components: `StarRatingControl`, `ChipGroupView`, `TagPillsView`, `VerificationStatusView`, `ReviewCardView`, `PhotoStripView`, `RatingBadgeView`, `RemoteImageView`.

## Key flows

- **Search:** `ExploreViewModel` debounces (350 ms), skips 1-character queries, tags each request with a generation number and cancels stale tasks. `VenueRepository.search` → `search_venues` RPC → cache write. On network failure it falls back to cached cards ranked locally and labels them stale.
- **Review:** `ReviewComposerViewModel` → `VisitVerificationService.verify` (permission → challenge → fresh reading, up to 3 attempts → server verdict) → form unlocked only with the server's verification id → `ReviewService.publish` (validation, idempotency key, then photos). A failure keeps the draft. An expired or used verification asks for a fresh one.
- **Capabilities:** `SessionService` holds `get_my_capabilities`. Admin, Business and Registered UI appears only from that value, and the backend re-checks every action.

## Design system

`Core/DesignSystem`: semantic colours in the asset catalog (light/dark), SF Rounded headings with Dynamic Type, a 4-pt spacing grid, Liquid Glass button styles, plus the components listed above. Thai is the source language (`L10n`, String Catalog). VoiceOver labels are on cards, stars (adjustable), chips and verification states.

## Testing

- `Nanglen_AppTests` (Swift Testing): 46 tests. They cover backend product rules through `DemoBackend`, ranking, validators, the reading evaluator, the verification service with a mock location provider, the repository's offline fallback, the cache, and a regression test for the v1→v2 migration.
- `Nanglen_AppUITests`: Guest browse + Guest review gate (Demo backend, no network).
- `supabase/tests/database`: pgTAP security and workflow suite (written, not yet executed here).
