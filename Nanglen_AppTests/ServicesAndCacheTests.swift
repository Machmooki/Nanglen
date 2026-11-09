import Foundation
import GRDB
import Testing
@testable import Nanglen_App

@MainActor
struct VisitVerificationServiceTests {
    private func service(backend: DemoBackend, location: MockLocation, clock: TestClock) -> VisitVerificationService {
        let cache = LocalCache(database: try! DatabaseManager.inMemory())
        return VisitVerificationService(reviews: ReviewRepository(remote: backend, cache: cache), location: location, clock: { clock.now })
    }

    private var venue: VenueSummary { Fixtures.summary(id: Fixtures.cafeID, average: nil, count: 0) }

    @Test func verifiedReturnsServerIssuedID() async throws {
        let clock = TestClock()
        let backend = makeBackend(clock: clock)
        try await registerUser(backend)
        let location = MockLocation(readings: [.success(LocationReading(point: Fixtures.cafe, horizontalAccuracy: 8, timestamp: clock.now))])
        var states: [VerificationState] = []
        let result = await service(backend: backend, location: location, clock: clock).verify(venue: venue) { states.append($0) }
        #expect(result.verificationID != nil)
        #expect(states.contains(.checkingLocation))
        #expect(states.contains(.verifying))
    }

    @Test func permissionIsRequestedOnlyAtReviewTimeAndDenialIsHandled() async throws {
        let clock = TestClock()
        let backend = makeBackend(clock: clock)
        try await registerUser(backend)
        let location = MockLocation(authorization: .denied, readings: [])
        let result = await service(backend: backend, location: location, clock: clock).verify(venue: venue) { _ in }
        #expect(result == .permissionDenied)
    }

    @Test func guestGetsRegistrationRequired() async throws {
        let clock = TestClock()
        let backend = makeBackend(clock: clock)
        try await backend.ensureSession()
        let location = MockLocation(readings: [.success(Fixtures.reading())])
        let result = await service(backend: backend, location: location, clock: clock).verify(venue: venue) { _ in }
        #expect(result == .registrationRequired)
    }

    @Test func inaccurateReadingsRetryThenReport() async throws {
        let clock = TestClock()
        let backend = makeBackend(clock: clock)
        try await registerUser(backend)
        let bad = LocationReading(point: Fixtures.cafe, horizontalAccuracy: 120, timestamp: clock.now)
        let location = MockLocation(readings: [.success(bad), .success(bad), .success(bad)])
        let result = await service(backend: backend, location: location, clock: clock).verify(venue: venue) { _ in }
        if case .inaccurate = result {} else { Issue.record("expected inaccurate, got \(result)") }
        #expect(location.readings.isEmpty, "all retries were used")
    }

    @Test func farAwayIsTooFar() async throws {
        let clock = TestClock()
        let backend = makeBackend(clock: clock)
        try await registerUser(backend)
        let far = LocationReading(point: Fixtures.north(of: Fixtures.cafe, meters: 400), horizontalAccuracy: 5, timestamp: clock.now)
        let result = await service(backend: backend, location: MockLocation(readings: [.success(far)]), clock: clock).verify(venue: venue) { _ in }
        if case .tooFar = result {} else { Issue.record("expected tooFar, got \(result)") }
    }
}

@MainActor
struct ReviewServiceTests {
    @Test func failedPublishKeepsDraftAndNeedsFreshVerification() async throws {
        let clock = TestClock()
        let backend = makeBackend(clock: clock)
        try await registerUser(backend)
        let cache = LocalCache(database: try DatabaseManager.inMemory())
        let repo = ReviewRepository(remote: backend, cache: cache)
        let service = ReviewService(reviews: repo, configuration: .standard, notifier: DataChangeNotifier())
        var draft = ReviewDraft(venueID: Fixtures.cafeID)
        draft.rating = 4
        await #expect(throws: BackendError.verificationInvalid) { try await service.publish(draft, verificationID: UUID(), photos: []) }
        #expect(await service.savedDraft(venueID: Fixtures.cafeID)?.rating == 4)
    }
}

