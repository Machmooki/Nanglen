import Foundation

/// Owns the signed-in identity (Guest or Registered) and its *server-derived* capabilities.
/// Capabilities are refreshed from the backend; nothing here grants privileges locally.
final class SessionService {
    private let auth: AuthRemote
    private let favorites: FavoriteRepository
    private let notifier: DataChangeNotifier
    private(set) var capabilities: UserCapabilities?
    private var starting: Task<Void, Error>?

    init(auth: AuthRemote, favorites: FavoriteRepository, notifier: DataChangeNotifier) {
        self.auth = auth
        self.favorites = favorites
        self.notifier = notifier
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

    func requestPhoneLink(rawPhone: String) async throws -> String {
        guard let e164 = PhoneNumberFormatter.e164(from: rawPhone) else { throw BackendError.invalidInput("invalid_phone") }
        try await auth.requestPhoneLink(phoneE164: e164)
        return e164
    }

    func confirmPhoneLink(phoneE164: String, code: String) async throws {
        let trimmed = code.filter(\.isNumber)
        guard (4...10).contains(trimmed.count) else { throw BackendError.invalidOTP }
        try await auth.confirmPhoneLink(phoneE164: phoneE164, code: trimmed)
        try await refresh()
    }

    func updateDisplayName(_ name: String) async throws {
        try await auth.updateDisplayName(name)
        try await refresh()
    }

    func signOut() async throws {
        try await auth.signOut()
        capabilities = nil
        favorites.reset()
        try await refresh()
    }
}
