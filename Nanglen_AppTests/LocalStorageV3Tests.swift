import Foundation
import GRDB
import UIKit
import Testing
@testable import Nanglen_App

// MARK: - Helpers

private func temporaryPath(_ name: String) -> String {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).sqlite").path
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("pending-\(UUID().uuidString)", isDirectory: true)
}

@MainActor
private func samplePhoto() throws -> PhotoUpload {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
        UIColor.systemOrange.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
    }
    return try #require(PhotoEncoder.upload(from: image))
}

private func count(_ table: String, in writer: any DatabaseWriter) throws -> Int {
    try writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") ?? 0 }
}

private func columns(_ table: String, in writer: any DatabaseWriter) throws -> Set<String> {
    try writer.read { db in Set(try db.columns(in: table).map(\.name)) }
}

// MARK: - Migration

@MainActor
struct V3MigrationTests {
    /// A v2 database with legacy v1 rows, cached cards, drafts and the server config migrates to v3:
    /// legacy tables gone, config moved to `app_kv` byte for byte, ownerless drafts dropped, new tables created.
    @Test func v2DatabaseWithDataMigratesToV3() throws {
        let path = temporaryPath("nanglen-v2")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let queue = try DatabaseQueue(path: path, configuration: DatabaseManager.configuration())
        try AppDatabaseMigrator.makeMigrator().migrate(queue, upTo: V2CacheAndLegacyArchive.identifier)

        var config = try JSONDecoder().decode(RemoteConfigValues.self, from: Data("{}".utf8))
        config.reviewMaxPhotos = 3
        config.visitRadiusMeters = 150
        let configData = try JSONEncoder().encode(config)
        let draftData = try JSONEncoder().encode(ReviewDraft(venueID: Fixtures.cafeID))
        try queue.write { db in
            let now = Date()
            try db.execute(sql: "INSERT INTO app_identity (id, guest_id, created_at, updated_at) VALUES (1, 'g1', ?, ?)", arguments: [now, now])
            try db.execute(sql: "INSERT INTO venues (id, external_place_id, name, latitude, longitude, category, created_at, updated_at) VALUES ('v1', 'e1', 'Old', 13.7, 100.5, 'cafe', ?, ?)", arguments: [now, now])
            try db.execute(sql: "INSERT INTO favorites (id, venue_id, guest_id, created_at) VALUES ('f1', 'v1', 'g1', ?)", arguments: [now])
            try db.execute(sql: "INSERT INTO check_ins (id, venue_id, guest_id, is_verified, created_at, expires_at) VALUES ('c1', 'v1', 'g1', 0, ?, ?)", arguments: [now, now.addingTimeInterval(60)])
            try db.execute(sql: "INSERT INTO cached_venues (id, name, category, latitude, longitude, payload, cached_at) VALUES ('x', 'X', 'cafe', 13.7, 100.5, x'00', ?)", arguments: [now])
            try db.execute(sql: "INSERT INTO cached_favorites (user_id, venue_id, position, cached_at) VALUES ('u', 'x', 0, ?)", arguments: [now])
            try db.execute(sql: "INSERT INTO local_drafts (key, payload, updated_at) VALUES (?, ?, ?)", arguments: [V3ProductionHardening.remoteConfigKey, configData, now])
            try db.execute(sql: "INSERT INTO local_drafts (key, payload, updated_at) VALUES ('review-draft-x', ?, ?)", arguments: [draftData, now])
        }

        let manager = try DatabaseManager(writer: queue)
        let tables = Set(try manager.tableNames())
        for legacy in ["check_ins", "favorites", "venues", "app_identity"] {
            #expect(!tables.contains(legacy), "\(legacy) should be dropped")
        }
        #expect(tables.isSuperset(of: ["cached_venues", "cached_venue_details", "cached_favorites", "local_drafts", "app_kv", "pending_uploads"]))

        // Config moved intact and is what the app reads at launch.
        let moved = try queue.read { try Data.fetchOne($0, sql: "SELECT value FROM app_kv WHERE key = ?", arguments: [V3ProductionHardening.remoteConfigKey]) }
        #expect(moved == configData)
        #expect(LocalCache(database: manager).cachedRemoteConfig() == config)

        #expect(try count("local_drafts", in: queue) == 0, "ownerless v2 drafts are discarded")
        #expect(try count("cached_venues", in: queue) == 0, "cache is rebuilt")
        #expect(try count("cached_favorites", in: queue) == 1, "cached_favorites is untouched")
        #expect(try columns("cached_venues", in: queue).isSuperset(of: ["payload_version", "last_accessed_at"]))
        #expect(try columns("local_drafts", in: queue).isSuperset(of: ["user_id", "key", "payload_version"]))
        #expect(try columns("pending_uploads", in: queue).isSuperset(of: [
            "id", "user_id", "kind", "target_id", "local_path", "mime_type", "attempts", "last_error", "next_attempt_at", "created_at",
        ]))
        let indexes = try queue.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type = 'index'") }
        #expect(indexes.contains("idx_cached_venues_last_accessed_at"))
        #expect(indexes.contains("idx_pending_uploads_next_attempt_at"))
        // Integrity: no dangling foreign keys after the drops.
        #expect(try queue.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_check") }.isEmpty)
    }

    @Test func freshDatabaseHasOnlyV3Tables() throws {
        let manager = try DatabaseManager.inMemory()
        #expect(Set(try manager.tableNames()) == ["app_kv", "cached_favorites", "cached_venue_details", "cached_venues", "local_drafts", "pending_uploads"])
    }

    @Test func pendingUploadKindIsConstrained() throws {
        let manager = try DatabaseManager.inMemory()
        #expect(throws: DatabaseError.self) {
            try manager.writer.write { db in
                try db.execute(sql: """
                    INSERT INTO pending_uploads (id, user_id, kind, target_id, local_path, mime_type, next_attempt_at, created_at)
                    VALUES ('1', 'u', 'avatar', 't', 'a.jpg', 'image/jpeg', ?, ?)
                    """, arguments: [Date(), Date()])
            }
        }
    }
}

