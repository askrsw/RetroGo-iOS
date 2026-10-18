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
import RACoordinator
import os

/// Features free users get a limited amount of. Playing itself is never
/// time-limited; see `GameFreePlayQuota` for which cores are free.
enum AppStoreProFeature {
    case cheats
    case fastForward
    case manualSaveSlot
    case saveStateOverwrite
    case controllerMapping
    case overlayLayout
    case overlayLayoutEditing
    case overlayLayoutSelection

    var lockedMessage: String {
        switch self {
        case .cheats:
            return Bundle.localizedString(forKey: "progate_cheats_locked")
        case .fastForward:
            return Bundle.localizedString(forKey: "progate_fast_forward_locked")
        case .manualSaveSlot:
            let format = Bundle.localizedString(forKey: "progate_manual_save_slot_locked_format")
            return String(format: format, AppStoreProFeaturePolicy.freeManualSavesPerGame)
        case .saveStateOverwrite:
            return Bundle.localizedString(forKey: "progate_save_overwrite_locked")
        case .controllerMapping:
            return Bundle.localizedString(forKey: "progate_controller_mapping_locked")
        case .overlayLayout:
            return Bundle.localizedString(forKey: "progate_overlay_layout_locked")
        case .overlayLayoutEditing:
            return Bundle.localizedString(forKey: "progate_overlay_layout_editing_locked")
        case .overlayLayoutSelection:
            return Bundle.localizedString(forKey: "progate_overlay_layout_selection_locked")
        }
    }
}

enum AppStoreProGatePresentation {
    case silent
    case toast
    case alert
    case purchasePage
}

/// What free users get. The limits only stop adding more: anything made or
/// switched on before (1.10.0 to 1.13.0 left everything open) keeps working.
/// Fast-forward is the exception: free users cannot use it at all.
enum AppStoreProFeaturePolicy {
    /// Cheats switched on at once in one game, user cheats and templates together.
    /// None: browsing, searching and editing cheats stay free, switching one on needs Pro.
    static let freeCheatsPerGame = 0
    /// Manual save slots per game; auto saves do not count. Overwriting a save
    /// needs Pro, so free users delete one to make room.
    static let freeManualSavesPerGame = 3
    /// Custom on-screen control layouts per platform and device class.
    static let freeOverlayLayoutsPerPlatform = 1

    static func sanitizedFastForwardMultiplier(_ multiplier: Double) -> Double {
        guard multiplier.isFinite else { return 2.0 }
        return max(1.0, min(multiplier, 6.0))
    }
}

@MainActor
final class AppStoreProFeatureGate {
    static let shared = AppStoreProFeatureGate()

    private init() { }

    private weak var visibleLockedAlert: UIAlertController?

    var isProUnlocked: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return AppStorePurchaseManager.shared.isProPurchased
        #endif
    }

    /// Whether fast-forward may run. Read from the game and input paths, so it
    /// uses the cached entitlement.
    nonisolated static var canFastForward: Bool {
        AppStorePurchaseManager.hasLocallyValidCachedProEntitlement
    }

    private nonisolated static let fastForwardNoticeShown = OSAllocatedUnfairLock(initialState: false)

    /// Lets the next refused fast-forward explain itself again; call when a game starts.
    nonisolated static func resetFastForwardNotice() {
        fastForwardNoticeShown.withLock { $0 = false }
    }

    /// The fast-forward speed to run at: the saved speed with Pro, 1 (no
    /// fast-forward) without it. The saved speed is never rewritten. A refusal
    /// is explained once per game in the game's own message area, without the
    /// alert, since a held controller button would raise it again and again.
    nonisolated static func effectiveFastForwardMultiplierForRuntime(_ requestedMultiplier: Double, shouldNotify: Bool = true) -> Double {
        let requested = AppStoreProFeaturePolicy.sanitizedFastForwardMultiplier(requestedMultiplier)
        guard !canFastForward else { return requested }

        let firstNotice = fastForwardNoticeShown.withLock { shown in
            defer { shown = true }
            return !shown
        }
        if shouldNotify, firstNotice {
            RetroGoLogger.game.info("Fast-forward refused without Pro")
            let message = EmuInGameMessage(message: AppStoreProFeature.fastForward.lockedMessage,
                                           title: nil, type: .info, duration: 3, priority: 0)
            NotificationCenter.default.post(name: .showInGameMessage, object: message)
        }
        return 1.0
    }

    /// Runs `allowed` and returns true with Pro; otherwise tells the user the
    /// way `presentation` says and returns false.
    @discardableResult
    func requirePro(
        feature: AppStoreProFeature,
        presentation: AppStoreProGatePresentation = .alert,
        from viewController: UIViewController? = nil,
        toastContext: AppToastContext = .ui,
        allowed: (() -> Void)? = nil
    ) -> Bool {
        guard !isProUnlocked else {
            allowed?()
            return true
        }

        RetroGoLogger.iap.info("Pro needed for \(String(describing: feature), privacy: .public)")
        switch presentation {
        case .silent:
            break
        case .toast:
            AppToastManager.shared.toast(feature.lockedMessage, context: toastContext, level: .info)
        case .alert:
            showAlert(feature: feature, from: viewController)
        case .purchasePage:
            presentPurchasePage(from: viewController)
        }
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
    func showAlert(feature: AppStoreProFeature, from viewController: UIViewController?) {
        guard visibleLockedAlert == nil else { return }

        guard let presenter = resolvedPresenter(from: viewController) else {
            AppToastManager.shared.toast(feature.lockedMessage, context: .ui, level: .info)
            return
        }

        guard !(presenter is UIAlertController), !isPurchasePageVisible(from: presenter) else { return }

        let formatter = Bundle.localizedString(forKey: "progate_alert_message_format")
        let alert = UIAlertController.gamePausedAlert(
            title: Bundle.localizedString(forKey: "progate_alert_title"),
            message: String(format: formatter, feature.lockedMessage)
        )

        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "progate_unlock_pro"), style: .default) { [weak self, weak presenter, weak alert] _ in
            // Hold the dismissed alert strongly: nothing else keeps it alive past the
            // yield, and its pause lease would leak with it, freezing the game.
            guard let alert else { return }
            Task { @MainActor [weak self, weak presenter] in
                self?.visibleLockedAlert = nil
                await Task.yield()
                // The purchase page takes its own pause lease before this one goes.
                self?.presentPurchasePage(from: presenter)
                alert.releaseGamePauseIfNeeded()
            }
        })

        let cancelTitle: String
        switch feature {
        case .overlayLayout, .overlayLayoutEditing, .overlayLayoutSelection:
            cancelTitle = Bundle.localizedString(forKey: "cancel")
        default:
            cancelTitle = Bundle.localizedString(forKey: "progate_not_now")
        }
        alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { [weak self, weak alert] _ in
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
