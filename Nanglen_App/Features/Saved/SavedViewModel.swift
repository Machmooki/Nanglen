import Foundation

/// Saved venues. Guests save against their anonymous account; Registered users sync across devices.
/// Offline, the cached list is shown with a stale label (no fake successful writes).
final class SavedViewModel {
    struct State: Equatable {
        var items: [VenueCardItem] = []
        var isLoading = false
        var hasLoaded = false
        var errorMessage: String?
        var source: DataSourceState = .live
        var isGuest = true
    }

    var onChange: ((State) -> Void)?
    var onMessage: ((String) -> Void)?
    private(set) var state = State() { didSet { if state != oldValue { onChange?(state) } } }

    private let favorites: FavoriteRepository
    private let venues: VenueRepository
    private let session: SessionService
    private let location: LocationProviding
    private let mapCoordinator: MapCoordinator
    private let notifier: DataChangeNotifier
    private var loadTask: Task<Void, Never>?

    init(favorites: FavoriteRepository, venues: VenueRepository, session: SessionService, location: LocationProviding,
         mapCoordinator: MapCoordinator, notifier: DataChangeNotifier) {
        self.favorites = favorites
        self.venues = venues
        self.session = session
        self.location = location
        self.mapCoordinator = mapCoordinator
        self.notifier = notifier
        notifier.subscribe(self) { [weak self] change in
            switch change {
            case .favoritesChanged, .sessionChanged, .reviewSubmitted, .cacheCleared: self?.load()
            default: break
            }
        }
    }

    func load() {
        loadTask?.cancel()
        if !state.hasLoaded { state.isLoading = true }
        loadTask = Task { [weak self] in
            guard let self else { return }
            defer { state.isLoading = false; state.hasLoaded = true }
            do {
                let caps = try await session.requireCapabilities()
                state.isGuest = caps.isGuest
                let source = try await favorites.refresh(userID: caps.userID)
                let ids = favorites.favoriteIDs
                let origin = location.lastKnownLocation?.point
                var cards: [VenueSummary]
                var resolvedSource = source
                do {
                    cards = try await venues.cards(ids: ids, origin: origin)
                } catch {
                    let cached = await cachedCards(ids)
                    cards = cached
                    resolvedSource = .offline(cachedAt: nil)
                }
                guard !Task.isCancelled else { return }
                let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
                cards.sort { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
                state.source = resolvedSource
                state.items = cards.map { VenueCardItem(venue: $0, isFavorite: true, isStale: resolvedSource != .live) }
                state.errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                state.errorMessage = L10n.Errors.message(for: error)
            }
        }
    }

    private func cachedCards(_ ids: [UUID]) async -> [VenueSummary] {
        var result: [VenueSummary] = []
        for id in ids {
            if let cached = await venues.cachedSummary(id: id) { result.append(cached.venue) }
        }
        return result
    }

    func remove(_ item: VenueCardItem) {
        let before = state.items
        state.items.removeAll { $0.id == item.id }
        Task {
            do {
                try await favorites.setFavorite(item.id, isFavorite: false)
                notifier.publish(.favoritesChanged(venueID: item.id))
            } catch {
                state.items = before
                onMessage?(L10n.Errors.message(for: error))
            }
        }
    }

    func openDirections(to item: VenueCardItem) {
        venues.log("navigation_opened", venueID: item.id)
        let venue = item.venue
        Task { await mapCoordinator.openInAppleMaps(venue) }
    }
}
