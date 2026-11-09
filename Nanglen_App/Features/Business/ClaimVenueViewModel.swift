import Foundation

/// Business claim request. Grants nothing by itself: an Admin must approve it on the server.
final class ClaimVenueViewModel {
    struct State: Equatable {
        var draft: VenueClaimDraft
        var isSubmitting = false
        var errorMessage: String?
        var submitted = false
    }

    var onChange: ((State) -> Void)?
    private(set) var state: State { didSet { if state != oldValue { onChange?(state) } } }
    let venue: VenueSummary
    private let business: BusinessRepository
    private let session: SessionService

    init(venue: VenueSummary, business: BusinessRepository, session: SessionService) {
        self.venue = venue
        self.business = business
        self.session = session
        state = State(draft: VenueClaimDraft(venueID: venue.id))
    }

    func update(_ change: (inout VenueClaimDraft) -> Void) { change(&state.draft) }

    func submit() {
        guard !state.isSubmitting else { return }
        guard !state.draft.businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state.errorMessage = L10n.Submission.nameRequired
            return
        }
        state.isSubmitting = true
        state.errorMessage = nil
        let draft = state.draft
        Task {
            defer { state.isSubmitting = false }
            do {
                _ = try await business.requestClaim(draft)
                state.submitted = true
            } catch {
                state.errorMessage = L10n.Errors.message(for: error)
            }
        }
    }
}
