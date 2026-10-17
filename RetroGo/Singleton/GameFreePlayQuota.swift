//
//  GameFreePlayQuota.swift
//  RetroGo
//
//  Created by haharsw on 2026/9/29.
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

/// Playing is never time-limited. Each platform has one free core; the
/// platform's other cores need Pro.
@MainActor
enum GameFreePlayQuota {
    enum Access {
        case unlimited
        case free
        case proOnly
    }

    /// The free core of each platform that has more than one; a platform with a
    /// single core uses that core.
    nonisolated private static let freeCoreByPlatform: [String: String] = [
        "nes": "fceumm",
        "game_boy": "gambatte",
        "game_boy_advance": "vbam",
        "playstation": "pcsx-rearmed",
        "sega_saturn": "yabause",
    ]

    /// Daily play-time counters of 1.10.0 to 1.13.0 (and the MAME-only one before).
    private static let legacyUsageKeys = [
        "free_play_day",
        "free_play_used_seconds",
        "mame_free_play_day",
        "mame_free_play_used_seconds",
    ]

    static func access(for core: EmuCoreInfoItem) -> Access {
        if AppStoreProFeatureGate.shared.isProUnlocked { return .unlimited }
        return isFreeCore(core) ? .free : .proOnly
    }

    /// Launch check: returns true when the game may start. Otherwise explains why
    /// on the current page and offers Pro.
    static func allowLaunch(core: EmuCoreInfoItem) -> Bool {
        guard access(for: core) == .proOnly else { return true }

        let alert = UIAlertController(
            title: Bundle.localizedString(forKey: "progate_alert_title"),
            message: proOnlyMessage(for: core),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "progate_unlock_pro"), style: .default) { _ in
            AppStoreProFeatureGate.shared.presentPurchasePage()
        })
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "progate_not_now"), style: .cancel))
        UIViewController.currentActive()?.present(alert, animated: true)
        return false
    }

    /// Drops the play-time counters older versions kept.
    static func removeLegacyUsage() {
        let defaults = UserDefaults.standard
        for key in legacyUsageKeys where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
        }
    }

    private static func proOnlyMessage(for core: EmuCoreInfoItem) -> String {
        let freeCoreId = freeCoreByPlatform[platform(of: core)]
        let freeCore = RetroArchX.shared().allCores.first { $0.coreId == freeCoreId }
        guard let freeCore else {
            return String(format: Bundle.localizedString(forKey: "progate_core_requires_pro_format"), core.displayName)
        }
        let formatter = Bundle.localizedString(forKey: "progate_core_requires_pro_with_free_format")
        return String(format: formatter, core.displayName, freeCore.displayName)
    }

    /// Automatic launches prefer a free core for every user. Keep candidate
    /// order as the tie-breaker, independent of StoreKit entitlement updates.
    nonisolated static func preferredDefaultCore(in cores: [EmuCoreInfoItem]) -> EmuCoreInfoItem? {
        cores.first(where: isFreeCore) ?? cores.first
    }

    nonisolated private static func isFreeCore(_ core: EmuCoreInfoItem) -> Bool {
        guard let freeCoreId = freeCoreByPlatform[platform(of: core)] else { return true }
        return core.coreId == freeCoreId
    }

    nonisolated private static func platform(of core: EmuCoreInfoItem) -> String {
        core.systemID ?? core.coreId
    }
}
