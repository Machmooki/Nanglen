import Foundation
import UIKit
import Testing
@testable import Nanglen_App

// Tests for the 2026-11-18 detail update: server-driven config, filter slider/stars,
// review photo/tag limits, and editing submission photos while changes are requested.

// MARK: - Remote config

@MainActor
struct RemoteConfigTests {
    @Test func missingValuesKeepDefaults() {
        let merged = AppConfiguration.standard.merged(with: RemoteConfigValues())
        #expect(merged.reviewMaxPhotos == 5)
        #expect(merged.reviewMaxTags == ReviewTag.catalog.count)
        #expect(merged.submissionMaxPhotos == 5)
        #expect(merged.filter == AppConfiguration.FilterLimits())
        #expect(merged.reviewMediaAutoApprove)
    }

    @Test func serverValuesOverrideDefaults() {
        let remote = RemoteConfigValues(reviewBodyMaxChars: 800, reviewMaxTags: 4, reviewMaxPhotos: 7, reviewMediaAutoApprove: false,
                                        submissionMaxPhotos: 8, mediaMaxBytes: 1_000_000,
                                        filterDistanceMinMeters: 1_000, filterDistanceMaxMeters: 30_000, filterDistanceStepMeters: 1_000,
                                        filterDistanceDefaultMeters: 5_000, filterRatingStep: 1, visitRadiusMeters: 150)
        let merged = AppConfiguration.standard.merged(with: remote)
        #expect(merged.reviewMaxBodyLength == 800)
        #expect(merged.reviewMaxTags == 4)
        #expect(merged.reviewMaxPhotos == 7)
        #expect(!merged.reviewMediaAutoApprove)
        #expect(merged.submissionMaxPhotos == 8)
        #expect(merged.mediaMaxBytes == 1_000_000)
        #expect(merged.filter.distanceMinMeters == 1_000)
        #expect(merged.filter.distanceMaxMeters == 30_000)
        #expect(merged.filter.distanceStepMeters == 1_000)
        #expect(merged.filter.distanceDefaultMeters == 5_000)
        #expect(merged.filter.ratingStep == 1)
        #expect(merged.verification.radiusMeters == 150)
    }

    @Test func nonsensicalValuesAreIgnored() {
        let remote = RemoteConfigValues(reviewMaxPhotos: -1, submissionMaxPhotos: 0,
                                        filterDistanceMinMeters: 9_000, filterDistanceMaxMeters: 2_000, filterRatingStep: 3)
        let merged = AppConfiguration.standard.merged(with: remote)
        #expect(merged.reviewMaxPhotos == 5)
        #expect(merged.submissionMaxPhotos == 5)
        #expect(merged.filter.distanceMinMeters == 500, "min > max keeps the whole default range")
        #expect(merged.filter.distanceMaxMeters == 20_000)
        #expect(merged.filter.ratingStep == 0.5)
    }

    @Test func defaultDistanceIsClampedIntoTheRange() {
        let merged = AppConfiguration.standard.merged(with: RemoteConfigValues(filterDistanceMaxMeters: 10_000, filterDistanceDefaultMeters: 50_000))
        #expect(merged.filter.distanceDefaultMeters == 10_000)
    }

