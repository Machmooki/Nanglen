import Foundation
import os

/// Composition root: builds every dependency once and hands out view models.
/// View controllers receive the container — never a singleton, never the backend directly.
final class AppContainer {
    let configuration: AppConfiguration
    let database: DatabaseManager
    let cache: LocalCache
    let backend: NanglenBackend
    let locationManager: LocationProviding
    let placeSearchProvider: PlaceSearchProvider
    let mapCoordinator: MapCoordinator
    let notifier = DataChangeNotifier()

    let venues: VenueRepository
    let favorites: FavoriteRepository
    let reviews: ReviewRepository
    let submissions: SubmissionRepository
    let business: BusinessRepository
    let admin: AdminRepository

    let session: SessionService
    let verification: VisitVerificationService
    let reviewService: ReviewService
    let submissionService: SubmissionService

    /// Whether the cache database had to fall back to memory (data won't persist).
    let isUsingVolatileStorage: Bool

    init(
        configuration: AppConfiguration = .standard,
        database: DatabaseManager,
        backend: NanglenBackend,
        isUsingVolatileStorage: Bool = false,
        locationManager: LocationProviding,
        placeSearchProvider: PlaceSearchProvider
    ) {
        self.configuration = configuration
        self.database = database
        self.backend = backend
        self.isUsingVolatileStorage = isUsingVolatileStorage
        self.locationManager = locationManager
        self.placeSearchProvider = placeSearchProvider
        cache = LocalCache(database: database)
        mapCoordinator = MapCoordinator()

        venues = VenueRepository(remote: backend, cache: cache, configuration: configuration)
        favorites = FavoriteRepository(remote: backend, cache: cache)
        reviews = ReviewRepository(remote: backend, cache: cache)
        submissions = SubmissionRepository(remote: backend, cache: cache)
        business = BusinessRepository(remote: backend)
        admin = AdminRepository(remote: backend)

        session = SessionService(auth: backend, favorites: favorites, notifier: notifier)
        verification = VisitVerificationService(reviews: reviews, location: locationManager)
        reviewService = ReviewService(reviews: reviews, configuration: configuration, notifier: notifier)
        submissionService = SubmissionService(submissions: submissions, configuration: configuration, notifier: notifier)
    }

    /// Production wiring: on-disk cache, real location and MapKit, Supabase when configured,
    /// otherwise the clearly-labelled Demo backend.
    static func live() -> AppContainer {
        let logger = Logger(subsystem: "Mach.Nanglen-App", category: "AppContainer")
        let arguments = ProcessInfo.processInfo.arguments
        // UI tests pass -NanglenResetData to start from a clean, first-launch state.
        let reset = arguments.contains("-NanglenResetData")
        let database: DatabaseManager
        var volatile = false
        do {
            database = try DatabaseManager.onDisk(reset: reset)
        } catch {
            logger.error("Falling back to in-memory cache: \(error.localizedDescription, privacy: .public)")
            do {
                database = try DatabaseManager.inMemory()
            } catch {
                fatalError("Unable to create any SQLite database: \(error)")
            }
            volatile = true
        }

        let backend: NanglenBackend
        if !arguments.contains("-NanglenDemoBackend"), let config = SupabaseConfiguration.load() {
            backend = SupabaseBackend(configuration: config)
        } else {
            let directory = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))?
                .appendingPathComponent("DemoBackend", isDirectory: true)
            backend = DemoBackend(directory: directory, reset: reset)
        }
        return AppContainer(
            database: database,
            backend: backend,
            isUsingVolatileStorage: volatile,
            locationManager: LocationManager(),
            placeSearchProvider: MapKitPlaceSearchProvider()
        )
    }

    var isDemo: Bool { backend.mode == .demo }

    // MARK: View model factories

    func makeExploreViewModel() -> ExploreViewModel {
        ExploreViewModel(venues: venues, favorites: favorites, session: session, location: locationManager,
                         notifier: notifier, configuration: configuration)
    }

    func makeVenueDetailViewModel(venue: VenueSummary) -> VenueDetailViewModel {
        VenueDetailViewModel(initial: venue, venues: venues, favorites: favorites, reviews: reviews, session: session,
                             mapCoordinator: mapCoordinator, notifier: notifier)
    }

    func makeReviewComposerViewModel(venue: VenueSummary, existing: MyReview?) -> ReviewComposerViewModel {
        ReviewComposerViewModel(venue: venue, existing: existing, verification: verification, service: reviewService,
                                session: session, configuration: configuration)
    }

    func makePhoneLinkViewModel() -> PhoneLinkViewModel {
        PhoneLinkViewModel(session: session)
    }

    func makeAddPlaceViewModel(editing: VenueSubmission? = nil) -> AddPlaceViewModel {
        AddPlaceViewModel(editing: editing, service: submissionService, venues: venues, places: placeSearchProvider,
                          location: locationManager, session: session, configuration: configuration)
    }

    func makeSavedViewModel() -> SavedViewModel {
        SavedViewModel(favorites: favorites, venues: venues, session: session, location: locationManager,
                       mapCoordinator: mapCoordinator, notifier: notifier)
    }

    func makeProfileViewModel() -> ProfileViewModel {
        ProfileViewModel(session: session, business: business, cache: cache, location: locationManager, notifier: notifier)
    }

    func makeMySubmissionsViewModel() -> MySubmissionsViewModel {
        MySubmissionsViewModel(service: submissionService, notifier: notifier)
    }

    func makeAdminQueueViewModel() -> AdminQueueViewModel {
        AdminQueueViewModel(admin: admin, notifier: notifier)
    }

    func makeAdminSubmissionViewModel(id: UUID) -> AdminSubmissionViewModel {
        AdminSubmissionViewModel(submissionID: id, admin: admin, venues: venues, notifier: notifier)
    }

    func makeClaimViewModel(venue: VenueSummary) -> ClaimVenueViewModel {
        ClaimVenueViewModel(venue: venue, business: business, session: session)
    }
}

/// Implemented by root view controllers that receive the container at launch.
protocol AppContainerConfigurable: AnyObject {
    func configure(with container: AppContainer)
}
