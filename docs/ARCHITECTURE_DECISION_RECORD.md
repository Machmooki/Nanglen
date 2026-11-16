# ADR-001 — Backend platform for Nanglen v2

**Status:** Accepted (2026-11-09) · **Deciders:** implementation agent, pending owner review
**Context docs:** Product Rules v1, Database & Backend Architecture v2, App Development v2

## Context

Nanglen needs: anonymous Guest → verified-identity Registered upgrade that keeps the same user id; relational data with transactional workflows (submission approval creates a venue + provider ref + audit row atomically; review submission consumes a one-time verification and writes a revision atomically); geospatial radius search and server-side distance checks; strict per-row authorization; private media; Admin audit trail; scoped business memberships; a small team with predictable cost.

## Options compared

| Criterion | 1. Supabase (Auth + Postgres + PostGIS + Storage) + GRDB cache | 2. Firebase Auth + Firestore + cache | 3. Custom API + Postgres/PostGIS |
|---|---|---|---|
| Relational modelling / constraints | Native FK, CHECK, UNIQUE, deferrable constraints | Document model; uniqueness and FK need transactions/Cloud Functions | Native |
| Transactions for approval / review | SQL functions (`security definer`) run in one transaction | Firestore transactions + Cloud Functions; cross-collection invariants harder | Native |
| Geospatial | PostGIS `geography`, GiST, `ST_DWithin`, `ST_Distance` | Geohash queries only; distance filtering on client/functions | PostGIS |
| Authorization | Postgres RLS + grants + `auth.uid()`/JWT claims | Security Rules (good, but no SQL invariants) | Must be hand-built in API layer |
| Media | Storage with RLS on `storage.objects` | Cloud Storage + rules | Must integrate S3 etc. |
| Anonymous → identity linking | Anonymous sign-ins + `updateUser(email:)` + `verifyOTP(type: .emailChange)` keeps the uid (free email OTP; phone OTP possible but SMS is billed) (manual linking must be enabled) | Anonymous + `linkWithCredential` keeps uid | Build yourself |
| Search | `pg_trgm` + ranking in SQL RPC | Needs external search (Algolia/Typesense) | Same as 1 |
| Offline | GRDB cache we control | Built-in offline cache (multi-master semantics we do not want) | GRDB |
| Swift integration | Official `supabase-swift` (v2.55.6 verified) | Official Firebase SDK | URLSession client to write |
| Ops burden | Managed; migrations via CLI | Managed | Highest (servers, auth, patching) |
| Cost predictability | Tiered plans; Postgres sizing; SMS billed by provider | Per-read/write pricing — fan-out reads can surprise | Infra + engineering time |
| Lock-in | Postgres is portable; Auth/Storage APIs are Supabase-specific | High (Firestore data model + rules) | Lowest |

## Decision

**Option 1:** Supabase Auth for Guest/Registered identity, PostgreSQL as source of truth, PostGIS in the `extensions` schema, Supabase Storage (private buckets, RLS) for media, SQL `security definer` RPCs (fixed `search_path`, explicit `EXECUTE` grants) for multi-step privileged workflows, GRDB as a bounded read cache. The iOS app talks to the backend only through repository/remote-data-source abstractions.

A second implementation of the same contract, **`DemoBackend`** (in-process, persisted to a JSON file, clearly labelled "Demo"), lets the app be run and UI-tested without credentials. It is selected automatically when `SUPABASE_URL`/`SUPABASE_ANON_KEY` are absent and is never presented as a real backend.

## Trade-offs accepted

- Business logic partly in SQL (harder to unit test than Swift) → mitigated by SQL tests (`supabase/tests`) and by mirroring rules in the Demo backend, which has Swift tests.
- Edge Functions not used for MVP; all workflows fit in Postgres functions. App Attest assertion validation will need an Edge Function later.
- Pending media is private and served with signed URLs; no public CDN bucket in MVP.

## Conditions that would justify revisiting

- Search relevance needs (typo tolerance across Thai/English, synonyms) exceed `pg_trgm` → add a search service fed from Postgres.
- Write volume or connection pressure beyond a single Postgres instance after pooling → read replicas / dedicated API.
- Requirement for on-device multi-master offline editing → re-evaluate sync engine.
- Supabase pricing/limits change materially or data residency requirements cannot be met in an available region.

## Verified facts (2026-11-09)

- `supabase-swift` 2.55.6 resolved via SPM. API used: `SupabaseClient(supabaseURL:supabaseKey:options:)`, `auth.signInAnonymously()`, `auth.update(user: UserAttributes(phone:))`, `auth.verifyOTP(phone:token:type: .phoneChange)`, `auth.session`, `client.rpc(_:params:)`, `storage.from(_:).upload(_:data:options:)`, `createSignedURL(path:expiresIn:)`.
- Pricing/limits were **not** re-checked online in this session; see `SCALABILITY_AND_COST_ANALYSIS.md` for assumption-labelled estimates.

## Amendment (2026-11-09): free identity

Phone OTP requires a billed SMS provider. The launch identity for **Registered** is now a **verified email (6-digit OTP)**, which is free with any SMTP sender. `private.app_settings.registered_via_email = 1`, `registered_via_phone = 0`; phone can be re-enabled later without a migration. Linking an email that already has an account never merges: the user explicitly signs in to that account instead (`signInWithOTP(email:shouldCreateUser: false)`). Sign in with Apple was considered but needs a paid Apple Developer Program membership; it can be added later via `signInWithIdToken`/`linkIdentityWithIdToken`.