    @Test func decodesServerPayloadLeniently() throws {
        let json = """
        {"review_max_photos": 5, "review_max_tags": "10", "review_media_auto_approve": true,
         "filter_distance_max_m": 20000, "filter_rating_step": 0.5, "unknown_future_key": 1}
        """
        let values = try JSONDecoder().decode(RemoteConfigValues.self, from: Data(json.utf8))
        #expect(values.reviewMaxPhotos == 5)
        #expect(values.reviewMaxTags == 10)
        #expect(values.reviewMediaAutoApprove == true)
        #expect(values.filterDistanceMaxMeters == 20_000)
        #expect(values.filterRatingStep == 0.5)
        #expect(values.submissionMaxPhotos == nil)
        let numericFlag = try JSONDecoder().decode(RemoteConfigValues.self, from: Data(#"{"review_media_auto_approve": 0}"#.utf8))
        #expect(numericFlag.reviewMediaAutoApprove == false)
    }

    @Test func serviceUsesCacheAtLaunchThenRefreshes() async {
        let cache = InMemoryRemoteConfigCache(values: RemoteConfigValues(reviewMaxPhotos: 4))
        let remote = StubConfigRemote(result: .success(RemoteConfigValues(reviewMaxPhotos: 6, filterDistanceDefaultMeters: 2_000)))
        let notifier = DataChangeNotifier()
        var events: [DataChange] = []
        let owner = NSObject()
        notifier.subscribe(owner) { events.append($0) }

        let service = RemoteConfigService(base: .standard, remote: remote, cache: cache, notifier: notifier)
        #expect(service.current.reviewMaxPhotos == 4, "cached server value applies before the network answers")

        await service.refresh()
        #expect(service.current.reviewMaxPhotos == 6)
        #expect(service.current.filter.distanceDefaultMeters == 2_000)
        #expect(cache.values?.reviewMaxPhotos == 6, "fresh values are cached for the next launch")
        #expect(events == [.configurationChanged])

        await service.refresh()
        #expect(events == [.configurationChanged], "unchanged values don't notify again")
    }

    @Test func offlineFallsBackToCacheOrDefaults() async {
        let offline = StubConfigRemote(result: .failure(BackendError.network))
        let cached = RemoteConfigService(base: .standard, remote: offline, cache: InMemoryRemoteConfigCache(values: RemoteConfigValues(reviewMaxPhotos: 3)))
        await cached.refresh()
        #expect(cached.current.reviewMaxPhotos == 3)

        let fresh = RemoteConfigService(base: .standard, remote: offline, cache: InMemoryRemoteConfigCache())
        await fresh.refresh()
        #expect(fresh.current.reviewMaxPhotos == AppConfiguration.standard.reviewMaxPhotos)
    }

    @Test func demoBackendServesItsLimitsAsConfig() async throws {
        let values = try await makeBackend().publicConfig()
        let merged = AppConfiguration.standard.merged(with: values)
        #expect(merged.reviewMaxPhotos == AppConfiguration.standard.reviewMaxPhotos)
        #expect(merged.filter == AppConfiguration.standard.filter)
    }
}

final class StubConfigRemote: ConfigRemote {
    let result: Result<RemoteConfigValues, Error>
    init(result: Result<RemoteConfigValues, Error>) { self.result = result }
    func publicConfig() async throws -> RemoteConfigValues { try result.get() }
}

// MARK: - Filter (distance slider, minimum-rating stars)

@MainActor
struct FilterSliderAndStarsTests {
    private let limits = AppConfiguration.FilterLimits()

    @Test func defaultFilterUsesConfiguredDistance() {
        var limits = limits
        limits.distanceDefaultMeters = 5_000
        let filter = VenueFilter(limits: limits)
        #expect(filter.distanceMeters == 5_000)
        #expect(filter.activeCount == 0)
        #expect(filter.activeItems.isEmpty)
    }

    @Test func changedDistanceIsActiveAndRemovable() {
        var filter = VenueFilter(limits: limits)
        filter.distanceMeters = 7_500
        #expect(filter.activeCount == 1)
        #expect(filter.activeItems == [.distance])
        #expect(FilterViewModel.title(for: .distance, in: filter) == L10n.Filter.within(FilterViewModel.distanceText(7_500)))
        filter.remove(.distance)
        #expect(filter.distanceMeters == limits.distanceDefaultMeters)
        #expect(filter.activeCount == 0)
    }

    @Test func ratingIsOptionalAndHalfStepped() {
        var filter = VenueFilter(limits: limits)
        filter.minimumRating = 3.5
        #expect(filter.activeItems == [.minimumRating])
        #expect(filter.matches(Fixtures.summary(average: 3.6, count: 2)))
        #expect(!filter.matches(Fixtures.summary(average: 3.4, count: 2)))
        filter.remove(.minimumRating)
        #expect(filter.minimumRating == nil)
    }

    @Test func sliderValuesSnapToTheConfiguredStep() {
        let viewModel = FilterViewModel(filter: VenueFilter(limits: limits), limits: limits)
        viewModel.setDistance(2_740)
        #expect(viewModel.filter.distanceMeters == 2_500)
        viewModel.setDistance(2_760)
        #expect(viewModel.filter.distanceMeters == 3_000)
        viewModel.setDistance(80_000)
        #expect(viewModel.filter.distanceMeters == 20_000)
        viewModel.setDistance(10)
        #expect(viewModel.filter.distanceMeters == 500)
    }

    @Test func starsSnapToRatingStepAndClear() {
        let viewModel = FilterViewModel(filter: VenueFilter(limits: limits), limits: limits)
        viewModel.setMinimumRating(3.7)
        #expect(viewModel.filter.minimumRating == 3.5)
        viewModel.setMinimumRating(4)
        #expect(viewModel.filter.minimumRating == 4)
        viewModel.setMinimumRating(nil)
        #expect(viewModel.filter.minimumRating == nil)

        var whole = limits
        whole.ratingStep = 1
        let wholeStars = FilterViewModel(filter: VenueFilter(limits: whole), limits: whole)
        wholeStars.setMinimumRating(3.5)
        #expect(wholeStars.filter.minimumRating == 4)
    }

    @Test func resetRestoresConfiguredDefaults() {
        var limits = limits
        limits.distanceDefaultMeters = 4_000
        let viewModel = FilterViewModel(filter: VenueFilter(limits: limits), limits: limits)
        viewModel.setDistance(12_000)
        viewModel.setMinimumRating(4.5)
        viewModel.setReviewedOnly(true)
        viewModel.reset()
        #expect(viewModel.filter == VenueFilter(limits: limits))
        #expect(viewModel.filter.distanceMeters == 4_000)
    }

    @Test func distanceLabelsKeepHalfKilometres() {
        #expect(FilterViewModel.distanceText(500) == Formatters.distance(500))
        #expect(FilterViewModel.distanceText(2_500).contains("2.5"))
        #expect(FilterViewModel.distanceText(12_500).contains("12.5"))
        #expect(FilterViewModel.distanceText(20_000).contains("20"))
        #expect(FilterViewModel.ratingText(nil) == L10n.Filter.anyRating)
    }

    @Test func searchUsesTheFilterDistance() async throws {
        let backend = makeBackend()
        try await backend.ensureSession()
        var filter = VenueFilter(limits: limits)
        filter.distanceMeters = 500
        let near = try await backend.searchVenues(VenueSearchQuery(origin: Fixtures.cafe, radiusMeters: filter.distanceMeters, filter: filter))
        filter.distanceMeters = 20_000
        let wide = try await backend.searchVenues(VenueSearchQuery(origin: Fixtures.cafe, radiusMeters: filter.distanceMeters, filter: filter))
        #expect(near.venues.count <= wide.venues.count)
        #expect(near.venues.allSatisfy { ($0.distanceMeters ?? 0) <= 500 })
    }
}

// MARK: - Facility ("Good for") filters: more than 3

@MainActor
struct FacilityFilterTests {
    @Test func everyGoodForTagCanBeSelectedByDefault() {
        let limits = AppConfiguration.standard.filter
        #expect(limits.maxTags == VenueFilter.goodForTags.count)
        #expect(limits.tagSelectionLimit == nil, "no 'pick up to 3' limit on the chips")
        let viewModel = FilterViewModel(filter: VenueFilter(limits: limits), limits: limits)
        viewModel.setTags(Set(VenueFilter.goodForTags))
        #expect(viewModel.filter.tags.count == VenueFilter.goodForTags.count)
        #expect(viewModel.filter.activeCount == VenueFilter.goodForTags.count)
    }

    @Test func serverCanStillSetALimit() {
        let merged = AppConfiguration.standard.merged(with: RemoteConfigValues(filterMaxTags: 4))
        #expect(merged.filter.tagSelectionLimit == 4)
        let viewModel = FilterViewModel(filter: VenueFilter(limits: merged.filter), limits: merged.filter)
        viewModel.setTags(Set(VenueFilter.goodForTags))
        #expect(viewModel.filter.tags.count == 4)
        let catalog = AppConfiguration.standard.merged(with: RemoteConfigValues(filterMaxTags: 10))
        #expect(catalog.filter.tagSelectionLimit == nil, "server value = whole catalog means unlimited")
    }

    @Test func searchAcceptsManyFacilityTags() async throws {
        let backend = makeBackend()
        try await backend.ensureSession()
        var filter = VenueFilter()
        filter.tags = Set(VenueFilter.goodForTags)
        _ = try await backend.searchVenues(VenueSearchQuery(origin: Fixtures.cafe, filter: filter))
        filter.tags = ["quiet", "good_wifi", "power_outlets", "study_friendly"]
        _ = try await backend.searchVenues(VenueSearchQuery(origin: Fixtures.cafe, filter: filter))
    }
}

// MARK: - Review tags and photos

@MainActor
struct ReviewLimitTests {
    private func verified(_ backend: DemoBackend) async throws -> UUID {
        let challenge = try await backend.issueVisitChallenge(venueID: Fixtures.cafeID)
        return try #require(try await backend.verifyVisit(challengeID: challenge.id, reading: Fixtures.reading()).verificationID)
    }

    private var photo: PhotoUpload { PhotoUpload(data: Data(repeating: 1, count: 100), mimeType: "image/jpeg", fileExtension: "jpg", width: 10, height: 10) }

    @Test func everyTagCanBeChosen() async throws {
        let config = AppConfiguration.standard
        let all = ReviewTag.catalog.map(\.slug)
        #expect(ReviewValidator.issues(rating: 4, tags: all, body: "", maxTags: config.reviewMaxTags, maxBody: config.reviewMaxBodyLength).isEmpty)

        let backend = makeBackend()
        try await registerUser(backend)
        let verification = try await verified(backend)
        let result = try await backend.submitReview(ReviewSubmission(venueID: Fixtures.cafeID, verificationID: verification, rating: 5,
                                                                     purpose: nil, tags: all, body: nil, idempotencyKey: UUID()))
        let mine = try await backend.reviews(venueID: Fixtures.cafeID, sort: .recent, limit: 50, offset: 0).reviews.first { $0.id == result.reviewID }
        #expect(mine?.tags.count == all.count)
    }

    @Test func reviewPhotosAreVisibleRightAwayUpToTheLimit() async throws {
        let backend = makeBackend()
        try await registerUser(backend)
        let verification = try await verified(backend)
        let result = try await backend.submitReview(ReviewSubmission(venueID: Fixtures.cafeID, verificationID: verification, rating: 4,
                                                                     purpose: nil, tags: [], body: nil, idempotencyKey: UUID()))
        for _ in 0..<AppConfiguration.standard.reviewMaxPhotos {
            try await backend.uploadReviewPhoto(revisionID: result.revisionID, photo: photo)
        }
        await #expect(throws: BackendError.invalidInput("too_many_photos")) {
            try await backend.uploadReviewPhoto(revisionID: result.revisionID, photo: photo)
        }
        let review = try await backend.reviews(venueID: Fixtures.cafeID, sort: .recent, limit: 50, offset: 0).reviews.first { $0.id == result.reviewID }
        #expect(review?.photoPaths.count == 5, "post-moderation: photos are public without an Admin step")
    }

    @Test func photosWaitForApprovalWhenAutoApproveIsOff() async throws {
        var limits = AppConfiguration.standard
        limits.reviewMediaAutoApprove = false
        let clock = TestClock()
        let backend = DemoBackend(directory: nil, seed: true, clock: { clock.now }, limits: limits)
        try await registerUser(backend)
        let verification = try await verified(backend)
        let result = try await backend.submitReview(ReviewSubmission(venueID: Fixtures.cafeID, verificationID: verification, rating: 4,
                                                                     purpose: nil, tags: [], body: nil, idempotencyKey: UUID()))
        try await backend.uploadReviewPhoto(revisionID: result.revisionID, photo: photo)
        let review = try await backend.reviews(venueID: Fixtures.cafeID, sort: .recent, limit: 50, offset: 0).reviews.first { $0.id == result.reviewID }
        #expect(review?.photoPaths.isEmpty == true)
    }

    @Test func reviewServiceReadsTheCurrentPhotoLimit() async throws {
        let backend = makeBackend()
        try await registerUser(backend)
        let database = try DatabaseManager.inMemory()
        var config = AppConfiguration.standard
        config.reviewMaxPhotos = 2
        let service = ReviewService(reviews: ReviewRepository(remote: backend, cache: LocalCache(database: database)),
                                    configuration: { config }, notifier: DataChangeNotifier())
        var draft = ReviewDraft(venueID: Fixtures.cafeID)
        draft.rating = 5
        let outcome = try await service.publish(draft, verificationID: try await verified(backend), photos: Array(repeating: photo, count: 4))
        #expect(outcome.failedPhotos == 0)
        let review = try await backend.reviews(venueID: Fixtures.cafeID, sort: .recent, limit: 50, offset: 0).reviews.first { $0.id == outcome.result.reviewID }
        #expect(review?.photoPaths.count == 2, "only as many photos as the server config allows are sent")
    }
}

// MARK: - Submission photos while changes are requested

@MainActor
struct SubmissionPhotoEditTests {
    private var photo: PhotoUpload { PhotoUpload(data: Data(repeating: 2, count: 100), mimeType: "image/jpeg", fileExtension: "jpg", width: 10, height: 10) }

