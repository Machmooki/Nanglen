import Foundation
import os

/// Where a list came from, so screens can label cached data honestly.
nonisolated enum DataSourceState: Hashable, Sendable {
    case live
    /// Served from the device cache because the backend could not be reached.
    case offline(cachedAt: Date?)
}

nonisolated struct VenueResults: Hashable, Sendable {
    var venues: [VenueSummary]
    var hasMore: Bool
    var source: DataSourceState
}

// MARK: - Venues

/// Approved venues: backend first, cache as fallback. Never shows unapproved places.
final class VenueRepository {
    private let remote: VenueRemote
    private let cache: LocalCache
    private let configuration: AppConfiguration
    private let clock: () -> Date
    private let logger = Logger(subsystem: "Mach.Nanglen-App", category: "VenueRepository")

    init(remote: VenueRemote, cache: LocalCache, configuration: AppConfiguration, clock: @escaping () -> Date = { Date() }) {
        self.remote = remote
        self.cache = cache
        self.configuration = configuration
        self.clock = clock
    }

    func search(_ query: VenueSearchQuery) async throws -> VenueResults {
        do {
            let page = try await remote.searchVenues(query)
            try? await cache.storeVenues(page.venues, at: clock())
            return VenueResults(venues: page.venues, hasMore: page.hasMore, source: .live)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as BackendError where error == .network {
            return try await cachedResults(for: query, error: error)
        } catch let error as URLError {
            return try await cachedResults(for: query, error: error)
        }
    }

    private func cachedResults(for query: VenueSearchQuery, error: Error) async throws -> VenueResults {
        logger.notice("Search offline, using cache: \(error.localizedDescription, privacy: .public)")
        let cached = try await cache.cachedVenues(
            near: query.origin, radiusMeters: query.radiusMeters, category: query.category,
            text: query.trimmedText, notOlderThan: clock().addingTimeInterval(-configuration.venueCacheMaxAge))
        guard !cached.isEmpty else { throw BackendError.network }
        let ranker = configuration.ranker
        // Offline approximation: tag filters use the cached top tags. Results are labelled stale.
        var venues = cached.map(\.venue).filter(query.filter.matches)
        venues = venues.map { venue in
            var scored = venue
            let relevance = query.trimmedText.isEmpty ? nil : ranker.relevance(name: venue.name, query: query.trimmedText)
            scored.rankScore = ranker.score(rating: venue.rating, distanceMeters: venue.distanceMeters, relevance: relevance)
            return scored
        }
        let sorted = ranker.sort(venues, by: query.filter.sort)
        return VenueResults(venues: Array(sorted.prefix(query.limit)), hasMore: false,
                            source: .offline(cachedAt: cached.map(\.cachedAt).min()))
    }

    func detail(id: UUID) async throws -> VenueDetail {
        let detail = try await remote.venueDetail(id: id)
        try? await cache.storeVenues([detail.summary], at: clock())
        return detail
    }

    func cachedSummary(id: UUID) async -> CachedVenue? {
        try? await cache.cachedVenues(ids: [id])[id]
    }

    func cards(ids: [UUID], origin: GeoPoint?) async throws -> [VenueSummary] {
        let cards = try await remote.venueCards(ids: ids, origin: origin)
        try? await cache.storeVenues(cards, at: clock())
        return cards
    }

    func reviews(venueID: UUID, sort: ReviewSort, offset: Int, limit: Int = 20) async throws -> ReviewPage {
        try await remote.reviews(venueID: venueID, sort: sort, limit: limit, offset: offset)
    }

    func canonicalVenueIDs(forAppleMapsIDs ids: [String]) async throws -> [String: UUID] {
        try await remote.matchProviderRefs(provider: "apple_maps", externalIDs: ids)
    }

    func signedURLs(paths: [String], bucket: MediaBucket) async -> [String: URL] {
        (try? await remote.signedMediaURLs(paths: paths, bucket: bucket)) ?? [:]
    }

    func log(_ event: String, venueID: UUID?) {
        let remote = remote
        Task { await remote.logEvent(event, venueID: venueID) }
    }
}

// MARK: - Favorites

/// Favorites are written to the backend first (no silent offline queue). The id set is mirrored
/// to the cache so Saved can render offline with a stale label.
final class FavoriteRepository {
    private let remote: FavoriteRemote
    private let cache: LocalCache
    private let clock: () -> Date
    private(set) var favoriteIDs: [UUID] = []
    private var userID: UUID?

    init(remote: FavoriteRemote, cache: LocalCache, clock: @escaping () -> Date = { Date() }) {
        self.remote = remote
        self.cache = cache
        self.clock = clock
    }

    func contains(_ id: UUID) -> Bool { favoriteIDs.contains(id) }

    /// Loads ids from the backend; falls back to the cached list when offline.
    @discardableResult
    func refresh(userID: UUID) async throws -> DataSourceState {
        self.userID = userID
        do {
            favoriteIDs = try await remote.favoriteVenueIDs()
            try? await cache.storeFavoriteIDs(favoriteIDs, userID: userID, at: clock())
            return .live
        } catch {
            favoriteIDs = (try? await cache.cachedFavoriteIDs(userID: userID)) ?? []
            if favoriteIDs.isEmpty { throw error }
            return .offline(cachedAt: nil)
        }
    }

