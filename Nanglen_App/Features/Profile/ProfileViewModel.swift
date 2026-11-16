import UIKit

/// Profile state. Role-specific entries come only from server-derived capabilities.
final class ProfileViewModel {
    struct State: Equatable {
        var capabilities: UserCapabilities?
        var claims: [VenueClaim] = []
        var location: LocationAuthorization = .notDetermined
        var mode: BackendMode = .demo
        var errorMessage: String?
        /// Signed URL of the current profile photo (resolved from `capabilities.avatarPath`).
        var avatarURL: URL?
        var isUploadingPhoto = false
    }

    var onChange: ((State) -> Void)?
    var onMessage: ((String) -> Void)?
    private(set) var state = State() { didSet { if state != oldValue { onChange?(state) } } }

    private let session: SessionService
    private let business: BusinessRepository
    private let venues: VenueRepository
    private let cache: LocalCache
    private var resolvedAvatarPath: String?
    private let location: LocationProviding
    private let notifier: DataChangeNotifier

    init(session: SessionService, business: BusinessRepository, venues: VenueRepository, cache: LocalCache,
         location: LocationProviding, notifier: DataChangeNotifier) {
        self.session = session
        self.business = business
        self.venues = venues
        self.cache = cache
        self.location = location
        self.notifier = notifier
        state.mode = session.mode
        notifier.subscribe(self) { [weak self] change in
            switch change {
            case .sessionChanged:
                self?.state.capabilities = self?.session.capabilities
                Task { await self?.resolveAvatar() }
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
            await resolveAvatar()
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

    /// Signs the avatar path only when it changed (a new upload always gets a new path).
    private func resolveAvatar() async {
        let path = state.capabilities?.avatarPath
        guard path != resolvedAvatarPath else { return }
        resolvedAvatarPath = path
        guard let path else {
            state.avatarURL = nil
            return
        }
        let urls = await venues.signedURLs(paths: [path], bucket: .avatar)
        guard resolvedAvatarPath == path else { return }
        state.avatarURL = urls[path]
        if state.avatarURL == nil { resolvedAvatarPath = nil }
    }

    /// Crops to a centred square, scales to 512 px and uploads. `nil` removes the photo.
    func setProfilePhoto(_ image: UIImage?) {
        guard !state.isUploadingPhoto else { return }
        let upload: PhotoUpload?
        if let image {
            guard let encoded = PhotoEncoder.upload(from: Self.squareCrop(image), maxBytes: 2 * 1_024 * 1_024, maxDimension: 512) else {
                onMessage?(L10n.Profile.photoUnreadable)
                return
            }
            upload = encoded
        } else {
            upload = nil
        }
        state.isUploadingPhoto = true
        Task {
            defer { state.isUploadingPhoto = false }
            do {
                try await session.updateAvatar(upload)
                state.capabilities = session.capabilities
                await resolveAvatar()
                onMessage?(image == nil ? L10n.Profile.photoRemoved : L10n.Profile.photoUpdated)
            } catch {
                onMessage?(L10n.Errors.message(for: error))
            }
        }
    }

    private static func squareCrop(_ image: UIImage) -> UIImage {
        let side = min(image.size.width, image.size.height)
        guard side > 0, image.size.width != image.size.height else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        let origin = CGPoint(x: (side - image.size.width) / 2, y: (side - image.size.height) / 2)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(at: origin)
        }
    }

    func clearCache() {
        Task {
            try? await cache.clearAll()
            notifier.publish(.cacheCleared)
            onMessage?(L10n.Profile.cacheCleared)
        }
    }

    func deleteAccount() {
        Task {
            do {
                try await session.deleteAccount()
                await load()
                onMessage?(L10n.Profile.accountDeleted)
            } catch {
                onMessage?(L10n.Errors.message(for: error))
            }
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