    private func draft() -> VenueSubmissionDraft {
        var draft = VenueSubmissionDraft()
        draft.name = "Photo Edit Loft"
        draft.category = .studySpace
        draft.coordinate = GeoPoint(latitude: 13.7600, longitude: 100.5600)
        draft.address = "Bangkok"
        return draft
    }

    /// Owner submission with `count` photos, sent back by an Admin for changes.
    private func needsChanges(_ backend: DemoBackend, photos count: Int) async throws -> UUID {
        try await registerUser(backend, email: "owner@example.test")
        guard case .submitted(let id, _, _) = try await backend.createSubmission(draft()) else { throw BackendError.server("not submitted") }
        for _ in 0..<count { try await backend.uploadSubmissionPhoto(submissionID: id, photo: photo) }
        try await registerUser(backend, email: DemoSeed.adminEmail)
        try await backend.adminDecide(submissionID: id, decision: .requestChanges(reason: "Clearer photo please"))
        try await registerUser(backend, email: "owner@example.test")
        return id
    }

    @Test func ownerCanRemovePhotosOnlyWhileChangesAreRequested() async throws {
        let backend = makeBackend()
        try await registerUser(backend, email: "owner@example.test")
        guard case .submitted(let id, _, _) = try await backend.createSubmission(draft()) else { return }
        try await backend.uploadSubmissionPhoto(submissionID: id, photo: photo)
        let pending = try #require(try await backend.submissionPhotos(submissionID: id).first)
        await #expect(throws: BackendError.invalidStatusTransition) { try await backend.removeSubmissionPhoto(id: pending.id) }

        try await registerUser(backend, email: DemoSeed.adminEmail)
        try await backend.adminDecide(submissionID: id, decision: .requestChanges(reason: "More photos"))
        await #expect(throws: BackendError.notFound) { try await backend.removeSubmissionPhoto(id: pending.id) }

        try await registerUser(backend, email: "owner@example.test")
        try await backend.removeSubmissionPhoto(id: pending.id)
        #expect(try await backend.submissionPhotos(submissionID: id).isEmpty)
    }

