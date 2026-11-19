import Foundation

nonisolated struct ReviewPublishOutcome: Hashable, Sendable {
    var result: ReviewSubmissionResult
    /// Photos that could not be uploaded and were not queued. The review itself is published.
    var failedPhotos: Int
    /// Photos that failed for a network reason and will be retried by `PendingUploadService`.
    var queuedPhotos: Int = 0
}

/// Shared by both services: queues a photo whose upload failed because the device is offline.
/// Returns true when it was queued (the caller then doesn't count it as failed).
private func queueIfOffline(_ error: Error, photo: PhotoUpload, kind: PendingUploadKind, targetID: UUID, venueID: UUID?,
                            userID: UUID?, uploads: PendingUploadStore?, now: Date) async -> Bool {
    guard NetworkFailure.isOffline(error), let userID, let uploads else { return false }
    return await uploads.enqueue(photo, kind: kind, targetID: targetID, venueID: venueID, userID: userID, now: now)
}

/// Business rules for publishing a review. Publication requires a current server verification;
/// a local draft is kept whenever publishing fails.
final class ReviewService {
    private let reviews: ReviewRepository
    private let currentConfiguration: () -> AppConfiguration
    private let notifier: DataChangeNotifier
    private let currentUserID: () async -> UUID?
    private let uploads: PendingUploadStore?
    private let clock: () -> Date
    private var configuration: AppConfiguration { currentConfiguration() }

    /// - Parameters:
    ///   - configuration: read on every use, so server limits fetched after launch apply immediately.
    ///   - userID: the signed-in user; drafts are stored per user and nothing is saved without one.
    ///   - uploads: photo outbox for uploads that fail offline (nil: such photos count as failed).
    init(reviews: ReviewRepository, configuration: @escaping () -> AppConfiguration, notifier: DataChangeNotifier,
         userID: @escaping () async -> UUID?, uploads: PendingUploadStore? = nil, clock: @escaping () -> Date = { Date() }) {
        self.reviews = reviews
        currentConfiguration = configuration
        self.notifier = notifier
        currentUserID = userID
        self.uploads = uploads
        self.clock = clock
    }

    convenience init(reviews: ReviewRepository, configuration: AppConfiguration, notifier: DataChangeNotifier,
                     userID: @escaping () async -> UUID?, uploads: PendingUploadStore? = nil) {
        self.init(reviews: reviews, configuration: { configuration }, notifier: notifier, userID: userID, uploads: uploads)
    }

    func issues(for draft: ReviewDraft) -> [ReviewValidator.Issue] {
        ReviewValidator.issues(rating: draft.rating, tags: draft.tags, body: draft.body,
                               maxTags: configuration.reviewMaxTags, maxBody: configuration.reviewMaxBodyLength)
    }

    func publish(_ draft: ReviewDraft, verificationID: UUID, photos: [PhotoUpload]) async throws -> ReviewPublishOutcome {
        guard issues(for: draft).isEmpty, let rating = draft.rating else { throw BackendError.invalidInput("invalid_rating") }
        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let submission = ReviewSubmission(
            venueID: draft.venueID, verificationID: verificationID, rating: rating, purpose: draft.purpose,
            tags: Array(Set(draft.tags)).sorted(), body: body.isEmpty ? nil : body, idempotencyKey: draft.idempotencyKey)
        let userID = await currentUserID()
        let result: ReviewSubmissionResult
        do {
            result = try await reviews.submit(submission)
        } catch {
            if let userID { await reviews.saveDraft(draft, userID: userID) }
            throw error
        }
        var failed = 0
        var queued = 0
        for photo in photos.prefix(configuration.reviewMaxPhotos) {
            do {
                try await reviews.uploadPhoto(revisionID: result.revisionID, photo: photo)
            } catch {
                if await queueIfOffline(error, photo: photo, kind: .reviewPhoto, targetID: result.revisionID, venueID: draft.venueID,
                                        userID: userID, uploads: uploads, now: clock()) {
                    queued += 1
                } else {
                    failed += 1
                }
            }
        }
        if let userID { await reviews.deleteDraft(venueID: draft.venueID, userID: userID) }
        notifier.publish(.reviewSubmitted(venueID: draft.venueID))
        return ReviewPublishOutcome(result: result, failedPhotos: failed, queuedPhotos: queued)
    }

    func savedDraft(venueID: UUID) async -> ReviewDraft? {
        guard let userID = await currentUserID() else { return nil }
        return await reviews.draft(venueID: venueID, userID: userID)
    }

    func saveDraft(_ draft: ReviewDraft) async {
        guard let userID = await currentUserID() else { return }
        await reviews.saveDraft(draft, userID: userID)
    }
}

