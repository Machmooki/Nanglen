import Foundation
import os

/// Composition root: builds every dependency once and hands out view models.
/// View controllers receive the container — never a singleton, never the backend directly.
final class AppContainer {
    /// Built-in defaults merged with the server's `get_public_config()` (see `AppConfiguration.swift`).
    /// Read it when a screen is created; it can change once after launch (`.configurationChanged`).
    var configuration: AppConfiguration { remoteConfig.current }
    let remoteConfig: RemoteConfigService
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
    let admin: AdminRepository

    let session: SessionService
    let verification: VisitVerificationService
    let reviewService: ReviewService
    let submissionService: SubmissionService
    /// Photo outbox: files + `pending_uploads` rows, retried by `pendingUploadService`.
    let uploadStore: PendingUploadStore
    let pendingUploadService: PendingUploadService

    /// Whether the cache database had to fall back to memory (data won't persist).
    let isUsingVolatileStorage: Bool

    init(
        configuration: AppConfiguration = .standard,
        database: DatabaseManager,
        backend: NanglenBackend,
        isUsingVolatileStorage: Bool = false,
        pendingUploadsDirectory: URL? = nil,
        locationManager: LocationProviding,
        placeSearchProvider: PlaceSearchProvider
    ) {
        self.database = database
        self.backend = backend
        self.isUsingVolatileStorage = isUsingVolatileStorage
        self.locationManager = locationManager
        self.placeSearchProvider = placeSearchProvider
        cache = LocalCache(database: database)
        mapCoordinator = MapCoordinator()
        let remoteConfig = RemoteConfigService(base: configuration, remote: backend, cache: LocalRemoteConfigCache(cache: cache), notifier: notifier)
        self.remoteConfig = remoteConfig

        // Rows of an in-memory database don't survive a relaunch, so files would be orphaned: no outbox then.
        let uploadStore = PendingUploadStore(cache: cache, directory: isUsingVolatileStorage ? nil : pendingUploadsDirectory)
        self.uploadStore = uploadStore

        let favorites = FavoriteRepository(remote: backend, cache: cache)
        self.favorites = favorites
        venues = VenueRepository(remote: backend, cache: cache, configuration: configuration, favorites: favorites)
        reviews = ReviewRepository(remote: backend, cache: cache)
        submissions = SubmissionRepository(remote: backend, cache: cache)
        admin = AdminRepository(remote: backend)

        let session = SessionService(auth: backend, favorites: favorites, notifier: notifier, cache: cache, uploads: uploadStore)
        self.session = session
        let currentUserID: () async -> UUID? = { [session] in try? await session.requireCapabilities().userID }
        verification = VisitVerificationService(reviews: reviews, location: locationManager)
        reviewService = ReviewService(reviews: reviews, configuration: { remoteConfig.current }, notifier: notifier,
                                      userID: currentUserID, uploads: uploadStore)
        submissionService = SubmissionService(submissions: submissions, configuration: { remoteConfig.current }, notifier: notifier,
                                              userID: currentUserID, uploads: uploadStore)
        pendingUploadService = PendingUploadService(store: uploadStore, reviews: backend, submissions: backend,
                                                    userID: { [session] in session.capabilities?.userID }, notifier: notifier)
    }

    /// Launch housekeeping off the main thread: evicts old/excess cache rows and orphaned outbox files.
    func startMaintenance() {
        let cache = cache
        let uploadStore = uploadStore
        let configuration = configuration
        Task.detached(priority: .utility) {
            do {
                try await cache.prune(configuration: configuration)
            } catch {
                Logger(subsystem: "Mach.Nanglen-App", category: "AppContainer")
                    .error("Cache prune failed: \(error.localizedDescription, privacy: .public)")
            }
            await uploadStore.removeOrphanFiles()
        }
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
        let uploadsDirectory = PendingUploadStore.defaultDirectory()
        if reset, let uploadsDirectory { try? FileManager.default.removeItem(at: uploadsDirectory) }
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
        // Unit-test host runs and UI tests never touch the real project (no stray anonymous users).
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let config = SupabaseConfiguration.load()
        if !arguments.contains("-NanglenDemoBackend"), !isTesting, let config {
            logger.notice("Backend: Supabase (\(config.url.host ?? "?", privacy: .public))")
            backend = SupabaseBackend(configuration: config)
        } else {
            let reason = arguments.contains("-NanglenDemoBackend") ? "-NanglenDemoBackend launch argument"
                : isTesting ? "running under XCTest"
                : Bundle.main.url(forResource: "Supabase", withExtension: "plist") == nil ? "Supabase.plist not in app bundle"
                : "Supabase.plist values invalid (URL must be https://<ref>.supabase.co, key must be publishable)"
            logger.notice("Backend: Demo — \(reason, privacy: .public)")
            let directory = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))?
                .appendingPathComponent("DemoBackend", isDirectory: true)
            backend = DemoBackend(directory: directory, reset: reset)
        }
        return AppContainer(
            database: database,
            backend: backend,
            isUsingVolatileStorage: volatile,
            pendingUploadsDirectory: uploadsDirectory,
            locationManager: LocationManager(),
            placeSearchProvider: MapKitPlaceSearchProvider()
        )
    }

    var isDemo: Bool { backend.mode == .demo }

    // MARK: View model factories

    func makeExploreViewModel() -> ExploreViewModel {
        ExploreViewModel(venues: venues, favorites: favorites, session: session, location: locationManager,
                         notifier: notifier, configuration: { [remoteConfig] in remoteConfig.current })
    }

    func makeVenueDetailViewModel(venue: VenueSummary) -> VenueDetailViewModel {
        VenueDetailViewModel(initial: venue, venues: venues, favorites: favorites, reviews: reviews, session: session,
                             mapCoordinator: mapCoordinator, notifier: notifier)
    }

    func makeReviewComposerViewModel(venue: VenueSummary, existing: MyReview?) -> ReviewComposerViewModel {
        ReviewComposerViewModel(venue: venue, existing: existing, verification: verification, service: reviewService,
                                session: session, configuration: configuration)
    }

    func makeSignInViewModel() -> SignInViewModel {
        SignInViewModel(session: session)
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
        ProfileViewModel(session: session, venues: venues, cache: cache, location: locationManager, notifier: notifier)
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
}

/// Implemented by root view controllers that receive the container at launch.
protocol AppContainerConfigurable: AnyObject {
    func configure(with container: AppContainer)
}