    @Test func resubmitRemovesThenUploadsThenRequeues() async throws {
        let backend = makeBackend()
        let id = try await needsChanges(backend, photos: 3)
        let existing = try await backend.submissionPhotos(submissionID: id)
        #expect(existing.map(\.displayOrder) == [0, 1, 2])

        let database = try DatabaseManager.inMemory()
        let service = SubmissionService(submissions: SubmissionRepository(remote: backend, cache: LocalCache(database: database)),
                                        configuration: { .standard }, notifier: DataChangeNotifier())
        let failed = try await service.resubmit(id: id, draft: draft(), removingPhotos: [existing[0].id],
                                                addingPhotos: [photo, photo, photo], keptPhotoCount: 2)
        #expect(failed == 0)
        let after = try await backend.submissionPhotos(submissionID: id)
        #expect(after.count == 5, "2 kept + 3 new = the submission limit")
        #expect(!after.contains { $0.id == existing[0].id })
        #expect(after.map(\.displayOrder) == [0, 1, 2, 3, 4])
        #expect(try await backend.mySubmissions().first { $0.id == id }?.status == .pendingReview)
    }

    @Test func extraPhotosOverTheLimitAreReportedNotLost() async throws {
        let backend = makeBackend()
        let id = try await needsChanges(backend, photos: 4)
        let database = try DatabaseManager.inMemory()
        let service = SubmissionService(submissions: SubmissionRepository(remote: backend, cache: LocalCache(database: database)),
                                        configuration: { .standard }, notifier: DataChangeNotifier())
        let failed = try await service.resubmit(id: id, draft: draft(), addingPhotos: [photo, photo, photo], keptPhotoCount: 4)
        #expect(failed == 2, "only one slot was left")
        #expect(try await backend.mySubmissions().first { $0.id == id }?.status == .pendingReview, "the rest of the edit still went through")
    }