// MARK: - Payload versions

@MainActor
struct PayloadVersionTests {
    @Test func venueWithOtherVersionIsDeletedOnRead() async throws {
        let database = try DatabaseManager.inMemory()
        let cache = LocalCache(database: database)
        let venue = Fixtures.summary(id: Fixtures.cafeID, average: 4, count: 2)
        try await cache.storeVenues([venue, Fixtures.summary(id: Fixtures.libraryID, average: nil, count: 0)], at: Fixtures.now)
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE cached_venues SET payload_version = ? WHERE id = ?",
                           arguments: [VenueSummary.payloadVersion + 1, Fixtures.cafeID.uuidString])
        }
        let read = try await cache.cachedVenues(ids: [Fixtures.cafeID, Fixtures.libraryID])
        #expect(read[Fixtures.cafeID] == nil)
        #expect(read[Fixtures.libraryID] != nil)
        #expect(try count("cached_venues", in: database.writer) == 1, "the outdated row is gone, not skipped")
    }

    @Test func undecodableVenueIsDeletedOnSearch() async throws {
        let database = try DatabaseManager.inMemory()
        let cache = LocalCache(database: database)
        try await cache.storeVenues([Fixtures.summary(id: Fixtures.cafeID, average: nil, count: 0)], at: Fixtures.now)
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE cached_venues SET payload = x'7b7d'") // "{}": right version, wrong shape
        }
        let read = try await cache.cachedVenues(near: Fixtures.cafe, radiusMeters: 1_000, category: nil, text: nil, notOlderThan: .distantPast)
        #expect(read.isEmpty)
        #expect(try count("cached_venues", in: database.writer) == 0)
    }

    @Test func draftWithOtherVersionIsDeletedOnRead() async throws {
        let database = try DatabaseManager.inMemory()
        let cache = LocalCache(database: database)
        let user = UUID()
        try await cache.saveDraft(ReviewDraft(venueID: Fixtures.cafeID), key: "k", userID: user)
        try await database.writer.write { db in try db.execute(sql: "UPDATE local_drafts SET payload_version = 0") }
        #expect(try await cache.draft(ReviewDraft.self, key: "k", userID: user) == nil)
        #expect(try count("local_drafts", in: database.writer) == 0)
    }

    @Test func detailWithOtherVersionIsDeletedOnRead() async throws {
        let database = try DatabaseManager.inMemory()
        let cache = LocalCache(database: database)
        try await cache.storeVenueDetail(DetailStubRemote.personalDetail(), at: Fixtures.now)
        try await database.writer.write { db in try db.execute(sql: "UPDATE cached_venue_details SET payload_version = 0") }
        #expect(try await cache.cachedVenueDetail(id: Fixtures.cafeID, notOlderThan: .distantPast) == nil)
        #expect(try count("cached_venue_details", in: database.writer) == 0)
    }

    @Test func unreadableRemoteConfigIsDeleted() async throws {
        let database = try DatabaseManager.inMemory()
        let cache = LocalCache(database: database)
        try await cache.setValue("not a config", forKey: LocalCache.remoteConfigKey)
        #expect(cache.cachedRemoteConfig() == nil)
        #expect(try count("app_kv", in: database.writer) == 0)
    }

    @Test func readingTouchesLastAccessedAt() async throws {
        let database = try DatabaseManager.inMemory()
        let cache = LocalCache(database: database)
        try await cache.storeVenues([Fixtures.summary(id: Fixtures.cafeID, average: nil, count: 0)], at: Fixtures.now)
        let later = Fixtures.now.addingTimeInterval(3_600)
        _ = try await cache.cachedVenues(ids: [Fixtures.cafeID], accessedAt: later)
        let accessed = try await database.writer.read { try Date.fetchOne($0, sql: "SELECT last_accessed_at FROM cached_venues") }
        #expect(accessed == later)
    }
}

