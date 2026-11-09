import Foundation

/// Server-derived capabilities. The app never infers privileges from local flags:
/// this value is always fetched from the backend (`get_my_capabilities`) and every
/// sensitive action is re-checked server-side.
nonisolated struct UserCapabilities: Hashable, Sendable {
    var userID: UUID
    var isAnonymous: Bool
    var isRegistered: Bool
    var isAdmin: Bool
    var displayName: String
    var favoritesCount: Int
    var reviewsCount: Int
    var openSubmissionsCount: Int
    var memberships: [BusinessMembership]

    var isGuest: Bool { !isRegistered }
    var isBusinessOwner: Bool { !memberships.isEmpty }
}

nonisolated struct BusinessMembership: Hashable, Sendable {
    var businessID: UUID
    var businessName: String
    var role: String
    var venueIDs: [UUID]
}

/// Which backend implementation is wired in. Demo is never presented as a real cloud backend.
nonisolated enum BackendMode: Hashable, Sendable {
    case supabase(host: String)
    case demo
}

// MARK: - Venue submissions

nonisolated enum SubmissionStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case draft
    case pendingReview = "pending_review"
    case needsChanges = "needs_changes"
    case approved
    case rejected
    case duplicate
    case withdrawn

    var canWithdraw: Bool { self == .pendingReview || self == .needsChanges }
    var canResubmit: Bool { self == .needsChanges }
}

nonisolated struct VenueSubmissionDraft: Hashable, Sendable, Codable {
    var clientRequestID = UUID()
    var name: String = ""
    var category: VenueCategory?
    var address: String = ""
    var coordinate: GeoPoint?
    var provider: String?
    var externalPlaceID: String?
    var description: String = ""
    var websiteURL: String = ""
    var phoneNumber: String = ""
    var note: String = ""
}

nonisolated struct VenueSubmission: Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var category: VenueCategory
    var address: String?
    var coordinate: GeoPoint
    var description: String?
    var websiteURL: String?
    var phoneNumber: String?
    var note: String?
    var status: SubmissionStatus
    var revision: Int
    var decisionReason: String?
    var duplicateOfVenueID: UUID?
    var approvedVenueID: UUID?
    var submittedAt: Date?
    var updatedAt: Date
}

nonisolated struct DuplicateCandidate: Hashable, Sendable {
    var venueID: UUID
    var name: String
    var address: String?
    var distanceMeters: Double
    var nameSimilarity: Double
    var providerMatch: Bool
}

nonisolated enum SubmissionReceipt: Hashable, Sendable {
    case submitted(submissionID: UUID, status: SubmissionStatus, duplicates: [DuplicateCandidate])
    /// Exact provider match: the place already exists on Nanglen.
    case alreadyListed(venueID: UUID)
}

// MARK: - Business claims

nonisolated enum ClaimStatus: String, Codable, Hashable, Sendable {
    case pendingReview = "pending_review"
    case approved
    case rejected
    case withdrawn
}

nonisolated enum ClaimantRole: String, CaseIterable, Hashable, Sendable {
    case owner, manager, editor
}

nonisolated struct VenueClaimDraft: Hashable, Sendable {
    var clientRequestID = UUID()
    var venueID: UUID
    var businessName: String = ""
    var role: ClaimantRole = .owner
    var contactNote: String = ""
    var evidenceNote: String = ""
}

nonisolated struct VenueClaim: Identifiable, Hashable, Sendable {
    var id: UUID
    var venueID: UUID
    var venueName: String?
    var businessName: String
    var role: ClaimantRole
    var status: ClaimStatus
    var decisionReason: String?
    var createdAt: Date
}

// MARK: - Admin

nonisolated struct AdminSubmissionRow: Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var category: VenueCategory
    var address: String?
    var coordinate: GeoPoint
    var status: SubmissionStatus
    var revision: Int
    var submittedAt: Date?
    var submitterName: String
    var mediaCount: Int
    var duplicateCandidateCount: Int
}

nonisolated struct AdminSubmissionDetail: Hashable, Sendable {
    var submission: VenueSubmission
    var provider: String?
    var externalPlaceID: String?
    var submitterName: String
    var submitterTotal: Int
    var submitterApproved: Int
    var mediaPaths: [String]
    var duplicates: [DuplicateCandidate]
    var history: [ModerationHistoryItem]
}

nonisolated struct ModerationHistoryItem: Hashable, Sendable {
    var action: String
    var reason: String?
    var createdAt: Date
}

nonisolated struct AdminClaimRow: Identifiable, Hashable, Sendable {
    var id: UUID
    var venueID: UUID
    var venueName: String
    var businessName: String
    var role: ClaimantRole
    var claimantName: String
    var contactNote: String?
    var evidenceNote: String?
    var createdAt: Date
}

nonisolated struct AdminFlaggedReview: Identifiable, Hashable, Sendable {
    var id: UUID
    var venueName: String
    var authorName: String
    var rating: Int
    var body: String?
    var status: ReviewStatus
    var openFlags: Int
    var reasons: [String]
}

nonisolated enum AdminSubmissionDecision: Hashable, Sendable {
    case approve(note: String?, force: Bool)
    case reject(reason: String)
    case requestChanges(reason: String)
    case markDuplicate(venueID: UUID, reason: String)
}
