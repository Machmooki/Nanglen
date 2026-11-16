import Foundation

/// A card on Explore/Saved: an approved venue plus the user's favorite state.
nonisolated struct VenueCardItem: Identifiable, Hashable, Sendable {
    var venue: VenueSummary
    var isFavorite: Bool
    var isStale = false
    /// Tags the user filtered by; shown first on the card so it's clear why the place matched.
    var highlightedTags: Set<String> = []
    /// Resolved (signed) URL for `venue.coverPath`, filled in after the list loads.
    var coverURL: URL?

    var id: UUID { venue.id }

    /// Up to three tags: matched filter tags first, then the venue's most-chosen tags.
    var displayTags: [String] {
        let matched = venue.topTags.filter(highlightedTags.contains) + highlightedTags.sorted().filter { !venue.topTags.contains($0) }
        return Array((matched + venue.topTags.filter { !highlightedTags.contains($0) }).prefix(3))
    }
}

/// Search-first discovery over **approved** Nanglen venues only.
/// Text input is debounced; every request carries a generation number and stale responses are dropped.
final class ExploreViewModel {
    enum LocationState: Equatable {
        case defaultArea, locating, current, mapArea, denied

        var text: String {
            switch self {
            case .defaultArea: L10n.Explore.defaultArea
            case .locating: L10n.Explore.locating
            case .current: L10n.Explore.nearYou
            case .mapArea: L10n.Explore.mapArea
            case .denied: L10n.Explore.locationOff
            }
        }

        var symbol: String {
            switch self {
            case .current: "location.fill"
            case .denied: "location.slash"
            case .mapArea: "map"
            default: "location"
            }
        }
    }

    nonisolated enum SectionKind: Hashable, Sendable { case recommended, results }

    struct Section: Equatable {
        var kind: SectionKind
        var title: String
        var subtitle: String?
        var items: [VenueCardItem]
    }

    struct State: Equatable {
        var query = ""
        var category: VenueCategory?
        var filter = VenueFilter.default
        var venues: [VenueSummary] = []
        var hasMore = false
        var isLoading = false
        var isLoadingMore = false
        var hasLoadedOnce = false
        var errorMessage: String?
        var source: DataSourceState = .live
        var locationState: LocationState = .defaultArea
        var favoriteIDs: Set<UUID> = []
        /// Signed cover-photo URLs keyed by storage path, resolved lazily for the cards on screen.
        var coverURLs: [String: URL] = [:]

        var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

        var items: [VenueCardItem] {
            venues.map {
                VenueCardItem(venue: $0, isFavorite: favoriteIDs.contains($0.id), isStale: source != .live,
                              highlightedTags: filter.tags, coverURL: $0.coverPath.flatMap { coverURLs[$0] })
            }
        }

        var sections: [Section] {
            guard !venues.isEmpty else { return [] }
            if isSearching {
                return [Section(kind: .results, title: L10n.Explore.results, subtitle: L10n.Explore.resultsCount(venues.count), items: items)]
            }
            return [Section(kind: .recommended, title: L10n.Explore.recommended, subtitle: L10n.Explore.recommendedSubtitle, items: items)]
        }

        var isEmpty: Bool { venues.isEmpty }

        var bannerText: String? {
            if case .offline(let cachedAt) = source {
                return cachedAt.map { L10n.Explore.offlineSince(Formatters.relative($0)) } ?? L10n.Explore.offlineBanner
            }
            return nil
        }
    }

    enum Event {
        case moveMap(SearchRegion)
        case fitMapToResults
        case showLocationDenied
    }