// MARK: - Pruning

@MainActor
struct PruneTests {
    @Test func pruneRemovesRowsOlderThanMaxAge() async throws {
        let database = try DatabaseManager.inMemory()
        let cache = LocalCache(database: database)
        let old = Fixtures.summary(name: "Old", average: nil, count: 0)
        let fresh = Fixtures.summary(name: "Fresh", average: nil, count: 0)
        try await cache.storeVenues([old], at: Fixtures.now.addingTimeInterval(-8 * 86_400))
        try await cache.storeVenues([fresh], at: Fixtures.now.addingTimeInterval(-86_400))
        var detail = DetailStubRemote.personalDetail()
        detail.summary.id = UUID()
        try await cache.storeVenueDetail(detail, at: Fixtures.now.addingTimeInterval(-8 * 86_400))

        let result = try await cache.prune(now: Fixtures.now, maxAge: 7 * 86_400, maxVenues: 100, maxDetails: 100)
        #expect(result == LocalCache.PruneResult(venues: 1, details: 1))
        #expect(try await cache.cachedVenues(ids: [old.id, fresh.id]).keys.sorted() == [fresh.id])
        #expect(try count("cached_venue_details", in: database.writer) == 0)
    }

    @Test func pruneKeepsMostRecentlyReadUpToCap() async throws {
        let database = try DatabaseManager.inMemory()
        let cache = LocalCache(database: database)
        let venues = (0..<5).map { Fixtures.summary(name: "V\($0)", average: nil, count: 0) }
        for (index, venue) in venues.enumerated() {
            try await cache.storeVenues([venue], at: Fixtures.now.addingTimeInterval(Double(index)))
        }
        // The two oldest-stored cards are read recently, so LRU keeps them over newer but unread ones.
        _ = try await cache.cachedVenues(ids: [venues[0].id, venues[1].id], accessedAt: Fixtures.now.addingTimeInterval(100))
        try await cache.prune(now: Fixtures.now.addingTimeInterval(200), maxAge: 86_400, maxVenues: 3, maxDetails: 10)
        let left = Set(try await cache.cachedVenues(ids: venues.map(\.id)).keys)
        #expect(left == [venues[0].id, venues[1].id, venues[4].id])
    }

    @Test func detailsAreCappedByLRU() async throws {
        let database = try DatabaseManager.inMemory()
        let cache = LocalCache(database: database)
        var ids: [UUID] = []
        for index in 0..<4 {
            var detail = DetailStubRemote.personalDetail()
            detail.summary.id = UUID()
            ids.append(detail.id)
            try await cache.storeVenueDetail(detail, at: Fixtures.now.addingTimeInterval(Double(index)))
        }
        _ = try await cache.cachedVenueDetail(id: ids[0], notOlderThan: .distantPast, accessedAt: Fixtures.now.addingTimeInterval(50))
        try await cache.prune(now: Fixtures.now.addingTimeInterval(60), maxAge: 86_400, maxVenues: 10, maxDetails: 2)
        #expect(try await cache.cachedVenueDetail(id: ids[0], notOlderThan: .distantPast) != nil)
        #expect(try await cache.cachedVenueDetail(id: ids[3], notOlderThan: .distantPast) != nil)
        #expect(try count("cached_venue_details", in: database.writer) == 2)
    }

