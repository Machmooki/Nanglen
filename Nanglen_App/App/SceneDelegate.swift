//
//  SceneDelegate.swift
//  Nanglen_App
//
//  Created by Mach Suwanpatikorn on 8/11/2569 BE.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    /// The splash never waits longer than this for launch work, so a slow network can't hold the app back.
    private static let startupTimeout: Duration = .seconds(4)

    /// Main.storyboard creates the window and tab bar; we inject dependencies
    /// into each tab's root view controller before anything is displayed.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard scene is UIWindowScene,
              let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        let container = appDelegate.container
        AppStyles.applyGlobalAppearance(to: window)

        guard let tabBarController = window?.rootViewController as? UITabBarController else {
            assertionFailure("Main.storyboard's initial view controller must be the tab bar controller")
            return
        }
        for child in tabBarController.viewControllers ?? [] {
            let root = (child as? UINavigationController)?.viewControllers.first ?? child
            (root as? AppContainerConfigurable)?.configure(with: container)
        }

        // UI tests pass -NanglenSkipSplash so they don't wait for the intro.
        if let window, !ProcessInfo.processInfo.arguments.contains("-NanglenSkipSplash") {
            showSplash(in: window, startup: appDelegate.startupTask)
        }
    }

    /// Back from the background: retry photos that failed to upload while offline.
    func sceneWillEnterForeground(_ scene: UIScene) {
        (UIApplication.shared.delegate as? AppDelegate)?.container.pendingUploadService.trigger()
    }

    /// Covers the app with the animated splash, then fades it out once both the intro
    /// and the launch work have finished (the launch work is cut off at `startupTimeout`).
    private func showSplash(in window: UIWindow, startup: Task<Void, Never>?) {
        // Install the root view first, so the splash stays on top of it.
        window.makeKeyAndVisible()
        let splash = SplashView(frame: window.bounds)
        splash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(splash)

        let deadline = ContinuousClock.now + Self.startupTimeout
        Task {
            await splash.playIntro()
            if let startup {
                await Self.wait(for: startup, until: deadline)
            }
            await splash.dismiss()
        }
    }

    /// Returns when `task` finishes or `deadline` passes, whichever comes first. `task` itself keeps running.
    private static func wait(for task: Task<Void, Never>, until deadline: ContinuousClock.Instant) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let gate = ResumeOnce(continuation)
            Task {
                await task.value
                gate.resume()
            }
            Task {
                try? await Task.sleep(until: deadline)
                gate.resume()
            }
        }
    }
}

/// Resumes a continuation exactly once, however many racing callers there are.
private final class ResumeOnce {
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
