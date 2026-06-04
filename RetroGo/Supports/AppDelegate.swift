//
//  AppDelegate.swift
//  RetroGo
//
//  Created by haharsw on 2026/2/11.
//  Copyright © 2026 haharsw. All rights reserved.
//
//  ---------------------------------------------------------------------------------
//  This file is part of RetroGo.
//  ---------------------------------------------------------------------------------
//
//  RetroGo is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  RetroGo is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import UIKit
import ObjcHelper
import RACoordinator

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    /// Global orientation mask. Defaults to `.allButUpsideDown` so all
    /// pages support free rotation. `GamePageViewController` may narrow
    /// this further (e.g. lock to landscape) and must restore the default
    /// on disappear.
    ///
    /// Mutated only through `AppDelegate.setOrientationLock(_:)`.
    fileprivate(set) var orientationLock: UIInterfaceOrientationMask = .allButUpsideDown

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        RetroRomFileManager.shared.performDataMigrationIfNeeded()
        DebugDataLink.sync()

        let _ = AppStorePurchaseManager.shared
        let _ = RetroArchX.shared()
        let _ = OnDemandResourceLoader.shared

        configNavigationBarAppearance()

        return true
    }

    /// UIKit consults this per-window when deciding whether to rotate.
    /// We funnel everything through the single `orientationLock` so the
    /// answer is consistent across windows / scenes.
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return orientationLock
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

extension AppDelegate {
    /// Set the app-wide orientation mask and ask UIKit to re-evaluate the
    /// current geometry immediately so the change takes effect without
    /// waiting for the user to rotate the device.
    ///
    /// Call sites:
    /// - `GamePageViewController.viewWillDisappear` → `.allButUpsideDown` (restore default)
    /// - Future: game page landscape-lock button → `.landscape`
    ///
    /// Targets iOS 17+, so we use the modern scene geometry API
    /// exclusively. `UIViewController.attemptRotationToDeviceOrientation()`
    /// is deprecated in iOS 16; its replacement
    /// `setNeedsUpdateOfSupportedInterfaceOrientations()` is called on
    /// the topmost VC as a belt-and-suspenders hint.
    static func setOrientationLock(_ mask: UIInterfaceOrientationMask) {
        guard let delegate = UIApplication.shared.delegate as? AppDelegate else { return }
        delegate.orientationLock = mask

        // Per-scene geometry request. The error handler is intentionally
        // a no-op: failures occur when the requested mask is incompatible
        // with the current device orientation, which is fine — UIKit
        // picks a valid orientation from the new mask on its own.
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .forEach { scene in
                let pref = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
                scene.requestGeometryUpdate(pref) { _ in }

                // Tell the topmost VC that its effective supported
                // orientations may have changed, so any cached state
                // keyed off them gets refreshed.
                topViewController(of: scene)?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
    }

    /// Walk from a scene's key window down to the deepest presented VC.
    /// Used by `setOrientationLock` to find the right target for
    /// `setNeedsUpdateOfSupportedInterfaceOrientations()`.
    private static func topViewController(of scene: UIWindowScene) -> UIViewController? {
        let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? scene.windows.first?.rootViewController
        guard var vc = root else { return nil }
        while let presented = vc.presentedViewController {
            vc = presented
        }
        return vc
    }
}

extension AppDelegate {
    private func configNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        // Opaque background — prevents the iOS 15+ default transparent
        // scrollEdgeAppearance from making modal-presented navigation
        // controllers look different from pushed ones.
        appearance.configureWithOpaqueBackground()
        // Use systemBackground so dark/light mode is respected automatically.
        // The app currently forces .dark, so this resolves to black.
        appearance.backgroundColor = .systemBackground
        // Remove the hairline separator below the nav bar. The app's
        // pages use insetGrouped cards / sections that carry their own
        // visual separation, so the system hairline reads as a
        // redundant intrusive line — particularly visible against the
        // dark background where it appears as a gray streak.
        appearance.shadowColor = .clear

        let proxy = UINavigationBar.appearance()
        proxy.standardAppearance   = appearance
        proxy.scrollEdgeAppearance = appearance
        proxy.compactAppearance    = appearance
    }
}

extension UIApplication {
    var sceneDelegate: SceneDelegate? {
        return self.connectedScenes
            .first { $0.activationState == .foregroundActive }
            .flatMap { $0.delegate as? SceneDelegate }
    }
}