    @Test func pruneLeavesUserDataAlone() async throws {
        let database = try DatabaseManager.inMemory()
        let cache = LocalCache(database: database)
        try await cache.saveDraft(ReviewDraft(venueID: Fixtures.cafeID), key: "k", userID: UUID(), at: .distantPast)
        try await cache.storeRemoteConfig(try JSONDecoder().decode(RemoteConfigValues.self, from: Data("{}".utf8)))
        try await cache.prune(now: Fixtures.now, maxAge: 1, maxVenues: 0, maxDetails: 0)
        #expect(try count("local_drafts", in: database.writer) == 1)
        #expect(try count("app_kv", in: database.writer) == 1)
    }
}

// MARK: - Drafts per user and sign-out

@MainActor
struct UserScopedDataTests {
    @Test func draftOfUserAIsInvisibleToUserB() async throws {
        let cache = LocalCache(database: try DatabaseManager.inMemory())
        let userA = UUID()
        let userB = UUID()
        var draft = ReviewDraft(venueID: Fixtures.cafeID)
        draft.rating = 3
        try await cache.saveDraft(draft, key: "review", userID: userA)
        #expect(try await cache.draft(ReviewDraft.self, key: "review", userID: userA)?.rating == 3)
        #expect(try await cache.draft(ReviewDraft.self, key: "review", userID: userB) == nil)

        // Same key for B doesn't overwrite A.
        draft.rating = 1
        try await cache.saveDraft(draft, key: "review", userID: userB)
        #expect(try await cache.draft(ReviewDraft.self, key: "review", userID: userA)?.rating == 3)

        try await cache.deleteDrafts(userID: userA)
        #expect(try await cache.draft(ReviewDraft.self, key: "review", userID: userA) == nil)
        #expect(try await cache.draft(ReviewDraft.self, key: "review", userID: userB)?.rating == 1)
    }

    @Test func serviceDraftsFollowTheSignedInUser() async throws {
        let cache = LocalCache(database: try DatabaseManager.inMemory())
        var current = UUID()
        let service = ReviewService(reviews: ReviewRepository(remote: makeBackend(), cache: cache), configuration: .standard,
                                    notifier: DataChangeNotifier(), userID: { current })
        var draft = ReviewDraft(venueID: Fixtures.cafeID)
        draft.rating = 4
        await service.saveDraft(draft)
        #expect(await service.savedDraft(venueID: Fixtures.cafeID)?.rating == 4)
        current = UUID()
        #expect(await service.savedDraft(venueID: Fixtures.cafeID) == nil)
    }

    @Test func signOutRemovesThatUsersPrivateDataOnly() async throws {
        let database = try DatabaseManager.inMemory()
        let cache = LocalCache(database: database)
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingUploadStore(cache: cache, directory: directory)
        let backend = makeBackend()
        try await registerUser(backend)
        let notifier = DataChangeNotifier()
        let session = SessionService(auth: backend, favorites: FavoriteRepository(remote: backend, cache: cache), notifier: notifier,
                                     cache: cache, uploads: store)
        try await session.start()
        let userA = try #require(session.capabilities?.userID)

        let other = UUID()
        try await cache.saveDraft(ReviewDraft(venueID: Fixtures.cafeID), key: "k", userID: userA)
        try await cache.saveDraft(ReviewDraft(venueID: Fixtures.cafeID), key: "k", userID: other)
        try await cache.storeFavoriteIDs([Fixtures.cafeID], userID: userA, at: Fixtures.now)
        #expect(await store.enqueue(try samplePhoto(), kind: .reviewPhoto, targetID: UUID(), venueID: Fixtures.cafeID, userID: userA, now: Fixtures.now))
        let queued = try #require(try await store.all(userID: userA).first)
        #expect(store.fileExists(queued))
        try await cache.storeVenues([Fixtures.summary(id: Fixtures.cafeID, average: nil, count: 0)], at: Fixtures.now)
        try await cache.storeVenueDetail(DetailStubRemote.personalDetail(), at: Fixtures.now)
        try await cache.storeRemoteConfig(try JSONDecoder().decode(RemoteConfigValues.self, from: Data("{}".utf8)))

        try await session.signOut()

        #expect(session.capabilities?.userID != userA)
        #expect(try await cache.draft(ReviewDraft.self, key: "k", userID: userA) == nil)
        #expect(try await cache.draft(ReviewDraft.self, key: "k", userID: other) != nil, "other users' drafts are not touched")
        #expect(try await cache.cachedFavoriteIDs(userID: userA).isEmpty)
        #expect(try await store.all(userID: userA).isEmpty)
        #expect(!store.fileExists(queued), "the queued photo file is deleted too")
        // Shared, non-personal data stays.
        #expect(try count("cached_venues", in: database.writer) == 1)
        #expect(try count("cached_venue_details", in: database.writer) == 1)
        #expect(try count("app_kv", in: database.writer) == 1)
    }
}

