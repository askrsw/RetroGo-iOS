//
//  RetroGoTabBarController.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/23.
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

// MARK: - Navigation controller

/// A UINavigationController that owns its own large-title configuration
/// rather than inheriting from the global `UINavigationBar.appearance()`
/// proxy in `AppDelegate`.
///
/// The global proxy is applied lazily at unpredictable points in the view
/// lifecycle and can clobber `prefersLargeTitles` settings made earlier.
/// Configuring the appearance + `prefersLargeTitles` together on each
/// nav bar — in `viewDidLoad`, which runs before the proxy has a chance
/// to interfere — sidesteps the race entirely.
private final class RetroGoNavigationController: UINavigationController {

    override func viewDidLoad() {
        super.viewDidLoad()
        installAppearance()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Re-assert on every appearance so a tab switch can't leave us
        // with a stale collapsed state. Toggle off→on forces UIKit to
        // discard cached layout — `= true` when already `true` is a no-op.
        navigationBar.prefersLargeTitles = false
        navigationBar.prefersLargeTitles = true
        navigationBar.setNeedsLayout()
    }

    private func installAppearance() {
        // Standard / compact: opaque black, keeps the nav bar from going
        // translucent over scrolled content.
        let opaque = UINavigationBarAppearance()
        opaque.configureWithOpaqueBackground()
        opaque.backgroundColor = .systemBackground
        opaque.shadowColor     = .clear

        // Scroll edge (also used for the large-title state): **transparent**.
        // When the scroll-edge appearance is opaque and identical to the
        // standard appearance, iOS 15+ optimizes by not rendering the
        // large-title area at all. Keeping scroll-edge transparent restores
        // the large title; visually it still looks black because the view
        // background underneath is `.systemBackground`.
        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        scrollEdge.shadowColor = .clear

        navigationBar.standardAppearance   = opaque
        navigationBar.compactAppearance    = opaque
        navigationBar.scrollEdgeAppearance = scrollEdge
        navigationBar.prefersLargeTitles   = true
    }
}

// MARK: - Tab bar controller

/// Root navigation container for RetroGo.
///
/// Hosts three tabs:
/// - **Library** — `HomePageViewController` (the ROM file browser)
/// - **Discover** — `DiscoverPlatformViewController` (game database)
/// - **Settings** — `AppSettingViewController` (app preferences)
///
/// Each tab is wrapped in its own `UINavigationController` so push
/// navigation within a tab doesn't affect the others.
final class RetroGoTabBarController: UITabBarController {

    init() {
        super.init(nibName: nil, bundle: nil)
        delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureAppearance()
        buildTabs()
    }
}

// MARK: - Appearance

private extension RetroGoTabBarController {

    /// Refresh the tab bar item titles when the user switches the in-app
    /// language. The tab order is fixed by `buildTabs()`, so we re-apply
    /// the same localization keys in the same order. Each tab's nav bar
    /// large title is the responsibility of that tab's root VC — it
    /// observes `.languageChanged` independently.
    @objc
    func languageChanged() {
        let keys = ["tab_library", "tab_discover", "tab_settings"]
        zip(viewControllers ?? [], keys).forEach { vc, key in
            vc.tabBarItem.title = Bundle.localizedString(forKey: key)
        }
    }

    func configureAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        tabBar.standardAppearance   = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = .mainColor
    }
}

// MARK: - Tab assembly

private extension RetroGoTabBarController {

    func buildTabs() {
        viewControllers = [
            makeNav(
                root:          HomePageViewController(),
                title:         Bundle.localizedString(forKey: "tab_library"),
                image:         UIImage(systemName: "books.vertical"),
                selectedImage: UIImage(systemName: "books.vertical.fill")
            ),
            makeNav(
                root:          DiscoverPlatformViewController(),
                title:         Bundle.localizedString(forKey: "tab_discover"),
                image:         UIImage(systemName: "safari"),
                selectedImage: UIImage(systemName: "safari.fill")
            ),
            makeNav(
                root:          AppSettingViewController(),
                title:         Bundle.localizedString(forKey: "tab_settings"),
                image:         UIImage(systemName: "gearshape"),
                selectedImage: UIImage(systemName: "gearshape.fill")
            )
        ]
    }

    func makeNav(
        root:          UIViewController,
        title:         String,
        image:         UIImage?,
        selectedImage: UIImage?
    ) -> UINavigationController {
        root.tabBarItem = UITabBarItem(title: title, image: image, selectedImage: selectedImage)
        let nav = RetroGoNavigationController(rootViewController: root)
        nav.navigationBar.prefersLargeTitles = true
        return nav
    }
}

// MARK: - UITabBarControllerDelegate

extension RetroGoTabBarController: UITabBarControllerDelegate {

    /// Fires only when the user taps a *different* tab — UIKit suppresses
    /// the callback when re-tapping the already-selected tab and when the
    /// selection is changed programmatically. So a single haptic per
    /// genuine tab switch, no spurious buzzes.
    func tabBarController(
        _ tabBarController: UITabBarController,
        didSelect viewController: UIViewController
    ) {
        Vibration.selection.vibrate()
    }
}

