import Foundation

/// Profile state. Role-specific entries come only from server-derived capabilities.
final class ProfileViewModel {
    struct State: Equatable {
        var capabilities: UserCapabilities?
        var claims: [VenueClaim] = []
        var location: LocationAuthorization = .notDetermined
        var mode: BackendMode = .demo
        var errorMessage: String?
    }

    var onChange: ((State) -> Void)?
    var onMessage: ((String) -> Void)?
    private(set) var state = State() { didSet { if state != oldValue { onChange?(state) } } }

    private let session: SessionService
    private let business: BusinessRepository
    private let cache: LocalCache
    private let location: LocationProviding
    private let notifier: DataChangeNotifier

    init(session: SessionService, business: BusinessRepository, cache: LocalCache, location: LocationProviding, notifier: DataChangeNotifier) {
        self.session = session
        self.business = business
        self.cache = cache
        self.location = location
        self.notifier = notifier
        state.mode = session.mode
        notifier.subscribe(self) { [weak self] change in
            switch change {
            case .sessionChanged:
                self?.state.capabilities = self?.session.capabilities
            case .favoritesChanged, .reviewSubmitted, .submissionsChanged:
                Task { await self?.load() }
            default: break
            }
        }
    }

    func load() async {
        state.location = location.authorization
        do {
            try await session.start()
            try await session.refresh()
            state.capabilities = session.capabilities
            state.errorMessage = nil
            if session.capabilities?.isRegistered == true {
                state.claims = (try? await business.myClaims()) ?? []
            } else {
                state.claims = []
            }
        } catch {
            state.capabilities = session.capabilities
            state.errorMessage = L10n.Errors.message(for: error)
        }
    }

    func updateDisplayName(_ name: String) {
        Task {
            do {
                try await session.updateDisplayName(name)
                state.capabilities = session.capabilities
            } catch {
                onMessage?(L10n.Errors.message(for: error))
            }
        }
    }

    func clearCache() {
        Task {
            try? await cache.clearAll()
            notifier.publish(.cacheCleared)
            onMessage?(L10n.Profile.cacheCleared)
        }
    }

    func signOut() {
        Task {
            do {
                try await session.signOut()
                await load()
            } catch {
                onMessage?(L10n.Errors.message(for: error))
            }
        }
    }
}
