import Foundation
import os

/// Server-driven limits (`get_public_config()` ← `private.app_settings`) merged over `AppConfiguration` defaults.
///
/// Launch: the last cached server values are applied synchronously, so the first screen already uses them.
/// Then `refresh()` fetches fresh values, caches them, and publishes `.configurationChanged`.
/// Offline: cached values, or the built-in defaults on a first launch.
final class RemoteConfigService {
    private(set) var current: AppConfiguration
    private(set) var remoteValues: RemoteConfigValues?
    private let base: AppConfiguration
    private let remote: ConfigRemote
    private let cache: RemoteConfigCaching
    private let notifier: DataChangeNotifier?
    private var refreshTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "Mach.Nanglen-App", category: "RemoteConfig")

    init(base: AppConfiguration, remote: ConfigRemote, cache: RemoteConfigCaching, notifier: DataChangeNotifier? = nil) {
        self.base = base
        self.remote = remote
        self.cache = cache
        self.notifier = notifier
        if let cached = cache.cachedRemoteConfig() {
            remoteValues = cached
            current = base.merged(with: cached)
        } else {
            current = base
        }
    }

    /// Fetches the server config once (concurrent calls share the same request). Failures keep the current values.
    func refresh() async {
        if let refreshTask { return await refreshTask.value }
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let values = try await remote.publicConfig()
                apply(values)
                cache.storeRemoteConfig(values)
            } catch {
                logger.notice("Remote config unavailable, using \(self.remoteValues == nil ? "defaults" : "cached values", privacy: .public)")
            }
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    func apply(_ values: RemoteConfigValues) {
        guard values != remoteValues else { return }
        remoteValues = values
        current = base.merged(with: values)
        notifier?.publish(.configurationChanged)
    }
}

/// Where the last server config is kept between launches (GRDB `app_kv` in the app).
protocol RemoteConfigCaching: AnyObject {
    func cachedRemoteConfig() -> RemoteConfigValues?
    func storeRemoteConfig(_ values: RemoteConfigValues)
}

/// In-memory cache for tests and previews.
final class InMemoryRemoteConfigCache: RemoteConfigCaching {
    var values: RemoteConfigValues?
    init(values: RemoteConfigValues? = nil) { self.values = values }
    func cachedRemoteConfig() -> RemoteConfigValues? { values }
    func storeRemoteConfig(_ values: RemoteConfigValues) { self.values = values }
}

/// Adapts `LocalCache` (thread-safe, synchronous read at launch).
final class LocalRemoteConfigCache: RemoteConfigCaching {
    private let cache: LocalCache
    init(cache: LocalCache) { self.cache = cache }
    func cachedRemoteConfig() -> RemoteConfigValues? { cache.cachedRemoteConfig() }
    func storeRemoteConfig(_ values: RemoteConfigValues) {
        let cache = cache
        Task { try? await cache.storeRemoteConfig(values) }
    }
}