// MARK: - Venue detail offline

/// Returns one detail full of per-user state, or fails like an offline device.
@MainActor
final class DetailStubRemote: VenueRemote {
    var offline = false

    static func personalDetail() -> VenueDetail {
        VenueDetail(summary: Fixtures.summary(id: Fixtures.cafeID, name: "Baicha", average: 4.5, count: 10, distance: 120),
                    description: "Quiet upstairs", websiteURL: URL(string: "https://example.test"), phoneNumber: "02",
                    detailsSource: "owner", appleMapsID: "am-1", ratingDistribution: [0, 0, 1, 4, 5], lastReviewAt: Fixtures.now,
                    tagCounts: [TagCount(slug: "wifi", count: 3)], photoPaths: ["a/b.jpg"], isFavorite: true, isManagedByMe: true,
                    myReview: MyReview(reviewID: UUID(), status: .published, rating: 5, purpose: nil, body: "mine", tags: [],
                                       revisionNumber: 1, updatedAt: Fixtures.now),
                    panoramaPath: "a/p.jpg")
    }

    func venueDetail(id: UUID) async throws -> VenueDetail {
        if offline { throw BackendError.network }
        return Self.personalDetail()
    }
    func searchVenues(_ query: VenueSearchQuery) async throws -> VenueSearchPage { throw BackendError.network }
    func venueCards(ids: [UUID], origin: GeoPoint?) async throws -> [VenueSummary] { throw BackendError.network }
    func matchProviderRefs(provider: String, externalIDs: [String]) async throws -> [String: UUID] { [:] }
    func reviews(venueID: UUID, sort: ReviewSort, limit: Int, offset: Int) async throws -> ReviewPage { throw BackendError.network }
    func signedMediaURLs(paths: [String], bucket: MediaBucket) async throws -> [String: URL] { [:] }
    func logEvent(_ name: String, venueID: UUID?) async {}
}

/// Favorite ids for `FavoriteRepository` without a backend.
@MainActor
final class StubFavorites: FavoriteRemote {
    var ids: [UUID]
    init(ids: [UUID]) { self.ids = ids }
    func favoriteVenueIDs() async throws -> [UUID] { ids }
    func setFavorite(venueID: UUID, isFavorite: Bool) async throws {}
}

@MainActor
struct VenueDetailOfflineTests {
    @Test func offlineDetailComesFromCacheWithoutPersonalFields() async throws {
        let database = try DatabaseManager.inMemory()
        let cache = LocalCache(database: database)
        let remote = DetailStubRemote()
        let repo = VenueRepository(remote: remote, cache: cache, configuration: .standard, clock: { Fixtures.now })

        let live = try await repo.detail(id: Fixtures.cafeID)
        #expect(live.source == .live)
        #expect(live.detail.myReview != nil)

        // Nothing personal is ever written to disk.
        let raw = try #require(try await database.writer.read { try Data.fetchOne($0, sql: "SELECT payload FROM cached_venue_details") })
        let json = String(decoding: raw, as: UTF8.self)
        #expect(!json.contains("mine"))
        #expect(!json.contains("isFavorite"))
        #expect(!json.contains("isManagedByMe"))

        remote.offline = true
        let offline = try await repo.detail(id: Fixtures.cafeID)
        #expect(offline.source == .offline(cachedAt: Fixtures.now))
        #expect(offline.detail.myReview == nil)
        #expect(offline.detail.isFavorite == false)
        #expect(offline.detail.isManagedByMe == false)
        #expect(offline.detail.summary.name == "Baicha")
        #expect(offline.detail.summary.distanceMeters == nil, "distance depends on where you are; not cached")
        #expect(offline.detail.tagCounts == live.detail.tagCounts)
        #expect(offline.detail.panoramaPath == "a/p.jpg")
    }

