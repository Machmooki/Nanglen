import Foundation

/// Typed errors mapped from backend error messages (`raise exception '<code>'` in SQL).
nonisolated enum BackendError: Error, Hashable, Sendable {
    case notConfigured
    case notAuthenticated
    case registrationRequired
    case adminRequired
    case rateLimited
    case notFound
    case venueNotReviewable
    case challengeExpired
    case challengeConsumed
    case verificationInvalid
    case verificationConsumed
    case verificationExpired
    case invalidInput(String)
    case invalidStatusTransition
    case likelyDuplicate
    case providerRefExists
    case reviewRemoved
    /// The email already belongs to another account (offer an explicit sign-in; never merge).
    case accountExists
    /// Active Admins must be revoked before their account can be deleted.
    case deletionBlocked
    case invalidOTP
    /// The auth server couldn't send the code email (SMTP rejected the login, provider down, ...).
    case emailNotSent
    case network
    case server(String)

    /// Maps the machine-readable message raised by the database functions.
    static func fromServerMessage(_ message: String) -> BackendError {
        let code = message.trimmingCharacters(in: .whitespacesAndNewlines)
        switch code {
        case "not_authenticated": return .notAuthenticated
        case "registration_required": return .registrationRequired
        case "admin_required": return .adminRequired
        case "rate_limited", "too_many_open_submissions": return .rateLimited
        case "venue_not_found", "submission_not_found", "claim_not_found", "review_not_found",
             "challenge_not_found", "revision_not_found", "media_not_found":
            return .notFound
        case "venue_not_reviewable": return .venueNotReviewable
        case "challenge_expired": return .challengeExpired
        case "challenge_consumed": return .challengeConsumed
        case "verification_invalid": return .verificationInvalid
        case "verification_consumed": return .verificationConsumed
        case "verification_expired": return .verificationExpired
        case "invalid_status_transition": return .invalidStatusTransition
        case "likely_duplicate": return .likelyDuplicate
        case "provider_ref_exists": return .providerRefExists
        case "review_removed": return .reviewRemoved
        case "invalid_rating", "body_too_long", "too_many_tags", "unknown_tag", "name_required",
             "invalid_coordinate", "invalid_website_url", "reason_required", "file_too_large",
             "too_many_photos", "invalid_storage_path", "invalid_display_name", "idempotency_conflict",
             "claim_already_pending", "already_manager", "cannot_flag_own_review", "reserved_display_name",
             "invalid_sort":
            return .invalidInput(code)
        default: return .server(code)
        }
    }

    /// The flow must restart from a fresh location verification.
    var requiresFreshVerification: Bool {
        switch self {
        case .challengeExpired, .challengeConsumed, .verificationConsumed, .verificationExpired, .verificationInvalid: true
        default: false
        }
    }
}

/// Private Storage buckets. Reads always go through short-lived signed URLs.
nonisolated enum MediaBucket: String, Sendable {
    /// Submission photos; approved ones double as public venue photos.
    case venue = "venue-submission-media"
    case review = "review-media"
    /// Profile photos ('<uuid>.<ext>' at the bucket root).
    case avatar = "avatars"
}

// MARK: - Remote data source contracts
//
// One contract, two implementations: `SupabaseBackend` (production) and `DemoBackend`
// (in-process, labelled "Demo", used when Supabase is not configured and in tests).
// Repositories and services depend on these protocols; view controllers never do.

protocol AuthRemote: AnyObject {
    var mode: BackendMode { get }
    /// Restores the persisted session or signs in anonymously (Guest).
    func ensureSession() async throws
    func capabilities() async throws -> UserCapabilities
    /// Sends a 6-digit code to link a verified email to the *current* user (keeps the same user id).
    func requestEmailLink(email: String) async throws
    func confirmEmailLink(email: String, code: String) async throws
    /// Returning user on a new device: sends a sign-in code for an existing account.
    func requestEmailSignIn(email: String) async throws
    func confirmEmailSignIn(email: String, code: String) async throws
    /// Deletes the caller's account and personal uploads, then starts a fresh Guest session.
    func deleteAccount() async throws
    func updateDisplayName(_ name: String) async throws
    /// Sets (or with `nil`, removes) the caller's profile photo. Registered users only.
    func updateAvatar(_ photo: PhotoUpload?) async throws
    func signOut() async throws
}

protocol VenueRemote: AnyObject {
    func searchVenues(_ query: VenueSearchQuery) async throws -> VenueSearchPage
    func venueCards(ids: [UUID], origin: GeoPoint?) async throws -> [VenueSummary]
    func venueDetail(id: UUID) async throws -> VenueDetail
    func matchProviderRefs(provider: String, externalIDs: [String]) async throws -> [String: UUID]
    func reviews(venueID: UUID, sort: ReviewSort, limit: Int, offset: Int) async throws -> ReviewPage
    func signedMediaURLs(paths: [String], bucket: MediaBucket) async throws -> [String: URL]
    func logEvent(_ name: String, venueID: UUID?) async
}

protocol FavoriteRemote: AnyObject {
    func favoriteVenueIDs() async throws -> [UUID]
    func setFavorite(venueID: UUID, isFavorite: Bool) async throws
}

protocol ReviewRemote: AnyObject {
    func verificationPolicy() async throws -> VerificationPolicy
    func issueVisitChallenge(venueID: UUID) async throws -> VisitChallenge
    func verifyVisit(challengeID: UUID, reading: LocationReading) async throws -> VisitVerificationResult
    func submitReview(_ submission: ReviewSubmission) async throws -> ReviewSubmissionResult
    func uploadReviewPhoto(revisionID: UUID, photo: PhotoUpload) async throws
    func flagReview(id: UUID, reason: FlagReason, note: String?) async throws
}

protocol SubmissionRemote: AnyObject {
    func createSubmission(_ draft: VenueSubmissionDraft) async throws -> SubmissionReceipt
    func resubmit(id: UUID, draft: VenueSubmissionDraft) async throws
    func withdrawSubmission(id: UUID) async throws
    func uploadSubmissionPhoto(submissionID: UUID, photo: PhotoUpload) async throws
    func mySubmissions() async throws -> [VenueSubmission]
}

protocol BusinessRemote: AnyObject {
    func requestClaim(_ draft: VenueClaimDraft) async throws -> ClaimStatus
    func myClaims() async throws -> [VenueClaim]
}

protocol AdminRemote: AnyObject {
    func adminSubmissions(status: SubmissionStatus) async throws -> [AdminSubmissionRow]
    func adminSubmissionDetail(id: UUID) async throws -> AdminSubmissionDetail
    func adminDecide(submissionID: UUID, decision: AdminSubmissionDecision) async throws
    func adminPendingClaims() async throws -> [AdminClaimRow]
    func adminDecideClaim(id: UUID, approve: Bool, reason: String?) async throws
    func adminFlaggedReviews() async throws -> [AdminFlaggedReview]
    func adminModerateReview(id: UUID, status: ReviewStatus, reason: String) async throws
}

typealias NanglenBackend = AuthRemote & VenueRemote & FavoriteRemote & ReviewRemote & SubmissionRemote & BusinessRemote & AdminRemote
