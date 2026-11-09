import Foundation

nonisolated struct ReviewPublishOutcome: Hashable, Sendable {
    var result: ReviewSubmissionResult
    /// Photos that could not be uploaded. The review itself is published.
    var failedPhotos: Int
}

/// Business rules for publishing a review. Publication requires a current server verification;
/// a local draft is kept whenever publishing fails.
final class ReviewService {
    private let reviews: ReviewRepository
    private let configuration: AppConfiguration
    private let notifier: DataChangeNotifier

    init(reviews: ReviewRepository, configuration: AppConfiguration, notifier: DataChangeNotifier) {
        self.reviews = reviews
        self.configuration = configuration
        self.notifier = notifier
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
        let result: ReviewSubmissionResult
        do {
            result = try await reviews.submit(submission)
        } catch {
            await reviews.saveDraft(draft)
            throw error
        }
        var failed = 0
        for photo in photos.prefix(configuration.reviewMaxPhotos) {
            do { try await reviews.uploadPhoto(revisionID: result.revisionID, photo: photo) } catch { failed += 1 }
        }
        await reviews.deleteDraft(venueID: draft.venueID)
        notifier.publish(.reviewSubmitted(venueID: draft.venueID))
        return ReviewPublishOutcome(result: result, failedPhotos: failed)
    }

    func savedDraft(venueID: UUID) async -> ReviewDraft? { await reviews.draft(venueID: venueID) }
    func saveDraft(_ draft: ReviewDraft) async { await reviews.saveDraft(draft) }
}

nonisolated struct SubmissionOutcome: Hashable, Sendable {
    var receipt: SubmissionReceipt
    var failedPhotos: Int
}

/// Venue submissions go to `venue_submissions` (pending Admin review), never to the public catalog.
final class SubmissionService {
    private let submissions: SubmissionRepository
    private let configuration: AppConfiguration
    private let notifier: DataChangeNotifier

    init(submissions: SubmissionRepository, configuration: AppConfiguration, notifier: DataChangeNotifier) {
        self.submissions = submissions
        self.configuration = configuration
        self.notifier = notifier
    }

    func issues(for draft: VenueSubmissionDraft) -> [SubmissionValidator.Issue] { SubmissionValidator.issues(draft) }

    func submit(_ draft: VenueSubmissionDraft, photos: [PhotoUpload]) async throws -> SubmissionOutcome {
        try SubmissionValidator.validate(draft)
        let receipt: SubmissionReceipt
        do {
            receipt = try await submissions.create(draft)
        } catch {
            await submissions.saveDraft(draft)
            throw error
        }
        var failed = 0
        if case .submitted(let id, _, _) = receipt {
            for photo in photos.prefix(configuration.submissionMaxPhotos) {
                do { try await submissions.uploadPhoto(submissionID: id, photo: photo) } catch { failed += 1 }
            }
        }
        await submissions.deleteDraft()
        notifier.publish(.submissionsChanged)
        return SubmissionOutcome(receipt: receipt, failedPhotos: failed)
    }

    func resubmit(id: UUID, draft: VenueSubmissionDraft) async throws {
        try SubmissionValidator.validate(draft)
        try await submissions.resubmit(id: id, draft: draft)
        notifier.publish(.submissionsChanged)
    }

    func withdraw(id: UUID) async throws {
        try await submissions.withdraw(id: id)
        notifier.publish(.submissionsChanged)
    }

    func mine() async throws -> [VenueSubmission] { try await submissions.mine() }
    func savedDraft() async -> VenueSubmissionDraft? { await submissions.draft() }
    func saveDraft(_ draft: VenueSubmissionDraft) async { await submissions.saveDraft(draft) }
}
