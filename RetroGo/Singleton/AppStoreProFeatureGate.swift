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

enum AppStoreProFeature {
    case cheats
    case fastForward
    case manualSaveSlot
    case controllerMapping
    case advancedConfiguration

    var lockedMessage: String {
        switch self {
        case .cheats:
            return Bundle.localizedString(forKey: "progate_cheats_locked")
        case .fastForward:
            return Bundle.localizedString(forKey: "progate_fast_forward_locked")
        case .manualSaveSlot:
            return Bundle.localizedString(forKey: "progate_manual_save_slot_locked")
        case .controllerMapping:
            return Bundle.localizedString(forKey: "progate_controller_mapping_locked")
        case .advancedConfiguration:
            return Bundle.localizedString(forKey: "progate_advanced_configuration_locked")
        }
    }
}

enum AppStoreProGatePresentation {
    case silent
    case toast
    case alert
    case purchasePage
}

enum AppStoreProFeaturePolicy {
    static let freeFastForwardMultiplier = 2.0
    static let fastForwardMultiplierEpsilon = 0.01

    static func sanitizedFastForwardMultiplier(_ multiplier: Double) -> Double {
        guard multiplier.isFinite else { return freeFastForwardMultiplier }
        return max(1.0, min(multiplier, 6.0))
    }
}

@MainActor
final class AppStoreProFeatureGate {
    static let shared = AppStoreProFeatureGate()

    private init() { }

    private weak var visibleLockedAlert: UIAlertController?

    var isProUnlocked: Bool {
        AppStorePurchaseManager.shared.isProPurchased
    }

    nonisolated static func effectiveFastForwardMultiplierForRuntime(_ requestedMultiplier: Double, shouldNotify: Bool = true) -> Double {
        let requested = AppStoreProFeaturePolicy.sanitizedFastForwardMultiplier(requestedMultiplier)
        let freeLimit = AppStoreProFeaturePolicy.freeFastForwardMultiplier
        let epsilon = AppStoreProFeaturePolicy.fastForwardMultiplierEpsilon

        guard requested > freeLimit + epsilon else {
            return requested
        }

        guard !AppStorePurchaseManager.hasLocallyValidCachedProEntitlement else {
            return requested
        }

        if shouldNotify {
            AppToastManager.shared.toast(AppStoreProFeature.fastForward.lockedMessage, context: .game, level: .info)
        }

        return freeLimit
    }

    @discardableResult
    func requirePro(
        feature: AppStoreProFeature,
        presentation: AppStoreProGatePresentation,
        from viewController: UIViewController? = nil,
        toastContext: AppToastContext = .ui,
        allowed: (() -> Void)? = nil
    ) -> Bool {
        guard !isProUnlocked else {
            allowed?()
            return true
        }

        handleLockedFeature(
            feature,
            presentation: presentation,
            from: viewController,
            toastContext: toastContext
        )
        return false
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
    func handleLockedFeature(
        _ feature: AppStoreProFeature,
        presentation: AppStoreProGatePresentation,
        from viewController: UIViewController?,
        toastContext: AppToastContext
    ) {
        switch presentation {
        case .silent:
            break
        case .toast:
            showToast(feature: feature, context: toastContext)
        case .alert:
            showAlert(feature: feature, from: viewController)
        case .purchasePage:
            presentPurchasePage(from: viewController)
        }
    }

    func showToast(feature: AppStoreProFeature, context: AppToastContext) {
        AppToastManager.shared.toast(feature.lockedMessage, context: context, level: .info)
    }

    func showAlert(feature: AppStoreProFeature, from viewController: UIViewController?) {
        if visibleLockedAlert != nil {
            return
        }

        guard let presenter = resolvedPresenter(from: viewController) else {
            showToast(feature: feature, context: .ui)
            return
        }

        guard !(presenter is UIAlertController) else {
            return
        }

        guard !isPurchasePageVisible(from: presenter) else {
            return
        }

        let formatter = Bundle.localizedString(forKey: "progate_alert_message_format")
        let message = String(format: formatter, feature.lockedMessage)
        let alert = UIAlertController.gamePausedAlert(
            title: Bundle.localizedString(forKey: "progate_alert_title"),
            message: message
        )

        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "progate_unlock_pro"), style: .default) { [weak self, weak presenter, weak alert] _ in
            alert?.releaseGamePauseIfNeeded()
            Task { @MainActor [weak self, weak presenter] in
                self?.visibleLockedAlert = nil
                await Task.yield()
                self?.presentPurchasePage(from: presenter)
            }
        })

        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "progate_not_now"), style: .cancel) { [weak self, weak alert] _ in
            alert?.releaseGamePauseIfNeeded()
            self?.visibleLockedAlert = nil
        })

        visibleLockedAlert = alert
        presenter.present(alert, animated: true)
    }

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
