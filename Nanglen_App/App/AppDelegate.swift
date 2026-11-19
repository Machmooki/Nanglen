//
//  AppDelegate.swift
//  Nanglen_App
//
//  Created by Mach Suwanpatikorn on 8/11/2569 BE.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    /// Built once per process and shared by all scenes.
    private(set) lazy var container = AppContainer.live()

    /// Launch work that runs in the background: finishes when both the session and the server config
    /// are ready (or have failed). The splash screen waits for it, up to its own timeout.
    private(set) var startupTask: Task<Void, Never>?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Guest-first: restore the session or sign in anonymously. No sign-up screen, no location prompt.
        let session = container.session
        let sessionStart = Task { try? await session.start() }
        // Server limits (private.app_settings). Cached values are already applied; this picks up edits.
        let remoteConfig = container.remoteConfig
        let configRefresh = Task { await remoteConfig.refresh() }
        // Cache eviction runs in the background; queued photos are retried once the session is up
        // (`PendingUploadService` listens for `.sessionChanged`).
        container.startMaintenance()
        startupTask = Task {
            _ = await sessionStart.value
            await configRefresh.value
        }
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