/// Venue search through the repository: offline falls back to cache and labels it.
@MainActor
struct VenueRepositoryTests {
    final class OfflineRemote: VenueRemote {
        func searchVenues(_ query: VenueSearchQuery) async throws -> VenueSearchPage { throw BackendError.network }
        func venueCards(ids: [UUID], origin: GeoPoint?) async throws -> [VenueSummary] { throw BackendError.network }
        func venueDetail(id: UUID) async throws -> VenueDetail { throw BackendError.network }
        func matchProviderRefs(provider: String, externalIDs: [String]) async throws -> [String: UUID] { [:] }
        func reviews(venueID: UUID, sort: ReviewSort, limit: Int, offset: Int) async throws -> ReviewPage { throw BackendError.network }
        func signedMediaURLs(paths: [String], bucket: MediaBucket) async throws -> [String: URL] { [:] }
        func logEvent(_ name: String, venueID: UUID?) async {}
    }

    @Test func liveResultsAreCachedAndOfflineIsLabelled() async throws {
        let database = try DatabaseManager.inMemory()
        let cache = LocalCache(database: database)
        let backend = makeBackend()
        try await backend.ensureSession()
        let live = VenueRepository(remote: backend, cache: cache, configuration: .standard, clock: { Fixtures.now })
        let query = VenueSearchQuery(origin: Fixtures.cafe, radiusMeters: 3_000)
        let first = try await live.search(query)
        #expect(first.source == .live)
        #expect(!first.venues.isEmpty)

        let offline = VenueRepository(remote: OfflineRemote(), cache: cache, configuration: .standard, clock: { Fixtures.now.addingTimeInterval(60) })
        let cached = try await offline.search(query)
        #expect(cached.source == .offline(cachedAt: Fixtures.now))
        #expect(Set(cached.venues.map(\.id)) == Set(first.venues.map(\.id)))
    }

    @Test func offlineWithEmptyCacheThrows() async throws {
        let cache = LocalCache(database: try DatabaseManager.inMemory())
        let repo = VenueRepository(remote: OfflineRemote(), cache: cache, configuration: .standard)
        await #expect(throws: BackendError.network) { try await repo.search(VenueSearchQuery(origin: Fixtures.cafe)) }
    }
}

@MainActor
struct LocalCacheTests {
    @Test func draftsAndFavoritesRoundTrip() async throws {
        let cache = LocalCache(database: try DatabaseManager.inMemory())
        var draft = ReviewDraft(venueID: Fixtures.cafeID)
        draft.rating = 5
        try await cache.saveDraft(draft, key: "k")
        #expect(try await cache.draft(ReviewDraft.self, key: "k")?.rating == 5)
        try await cache.deleteDraft(key: "k")
        #expect(try await cache.draft(ReviewDraft.self, key: "k") == nil)

        let user = UUID()
        try await cache.storeFavoriteIDs([Fixtures.cafeID, Fixtures.libraryID], userID: user, at: Fixtures.now)
        #expect(try await cache.cachedFavoriteIDs(userID: user) == [Fixtures.cafeID, Fixtures.libraryID])
        #expect(try await cache.cachedFavoriteIDs(userID: UUID()).isEmpty)
    }

    /// Regression: a v1 database with check-ins/favorites must migrate to v2 without FK failures,
    /// keeping the legacy rows untouched.
    @Test func v1DatabaseWithLegacyRowsMigratesToV2() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("nanglen-v1-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let queue = try DatabaseQueue(path: path, configuration: DatabaseManager.configuration())
        var v1 = DatabaseMigrator()
        V1InitialSchema.register(in: &v1)
        try v1.migrate(queue)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO app_identity (id, guest_id, created_at, updated_at) VALUES (1, 'g1', ?, ?)", arguments: [Date(), Date()])
            try db.execute(sql: "INSERT INTO venues (id, external_place_id, name, latitude, longitude, category, created_at, updated_at) VALUES ('v1', 'e1', 'Old', 13.7, 100.5, 'cafe', ?, ?)", arguments: [Date(), Date()])
            try db.execute(sql: "INSERT INTO favorites (id, venue_id, guest_id, created_at) VALUES ('f1', 'v1', 'g1', ?)", arguments: [Date()])
            try db.execute(sql: "INSERT INTO check_ins (id, venue_id, guest_id, is_verified, created_at, expires_at) VALUES ('c1', 'v1', 'g1', 0, ?, ?)", arguments: [Date(), Date().addingTimeInterval(60)])
        }
        let manager = try DatabaseManager(writer: queue)
        let tables = try manager.tableNames()
        #expect(tables.contains("cached_venues"))
        #expect(tables.contains("local_drafts"))
        #expect(try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM check_ins") } == 1)
    }
}
