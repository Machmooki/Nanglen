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

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Guest-first: restore the session or sign in anonymously. No sign-up screen, no location prompt.
        let session = container.session
        Task { try? await session.start() }
        // Server limits (private.app_settings). Cached values are already applied; this picks up edits.
        let remoteConfig = container.remoteConfig
        Task { await remoteConfig.refresh() }
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
