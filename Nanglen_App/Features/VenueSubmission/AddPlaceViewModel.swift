import UIKit

/// Add Place: creates a `venue_submission` (pending Admin review) — never a public venue.
final class AddPlaceViewModel {
    struct State: Equatable {
        var draft: VenueSubmissionDraft
        var photos: [UIImage] = []
        var isSubmitting = false
        var issues: [SubmissionValidator.Issue] = []
        var errorMessage: String?
        var showValidation = false
    }

    struct CandidateRow: Hashable {
        var candidate: PlaceCandidate
        /// Set when this Apple Maps place is already an approved Nanglen venue.
        var existingVenueID: UUID?
    }

    enum Outcome: Equatable {
        case submitted(duplicates: [DuplicateCandidate])
        case resubmitted
        case alreadyListed(venueID: UUID)
        case needsRegistration
    }

    var onChange: ((State) -> Void)?
    var onOutcome: ((Outcome) -> Void)?
    private(set) var state: State { didSet { if state != oldValue { onChange?(state) } } }

    let editing: VenueSubmission?
    let configuration: AppConfiguration
    private let service: SubmissionService
    private let venues: VenueRepository
    private let places: PlaceSearchProvider
    private let location: LocationProviding
    private let session: SessionService
    private var selectedCandidate: PlaceCandidate?

    init(editing: VenueSubmission?, service: SubmissionService, venues: VenueRepository, places: PlaceSearchProvider,
         location: LocationProviding, session: SessionService, configuration: AppConfiguration) {
        self.editing = editing
        self.service = service
        self.venues = venues
        self.places = places
        self.location = location
        self.session = session
        self.configuration = configuration
        var draft = VenueSubmissionDraft()
        if let editing {
            draft.name = editing.name
            draft.category = editing.category
            draft.address = editing.address ?? ""
            draft.coordinate = editing.coordinate
            draft.description = editing.description ?? ""
            draft.websiteURL = editing.websiteURL ?? ""
            draft.phoneNumber = editing.phoneNumber ?? ""
            draft.note = editing.note ?? ""
        }
        state = State(draft: draft)
    }

    var isRegistered: Bool { session.capabilities?.isRegistered == true }

    func start() {
        guard editing == nil else { return }
        Task {
            if let saved = await service.savedDraft() { state.draft = saved }
            if state.draft.coordinate == nil, location.authorization == .authorized,
               let reading = try? await location.requestCurrentLocation() {
                state.draft.coordinate = reading.point
            }
            refreshIssues()
        }
    }

    var initialCenter: GeoPoint { state.draft.coordinate ?? location.lastKnownLocation?.point ?? configuration.defaultCenter }

    // MARK: Input

    func update(_ change: (inout VenueSubmissionDraft) -> Void) {
        change(&state.draft)
        refreshIssues()
    }

    /// Pin moved on the map. Moving far from a selected Apple Maps place drops its provider reference.
    func setPin(_ point: GeoPoint) {
        state.draft.coordinate = point
        if let candidate = selectedCandidate, candidate.coordinate.distance(to: point) > 75 {
            selectedCandidate = nil
            state.draft.provider = nil
            state.draft.externalPlaceID = nil
        }
        refreshIssues()
    }

    func select(_ candidate: PlaceCandidate) {
        selectedCandidate = candidate
        update { draft in
            draft.name = candidate.name
            draft.address = candidate.address ?? draft.address
            draft.coordinate = candidate.coordinate
            if draft.category == nil { draft.category = candidate.category }
            if draft.websiteURL.isEmpty, let website = candidate.websiteURL, website.lowercased().hasPrefix("http") { draft.websiteURL = website }
            if draft.phoneNumber.isEmpty, let phone = candidate.phoneNumber { draft.phoneNumber = phone }
            draft.provider = candidate.hasProviderIdentifier ? "apple_maps" : nil
            draft.externalPlaceID = candidate.hasProviderIdentifier ? candidate.externalPlaceID : nil
        }
    }

    /// MapKit candidates around the current pin, each marked if already on Nanglen.
    func searchCandidates(_ text: String) async -> [CandidateRow] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let region = SearchRegion.around(initialCenter, radiusMeters: 5_000)
        guard let candidates = try? await places.search(query: trimmed, region: region, categoryHint: nil) else { return [] }
        let ids = candidates.filter(\.hasProviderIdentifier).map(\.externalPlaceID)
        let matches = (try? await venues.canonicalVenueIDs(forAppleMapsIDs: ids)) ?? [:]
        return candidates.prefix(25).map { CandidateRow(candidate: $0, existingVenueID: matches[$0.externalPlaceID]) }
    }

    func addPhoto(_ image: UIImage) {
        guard state.photos.count < configuration.submissionMaxPhotos else { return }
        state.photos.append(image)
    }

    func removePhoto(at index: Int) {
        guard state.photos.indices.contains(index) else { return }
        state.photos.remove(at: index)
    }

    private func refreshIssues() {
        state.issues = service.issues(for: state.draft)
    }

    // MARK: Submit

    func submit() {
        state.showValidation = true
        refreshIssues()
        guard state.issues.isEmpty, !state.isSubmitting else { return }
        guard isRegistered else {
            onOutcome?(.needsRegistration)
            return
        }
        state.isSubmitting = true
        state.errorMessage = nil
        let draft = state.draft
        let photos = state.photos.compactMap { PhotoEncoder.upload(from: $0, maxBytes: configuration.mediaMaxBytes) }
        Task {
            defer { state.isSubmitting = false }
            do {
                if let editing {
                    try await service.resubmit(id: editing.id, draft: draft)
                    onOutcome?(.resubmitted)
                    return
                }
                let outcome = try await service.submit(draft, photos: photos)
                try? await session.refresh()
                switch outcome.receipt {
                case .submitted(_, _, let duplicates): onOutcome?(.submitted(duplicates: duplicates))
                case .alreadyListed(let venueID): onOutcome?(.alreadyListed(venueID: venueID))
                }
            } catch BackendError.registrationRequired {
                onOutcome?(.needsRegistration)
            } catch {
                state.errorMessage = L10n.Errors.message(for: error)
            }
        }
    }

    func cancel() {
        guard editing == nil, !state.draft.name.isEmpty || state.draft.coordinate != nil else { return }
        let draft = state.draft
        Task { await service.saveDraft(draft) }
    }

    func venueSummary(id: UUID) async -> VenueSummary? {
        if let cached = await venues.cachedSummary(id: id) { return cached.venue }
        return try? await venues.detail(id: id).summary
    }
}