    func setFavorite(_ venueID: UUID, isFavorite: Bool) async throws {
        try await remote.setFavorite(venueID: venueID, isFavorite: isFavorite)
        favoriteIDs.removeAll { $0 == venueID }
        if isFavorite { favoriteIDs.insert(venueID, at: 0) }
        if let userID { try? await cache.storeFavoriteIDs(favoriteIDs, userID: userID, at: clock()) }
    }

    func reset() {
        favoriteIDs = []
        userID = nil
    }
}

// MARK: - Reviews

final class ReviewRepository {
    private let remote: ReviewRemote
    private let cache: LocalCache

    init(remote: ReviewRemote, cache: LocalCache) {
        self.remote = remote
        self.cache = cache
    }

    func policy() async -> VerificationPolicy? { try? await remote.verificationPolicy() }
    func issueChallenge(venueID: UUID) async throws -> VisitChallenge { try await remote.issueVisitChallenge(venueID: venueID) }
    func verify(challengeID: UUID, reading: LocationReading) async throws -> VisitVerificationResult {
        try await remote.verifyVisit(challengeID: challengeID, reading: reading)
    }
    func submit(_ submission: ReviewSubmission) async throws -> ReviewSubmissionResult { try await remote.submitReview(submission) }
    func uploadPhoto(revisionID: UUID, photo: PhotoUpload) async throws { try await remote.uploadReviewPhoto(revisionID: revisionID, photo: photo) }
    func flag(reviewID: UUID, reason: FlagReason, note: String?) async throws { try await remote.flagReview(id: reviewID, reason: reason, note: note) }

    // Local drafts — preserved when verification or upload fails; never shown as published.
    private func key(_ venueID: UUID) -> String { "review-draft-\(venueID.uuidString)" }
    func draft(venueID: UUID) async -> ReviewDraft? { try? await cache.draft(ReviewDraft.self, key: key(venueID)) }
    func saveDraft(_ draft: ReviewDraft) async { try? await cache.saveDraft(draft, key: key(draft.venueID)) }
    func deleteDraft(venueID: UUID) async { try? await cache.deleteDraft(key: key(venueID)) }
}

// MARK: - Submissions, business, admin

final class SubmissionRepository {
    private let remote: SubmissionRemote
    private let cache: LocalCache
    private static let draftKey = "venue-submission-draft"

    init(remote: SubmissionRemote, cache: LocalCache) {
        self.remote = remote
        self.cache = cache
    }

    func create(_ draft: VenueSubmissionDraft) async throws -> SubmissionReceipt { try await remote.createSubmission(draft) }
    func resubmit(id: UUID, draft: VenueSubmissionDraft) async throws { try await remote.resubmit(id: id, draft: draft) }
    func withdraw(id: UUID) async throws { try await remote.withdrawSubmission(id: id) }
    func uploadPhoto(submissionID: UUID, photo: PhotoUpload) async throws { try await remote.uploadSubmissionPhoto(submissionID: submissionID, photo: photo) }
    func mine() async throws -> [VenueSubmission] { try await remote.mySubmissions() }

    func draft() async -> VenueSubmissionDraft? { try? await cache.draft(VenueSubmissionDraft.self, key: Self.draftKey) }
    func saveDraft(_ draft: VenueSubmissionDraft) async { try? await cache.saveDraft(draft, key: Self.draftKey) }
    func deleteDraft() async { try? await cache.deleteDraft(key: Self.draftKey) }
}

final class BusinessRepository {
    private let remote: BusinessRemote
    init(remote: BusinessRemote) { self.remote = remote }
    func requestClaim(_ draft: VenueClaimDraft) async throws -> ClaimStatus { try await remote.requestClaim(draft) }
    func myClaims() async throws -> [VenueClaim] { try await remote.myClaims() }
}

/// Admin operations. UI visibility follows server capabilities, but authorization is enforced by
/// the backend on every call — hiding a button is not security.
final class AdminRepository {
    private let remote: AdminRemote
    init(remote: AdminRemote) { self.remote = remote }
    func submissions(status: SubmissionStatus = .pendingReview) async throws -> [AdminSubmissionRow] { try await remote.adminSubmissions(status: status) }
    func submissionDetail(id: UUID) async throws -> AdminSubmissionDetail { try await remote.adminSubmissionDetail(id: id) }
    func decide(submissionID: UUID, decision: AdminSubmissionDecision) async throws { try await remote.adminDecide(submissionID: submissionID, decision: decision) }
    func pendingClaims() async throws -> [AdminClaimRow] { try await remote.adminPendingClaims() }
    func decideClaim(id: UUID, approve: Bool, reason: String?) async throws { try await remote.adminDecideClaim(id: id, approve: approve, reason: reason) }
    func flaggedReviews() async throws -> [AdminFlaggedReview] { try await remote.adminFlaggedReviews() }
    func moderateReview(id: UUID, status: ReviewStatus, reason: String) async throws { try await remote.adminModerateReview(id: id, status: status, reason: reason) }
}
