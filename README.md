# Nanglen (นั่งเล่น)

**Discover places worth staying.**

A community-powered place discovery app for students, freelancers and remote workers. Guests browse
**Admin-approved** places right away. Registered users (free verified email) write reviews **after a
location-verified visit** and suggest new places, which go public **only after an Admin approves them**.

- iOS: UIKit + Storyboard, Swift 6, MVVM + Repository + Service
- Backend: Supabase (Auth, PostgreSQL + PostGIS, Storage) with RLS and `SECURITY DEFINER` RPCs
- Local: GRDB read cache + drafts
- Product source of truth: `../Docs/Product_Business_Rules_v1.md`

## Status (2026-11-09)

| Area | Status |
|---|---|
| Supabase schema, RLS, grants, RPCs, Storage policies (`supabase/migrations`) | **Implemented**; pgTAP suite written; **not executed** (no Docker/Postgres in this environment) |
| iOS app on the Supabase backend (`SupabaseBackend`) | **Implemented and compiles**; **not run against a live project** (no credentials) |
| iOS app on the Demo backend (same rules, in-process) | **Implemented, tested** (55 unit tests + 2 UI tests pass); main flows checked by hand on the iPhone 17 simulator |
| Email OTP (free SMTP), CAPTCHA, buckets, `delete-account` function deploy, first Admin | **Requires external configuration** (see `docs/PRODUCTION_DEPLOYMENT.md`) |
| App Attest, Admin photo approval UI, business tools beyond claims, English localisation | **Planned** |

## Running

Requirements: Xcode 27.1+, iOS 26+ (tests 27), Swift packages GRDB 7.x and supabase-swift 2.55.x (resolved automatically).

```bash
xcodebuild build -project Nanglen_App.xcodeproj -scheme Nanglen_App -destination 'platform=iOS Simulator,name=iPhone Air,OS=27.0'
```

**Demo mode (default, no credentials).** Data stays on the device and the UI shows "โหมดสาธิต":
- The email code is always `123456`. No email is sent.
- In debug builds, verifying `admin@demo.nanglen.app` grants Demo Admin.
- Fictional seed venues sit around Siam, Bangkok. To test a verified review, set the simulator location near one, e.g.:

```bash
xcrun simctl location booted set 13.7462,100.5326
```

**Supabase mode:** copy `Config/Supabase.example.plist` to `Nanglen_App/Resources/Supabase.plist`, add the project URL and the **anon/publishable key only**, then follow `docs/PRODUCTION_DEPLOYMENT.md`.

## Tests

```bash
xcodebuild test -project Nanglen_App.xcodeproj -scheme Nanglen_App -destination 'platform=iOS Simulator,name=iPhone Air,OS=27.0'
```

```bash
supabase start && supabase db reset && supabase test db
```

## Project layout

```
Nanglen_App/
├── App/              AppDelegate, SceneDelegate, AppContainer (composition root, backend selection)
├── Base.lproj/       Main.storyboard (tab bar + all scenes), LaunchScreen
├── Core/             DesignSystem (+ Components), Database (GRDB migrations), Location, Map, Utilities (L10n…)
├── Domain/           Models (Venue, Review, VisitVerification, Account) · Services (Session, VisitVerification,
│                     Review/Submission, VenueRanker, Validators, CategoryClassifier)
├── Data/             Remote (NanglenBackend protocols, Supabase/, Demo/) · Local (LocalCache) · Repositories · Providers (MapKit)
└── Features/         Explore, Filter, VenueDetail, ReviewComposer, Account (email sign-in), VenueSubmission (Add Place),
                      MySubmissions, Saved, Profile, Business (claim), AdminModeration, Shared
supabase/             config.toml, migrations/ (8 ordered files), functions/delete-account, templates/email_otp.html, seed.sql (dev only), tests/database/
Config/               Supabase.example.plist
docs/                 audits, ADR, design, security, verification, workflows, performance, cost, cache, deployment
```

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [FEATURES_AND_USER_FLOWS](docs/FEATURES_AND_USER_FLOWS.md)
- [APP_IMPLEMENTATION_AUDIT](docs/APP_IMPLEMENTATION_AUDIT.md)
- [DATABASE_ARCHITECTURE_AUDIT](docs/DATABASE_ARCHITECTURE_AUDIT.md)
- [ARCHITECTURE_DECISION_RECORD](docs/ARCHITECTURE_DECISION_RECORD.md)
- [DATABASE_DESIGN](docs/DATABASE_DESIGN.md)
- [ERD](docs/ERD.md)
- [SECURITY_AND_RLS](docs/SECURITY_AND_RLS.md)
- [LOCATION_VERIFICATION_DESIGN](docs/LOCATION_VERIFICATION_DESIGN.md)
- [REVIEW_AND_MODERATION_WORKFLOW](docs/REVIEW_AND_MODERATION_WORKFLOW.md)
- [BUSINESS_OWNER_MODEL](docs/BUSINESS_OWNER_MODEL.md)
- [PERFORMANCE_STRATEGY](docs/PERFORMANCE_STRATEGY.md)
- [SCALABILITY_AND_COST_ANALYSIS](docs/SCALABILITY_AND_COST_ANALYSIS.md)
- [SYNC_AND_CACHE_STRATEGY](docs/SYNC_AND_CACHE_STRATEGY.md)
- [PRODUCTION_DEPLOYMENT](docs/PRODUCTION_DEPLOYMENT.md)

## Known limitations

- GPS verification checks the coordinates the device submits. It is not proof of physical presence (see the location verification doc).
- Guest data can be lost if the app is deleted before the user verifies an email.
- Venue cover photos aren't shown on list cards yet; they appear on Venue Detail.
- The local cache keeps the v1 tables (check-ins etc.) untouched and unused.
