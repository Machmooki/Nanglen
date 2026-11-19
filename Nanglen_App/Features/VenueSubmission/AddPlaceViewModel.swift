import UIKit

/// Add Place: creates a `venue_submission` (pending Admin review) — never a public venue.
final class AddPlaceViewModel {
    /// A photo already on the server (edit mode), with its signed URL once resolved.
    struct ExistingPhoto: Equatable {
        var photo: SubmissionPhoto
        var url: URL?
    }

    struct State: Equatable {
        var draft: VenueSubmissionDraft
        /// New photos picked on this device (uploaded on submit / resubmit).
        var photos: [UIImage] = []
        /// Edit mode: photos already attached that the person keeps.
        var existingPhotos: [ExistingPhoto] = []
        /// Edit mode: photos the person removed (deleted on resubmit, before new uploads).
        var removedPhotoIDs: [UUID] = []
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
        case resubmitted(failedPhotos: Int)
        case alreadyListed(venueID: UUID)
        case needsRegistration
    }

    enum LocateResult: Equatable {
        case moved(GeoPoint)
        case denied
        case unavailable
    }

    var onChange: ((State) -> Void)?
    var onOutcome: ((Outcome) -> Void)?
    /// Asks the screen to move the map (restored draft, or the person's location when adding a new place).
    var onMoveMap: ((GeoPoint) -> Void)?
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

    var isLocationAuthorized: Bool { location.authorization == .authorized }

    func start() {
        if let editing {
            Task { await loadExistingPhotos(editing.id) }
            return
        }
        Task {
            if let saved = await service.savedDraft() {
                state.draft = saved
                if let point = saved.coordinate { onMoveMap?(point) }
            }
            // New place: open the map where the person is, if location is already allowed (no prompt here).
            if state.draft.coordinate == nil, location.authorization == .authorized,
               let reading = try? await location.requestCurrentLocation() {
                state.draft.coordinate = reading.point
                onMoveMap?(reading.point)
            }
            refreshIssues()
        }
    }

    /// "My location" button: asks When-In-Use permission if needed, then moves the pin to the person.
    func locateMe() async -> LocateResult {
        var status = location.authorization
        if status == .notDetermined { status = await location.requestAuthorization() }
        switch status {
        case .authorized: break
        case .denied, .restricted: return .denied
        case .notDetermined: return .unavailable
        }
        guard let reading = try? await location.requestCurrentLocation() else { return .unavailable }
        setPin(reading.point)
        return .moved(reading.point)
    }

    // MARK: Photos

    /// Photos can be changed when adding a place, or while an Admin asks for changes.
    var canEditPhotos: Bool { editing == nil || editing?.status == .needsChanges }

    var photoCount: Int { state.existingPhotos.count + state.photos.count }
    var remainingPhotoSlots: Int { max(0, configuration.submissionMaxPhotos - photoCount) }

    /// Existing photos first, then new ones (same order as `removePhoto(at:)`).
    var photoItems: [PhotoStripView.Item] {
        state.existingPhotos.map { .remote($0.url) } + state.photos.map { .local($0) }
    }

    private func loadExistingPhotos(_ submissionID: UUID) async {
        guard let photos = try? await service.photos(submissionID: submissionID), !photos.isEmpty else { return }
        state.existingPhotos = photos.map { ExistingPhoto(photo: $0, url: nil) }
        let urls = await venues.signedURLs(paths: photos.map(\.storagePath), bucket: .venue)
        for index in state.existingPhotos.indices {
            state.existingPhotos[index].url = urls[state.existingPhotos[index].photo.storagePath]
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

    func addPhotos(_ images: [UIImage]) {
        state.photos += images.prefix(remainingPhotoSlots)
    }

    func removePhoto(at index: Int) {
        if state.existingPhotos.indices.contains(index) {
            let removed = state.existingPhotos.remove(at: index)
            state.removedPhotoIDs.append(removed.photo.id)
            return
        }
        let localIndex = index - state.existingPhotos.count
        guard state.photos.indices.contains(localIndex) else { return }
        state.photos.remove(at: localIndex)
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
                    // Order: remove photos → upload new ones → resubmit. Photo failures are reported, not fatal.
                    let failed = try await service.resubmit(
                        id: editing.id, draft: draft,
                        removingPhotos: canEditPhotos ? state.removedPhotoIDs : [],
                        addingPhotos: canEditPhotos ? photos : [],
                        keptPhotoCount: state.existingPhotos.count)
                    state.removedPhotoIDs = []
                    onOutcome?(.resubmitted(failedPhotos: failed))
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
        return try? await venues.detail(id: id).detail.summary
    }
}