nonisolated struct SubmissionOutcome: Hashable, Sendable {
    var receipt: SubmissionReceipt
    var failedPhotos: Int
    /// Photos queued for retry after a network failure.
    var queuedPhotos: Int = 0
}

/// Venue submissions go to `venue_submissions` (pending Admin review), never to the public catalog.
final class SubmissionService {
    private let submissions: SubmissionRepository
    private let currentConfiguration: () -> AppConfiguration
    private let notifier: DataChangeNotifier
    private let currentUserID: () async -> UUID?
    private let uploads: PendingUploadStore?
    private let clock: () -> Date
    private var configuration: AppConfiguration { currentConfiguration() }

    init(submissions: SubmissionRepository, configuration: @escaping () -> AppConfiguration, notifier: DataChangeNotifier,
         userID: @escaping () async -> UUID?, uploads: PendingUploadStore? = nil, clock: @escaping () -> Date = { Date() }) {
        self.submissions = submissions
        currentConfiguration = configuration
        self.notifier = notifier
        currentUserID = userID
        self.uploads = uploads
        self.clock = clock
    }

    convenience init(submissions: SubmissionRepository, configuration: AppConfiguration, notifier: DataChangeNotifier,
                     userID: @escaping () async -> UUID?, uploads: PendingUploadStore? = nil) {
        self.init(submissions: submissions, configuration: { configuration }, notifier: notifier, userID: userID, uploads: uploads)
    }

    func issues(for draft: VenueSubmissionDraft) -> [SubmissionValidator.Issue] { SubmissionValidator.issues(draft) }

    func submit(_ draft: VenueSubmissionDraft, photos: [PhotoUpload]) async throws -> SubmissionOutcome {
        try SubmissionValidator.validate(draft)
        let userID = await currentUserID()
        let receipt: SubmissionReceipt
        do {
            receipt = try await submissions.create(draft)
        } catch {
            if let userID { await submissions.saveDraft(draft, userID: userID) }
            throw error
        }
        var failed = 0
        var queued = 0
        if case .submitted(let id, _, _) = receipt {
            for photo in photos.prefix(configuration.submissionMaxPhotos) {
                do {
                    try await submissions.uploadPhoto(submissionID: id, photo: photo)
                } catch {
                    if await queueIfOffline(error, photo: photo, kind: .submissionPhoto, targetID: id, venueID: nil,
                                            userID: userID, uploads: uploads, now: clock()) {
                        queued += 1
                    } else {
                        failed += 1
                    }
                }
            }
        }
        if let userID { await submissions.deleteDraft(userID: userID) }
        notifier.publish(.submissionsChanged)
        return SubmissionOutcome(receipt: receipt, failedPhotos: failed, queuedPhotos: queued)
    }

    /// Resubmits after an Admin asked for changes. Photo edits run first — remove, then upload — and the
    /// submission goes back to the queue even if some photos fail (the count is reported, nothing else is lost).
    @discardableResult
    func resubmit(id: UUID, draft: VenueSubmissionDraft, removingPhotos removed: [UUID] = [],
                  addingPhotos added: [PhotoUpload] = [], keptPhotoCount: Int = 0) async throws -> Int {
        try SubmissionValidator.validate(draft)
        var failed = 0
        for photoID in removed {
            do {
                try await submissions.removePhoto(id: photoID)
            } catch BackendError.notFound {
                // Already removed (e.g. a retry after a failed resubmit).
            } catch {
                failed += 1
            }
        }
        let room = max(0, configuration.submissionMaxPhotos - keptPhotoCount - failed)
        for photo in added.prefix(room) {
            do { try await submissions.uploadPhoto(submissionID: id, photo: photo) } catch { failed += 1 }
        }
        failed += max(0, added.count - room)
        try await submissions.resubmit(id: id, draft: draft)
        notifier.publish(.submissionsChanged)
        return failed
    }

    func photos(submissionID: UUID) async throws -> [SubmissionPhoto] { try await submissions.photos(submissionID: submissionID) }

    func withdraw(id: UUID) async throws {
        try await submissions.withdraw(id: id)
        notifier.publish(.submissionsChanged)
    }

    func mine() async throws -> [VenueSubmission] { try await submissions.mine() }
    func savedDraft() async -> VenueSubmissionDraft? {
        guard let userID = await currentUserID() else { return nil }
        return await submissions.draft(userID: userID)
    }

    func saveDraft(_ draft: VenueSubmissionDraft) async {
        guard let userID = await currentUserID() else { return }
        await submissions.saveDraft(draft, userID: userID)
    }
}