    @Test func offlineDetailTakesFavoriteFromFavoriteRepository() async throws {
        let cache = LocalCache(database: try DatabaseManager.inMemory())
        let favorites = FavoriteRepository(remote: StubFavorites(ids: [Fixtures.cafeID]), cache: cache)
        try await favorites.refresh(userID: UUID())
        let remote = DetailStubRemote()
        let repo = VenueRepository(remote: remote, cache: cache, configuration: .standard, favorites: favorites, clock: { Fixtures.now })
        _ = try await repo.detail(id: Fixtures.cafeID)
        remote.offline = true
        #expect(try await repo.detail(id: Fixtures.cafeID).detail.isFavorite)
    }

    @Test func offlineWithoutCacheOrTooOldThrows() async throws {
        let cache = LocalCache(database: try DatabaseManager.inMemory())
        let remote = DetailStubRemote()
        remote.offline = true
        var now = Fixtures.now
        let repo = VenueRepository(remote: remote, cache: cache, configuration: .standard, clock: { now })
        await #expect(throws: BackendError.network) { try await repo.detail(id: Fixtures.cafeID) }

        try await cache.storeVenueDetail(DetailStubRemote.personalDetail(), at: Fixtures.now)
        now = Fixtures.now.addingTimeInterval(AppConfiguration.standard.venueCacheMaxAge + 1)
        await #expect(throws: BackendError.network) { try await repo.detail(id: Fixtures.cafeID) }
    }

    @Test func viewModelShowsOfflineBannerAndDisablesNetworkActions() async throws {
        let cache = LocalCache(database: try DatabaseManager.inMemory())
        let remote = DetailStubRemote()
        let backend = makeBackend()
        let notifier = DataChangeNotifier()
        let favorites = FavoriteRepository(remote: backend, cache: cache)
        let repo = VenueRepository(remote: remote, cache: cache, configuration: .standard, favorites: favorites, clock: { Fixtures.now })
        _ = try await repo.detail(id: Fixtures.cafeID)
        remote.offline = true
        let viewModel = VenueDetailViewModel(
            initial: Fixtures.summary(id: Fixtures.cafeID, average: nil, count: 0), venues: repo, favorites: favorites,
            reviews: ReviewRepository(remote: backend, cache: cache),
            session: SessionService(auth: backend, favorites: favorites, notifier: notifier),
            mapCoordinator: MapCoordinator(), notifier: notifier)
        await viewModel.load()
        #expect(viewModel.state.isOffline)
        #expect(viewModel.state.offlineBannerText != nil)
        #expect(!viewModel.state.canWriteReview)
        #expect(!viewModel.state.canToggleFavorite)
        #expect(viewModel.writeReviewRoute() == .offline)
        viewModel.toggleFavorite()
        #expect(viewModel.state.isFavorite == false, "favorite is not toggled offline")
    }
}

// MARK: - Pending uploads

/// Upload remote whose next answers are scripted (nil = success).
@MainActor
final class ScriptedUploads: ReviewRemote, SubmissionRemote {
    var results: [Error?]
    private(set) var reviewUploads: [UUID] = []
    private(set) var submissionUploads: [UUID] = []

    init(_ results: [Error?]) { self.results = results }

    private func next() throws {
        let result = results.isEmpty ? nil : results.removeFirst()
        if let result { throw result }
    }

    func uploadReviewPhoto(revisionID: UUID, photo: PhotoUpload) async throws {
        try next()
        reviewUploads.append(revisionID)
    }
    func uploadSubmissionPhoto(submissionID: UUID, photo: PhotoUpload) async throws {
        try next()
        submissionUploads.append(submissionID)
    }
    func submitReview(_ submission: ReviewSubmission) async throws -> ReviewSubmissionResult {
        ReviewSubmissionResult(reviewID: UUID(), revisionID: UUID(), revisionNumber: 1, status: .published, replayed: false)
    }
    func createSubmission(_ draft: VenueSubmissionDraft) async throws -> SubmissionReceipt {
        .submitted(submissionID: UUID(), status: .pendingReview, duplicates: [])
    }

    func verificationPolicy() async throws -> VerificationPolicy { .default }
    func issueVisitChallenge(venueID: UUID) async throws -> VisitChallenge { throw BackendError.network }
    func verifyVisit(challengeID: UUID, reading: LocationReading) async throws -> VisitVerificationResult { throw BackendError.network }
    func flagReview(id: UUID, reason: FlagReason, note: String?) async throws {}
    func resubmit(id: UUID, draft: VenueSubmissionDraft) async throws {}
    func withdrawSubmission(id: UUID) async throws {}
    func mySubmissions() async throws -> [VenueSubmission] { [] }
    func submissionPhotos(submissionID: UUID) async throws -> [SubmissionPhoto] { [] }
    func removeSubmissionPhoto(id: UUID) async throws {}
}

