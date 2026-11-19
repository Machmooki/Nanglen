import Foundation

final class VenueDetailViewModel {
    struct State: Equatable {
        var venue: VenueSummary
        var detail: VenueDetail?
        var reviews: [PublishedReview] = []
        var reviewSort: ReviewSort = .relevant
        var hasMoreReviews = false
        var isLoading = true
        var isLoadingReviews = false
        var errorMessage: String?
        var isFavorite = false
        var mediaURLs: [String: URL] = [:]
        var isRegistered = false

        var myReview: MyReview? { detail?.myReview }
        /// Signed URL of the place's own 360° photo, once resolved.
        var panoramaURL: URL? { detail?.panoramaPath.flatMap { mediaURLs[$0] } }
        var acceptsReviews: Bool { venue.status.acceptsReviews }
    }

    enum WriteReviewRoute: Equatable {
        case needsRegistration
        case compose(existing: MyReview?)
        case notReviewable
    }

    var onChange: ((State) -> Void)?
    var onMessage: ((String) -> Void)?
    private(set) var state: State { didSet { if state != oldValue { onChange?(state) } } }

    private let venues: VenueRepository
    private let favorites: FavoriteRepository
    private let reviews: ReviewRepository
    private let session: SessionService
    private let mapCoordinator: MapCoordinator
    private let notifier: DataChangeNotifier
    private let pageSize = 10

    init(initial: VenueSummary, venues: VenueRepository, favorites: FavoriteRepository, reviews: ReviewRepository,
         session: SessionService, mapCoordinator: MapCoordinator, notifier: DataChangeNotifier) {
        state = State(venue: initial, isFavorite: favorites.contains(initial.id))
        self.venues = venues
        self.favorites = favorites
        self.reviews = reviews
        self.session = session
        self.mapCoordinator = mapCoordinator
        self.notifier = notifier
        notifier.subscribe(self) { [weak self] change in
            guard let self else { return }
            switch change {
            case .reviewSubmitted(let id) where id == state.venue.id: Task { await self.load() }
            case .sessionChanged: state.isRegistered = session.capabilities?.isRegistered ?? false
            case .favoritesChanged(let id) where id == state.venue.id: state.isFavorite = favorites.contains(id)
            default: break
            }
        }
    }

    var venueID: UUID { state.venue.id }

    func load() async {
        state.errorMessage = nil
        try? await session.start()
        state.isRegistered = session.capabilities?.isRegistered ?? false
        do {
            let detail = try await venues.detail(id: state.venue.id)
            var venue = detail.summary
            venue.distanceMeters = state.venue.distanceMeters
            state.venue = venue
            state.detail = detail
            state.isFavorite = detail.isFavorite
            venues.log("venue_detail_view", venueID: venue.id)
            await loadReviews(reset: true)
            await loadMedia(venuePhotos: detail.photoPaths, panorama: detail.panoramaPath)
        } catch {
            state.errorMessage = L10n.Errors.message(for: error)
        }
        state.isLoading = false
    }

    func setSort(_ sort: ReviewSort) {
        guard sort != state.reviewSort else { return }
        state.reviewSort = sort
        Task { await loadReviews(reset: true) }
    }

    func loadMoreReviews() {
        guard state.hasMoreReviews, !state.isLoadingReviews else { return }
        Task { await loadReviews(reset: false) }
    }

    private func loadReviews(reset: Bool) async {
        state.isLoadingReviews = true
        defer { state.isLoadingReviews = false }
        let offset = reset ? 0 : state.reviews.count
        guard let page = try? await venues.reviews(venueID: state.venue.id, sort: state.reviewSort, offset: offset, limit: pageSize) else { return }
        state.reviews = reset ? page.reviews : state.reviews + page.reviews.filter { new in !state.reviews.contains { $0.id == new.id } }
        state.hasMoreReviews = page.hasMore
        // Sign every photo of every review on this page (not only the first few) that isn't signed yet.
        let reviewPhotos = Array(Set(page.reviews.flatMap(\.photoPaths)).filter { state.mediaURLs[$0] == nil })
        if !reviewPhotos.isEmpty {
            let urls = await venues.signedURLs(paths: reviewPhotos, bucket: .review)
            state.mediaURLs.merge(urls) { _, new in new }
        }
    }

    private func loadMedia(venuePhotos: [String], panorama: String?) async {
        let paths = Array(venuePhotos.prefix(10)) + [panorama].compactMap { $0 }
        guard !paths.isEmpty else { return }
        let urls = await venues.signedURLs(paths: paths, bucket: .venue)
        state.mediaURLs.merge(urls) { _, new in new }
    }

    func toggleFavorite() {
        let target = !state.isFavorite
        state.isFavorite = target
        Task {
            do {
                try await session.start()
                try await favorites.setFavorite(state.venue.id, isFavorite: target)
                if target { venues.log("favorite_added", venueID: state.venue.id) }
                notifier.publish(.favoritesChanged(venueID: state.venue.id))
            } catch {
                state.isFavorite = !target
                onMessage?(L10n.Errors.message(for: error))
            }
        }
    }

    func writeReviewRoute() -> WriteReviewRoute {
        guard state.acceptsReviews else { return .notReviewable }
        guard session.capabilities?.isRegistered == true else { return .needsRegistration }
        return .compose(existing: state.myReview)
    }

    func openDirections() {
        venues.log("navigation_opened", venueID: state.venue.id)
        let venue = state.venue
        let appleMapsID = state.detail?.appleMapsID
        Task { await mapCoordinator.openInAppleMaps(venue, appleMapsID: appleMapsID) }
    }

    func report(reviewID: UUID, reason: FlagReason) {
        Task {
            do {
                try await reviews.flag(reviewID: reviewID, reason: reason, note: nil)
                onMessage?(L10n.Detail.reportSent)
            } catch {
                onMessage?(L10n.Errors.message(for: error))
            }
        }
    }

    func photoURLs(for paths: [String]) -> [URL] { paths.compactMap { state.mediaURLs[$0] } }
}
