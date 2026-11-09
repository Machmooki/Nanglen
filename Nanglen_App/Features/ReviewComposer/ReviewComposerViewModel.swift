import UIKit

/// Review flow: verify the visit first (server-issued, one-time), then a one-screen form.
/// Publish is only possible with a valid verification id returned by the backend.
final class ReviewComposerViewModel {
    struct State: Equatable {
        var verification: VerificationState = .idle
        var draft: ReviewDraft
        var photos: [UIImage] = []
        var isSubmitting = false
        var notice: String?

        var verificationID: UUID? { verification.verificationID }
        var canEdit: Bool { verificationID != nil && !isSubmitting }
    }

    enum Outcome: Equatable {
        case published(message: String)
        case needsRegistration
    }

    var onChange: ((State) -> Void)?
    var onOutcome: ((Outcome) -> Void)?
    private(set) var state: State { didSet { if state != oldValue { onChange?(state) } } }

    let venue: VenueSummary
    let existing: MyReview?
    let configuration: AppConfiguration
    private let verification: VisitVerificationService
    private let service: ReviewService
    private let session: SessionService
    private var verifyTask: Task<Void, Never>?

    init(venue: VenueSummary, existing: MyReview?, verification: VisitVerificationService, service: ReviewService,
         session: SessionService, configuration: AppConfiguration) {
        self.venue = venue
        self.existing = existing
        self.verification = verification
        self.service = service
        self.session = session
        self.configuration = configuration
        var draft = ReviewDraft(venueID: venue.id)
        if let existing {
            draft.rating = existing.rating
            draft.purpose = existing.purpose
            draft.tags = existing.tags
            draft.body = existing.body ?? ""
        }
        state = State(draft: draft)
    }

    var issues: [ReviewValidator.Issue] { service.issues(for: state.draft) }
    var canSubmit: Bool { state.verificationID != nil && issues.isEmpty && !state.isSubmitting }

    func start() {
        Task {
            if let saved = await service.savedDraft(venueID: venue.id) {
                state.draft = saved
                state.notice = L10n.Review.draftRestored
            }
            verify()
        }
    }

    func verify() {
        verifyTask?.cancel()
        verifyTask = Task { [weak self] in
            guard let self else { return }
            let result = await verification.verify(venue: venue) { [weak self] newState in
                self?.state.verification = newState
            }
            if case .registrationRequired = result { onOutcome?(.needsRegistration) }
        }
    }

    // MARK: Form input

    func setRating(_ rating: Int) { state.draft.rating = (1...5).contains(rating) ? rating : nil }

    func setPurpose(_ slug: String?) { state.draft.purpose = slug.flatMap(VisitPurpose.init(rawValue:)) }

    func setTags(_ tags: Set<String>) { state.draft.tags = Array(tags.prefix(configuration.reviewMaxTags)).sorted() }

    func setBody(_ text: String) { state.draft.body = String(text.prefix(configuration.reviewMaxBodyLength)) }

    func addPhoto(_ image: UIImage) {
        guard state.photos.count < configuration.reviewMaxPhotos else { return }
        state.photos.append(image)
    }

    func removePhoto(at index: Int) {
        guard state.photos.indices.contains(index) else { return }
        state.photos.remove(at: index)
    }

    /// Keeps an unsent draft locally (never shown as published).
    func saveDraftIfNeeded() {
        guard state.draft.rating != nil || !state.draft.body.isEmpty || !state.draft.tags.isEmpty else { return }
        let draft = state.draft
        Task { await service.saveDraft(draft) }
    }

    // MARK: Submit

    func submit() {
        guard canSubmit, let verificationID = state.verificationID else { return }
        state.isSubmitting = true
        state.notice = nil
        let draft = state.draft
        let photos = state.photos.compactMap { PhotoEncoder.upload(from: $0, maxBytes: configuration.mediaMaxBytes) }
        Task {
            defer { state.isSubmitting = false }
            do {
                let outcome = try await service.publish(draft, verificationID: verificationID, photos: photos)
                try? await session.refresh()
                var message = outcome.result.revisionNumber > 1 ? L10n.Review.updated : L10n.Review.published
                if outcome.failedPhotos > 0 {
                    message += "\n" + L10n.Review.photosFailed(outcome.failedPhotos)
                } else if !photos.isEmpty {
                    message += "\n" + L10n.Review.photosPending
                }
                onOutcome?(.published(message: message))
            } catch let error as BackendError where error.requiresFreshVerification {
                // One-time verification expired or consumed: the draft is kept, verify again.
                state.verification = .failed(L10n.Review.reverify)
                state.notice = L10n.Review.draftSaved
            } catch BackendError.registrationRequired {
                onOutcome?(.needsRegistration)
            } catch {
                state.notice = L10n.Errors.message(for: error) + "\n" + L10n.Review.draftSaved
            }
        }
    }

    func cancel() {
        verifyTask?.cancel()
        saveDraftIfNeeded()
    }
}