@MainActor
final class ChangeRecorder {
    var changes: [DataChange] = []
    init(_ notifier: DataChangeNotifier) {
        notifier.subscribe(self) { [weak self] in self?.changes.append($0) }
    }
}

@MainActor
struct PendingUploadTests {
    private struct Harness {
        let cache: LocalCache
        let store: PendingUploadStore
        let remote: ScriptedUploads
        let notifier: DataChangeNotifier
        let service: PendingUploadService
        let clock: TestClock
        let user: UUID
        let directory: URL
    }

    private func harness(_ results: [Error?], user: UUID = UUID()) throws -> Harness {
        let cache = LocalCache(database: try DatabaseManager.inMemory())
        let directory = temporaryDirectory()
        let store = PendingUploadStore(cache: cache, directory: directory)
        let remote = ScriptedUploads(results)
        let notifier = DataChangeNotifier()
        let clock = TestClock()
        let service = PendingUploadService(store: store, reviews: remote, submissions: remote, userID: { user },
                                           notifier: notifier, clock: { clock.now })
        return Harness(cache: cache, store: store, remote: remote, notifier: notifier, service: service, clock: clock,
                       user: user, directory: directory)
    }

    private func enqueueReviewPhoto(_ h: Harness, revision: UUID = UUID(), user: UUID? = nil) async throws -> PendingUpload {
        let owner = user ?? h.user
        #expect(await h.store.enqueue(try samplePhoto(), kind: .reviewPhoto, targetID: revision, venueID: Fixtures.cafeID,
                                      userID: owner, now: h.clock.now))
        return try #require(try await h.store.all(userID: owner).last)
    }

    @Test func successRemovesRowAndFileAndNotifies() async throws {
        let h = try harness([nil])
        defer { try? FileManager.default.removeItem(at: h.directory) }
        let recorder = ChangeRecorder(h.notifier)
        let revision = UUID()
        let upload = try await enqueueReviewPhoto(h, revision: revision)

        let summary = await h.service.run()
        #expect(summary.uploaded == 1)
        #expect(h.remote.reviewUploads == [revision])
        #expect(try await h.store.all(userID: h.user).isEmpty)
        #expect(!h.store.fileExists(upload))
        #expect(recorder.changes.contains(.reviewSubmitted(venueID: Fixtures.cafeID)))
    }

    @Test func transientErrorBacksOffAndRetries() async throws {
        let h = try harness([BackendError.network, URLError(.timedOut), nil])
        defer { try? FileManager.default.removeItem(at: h.directory) }
        let upload = try await enqueueReviewPhoto(h)

        #expect(await h.service.run().retrying == 1)
        var stored = try #require(try await h.store.all(userID: h.user).first)
        #expect(stored.attempts == 1)
        #expect(stored.nextAttemptAt == h.clock.now.addingTimeInterval(30))
        #expect(stored.lastError != nil)

        // Not due yet: nothing is sent.
        #expect(await h.service.run() == PendingUploadService.RunSummary())
        h.clock.advance(30)
        #expect(await h.service.run().retrying == 1)
        stored = try #require(try await h.store.all(userID: h.user).first)
        #expect(stored.attempts == 2)
        #expect(stored.nextAttemptAt == h.clock.now.addingTimeInterval(60), "exponential backoff")

        h.clock.advance(60)
        #expect(await h.service.run().uploaded == 1)
        #expect(try await h.store.all(userID: h.user).isEmpty)
        #expect(!h.store.fileExists(upload))
    }

    @Test func givesUpAfterMaxAttempts() async throws {
        let h = try harness(Array(repeating: BackendError.network, count: 10))
        defer { try? FileManager.default.removeItem(at: h.directory) }
        let upload = try await enqueueReviewPhoto(h)
        var dropped = 0
        for _ in 0..<PendingUploadService.maxAttempts {
            dropped += await h.service.run().dropped
            h.clock.advance(3_600)
        }
        #expect(dropped == 1)
        #expect(h.remote.results.count == 10 - PendingUploadService.maxAttempts, "exactly maxAttempts tries")
        #expect(try await h.store.all(userID: h.user).isEmpty)
        #expect(!h.store.fileExists(upload))
    }

    @Test func permanentErrorStopsImmediately() async throws {
        let h = try harness([BackendError.notFound])
        defer { try? FileManager.default.removeItem(at: h.directory) }
        let upload = try await enqueueReviewPhoto(h)
        #expect(await h.service.run().dropped == 1)
        #expect(try await h.store.all(userID: h.user).isEmpty)
        #expect(!h.store.fileExists(upload))
        #expect(h.remote.results.isEmpty, "tried once only")
    }

    @Test func onlyTheCurrentUsersItemsAreSent() async throws {
        let h = try harness([nil, nil])
        defer { try? FileManager.default.removeItem(at: h.directory) }
        let someoneElse = UUID()
        _ = try await enqueueReviewPhoto(h, user: someoneElse)
        _ = try await enqueueReviewPhoto(h)
        #expect(await h.service.run().uploaded == 1)
        #expect(try await h.store.all(userID: someoneElse).count == 1)
    }

    @Test func classification() {
        #expect(PendingUploadService.isTransient(BackendError.network))
        #expect(PendingUploadService.isTransient(URLError(.notConnectedToInternet)))
        #expect(PendingUploadService.isTransient(BackendError.rateLimited))
        #expect(PendingUploadService.isTransient(BackendError.server("boom")))
        #expect(!PendingUploadService.isTransient(BackendError.notFound))
        #expect(!PendingUploadService.isTransient(BackendError.invalidInput("file_too_large")))
        #expect(!PendingUploadService.isTransient(BackendError.reviewRemoved))
        #expect(!PendingUploadService.isTransient(BackendError.registrationRequired))
    }

    @Test func reviewServiceQueuesPhotosThatFailOffline() async throws {
        let cache = LocalCache(database: try DatabaseManager.inMemory())
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingUploadStore(cache: cache, directory: directory)
        let remote = ScriptedUploads([nil, BackendError.network, BackendError.invalidInput("file_too_large")])
        let user = UUID()
        let service = ReviewService(reviews: ReviewRepository(remote: remote, cache: cache), configuration: .standard,
                                    notifier: DataChangeNotifier(), userID: { user }, uploads: store)
        var draft = ReviewDraft(venueID: Fixtures.cafeID)
        draft.rating = 5
        let photo = try samplePhoto()
        let outcome = try await service.publish(draft, verificationID: UUID(), photos: [photo, photo, photo])
        #expect(outcome.failedPhotos == 1, "a rejected photo is not queued")
        #expect(outcome.queuedPhotos == 1)
        let queued = try #require(try await store.all(userID: user).first)
        #expect(queued.kind == .reviewPhoto)
        #expect(queued.targetID == outcome.result.revisionID)
        #expect(queued.venueID == Fixtures.cafeID)
        #expect(store.photo(for: queued)?.width == photo.width)
    }

    @Test func submissionServiceQueuesPhotosThatFailOffline() async throws {
        let cache = LocalCache(database: try DatabaseManager.inMemory())
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingUploadStore(cache: cache, directory: directory)
        let remote = ScriptedUploads([URLError(.networkConnectionLost)])
        let user = UUID()
        let service = SubmissionService(submissions: SubmissionRepository(remote: remote, cache: cache), configuration: .standard,
                                        notifier: DataChangeNotifier(), userID: { user }, uploads: store)
        var draft = VenueSubmissionDraft()
        draft.name = "New place"
        draft.category = .cafe
        draft.coordinate = Fixtures.cafe
        let outcome = try await service.submit(draft, photos: [try samplePhoto()])
        #expect(outcome.queuedPhotos == 1)
        #expect(outcome.failedPhotos == 0)
        guard case .submitted(let id, _, _) = outcome.receipt else { Issue.record("expected submitted"); return }
        #expect(try await store.all(userID: user).first?.targetID == id)
    }

    @Test func orphanFilesAreRemoved() async throws {
        let h = try harness([])
        defer { try? FileManager.default.removeItem(at: h.directory) }
        let kept = try await enqueueReviewPhoto(h)
        let orphan = h.directory.appendingPathComponent("orphan.jpg")
        try Data([1, 2, 3]).write(to: orphan)
        await h.store.removeOrphanFiles()
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(h.store.fileExists(kept))
    }
}