    var onStateChange: ((State) -> Void)?
    var onEvent: ((Event) -> Void)?
    private(set) var state = State() {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    private let venues: VenueRepository
    private let favorites: FavoriteRepository
    private let session: SessionService
    private let location: LocationProviding
    private let notifier: DataChangeNotifier
    private let configuration: AppConfiguration
    private var region: SearchRegion
    private var searchTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var generation = 0

    init(venues: VenueRepository, favorites: FavoriteRepository, session: SessionService, location: LocationProviding,
         notifier: DataChangeNotifier, configuration: AppConfiguration) {
        self.venues = venues
        self.favorites = favorites
        self.session = session
        self.location = location
        self.notifier = notifier
        self.configuration = configuration
        region = SearchRegion.around(configuration.defaultCenter, radiusMeters: VenueFilter.default.distance.meters)
        notifier.subscribe(self) { [weak self] change in self?.handle(change) }
    }

    // MARK: Lifecycle

    func start() {
        onEvent?(.moveMap(region))
        if location.authorization == .authorized {
            useMyLocation()
        } else {
            state.locationState = location.authorization == .denied ? .denied : .defaultArea
            reload()
        }
    }

    private func handle(_ change: DataChange) {
        switch change {
        case .favoritesChanged, .sessionChanged:
            state.favoriteIDs = Set(favorites.favoriteIDs)
        case .reviewSubmitted, .moderationChanged:
            reload(showSpinner: false)
        case .cacheCleared, .submissionsChanged:
            break
        }
    }

    // MARK: Input

    func updateQuery(_ text: String) {
        guard text != state.query else { return }
        state.query = text
        debounceTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Avoid a request per keystroke: wait, and skip 1-character queries.
        if !trimmed.isEmpty && trimmed.count < configuration.minimumQueryLength { return }
        debounceTask = Task { [weak self, delay = configuration.searchDebounce] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    func submitSearch() {
        debounceTask?.cancel()
        reload()
    }

    func selectCategory(_ category: VenueCategory?) {
        guard category != state.category else { return }
        state.category = category
        reload()
    }

    func apply(_ filter: VenueFilter) {
        guard filter != state.filter else { return }
        state.filter = filter
        region = SearchRegion.around(region.center, radiusMeters: filter.distance.meters)
        reload()
    }

    func removeFilter(_ item: VenueFilter.Item) {
        var filter = state.filter
        filter.remove(item)
        apply(filter)
    }

    func resetFilters() {
        state.filter = .default
        state.category = nil
        reload()
    }

    func searchArea(_ newRegion: SearchRegion) {
        region = newRegion
        state.locationState = .mapArea
        reload()
    }

    func retry() { reload() }

    func useMyLocation() {
        if location.authorization == .denied || location.authorization == .restricted {
            state.locationState = .denied
            onEvent?(.showLocationDenied)
            return
        }
        state.locationState = .locating
        Task { [weak self] in
            guard let self else { return }
            do {
                let reading = try await location.requestCurrentLocation()
                region = SearchRegion.around(reading.point, radiusMeters: state.filter.distance.meters)
                state.locationState = .current
                onEvent?(.moveMap(region))
            } catch {
                state.locationState = location.authorization == .denied ? .denied : .defaultArea
            }
            reload()
        }
    }

    func loadMore() {
        guard state.hasMore, !state.isLoadingMore, !state.isLoading else { return }
        state.isLoadingMore = true
        let query = makeQuery(offset: state.venues.count)
        let current = generation
        Task { [weak self] in
            guard let self else { return }
            defer { if current == generation { state.isLoadingMore = false } }
            guard let page = try? await venues.search(query), current == generation else { return }
            let known = Set(state.venues.map(\.id))
            state.venues += page.venues.filter { !known.contains($0.id) }
            state.hasMore = page.hasMore
            resolveCovers(for: page.venues)
        }
    }

    /// Signs cover-photo paths that aren't resolved yet, then updates the cards in place.
    private func resolveCovers(for list: [VenueSummary]) {
        let missing = Set(list.compactMap(\.coverPath)).subtracting(state.coverURLs.keys)
        guard !missing.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            let urls = await venues.signedURLs(paths: Array(missing), bucket: .venue)
            guard !urls.isEmpty else { return }
            state.coverURLs.merge(urls) { _, new in new }
        }
    }

    // MARK: Loading

    private func makeQuery(offset: Int = 0) -> VenueSearchQuery {
        VenueSearchQuery(
            text: state.query, origin: region.center,
            radiusMeters: max(state.filter.distance.meters, min(region.radiusMeters, 50_000)),
            category: state.category, filter: state.filter, limit: configuration.searchPageSize, offset: offset)
    }

    func reload(showSpinner: Bool = true) {
        searchTask?.cancel()
        generation += 1
        let current = generation
        let query = makeQuery()
        if showSpinner { state.isLoading = true }
        state.errorMessage = nil
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await session.start()
            do {
                let results = try await venues.search(query)
                guard !Task.isCancelled, current == generation else { return }
                state.favoriteIDs = Set(favorites.favoriteIDs)
                state.venues = results.venues
                state.hasMore = results.hasMore
                state.source = results.source
                state.hasLoadedOnce = true
                state.isLoading = false
                resolveCovers(for: results.venues)
                if state.isSearching { onEvent?(.fitMapToResults) }
                if !query.trimmedText.isEmpty { venues.log("search", venueID: nil) }
            } catch is CancellationError {
                return
            } catch {
                guard current == generation else { return }
                state.venues = []
                state.hasMore = false
                state.errorMessage = L10n.Errors.message(for: error)
                state.hasLoadedOnce = true
                state.isLoading = false
            }
        }
    }
}
