import Foundation
import os

/// In-process implementation of the Nanglen backend contract for development, demos and tests.
///
/// It enforces the same rules as the SQL functions (registered-only contributions, one-time
/// expiring challenges, server-side distance/accuracy/age checks, one current review per user and
/// venue with revisions, Admin-only approval with an audit trail). It is **not** a server: data
/// lives in a JSON file on this device and the UI labels the mode "Demo". Email codes are a fixed
/// demo value shown in the UI; no email is sent.
final class DemoBackend: NanglenBackend {
    // MARK: Stored state (Codable, persisted as JSON)

    nonisolated struct User: Codable, Hashable {
        var id: UUID
        var isAnonymous: Bool
        var email: String?
        var displayName: String
        var avatarPath: String? = nil
    }

    nonisolated struct VenueRow: Codable, Hashable {
        var id: UUID
        var name: String
        var description: String?
        var category: VenueCategory
        var address: String?
        var latitude: Double
        var longitude: Double
        var websiteURL: String?
        var phoneNumber: String?
        var detailsSource: String?
        var status: VenueStatus
        var businessID: UUID?
        var createdAt: Date
    }

    nonisolated struct ProviderRef: Codable, Hashable {
        var venueID: UUID
        var provider: String
        var externalID: String
    }

    nonisolated struct SubmissionRow: Codable, Hashable {
        var id: UUID
        var submittedBy: UUID
        var clientRequestID: UUID
        var draft: VenueSubmissionDraft
        var status: SubmissionStatus
        var revision: Int
        var decisionReason: String?
        var duplicateOf: UUID?
        var approvedVenueID: UUID?
        var submittedAt: Date
        var updatedAt: Date
    }

    nonisolated struct Challenge: Codable, Hashable {
        var id: UUID
        var userID: UUID
        var venueID: UUID
        var issuedAt: Date
        var expiresAt: Date
        var consumedAt: Date?
    }

    nonisolated struct Verification: Codable, Hashable {
        var id: UUID
        var challengeID: UUID
        var userID: UUID
        var venueID: UUID
        var status: VisitVerificationStatus
        var distanceBucket: String
        var expiresAt: Date
        var consumedAt: Date?
    }

    nonisolated struct ReviewRow: Codable, Hashable {
        var id: UUID
        var venueID: UUID
        var userID: UUID
        var currentRevisionID: UUID?
        var status: ReviewStatus
    }

    nonisolated struct RevisionRow: Codable, Hashable {
        var id: UUID
        var reviewID: UUID
        var userID: UUID
        var number: Int
        var verificationID: UUID?
        var rating: Int
        var purpose: VisitPurpose?
        var body: String?
        var tags: [String]
        var idempotencyKey: UUID
        var createdAt: Date
    }

    nonisolated struct MediaRow: Codable, Hashable {
        var path: String
        var kind: String // "review" | "submission"
        var parentID: UUID
        var ownerID: UUID
        var status: String // pending | approved | rejected
        var venueID: UUID?
    }

    nonisolated struct ClaimRow: Codable, Hashable {
        var id: UUID
        var clientRequestID: UUID
        var venueID: UUID
        var requestedBy: UUID
        var businessName: String
        var role: String
        var contactNote: String?
        var evidenceNote: String?
        var status: ClaimStatus
        var decisionReason: String?
        var createdAt: Date
    }

    nonisolated struct Membership: Codable, Hashable {
        var businessID: UUID
        var businessName: String
        var userID: UUID
        var role: String
    }

    nonisolated struct Flag: Codable, Hashable {
        var reviewID: UUID
        var userID: UUID
        var reason: String
        var open: Bool
        var createdAt: Date
    }

    nonisolated struct AuditRow: Codable, Hashable {
        var actorID: UUID
        var action: String
        var targetID: UUID
        var reason: String?
        var createdAt: Date
    }

    nonisolated struct State: Codable {
        var users: [User] = []
        var currentUserID: UUID?
        var adminEmails: Set<String> = DemoBackend.defaultAdminEmails
        var venues: [VenueRow] = []
        var providerRefs: [ProviderRef] = []
        var submissions: [SubmissionRow] = []
        var challenges: [Challenge] = []
        var verifications: [Verification] = []
        var reviews: [ReviewRow] = []
        var revisions: [RevisionRow] = []
        var media: [MediaRow] = []
        var favorites: [UUID: [UUID]] = [:]
        var claims: [ClaimRow] = []
        var memberships: [Membership] = []
        var flags: [Flag] = []
        var audit: [AuditRow] = []
        var pendingEmailLink: [UUID: String] = [:]
        var pendingSignIn: [UUID: String] = [:]
    }

    // MARK: Configuration

    let mode: BackendMode = .demo
    private var state: State
    private let fileURL: URL?
    private let mediaDirectory: URL?
    private let clock: () -> Date
    private let policy: VerificationPolicy
    private let ranker: VenueRanker
    private let challengeTTL: TimeInterval = 120
    private let verificationTTL: TimeInterval = 900
    private let logger = Logger(subsystem: "Mach.Nanglen-App", category: "DemoBackend")

