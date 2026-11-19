import Foundation
import os

/// Owns the signed-in identity (Guest or Registered) and its *server-derived* capabilities.
/// Capabilities are refreshed from the backend; nothing here grants privileges locally.
final class SessionService {
    private let auth: AuthRemote
    private let favorites: FavoriteRepository
    private let notifier: DataChangeNotifier
    private let cache: LocalCache?
    private let uploads: PendingUploadStore?
    private(set) var capabilities: UserCapabilities?
    private var starting: Task<Void, Error>?
    private let logger = Logger(subsystem: "Mach.Nanglen-App", category: "Session")

    /// - Parameters:
    ///   - cache, uploads: where the user's private local data lives; wiped when that user leaves this device
    ///     (sign out, account switch, account deletion). Shared caches (venues, details, `app_kv`) are kept.
    init(auth: AuthRemote, favorites: FavoriteRepository, notifier: DataChangeNotifier,
         cache: LocalCache? = nil, uploads: PendingUploadStore? = nil) {
        self.auth = auth
        self.favorites = favorites
        self.notifier = notifier
        self.cache = cache
        self.uploads = uploads
    }

    var mode: BackendMode { auth.mode }

    /// Restores the session or creates an anonymous Guest. Safe to call repeatedly.
    func start() async throws {
        if capabilities != nil { return }
        if let starting { return try await starting.value }
        let task = Task { [auth] in
            try await auth.ensureSession()
            try await refresh()
        }
        starting = task
        defer { starting = nil }
        try await task.value
    }

    func refresh() async throws {
        let caps = try await auth.capabilities()
        capabilities = caps
        _ = try? await favorites.refresh(userID: caps.userID)
        notifier.publish(.sessionChanged)
    }

    func requireCapabilities() async throws -> UserCapabilities {
        if let capabilities { return capabilities }
        try await start()
        guard let capabilities else { throw BackendError.notAuthenticated }
        return capabilities
    }

    /// Guest → Registered on this device. Returns the normalised email the code was sent to.
    func requestEmailLink(rawEmail: String) async throws -> String {
        guard let email = EmailAddress.normalized(rawEmail) else { throw BackendError.invalidInput("invalid_email") }
        try await auth.requestEmailLink(email: email)
        return email
    }

    func confirmEmailLink(email: String, code: String) async throws {
        try await auth.confirmEmailLink(email: email, code: try Self.cleanCode(code))
        try await refresh()
    }

    /// Returning user: switch to an existing account (explicit choice; guest data on this device is not merged).
    func requestEmailSignIn(email: String) async throws {
        try await auth.requestEmailSignIn(email: email)
    }

    func confirmEmailSignIn(email: String, code: String) async throws {
        let previous = capabilities?.userID
        try await auth.confirmEmailSignIn(email: email, code: try Self.cleanCode(code))
        await removeLocalData(of: previous)
        capabilities = nil
        favorites.reset()
        try await refresh()
    }

    func deleteAccount() async throws {
        let previous = capabilities?.userID
        try await auth.deleteAccount()
        await removeLocalData(of: previous)
        capabilities = nil
        favorites.reset()
        try await refresh()
    }

    private static func cleanCode(_ code: String) throws -> String {
        let digits = code.filter(\.isNumber)
        guard (6...10).contains(digits.count) else { throw BackendError.invalidOTP }
        return digits
    }

    func updateDisplayName(_ name: String) async throws {
        try await auth.updateDisplayName(name)
        try await refresh()
    }

    func updateAvatar(_ photo: PhotoUpload?) async throws {
        try await auth.updateAvatar(photo)
        try await refresh()
    }

    func signOut() async throws {
        let previous = capabilities?.userID
        try await auth.signOut()
        await removeLocalData(of: previous)
        capabilities = nil
        favorites.reset()
        try await refresh()
    }

    /// Deletes the user's drafts, cached favorites and queued photos (rows and files).
    private func removeLocalData(of userID: UUID?) async {
        guard let userID, let cache else { return }
        do {
            let files = try await cache.removeUserData(userID: userID)
            uploads?.deleteFiles(files)
        } catch {
            logger.error("Could not remove local data of the previous user: \(error.localizedDescription, privacy: .public)")
        }
    }
}
