//
//  SceneDelegate.swift
//  Nanglen_App
//
//  Created by Mach Suwanpatikorn on 8/11/2569 BE.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

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
    }
}