    /// - Parameters:
    ///   - directory: where state and media are persisted; `nil` keeps everything in memory (tests).
    init(directory: URL?, reset: Bool = false, seed: Bool = true, clock: @escaping () -> Date = { Date() },
         policy: VerificationPolicy = .default, ranker: VenueRanker = VenueRanker()) {
        self.clock = clock
        self.policy = policy
        self.ranker = ranker
        if let directory {
            if reset { try? FileManager.default.removeItem(at: directory) }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            fileURL = directory.appendingPathComponent("demo-state.json")
            mediaDirectory = directory.appendingPathComponent("media", isDirectory: true)
        } else {
            fileURL = nil
            mediaDirectory = nil
        }
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            state = decoded
        } else {
            state = State()
            if seed { applySeed() }
        }
    }

    private func applySeed() {
        let created = clock().addingTimeInterval(-30 * 86_400)
        for venue in DemoSeed.venues {
            guard let id = UUID(uuidString: venue.id) else { continue }
            state.venues.append(VenueRow(id: id, name: venue.name, description: venue.description, category: venue.category,
                                         address: venue.address, latitude: venue.latitude, longitude: venue.longitude,
                                         websiteURL: nil, phoneNumber: nil, detailsSource: nil, status: .active,
                                         businessID: nil, createdAt: created))
            state.providerRefs.append(ProviderRef(venueID: id, provider: "curated", externalID: "seed:\(venue.id)"))
        }
        var authors: [String: UUID] = [:]
        for (offset, seed) in DemoSeed.reviews.enumerated() {
            let author = authors[seed.author] ?? {
                let user = User(id: UUID(), isAnonymous: false, email: nil, displayName: seed.author)
                state.users.append(user)
                authors[seed.author] = user.id
                return user.id
            }()
            let venueID = state.venues[seed.venueIndex].id
            let review = ReviewRow(id: UUID(), venueID: venueID, userID: author, currentRevisionID: nil, status: .published)
            let revision = RevisionRow(id: UUID(), reviewID: review.id, userID: author, number: 1, verificationID: nil,
                                       rating: seed.rating, purpose: seed.purpose, body: seed.body, tags: seed.tags,
                                       idempotencyKey: UUID(), createdAt: created.addingTimeInterval(Double(offset) * 86_400))
            var stored = review
            stored.currentRevisionID = revision.id
            state.reviews.append(stored)
            state.revisions.append(revision)
        }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Demo state save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Identity helpers (server-side derivation)

    private func currentUser() throws -> User {
        guard let id = state.currentUserID, let user = state.users.first(where: { $0.id == id }) else {
            throw BackendError.notAuthenticated
        }
        return user
    }

    nonisolated static var defaultAdminEmails: Set<String> {
        #if DEBUG
        [DemoSeed.adminEmail]
        #else
        []
        #endif
    }

    private func isRegistered(_ user: User) -> Bool { !user.isAnonymous && user.email != nil }
    private func isAdmin(_ user: User) -> Bool { isRegistered(user) && user.email.map(state.adminEmails.contains) == true }

    private func requireRegistered() throws -> User {
        let user = try currentUser()
        guard isRegistered(user) else { throw BackendError.registrationRequired }
        return user
    }

    private func requireAdmin() throws -> User {
        let user = try currentUser()
        guard isAdmin(user) else { throw BackendError.adminRequired }
        return user
    }

    private func audit(_ actor: User, _ action: String, _ target: UUID, _ reason: String?) {
        state.audit.append(AuditRow(actorID: actor.id, action: action, targetID: target, reason: reason, createdAt: clock()))
    }

    // MARK: AuthRemote

    func ensureSession() async throws {
        if let id = state.currentUserID, state.users.contains(where: { $0.id == id }) { return }
        let user = User(id: UUID(), isAnonymous: true, email: nil, displayName: "Nanglen user")
        state.users.append(user)
        state.currentUserID = user.id
        save()
    }

    func capabilities() async throws -> UserCapabilities {
        let user = try currentUser()
        let memberships = isRegistered(user) ? state.memberships.filter { $0.userID == user.id }.map { membership in
            BusinessMembership(businessID: membership.businessID, businessName: membership.businessName, role: membership.role,
                               venueIDs: state.venues.filter { $0.businessID == membership.businessID }.map(\.id))
        } : []
        return UserCapabilities(
            userID: user.id, isAnonymous: user.isAnonymous, isRegistered: isRegistered(user), isAdmin: isAdmin(user),
            displayName: user.displayName,
            favoritesCount: state.favorites[user.id]?.count ?? 0,
            reviewsCount: state.reviews.filter { $0.userID == user.id && $0.status != .removed }.count,
            openSubmissionsCount: state.submissions.filter { $0.submittedBy == user.id && $0.status.canWithdraw }.count,
            memberships: memberships,
            contactHint: user.email.map(EmailAddress.masked), avatarPath: user.avatarPath)
    }

    func requestEmailLink(email: String) async throws {
        let user = try currentUser()
        guard let email = EmailAddress.normalized(email) else { throw BackendError.invalidInput("invalid_email") }
        if state.users.contains(where: { $0.email == email && $0.id != user.id }) {
            // Never silently merge or switch accounts: the app offers an explicit sign-in instead.
            throw BackendError.accountExists
        }
        state.pendingEmailLink[user.id] = email
        save()
    }

    func confirmEmailLink(email: String, code: String) async throws {
        var user = try currentUser()
        guard let email = EmailAddress.normalized(email), state.pendingEmailLink[user.id] == email,
              code == DemoSeed.demoOTP else { throw BackendError.invalidOTP }
        if state.users.contains(where: { $0.email == email && $0.id != user.id }) { throw BackendError.accountExists }
        // Same user id is kept: favorites and everything owned stay attached.
        user.email = email
        user.isAnonymous = false
        replaceUser(user)
        state.pendingEmailLink[user.id] = nil
        save()
    }

    func requestEmailSignIn(email: String) async throws {
        let user = try currentUser()
        guard let email = EmailAddress.normalized(email) else { throw BackendError.invalidInput("invalid_email") }
        guard state.users.contains(where: { $0.email == email }) else { throw BackendError.notFound }
        state.pendingSignIn[user.id] = email
        save()
    }

    func confirmEmailSignIn(email: String, code: String) async throws {
        let current = try currentUser()
        guard let email = EmailAddress.normalized(email), state.pendingSignIn[current.id] == email,
              code == DemoSeed.demoOTP, let existing = state.users.first(where: { $0.email == email }) else {
            throw BackendError.invalidOTP
        }
        state.pendingSignIn[current.id] = nil
        state.currentUserID = existing.id
        save()
    }

    func deleteAccount() async throws {
        let user = try currentUser()
        if isAdmin(user) { throw BackendError.deletionBlocked }
        let reviewIDs = Set(state.reviews.filter { $0.userID == user.id }.map(\.id))
        let revisionIDs = Set(state.revisions.filter { reviewIDs.contains($0.reviewID) }.map(\.id))
        let submissionIDs = Set(state.submissions.filter { $0.submittedBy == user.id }.map(\.id))
        for media in state.media where media.ownerID == user.id && media.venueID == nil {
            if let mediaDirectory { try? FileManager.default.removeItem(at: mediaDirectory.appendingPathComponent(media.path)) }
        }
        state.media.removeAll { $0.ownerID == user.id && $0.venueID == nil }
        state.revisions.removeAll { revisionIDs.contains($0.id) }
        state.reviews.removeAll { reviewIDs.contains($0.id) }
        state.submissions.removeAll { submissionIDs.contains($0.id) }
        state.favorites[user.id] = nil
        state.claims.removeAll { $0.requestedBy == user.id }
        state.memberships.removeAll { $0.userID == user.id }
        state.flags.removeAll { $0.userID == user.id }
        state.challenges.removeAll { $0.userID == user.id }
        state.verifications.removeAll { $0.userID == user.id }
        state.users.removeAll { $0.id == user.id }
        state.currentUserID = nil
        save()
        try await ensureSession()
    }

    func updateDisplayName(_ name: String) async throws {
        var user = try requireRegistered()
        let trimmed = DisplayNamePolicy.clean(name)
        guard (2...40).contains(trimmed.count) else { throw BackendError.invalidInput("invalid_display_name") }
        if !isAdmin(user), DisplayNamePolicy.isReserved(trimmed) { throw BackendError.invalidInput("reserved_display_name") }
        user.displayName = trimmed
        replaceUser(user)
        save()
    }

    func updateAvatar(_ photo: PhotoUpload?) async throws {
        var user = try requireRegistered()
        let previous = user.avatarPath
        if let photo {
            let path = "avatars/\(UUID().uuidString.lowercased()).\(photo.fileExtension)"
            try writeMedia(photo.data, path: path)
            user.avatarPath = path
        } else {
            user.avatarPath = nil
        }
        replaceUser(user)
        save()
        if let previous, let mediaDirectory {
            try? FileManager.default.removeItem(at: mediaDirectory.appendingPathComponent(previous))
        }
    }

    func signOut() async throws {
        state.currentUserID = nil
        save()
        try await ensureSession()
    }

    private func replaceUser(_ user: User) {
        if let index = state.users.firstIndex(where: { $0.id == user.id }) { state.users[index] = user }
    }

    // MARK: VenueRemote

    private func ratingSummary(venueID: UUID) -> RatingSummary {
        let ratings = currentPublishedRevisions(venueID: venueID).map(\.rating)
        guard !ratings.isEmpty else { return .empty }
        let average = Double(ratings.reduce(0, +)) / Double(ratings.count)
        return RatingSummary(reviewCount: ratings.count, average: (average * 100).rounded() / 100)
    }

    private func currentPublishedRevisions(venueID: UUID) -> [RevisionRow] {
        state.reviews.filter { $0.venueID == venueID && $0.status == .published }
            .compactMap { review in state.revisions.first { $0.id == review.currentRevisionID } }
    }

    private func tagCounts(venueID: UUID) -> [TagCount] {
        var counts: [String: Int] = [:]
        currentPublishedRevisions(venueID: venueID).flatMap(\.tags).forEach { counts[$0, default: 0] += 1 }
        return counts.map { TagCount(slug: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.slug < $1.slug }
    }

    private func summary(for venue: VenueRow, origin: GeoPoint?, query: String?) -> VenueSummary {
        let point = GeoPoint(latitude: venue.latitude, longitude: venue.longitude)
        let rating = ratingSummary(venueID: venue.id)
        let distance = origin.map { point.distance(to: $0) }
        let relevance = query.map { ranker.relevance(name: venue.name, query: $0) }
        return VenueSummary(
            id: venue.id, name: venue.name, category: venue.category, address: venue.address, coordinate: point,
            status: venue.status, rating: rating, topTags: Array(tagCounts(venueID: venue.id).prefix(3).map(\.slug)),
            coverPath: state.media.first { $0.venueID == venue.id && $0.status == "approved" }?.path
                ?? DemoSeed.photoURLs(for: venue.id).first,
            distanceMeters: distance, rankScore: ranker.score(rating: rating, distanceMeters: distance, relevance: relevance))
    }

    func searchVenues(_ query: VenueSearchQuery) async throws -> VenueSearchPage {
        let text = query.trimmedText.isEmpty ? nil : query.trimmedText
        var results = state.venues
            .filter { $0.status == .active || $0.status == .temporarilyClosed }
            .filter { query.category == nil || $0.category == query.category }
            .map { summary(for: $0, origin: query.origin, query: text) }
        if let text {
            results = results.filter { ranker.relevance(name: $0.name, query: text) >= 0.3 }
        } else if query.origin != nil {
            results = results.filter { ($0.distanceMeters ?? 0) <= query.radiusMeters }
        }
        if let minimum = query.filter.minimumRating.value {
            results = results.filter { ($0.rating.average ?? 0) >= minimum }
        }
        if query.filter.reviewedOnly {
            results = results.filter(\.rating.hasReviews)
        }
        if !query.filter.tags.isEmpty {
            guard query.filter.tags.count <= 5 else { throw BackendError.invalidInput("too_many_tags") }
            guard query.filter.tags.allSatisfy({ ReviewTag.named($0) != nil }) else { throw BackendError.invalidInput("unknown_tag") }
            results = results.filter { venue in
                let counts = Dictionary(uniqueKeysWithValues: tagCounts(venueID: venue.id).map { ($0.slug, $0.count) })
                return query.filter.tags.allSatisfy { (counts[$0] ?? 0) >= 1 }
            }
        }
        let sorted = ranker.sort(results, by: query.filter.sort)
        let page = Array(sorted.dropFirst(query.offset).prefix(query.limit))
        return VenueSearchPage(venues: page, hasMore: sorted.count > query.offset + page.count)
    }

    func venueCards(ids: [UUID], origin: GeoPoint?) async throws -> [VenueSummary] {
        state.venues.filter { ids.contains($0.id) && $0.status != .archived }.map { summary(for: $0, origin: origin, query: nil) }
    }

    func venueDetail(id: UUID) async throws -> VenueDetail {
        guard let venue = state.venues.first(where: { $0.id == id && $0.status != .archived }) else { throw BackendError.notFound }
        let user = try? currentUser()
        let distribution: [Int]? = {
            let ratings = currentPublishedRevisions(venueID: id).map(\.rating)
            guard !ratings.isEmpty else { return nil }
            return (1...5).map { star in ratings.filter { $0 == star }.count }
        }()
        let myReview: MyReview? = user.flatMap { user in
            guard let review = state.reviews.first(where: { $0.venueID == id && $0.userID == user.id }),
                  let revision = state.revisions.first(where: { $0.id == review.currentRevisionID }) else { return nil }
            return MyReview(reviewID: review.id, status: review.status, rating: revision.rating, purpose: revision.purpose,
                            body: revision.body, tags: revision.tags, revisionNumber: revision.number, updatedAt: revision.createdAt)
        }
        let managed = user.map { user in
            isRegistered(user) && venue.businessID.map { business in
                state.memberships.contains { $0.businessID == business && $0.userID == user.id }
            } == true
        } ?? false
        return VenueDetail(
            summary: summary(for: venue, origin: nil, query: nil), description: venue.description,
            websiteURL: venue.detailsSource == nil ? nil : venue.websiteURL.flatMap(URL.init(string:)),
            phoneNumber: venue.detailsSource == nil ? nil : venue.phoneNumber,
            detailsSource: venue.detailsSource,
            appleMapsID: state.providerRefs.first { $0.venueID == id && $0.provider == "apple_maps" }?.externalID,
            ratingDistribution: distribution,
            lastReviewAt: currentPublishedRevisions(venueID: id).map(\.createdAt).max(),
            tagCounts: tagCounts(venueID: id),
            photoPaths: state.media.filter { $0.venueID == id && $0.status == "approved" }.map(\.path) + DemoSeed.photoURLs(for: id),
            isFavorite: user.map { state.favorites[$0.id]?.contains(id) == true } ?? false,
            isManagedByMe: managed, myReview: myReview,
            panoramaPath: DemoSeed.panoramaURL(for: id))
    }

    func matchProviderRefs(provider: String, externalIDs: [String]) async throws -> [String: UUID] {
        var result: [String: UUID] = [:]
        for ref in state.providerRefs where ref.provider == provider && externalIDs.contains(ref.externalID) {
            result[ref.externalID] = ref.venueID
        }
        return result
    }

    func reviews(venueID: UUID, sort: ReviewSort, limit: Int, offset: Int) async throws -> ReviewPage {
        let me = try? currentUser()
        let now = clock()
        let rows: [(ReviewRow, RevisionRow)] = state.reviews
            .filter { $0.venueID == venueID && $0.status == .published }
            .compactMap { review in state.revisions.first { $0.id == review.currentRevisionID }.map { (review, $0) } }
        let sorted = rows.sorted { lhs, rhs in
            switch sort {
            case .recent:
                return lhs.1.createdAt > rhs.1.createdAt
            case .relevant:
                func score(_ revision: RevisionRow) -> Double {
                    (revision.body == nil ? 0 : 2) + Double(revision.tags.count) * 0.25 - now.timeIntervalSince(revision.createdAt) / (86_400 * 60)
                }
                return score(lhs.1) > score(rhs.1)
            }
        }
        let page = sorted.dropFirst(offset).prefix(limit).map { review, revision in
            PublishedReview(
                id: review.id,
                authorName: state.users.first { $0.id == review.userID }?.displayName ?? "Nanglen user",
                rating: revision.rating, purpose: revision.purpose, body: revision.body, tags: revision.tags.sorted(),
                photoPaths: state.media.filter { $0.kind == "review" && $0.parentID == revision.id && $0.status == "approved" }.map(\.path),
                revisionNumber: revision.number, updatedAt: revision.createdAt, isMine: review.userID == me?.id,
                isVerifiedVisit: revision.verificationID != nil)
        }
        return ReviewPage(reviews: Array(page), hasMore: sorted.count > offset + page.count)
    }

    func signedMediaURLs(paths: [String], bucket: MediaBucket) async throws -> [String: URL] {
        var result: [String: URL] = [:]
        // Demo seed media is already a public https URL (see `DemoSeed.photos`).
        for path in paths where path.hasPrefix("https://") {
            result[path] = URL(string: path)
        }
        guard let mediaDirectory else { return result }
        for path in paths where !path.hasPrefix("https://") {
            let url = mediaDirectory.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) { result[path] = url }
        }
        return result
    }

    func logEvent(_ name: String, venueID: UUID?) async {}

    // MARK: FavoriteRemote

    func favoriteVenueIDs() async throws -> [UUID] {
        let user = try currentUser()
        return state.favorites[user.id] ?? []
    }

    func setFavorite(venueID: UUID, isFavorite: Bool) async throws {
        let user = try currentUser()
        guard state.venues.contains(where: { $0.id == venueID && $0.status != .archived }) else { throw BackendError.notFound }
        var list = state.favorites[user.id] ?? []
        list.removeAll { $0 == venueID }
        if isFavorite { list.insert(venueID, at: 0) }
        state.favorites[user.id] = list
        save()
    }

    // MARK: ReviewRemote

    func verificationPolicy() async throws -> VerificationPolicy { policy }

    func issueVisitChallenge(venueID: UUID) async throws -> VisitChallenge {
        let user = try requireRegistered()
        guard let venue = state.venues.first(where: { $0.id == venueID }), venue.status.acceptsReviews else {
            throw BackendError.venueNotReviewable
        }
        let now = clock()
        let recent = state.challenges.filter { $0.userID == user.id && now.timeIntervalSince($0.issuedAt) < 600 }.count
        guard recent < 10 else { throw BackendError.rateLimited }
        let challenge = Challenge(id: UUID(), userID: user.id, venueID: venueID, issuedAt: now,
                                  expiresAt: now.addingTimeInterval(challengeTTL), consumedAt: nil)
        state.challenges.append(challenge)
        save()
        return VisitChallenge(id: challenge.id, venueID: venueID, issuedAt: now, expiresAt: challenge.expiresAt, policy: policy)
    }

    func verifyVisit(challengeID: UUID, reading: LocationReading) async throws -> VisitVerificationResult {
        let user = try requireRegistered()
        guard let index = state.challenges.firstIndex(where: { $0.id == challengeID && $0.userID == user.id }) else {
            throw BackendError.notFound
        }
        let now = clock()
        let challenge = state.challenges[index]
        if challenge.consumedAt != nil { throw BackendError.challengeConsumed }
        if challenge.expiresAt <= now { throw BackendError.challengeExpired }
        state.challenges[index].consumedAt = now

        let skew: TimeInterval = 5
        let venue = state.venues.first { $0.id == challenge.venueID }
        let status: VisitVerificationStatus
        var distance: Double?
        if let venue, venue.status.acceptsReviews {
            let venuePoint = GeoPoint(latitude: venue.latitude, longitude: venue.longitude)
            if !reading.point.isValid || reading.horizontalAccuracy < 0 || reading.timestamp > now.addingTimeInterval(skew) {
                status = .invalid
            } else if reading.timestamp < challenge.issuedAt.addingTimeInterval(-skew)
                        || now.timeIntervalSince(reading.timestamp) > policy.maxLocationAge {
                status = .stale
            } else if reading.horizontalAccuracy > policy.maxHorizontalAccuracy {
                status = .inaccurate
            } else {
                let meters = reading.point.distance(to: venuePoint)
                distance = meters
                status = meters <= policy.radiusMeters ? .verified : .tooFar
            }
        } else {
            status = .invalid
        }
        // Store only a coarse bucket — never the raw coordinate.
        let verification = Verification(id: UUID(), challengeID: challenge.id, userID: user.id, venueID: challenge.venueID,
                                         status: status, distanceBucket: Self.distanceBucket(distance),
                                         expiresAt: now.addingTimeInterval(verificationTTL), consumedAt: nil)
        state.verifications.append(verification)
        save()
        return VisitVerificationResult(status: status, verificationID: status == .verified ? verification.id : nil,
                                       expiresAt: status == .verified ? verification.expiresAt : nil,
                                       distanceBucket: verification.distanceBucket)
    }

    func submitReview(_ submission: ReviewSubmission) async throws -> ReviewSubmissionResult {
        let user = try requireRegistered()
        if let existing = state.revisions.first(where: { $0.userID == user.id && $0.idempotencyKey == submission.idempotencyKey }),
           let review = state.reviews.first(where: { $0.id == existing.reviewID }) {
            guard review.venueID == submission.venueID else { throw BackendError.invalidInput("idempotency_conflict") }
            return ReviewSubmissionResult(reviewID: review.id, revisionID: existing.id, revisionNumber: existing.number,
                                          status: review.status, replayed: true)
        }
        try ReviewValidator.validate(rating: submission.rating, tags: submission.tags, body: submission.body ?? "",
                                     maxTags: 3, maxBody: 500)
        guard submission.tags.allSatisfy({ ReviewTag.named($0) != nil }) else { throw BackendError.invalidInput("unknown_tag") }

        let now = clock()
        guard let vIndex = state.verifications.firstIndex(where: { $0.id == submission.verificationID }) else {
            throw BackendError.verificationInvalid
        }
        let verification = state.verifications[vIndex]
        guard verification.userID == user.id, verification.venueID == submission.venueID, verification.status == .verified else {
            throw BackendError.verificationInvalid
        }
        if verification.consumedAt != nil { throw BackendError.verificationConsumed }
        if verification.expiresAt <= now { throw BackendError.verificationExpired }
        guard state.venues.first(where: { $0.id == submission.venueID })?.status.acceptsReviews == true else {
            throw BackendError.venueNotReviewable
        }

        var reviewIndex = state.reviews.firstIndex { $0.venueID == submission.venueID && $0.userID == user.id }
        if reviewIndex == nil {
            state.reviews.append(ReviewRow(id: UUID(), venueID: submission.venueID, userID: user.id, currentRevisionID: nil, status: .published))
            reviewIndex = state.reviews.count - 1
        }
        guard let reviewIndex else { throw BackendError.server("review_upsert_failed") }
        if state.reviews[reviewIndex].status == .removed { throw BackendError.reviewRemoved }
        let reviewID = state.reviews[reviewIndex].id
        let number = (state.revisions.filter { $0.reviewID == reviewID }.map(\.number).max() ?? 0) + 1
        let body = submission.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        let revision = RevisionRow(id: UUID(), reviewID: reviewID, userID: user.id, number: number,
                                   verificationID: verification.id, rating: submission.rating, purpose: submission.purpose,
                                   body: (body?.isEmpty ?? true) ? nil : body, tags: Array(Set(submission.tags)).sorted(),
                                   idempotencyKey: submission.idempotencyKey, createdAt: now)
        state.revisions.append(revision)
        state.reviews[reviewIndex].currentRevisionID = revision.id
        state.verifications[vIndex].consumedAt = now
        save()
        return ReviewSubmissionResult(reviewID: reviewID, revisionID: revision.id, revisionNumber: number,
                                      status: state.reviews[reviewIndex].status, replayed: false)
    }

    func uploadReviewPhoto(revisionID: UUID, photo: PhotoUpload) async throws {
        let user = try requireRegistered()
        guard state.revisions.contains(where: { $0.id == revisionID && $0.userID == user.id }) else { throw BackendError.notFound }
        guard photo.data.count <= 5 * 1_024 * 1_024 else { throw BackendError.invalidInput("file_too_large") }
        guard state.media.filter({ $0.parentID == revisionID }).count < 3 else { throw BackendError.invalidInput("too_many_photos") }
        let path = "\(revisionID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(photo.fileExtension)"
        try writeMedia(photo.data, path: path)
        state.media.append(MediaRow(path: path, kind: "review", parentID: revisionID, ownerID: user.id, status: "pending", venueID: nil))
        save()
    }

    func flagReview(id: UUID, reason: FlagReason, note: String?) async throws {
        let user = try requireRegistered()
        guard let review = state.reviews.first(where: { $0.id == id && $0.status == .published }) else { throw BackendError.notFound }
        guard review.userID != user.id else { throw BackendError.invalidInput("cannot_flag_own_review") }
        guard !state.flags.contains(where: { $0.reviewID == id && $0.userID == user.id }) else { return }
        state.flags.append(Flag(reviewID: id, userID: user.id, reason: reason.rawValue, open: true, createdAt: clock()))
        save()
    }

    private func writeMedia(_ data: Data, path: String) throws {
        guard let mediaDirectory else { return }
        let url = mediaDirectory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    // MARK: SubmissionRemote

    func createSubmission(_ draft: VenueSubmissionDraft) async throws -> SubmissionReceipt {
        let user = try requireRegistered()
        if let existing = state.submissions.first(where: { $0.submittedBy == user.id && $0.clientRequestID == draft.clientRequestID }) {
            return .submitted(submissionID: existing.id, status: existing.status, duplicates: duplicates(for: existing.draft))
        }
        try SubmissionValidator.validate(draft)
        if let external = draft.externalPlaceID, let provider = draft.provider,
           let ref = state.providerRefs.first(where: { $0.provider == provider && $0.externalID == external }) {
            return .alreadyListed(venueID: ref.venueID)
        }
        guard state.submissions.filter({ $0.submittedBy == user.id && $0.status.canWithdraw }).count < 10 else {
            throw BackendError.rateLimited
        }
        let now = clock()
        let row = SubmissionRow(id: UUID(), submittedBy: user.id, clientRequestID: draft.clientRequestID, draft: draft,
                                status: .pendingReview, revision: 1, decisionReason: nil, duplicateOf: nil,
                                approvedVenueID: nil, submittedAt: now, updatedAt: now)
        state.submissions.append(row)
        save()
        return .submitted(submissionID: row.id, status: row.status, duplicates: duplicates(for: draft))
    }

    private func duplicates(for draft: VenueSubmissionDraft) -> [DuplicateCandidate] {
        guard let coordinate = draft.coordinate else { return [] }
        return state.venues.filter { $0.status != .archived }.compactMap { venue in
            let distance = GeoPoint(latitude: venue.latitude, longitude: venue.longitude).distance(to: coordinate)
            let providerMatch = draft.externalPlaceID != nil && state.providerRefs.contains {
                $0.venueID == venue.id && $0.provider == draft.provider && $0.externalID == draft.externalPlaceID
            }
            guard distance <= 150 || providerMatch else { return nil }
            return DuplicateCandidate(venueID: venue.id, name: venue.name, address: venue.address, distanceMeters: distance,
                                      nameSimilarity: ranker.relevance(name: venue.name, query: draft.name), providerMatch: providerMatch)
        }
        .sorted { $0.nameSimilarity > $1.nameSimilarity }
        .prefix(5).map { $0 }
    }

    func resubmit(id: UUID, draft: VenueSubmissionDraft) async throws {
        let user = try requireRegistered()
        guard let index = state.submissions.firstIndex(where: { $0.id == id && $0.submittedBy == user.id }) else {
            throw BackendError.notFound
        }
        guard state.submissions[index].status == .needsChanges else { throw BackendError.invalidStatusTransition }
        try SubmissionValidator.validate(draft)
        var updated = draft
        updated.clientRequestID = state.submissions[index].clientRequestID
        state.submissions[index].draft = updated
        state.submissions[index].status = .pendingReview
        state.submissions[index].revision += 1
        state.submissions[index].decisionReason = nil
        state.submissions[index].submittedAt = clock()
        state.submissions[index].updatedAt = clock()
        save()
    }

    func withdrawSubmission(id: UUID) async throws {
        let user = try currentUser()
        guard let index = state.submissions.firstIndex(where: { $0.id == id && $0.submittedBy == user.id }),
              state.submissions[index].status.canWithdraw else { throw BackendError.invalidStatusTransition }
        state.submissions[index].status = .withdrawn
        state.submissions[index].updatedAt = clock()
        save()
    }

    func uploadSubmissionPhoto(submissionID: UUID, photo: PhotoUpload) async throws {
        let user = try requireRegistered()
        guard state.submissions.contains(where: { $0.id == submissionID && $0.submittedBy == user.id && $0.status.canWithdraw }) else {
            throw BackendError.notFound
        }
        guard photo.data.count <= 5 * 1_024 * 1_024 else { throw BackendError.invalidInput("file_too_large") }
        guard state.media.filter({ $0.parentID == submissionID }).count < 5 else { throw BackendError.invalidInput("too_many_photos") }
        let path = "\(submissionID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(photo.fileExtension)"
        try writeMedia(photo.data, path: path)
        state.media.append(MediaRow(path: path, kind: "submission", parentID: submissionID, ownerID: user.id, status: "pending", venueID: nil))
        save()
    }

    func mySubmissions() async throws -> [VenueSubmission] {
        let user = try currentUser()
        return state.submissions.filter { $0.submittedBy == user.id }.sorted { $0.updatedAt > $1.updatedAt }.map(Self.model)
    }

    private static func model(_ row: SubmissionRow) -> VenueSubmission {
        VenueSubmission(
            id: row.id, name: row.draft.name, category: row.draft.category ?? .other,
            address: row.draft.address.isEmpty ? nil : row.draft.address,
            coordinate: row.draft.coordinate ?? GeoPoint(latitude: 0, longitude: 0),
            description: row.draft.description.isEmpty ? nil : row.draft.description,
            websiteURL: row.draft.websiteURL.isEmpty ? nil : row.draft.websiteURL,
            phoneNumber: row.draft.phoneNumber.isEmpty ? nil : row.draft.phoneNumber,
            note: row.draft.note.isEmpty ? nil : row.draft.note,
            status: row.status, revision: row.revision, decisionReason: row.decisionReason,
            duplicateOfVenueID: row.duplicateOf, approvedVenueID: row.approvedVenueID,
            submittedAt: row.submittedAt, updatedAt: row.updatedAt)
    }

    // MARK: BusinessRemote

    func requestClaim(_ draft: VenueClaimDraft) async throws -> ClaimStatus {
        let user = try requireRegistered()
        if let existing = state.claims.first(where: { $0.requestedBy == user.id && $0.clientRequestID == draft.clientRequestID }) {
            return existing.status
        }
        guard state.venues.contains(where: { $0.id == draft.venueID }) else { throw BackendError.notFound }
        let name = draft.businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...120).contains(name.count) else { throw BackendError.invalidInput("name_required") }
        guard !state.claims.contains(where: { $0.venueID == draft.venueID && $0.requestedBy == user.id && $0.status == .pendingReview }) else {
            throw BackendError.invalidInput("claim_already_pending")
        }
        state.claims.append(ClaimRow(id: UUID(), clientRequestID: draft.clientRequestID, venueID: draft.venueID, requestedBy: user.id,
                                     businessName: name, role: draft.role.rawValue,
                                     contactNote: draft.contactNote.isEmpty ? nil : draft.contactNote,
                                     evidenceNote: draft.evidenceNote.isEmpty ? nil : draft.evidenceNote,
                                     status: .pendingReview, decisionReason: nil, createdAt: clock()))
        save()
        return .pendingReview
    }

    func myClaims() async throws -> [VenueClaim] {
        let user = try currentUser()
        return state.claims.filter { $0.requestedBy == user.id }.sorted { $0.createdAt > $1.createdAt }.map { claim in
            VenueClaim(id: claim.id, venueID: claim.venueID, venueName: state.venues.first { $0.id == claim.venueID }?.name,
                       businessName: claim.businessName, role: ClaimantRole(rawValue: claim.role) ?? .owner,
                       status: claim.status, decisionReason: claim.decisionReason, createdAt: claim.createdAt)
        }
    }

    // MARK: AdminRemote

    func adminSubmissions(status: SubmissionStatus) async throws -> [AdminSubmissionRow] {
        _ = try requireAdmin()
        return state.submissions.filter { $0.status == status }.sorted { $0.submittedAt < $1.submittedAt }.map { row in
            AdminSubmissionRow(
                id: row.id, name: row.draft.name, category: row.draft.category ?? .other,
                address: row.draft.address.isEmpty ? nil : row.draft.address,
                coordinate: row.draft.coordinate ?? GeoPoint(latitude: 0, longitude: 0), status: row.status,
                revision: row.revision, submittedAt: row.submittedAt,
                submitterName: state.users.first { $0.id == row.submittedBy }?.displayName ?? "-",
                mediaCount: state.media.filter { $0.parentID == row.id }.count,
                duplicateCandidateCount: duplicates(for: row.draft).count)
        }
    }

    func adminSubmissionDetail(id: UUID) async throws -> AdminSubmissionDetail {
        _ = try requireAdmin()
        guard let row = state.submissions.first(where: { $0.id == id }) else { throw BackendError.notFound }
        let mine = state.submissions.filter { $0.submittedBy == row.submittedBy }
        return AdminSubmissionDetail(
            submission: Self.model(row), provider: row.draft.provider, externalPlaceID: row.draft.externalPlaceID,
            submitterName: state.users.first { $0.id == row.submittedBy }?.displayName ?? "-",
            submitterTotal: mine.count, submitterApproved: mine.filter { $0.status == .approved }.count,
            mediaPaths: state.media.filter { $0.parentID == row.id }.map(\.path),
            duplicates: duplicates(for: row.draft),
            history: state.audit.filter { $0.targetID == row.id }.sorted { $0.createdAt > $1.createdAt }
                .map { ModerationHistoryItem(action: $0.action, reason: $0.reason, createdAt: $0.createdAt) })
    }

    func adminDecide(submissionID: UUID, decision: AdminSubmissionDecision) async throws {
        let admin = try requireAdmin()
        guard let index = state.submissions.firstIndex(where: { $0.id == submissionID }) else { throw BackendError.notFound }
        guard state.submissions[index].status == .pendingReview else { throw BackendError.invalidStatusTransition }
        let row = state.submissions[index]
        let now = clock()
        switch decision {
        case .approve(let note, let force):
            if let ext = row.draft.externalPlaceID, let provider = row.draft.provider,
               state.providerRefs.contains(where: { $0.provider == provider && $0.externalID == ext }) {
                throw BackendError.providerRefExists
            }
            let likely = duplicates(for: row.draft).filter { $0.nameSimilarity >= 0.6 && $0.distanceMeters <= 50 }
            if !likely.isEmpty && !force { throw BackendError.likelyDuplicate }
            guard let coordinate = row.draft.coordinate, let category = row.draft.category else { throw BackendError.invalidInput("invalid_coordinate") }
            let hasDetails = !row.draft.websiteURL.isEmpty || !row.draft.phoneNumber.isEmpty
            let venue = VenueRow(id: UUID(), name: row.draft.name, description: row.draft.description.isEmpty ? nil : row.draft.description,
                                 category: category, address: row.draft.address.isEmpty ? nil : row.draft.address,
                                 latitude: coordinate.latitude, longitude: coordinate.longitude,
                                 websiteURL: row.draft.websiteURL.isEmpty ? nil : row.draft.websiteURL,
                                 phoneNumber: row.draft.phoneNumber.isEmpty ? nil : row.draft.phoneNumber,
                                 detailsSource: hasDetails ? "community_submission" : nil, status: .active, businessID: nil, createdAt: now)
            state.venues.append(venue)
            if let ext = row.draft.externalPlaceID, let provider = row.draft.provider {
                state.providerRefs.append(ProviderRef(venueID: venue.id, provider: provider, externalID: ext))
            }
            for mediaIndex in state.media.indices where state.media[mediaIndex].parentID == row.id {
                state.media[mediaIndex].status = "approved"
                state.media[mediaIndex].venueID = venue.id
            }
            state.submissions[index].status = .approved
            state.submissions[index].approvedVenueID = venue.id
            state.submissions[index].decisionReason = note
            audit(admin, "submission_approved", row.id, note)
        case .reject(let reason), .requestChanges(let reason), .markDuplicate(_, let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw BackendError.invalidInput("reason_required") }
            switch decision {
            case .reject:
                state.submissions[index].status = .rejected
                audit(admin, "submission_rejected", row.id, trimmed)
            case .requestChanges:
                state.submissions[index].status = .needsChanges
                audit(admin, "submission_needs_changes", row.id, trimmed)
            case .markDuplicate(let venueID, _):
                guard state.venues.contains(where: { $0.id == venueID }) else { throw BackendError.notFound }
                state.submissions[index].status = .duplicate
                state.submissions[index].duplicateOf = venueID
                audit(admin, "submission_duplicate", row.id, trimmed)
            case .approve:
                break
            }
            state.submissions[index].decisionReason = trimmed
        }
        state.submissions[index].updatedAt = now
        save()
    }

    func adminPendingClaims() async throws -> [AdminClaimRow] {
        _ = try requireAdmin()
        return state.claims.filter { $0.status == .pendingReview }.map { claim in
            AdminClaimRow(id: claim.id, venueID: claim.venueID, venueName: state.venues.first { $0.id == claim.venueID }?.name ?? "-",
                          businessName: claim.businessName, role: ClaimantRole(rawValue: claim.role) ?? .owner,
                          claimantName: state.users.first { $0.id == claim.requestedBy }?.displayName ?? "-",
                          contactNote: claim.contactNote, evidenceNote: claim.evidenceNote, createdAt: claim.createdAt)
        }
    }

    func adminDecideClaim(id: UUID, approve: Bool, reason: String?) async throws {
        let admin = try requireAdmin()
        guard let index = state.claims.firstIndex(where: { $0.id == id }) else { throw BackendError.notFound }
        guard state.claims[index].status == .pendingReview else { throw BackendError.invalidStatusTransition }
        let claim = state.claims[index]
        if !approve {
            guard let reason, !reason.trimmingCharacters(in: .whitespaces).isEmpty else { throw BackendError.invalidInput("reason_required") }
            state.claims[index].status = .rejected
            state.claims[index].decisionReason = reason
            audit(admin, "claim_rejected", id, reason)
        } else {
            guard let venueIndex = state.venues.firstIndex(where: { $0.id == claim.venueID }) else { throw BackendError.notFound }
            let businessID = state.venues[venueIndex].businessID ?? UUID()
            state.venues[venueIndex].businessID = businessID
            state.memberships.removeAll { $0.businessID == businessID && $0.userID == claim.requestedBy }
            state.memberships.append(Membership(businessID: businessID, businessName: claim.businessName, userID: claim.requestedBy, role: claim.role))
            state.claims[index].status = .approved
            state.claims[index].decisionReason = reason
            audit(admin, "claim_approved", id, reason)
        }
        save()
    }

    func adminFlaggedReviews() async throws -> [AdminFlaggedReview] {
        _ = try requireAdmin()
        let grouped = Dictionary(grouping: state.flags.filter(\.open), by: \.reviewID)
        return grouped.compactMap { reviewID, flags in
            guard let review = state.reviews.first(where: { $0.id == reviewID }),
                  let revision = state.revisions.first(where: { $0.id == review.currentRevisionID }) else { return nil }
            return AdminFlaggedReview(id: reviewID, venueName: state.venues.first { $0.id == review.venueID }?.name ?? "-",
                                      authorName: state.users.first { $0.id == review.userID }?.displayName ?? "-",
                                      rating: revision.rating, body: revision.body, status: review.status,
                                      openFlags: flags.count, reasons: Array(Set(flags.map(\.reason))).sorted())
        }
        .sorted { $0.openFlags > $1.openFlags }
    }

    func adminModerateReview(id: UUID, status: ReviewStatus, reason: String) async throws {
        let admin = try requireAdmin()
        guard !reason.trimmingCharacters(in: .whitespaces).isEmpty else { throw BackendError.invalidInput("reason_required") }
        guard let index = state.reviews.firstIndex(where: { $0.id == id }) else { throw BackendError.notFound }
        guard state.reviews[index].status != .removed else { throw BackendError.invalidStatusTransition }
        state.reviews[index].status = status
        for flagIndex in state.flags.indices where state.flags[flagIndex].reviewID == id { state.flags[flagIndex].open = false }
        audit(admin, "review_\(status.rawValue)", id, reason)
        save()
    }

    // MARK: Test / diagnostics hooks

    /// Number of append-only audit events (tests).
    var auditCount: Int { state.audit.count }

    /// Test hook: resume the session of an existing demo user by email (simulates signing in on a
    /// device where that user's session is stored). Returns false when no such user exists.
    @discardableResult
    func resumeSessionForTesting(email: String) -> Bool {
        guard let user = state.users.first(where: { $0.email == email }) else { return false }
        state.currentUserID = user.id
        return true
    }

    static func distanceBucket(_ meters: Double?) -> String {
        guard let meters else { return "unknown" }
        switch meters {
        case ...25: return "0-25"
        case ...50: return "25-50"
        case ...100: return "50-100"
        case ...250: return "100-250"
        default: return "250+"
        }
    }
}