    @Test func retryAfterAlreadyRemovedPhotoStillResubmits() async throws {
        let backend = makeBackend()
        let id = try await needsChanges(backend, photos: 1)
        let photoID = try #require(try await backend.submissionPhotos(submissionID: id).first?.id)
        try await backend.removeSubmissionPhoto(id: photoID)
        let database = try DatabaseManager.inMemory()
        let service = SubmissionService(submissions: SubmissionRepository(remote: backend, cache: LocalCache(database: database)),
                                        configuration: { .standard }, notifier: DataChangeNotifier())
        let failed = try await service.resubmit(id: id, draft: draft(), removingPhotos: [photoID])
        #expect(failed == 0)
    }

    @Test func addPlaceViewModelEditsExistingPhotos() async throws {
        let backend = makeBackend()
        let id = try await needsChanges(backend, photos: 2)
        let submission = try #require(try await backend.mySubmissions().first { $0.id == id })
        let container = AppContainer(database: try DatabaseManager.inMemory(), backend: backend,
                                     locationManager: MockLocation(readings: []), placeSearchProvider: NoPlaces())
        let viewModel = container.makeAddPlaceViewModel(editing: submission)
        #expect(viewModel.canEditPhotos)
        viewModel.start()
        for _ in 0..<50 where viewModel.state.existingPhotos.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(viewModel.state.existingPhotos.count == 2)
        #expect(viewModel.remainingPhotoSlots == 3)
        viewModel.removePhoto(at: 0)
        #expect(viewModel.state.existingPhotos.count == 1)
        #expect(viewModel.state.removedPhotoIDs.count == 1)
        viewModel.addPhotos(Array(repeating: UIImageFixture.make(), count: 6))
        #expect(viewModel.state.photos.count == 4, "never more than the submission limit")
        #expect(viewModel.photoItems.count == 5)
    }
}

// MARK: - Suggest a Place: my location

@MainActor
struct AddPlaceLocationTests {
    private func viewModel(_ location: MockLocation) throws -> AddPlaceViewModel {
        let container = AppContainer(database: try DatabaseManager.inMemory(), backend: makeBackend(),
                                     locationManager: location, placeSearchProvider: NoPlaces())
        return container.makeAddPlaceViewModel()
    }

    @Test func locateMeAsksPermissionThenMovesThePin() async throws {
        let location = MockLocation(authorization: .notDetermined, readings: [.success(Fixtures.reading())])
        let viewModel = try viewModel(location)
        #expect(await viewModel.locateMe() == .moved(Fixtures.cafe))
        #expect(location.authorizationRequests == 1)
        #expect(viewModel.state.draft.coordinate == Fixtures.cafe)
    }

    @Test func locateMeReportsDeniedPermission() async throws {
        let viewModel = try viewModel(MockLocation(authorization: .denied, readings: []))
        #expect(await viewModel.locateMe() == .denied)
        #expect(viewModel.state.draft.coordinate == nil)
    }
}

final class NoPlaces: PlaceSearchProvider {
    func search(query: String, region: SearchRegion, categoryHint: VenueCategory?) async throws -> [PlaceCandidate] { [] }
    func discover(category: VenueCategory?, region: SearchRegion) async throws -> [PlaceCandidate] { [] }
}

enum UIImageFixture {
    static func make() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}
