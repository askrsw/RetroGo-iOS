//
//  AppStoreProFeatureGate.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/14.
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

/// Pro is sold as unlimited play: every feature is open to everyone, and free
/// users are only limited in play time (see `GameFreePlayQuota`).
@MainActor
final class AppStoreProFeatureGate {
    static let shared = AppStoreProFeatureGate()

    private init() { }

    var isProUnlocked: Bool {
        AppStorePurchaseManager.shared.isProPurchased
    }

    func presentPurchasePage(from viewController: UIViewController? = nil) {
        guard let presenter = resolvedPresenter(from: viewController) else { return }
        guard !isPurchasePageVisible(from: presenter) else { return }

        let controller = AppStorePurchaseViewController()
        let navigationController = UINavigationController(rootViewController: controller)
        presenter.present(navigationController, animated: true)
    }
}

private extension AppStoreProFeatureGate {
    func resolvedPresenter(from viewController: UIViewController?) -> UIViewController? {
        var current = viewController ?? UIViewController.currentActive()

        while let presented = current?.presentedViewController {
            current = presented
        }

        if let navigationController = current as? UINavigationController {
            return navigationController.visibleViewController ?? navigationController
        }

        if let tabBarController = current as? UITabBarController {
            return tabBarController.selectedViewController ?? tabBarController
        }

        return current
    }

    func isPurchasePageVisible(from viewController: UIViewController) -> Bool {
        if viewController is AppStorePurchaseViewController {
            return true
        }

        if let navigationController = viewController as? UINavigationController {
            return navigationController.viewControllers.contains { $0 is AppStorePurchaseViewController }
        }

        if let presented = viewController.presentedViewController {
            return isPurchasePageVisible(from: presented)
        }

        return false
    }
}
