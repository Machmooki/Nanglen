# Database Architecture Audit

**Date:** 2026-11-09 · **Scope:** `Nanglen_App/` (Xcode project) before the v2 (Product Rules v1) migration.
A full tarball of the pre-migration project was taken before any edit (outside the repo; the project is not under git).

## 1. Current state (evidence)

| Area | Evidence | Finding |
|---|---|---|
| Project | `Nanglen_App.xcodeproj` (objectVersion 110, file-system synchronized groups), targets `Nanglen_App`, `Nanglen_AppTests`, `Nanglen_AppUITests`; bundle id `Mach.Nanglen-App`; app deployment target 26, tests 27.0; Swift 6, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` | Modern Xcode 27 project; new files are picked up automatically. |
| Dependencies | `XCRemoteSwiftPackageReference "GRDB"` 7.12.0 | Only GRDB. No cloud SDK. |
| Lifecycle | `App/AppDelegate.swift`, `App/SceneDelegate.swift`, `Base.lproj/Main.storyboard` (initial VC `tab-vc`) | UIKit scene lifecycle, Storyboard tab bar → 3 nav controllers. DI through `AppContainer` + `AppContainerConfigurable`. |
| Local DB | `Core/Database/DatabaseManager.swift`, `Core/Database/Migrations/V1InitialSchema.swift` | SQLite is the **primary and only** store: `app_identity`, `venues` (MapKit place cache with amenity columns), `check_ins` (crowd/noise/seat/wifi/power, `is_verified`, `expires_at`), `favorites` keyed by `guest_id`. |
| Domain | `Domain/Models/CheckIn.swift` (`CrowdLevel`, `NoiseLevel`, `SeatAvailability`, `VenueConditions`), `Domain/Services/ConditionAggregator.swift`, `CheckInService.swift`, `CheckInVerifier.swift`, `RecommendationService.swift`, `SpotFilterEngine.swift` | Whole ranking/filter pipeline is built on live crowd/noise reports with a 2 h expiry. |
| Identity | `Domain/Services/IdentityProvider.swift` (`GuestIdentityProvider`, `AccountLinkingService` protocol only) | Device-local guest UUID; no auth backend; phone linking deliberately unimplemented. |
| Verification | `CheckInVerifier` (100 m, accuracy ≤ 100 m, age ≤ 120 s) | **Client sets `is_verified`** and stores the report locally — not acceptable under the new rules. |
| Venues | `Data/Providers/MapKitPlaceSearchProvider.swift`, `Data/Repositories/VenueRepository.swift` | Every MapKit result is upserted into `venues` and treated as a Nanglen place. No approval workflow. |
| Cloud | none | No migrations, SQL, env config, secrets, or production data. |

## 2. Outdated / inconsistent assumptions (vs. Product Rules v1)

1. `check_ins` / crowd-noise-seat snapshots / 2 h expiry are the core feature → **obsolete** (Product Rules §8, §14).
2. SQLite as source of truth → cloud must be authoritative; SQLite becomes a bounded cache.
3. Any MapKit result is a "venue" → only **Admin-approved canonical venues** may be listed/reviewed.
4. Client-computed `is_verified` → verification must be a **server-issued, one-time** record.
5. No Registered/Business/Admin capabilities → required.
6. Recommendation score built from crowd/noise/power/Wi‑Fi weights → replaced by rating + Bayesian confidence + relevance + distance.

## 3. Risks and blockers

| Risk | Mitigation |
|---|---|
| No Supabase project/credentials available in this environment | Ship complete migrations, RLS, RPCs, Storage policies, config template; app runs in clearly-labelled **Demo backend** mode until `Supabase.xcconfig` values exist. Live remote verification is **blocked** and documented. |
| No local Postgres/Docker; installing PGlite was blocked by the environment's permission policy | SQL tests and a Node/PGlite harness are written (`supabase/tests`) but were **not executed** here. |
| Location spoofing | Documented limitation; server checks submitted values only; App Attest/QR planned. |
| Phone OTP needs an SMS provider (Twilio/MessageBird/Vonage) configured in Supabase Auth | Requires external configuration. |

## 4. Data migration considerations

- No cloud data exists → cloud schema is created from an empty database (ordered migrations).
- Local SQLite holds device-only data. The app's GRDB migration `v2_cache_and_legacy_archive` **leaves** the v1 tables `check_ins`, `venues`, `favorites`, `app_identity` in place, unused (nothing deleted or renamed) and creates the new cache tables. Old reports are **not** reinterpreted as reviews (different meaning, unverified by a server). Old favorites reference MapKit places, not approved venues, so they cannot be migrated automatically; they stay in the v1 `favorites` table for a future explicit mapping.
- The local `app_identity.guest_id` is superseded by the Supabase anonymous auth UUID.

## 5. Recommended staged implementation

1. Supabase schema + RLS + RPCs + Storage policies (this change).
2. iOS backend abstraction (`NanglenBackend` remote data sources) with Supabase and Demo implementations; GRDB v2 cache.
3. Feature rewrite: Explore/Detail → Review Composer with visit verification → Add Place → My Submissions → Admin queue → Business claim.
4. External setup: Supabase project, phone provider, manual linking, anonymous sign-ins + CAPTCHA, Storage buckets, first Admin grant.
5. Production hardening: App Attest, rate-limit tuning, moderation console, monitoring.
