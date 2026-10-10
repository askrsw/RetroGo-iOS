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

        WhatsNewViewController.showIfNeeded()
        AppWelcomeViewController.showIfNeeded()
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

    /// Last size class pushed to the tabs, so layout passes don't reapply it.
    private var appliedChildSizeClass: UIUserInterfaceSizeClass?
    /// The "can't download offline resources" alert while it is on screen.
    private weak var networkDeniedAlert: UIAlertController?

    init() {
        super.init(nibName: nil, bundle: nil)
        delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(networkAccessDenied(_:)), name: .odrNetworkAccessDenied, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(networkAccessRestored), name: .odrNetworkAccessRestored, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        buildTabs()
        configureAppearance()
    }

    /// Covers every way the window can change width: rotation, iPad window
    /// resizing and folding/unfolding a foldable phone.
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        syncChildSizeClass()
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
        if #available(iOS 18.0, *) {
            mode = .tabBar
            if keepsTabBarAtBottom {
                // From iOS 18 UIKit moves the tab bar to the top whenever the
                // horizontal size class is regular, which on iPad leaves it
                // crowded right above each tab's navigation bar. RetroGo has no
                // sidebar to justify that layout, so the tab bar stays at the
                // bottom on every device, as it is on iPhone.
                traitOverrides.horizontalSizeClass = .compact
            }
            syncChildSizeClass()
        }

        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior = .automatic
            tabBar.isTranslucent = true
            tabBar.backgroundColor = .clear
        } else {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.shadowColor = .clear
            tabBar.tintColor = .mainColor

            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            tabBar.isTranslucent = false
        }
    }

    /// Whether the bottom tab bar is kept by overriding this controller's own
    /// size class. Only iOS 18 and later relocate the tab bar.
    var keepsTabBarAtBottom: Bool {
        guard #available(iOS 18.0, *) else { return false }
        return true
    }

    /// The size class the window really has. Reading it from the window keeps
    /// it free of the compact override applied to this controller, so a wide
    /// iPad window and an unfolded foldable phone both report `.regular`.
    var environmentSizeClass: UIUserInterfaceSizeClass {
        if let window = view.window {
            return window.traitCollection.horizontalSizeClass
        }
        // Before the view reaches a window, fall back to the regular-width
        // threshold UIKit itself uses.
        return view.bounds.width >= 768 ? .regular : .compact
    }

    /// Passes the real size class down to the tabs. Only this controller is
    /// pinned to compact; its children must keep adapting, otherwise a narrow
    /// window would still lay out as if it were full screen.
    func syncChildSizeClass() {
        guard keepsTabBarAtBottom, let viewControllers else { return }
        let sizeClass = environmentSizeClass
        guard sizeClass != appliedChildSizeClass else { return }
        appliedChildSizeClass = sizeClass
        viewControllers.forEach { controller in
            controller.traitOverrides.horizontalSizeClass = sizeClass
        }
    }
}

// MARK: - Tab assembly

private extension RetroGoTabBarController {
    func buildTabs() {
        viewControllers = [
            makeNav(
                root:          RetroRomFolderHostViewController(),
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

// MARK: - Offline resources without network access

private extension RetroGoTabBarController {

    /// RetroGo may not use the network (e.g. the system's WLAN & Cellular
    /// permission was declined), so resources it needs can't be downloaded.
    /// Name them, say what is unavailable, and offer the Settings app. The
    /// downloads start on their own once access is allowed.
    @objc
    func networkAccessDenied(_ note: Notification) {
        guard let missing = note.object as? [ODRResource], !missing.isEmpty else { return }
        let names = missing.map { $0.nativeName ?? Bundle.localizedString(forKey: $0.titleKey) }
            .joined(separator: Bundle.localizedString(forKey: "odr_list_separator"))
        let alert = UIAlertController(
            title: Bundle.localizedString(forKey: "odr_network_denied_title"),
            message: String(format: Bundle.localizedString(forKey: "odr_network_denied_msg_fmt"), names),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .cancel))
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "odr_network_denied_settings"), style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        networkDeniedAlert = alert
        (UIViewController.currentActive() ?? self).present(alert, animated: true)
    }

    /// Access came back (the downloads resume on their own): the alert no
    /// longer applies.
    @objc
    func networkAccessRestored() {
        guard let alert = networkDeniedAlert, alert.presentingViewController != nil else { return }
        alert.dismiss(animated: true)
    }
}
