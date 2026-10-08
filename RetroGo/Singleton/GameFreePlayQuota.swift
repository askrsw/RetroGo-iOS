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

/// Pro is unlimited play. Free users get a daily allowance per platform on that
/// platform's free core; the platform's other cores need Pro. Counters reset at
/// local midnight.
@MainActor
enum GameFreePlayQuota {
    static let dailyAllowance: TimeInterval = 10 * 60

    enum Access {
        case unlimited
        case limited
        case proOnly
    }

    /// The free core of each platform that has more than one; a platform with a
    /// single core uses that core.
    private static let freeCoreByPlatform: [String: String] = [
        "nes": "fceumm",
        "game_boy": "gambatte",
        "playstation": "pcsx-rearmed",
        "sega_saturn": "yabause",
    ]

    private static let dayKey = "free_play_day"
    private static let usedKey = "free_play_used_seconds"

    static func access(for core: EmuCoreInfoItem) -> Access {
        if AppStoreProFeatureGate.shared.isProUnlocked { return .unlimited }
        return isFreeCore(core) ? .limited : .proOnly
    }

    static func remainingToday(for core: EmuCoreInfoItem) -> TimeInterval {
        max(0, dailyAllowance - usedToday[platform(of: core), default: 0])
    }

    static func isExhausted(for core: EmuCoreInfoItem) -> Bool {
        switch access(for: core) {
        case .unlimited: return false
        case .proOnly: return true
        case .limited: return remainingToday(for: core) <= 0
        }
    }

    static func consume(_ seconds: TimeInterval, for core: EmuCoreInfoItem) {
        guard seconds > 0, access(for: core) == .limited else { return }
        var used = usedToday
        let key = platform(of: core)
        used[key] = min(dailyAllowance, used[key, default: 0] + seconds)
        let defaults = UserDefaults.standard
        defaults.set(today, forKey: dayKey)
        defaults.set(used, forKey: usedKey)
    }

    /// Launch check: returns true when the game may start. Otherwise explains why
    /// on the current page and offers Pro.
    static func allowLaunch(core: EmuCoreInfoItem) -> Bool {
        let message: String
        switch access(for: core) {
        case .unlimited:
            return true
        case .limited:
            guard remainingToday(for: core) <= 0 else { return true }
            message = dailyLimitMessage(for: core)
        case .proOnly:
            message = proOnlyMessage(for: core)
        }

        let alert = UIAlertController(
            title: Bundle.localizedString(forKey: "progate_alert_title"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "progate_unlock_pro"), style: .default) { _ in
            AppStoreProFeatureGate.shared.presentPurchasePage()
        })
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "progate_not_now"), style: .cancel))
        UIViewController.currentActive()?.present(alert, animated: true)
        return false
    }

    static func dailyLimitMessage(for core: EmuCoreInfoItem) -> String {
        let formatter = Bundle.localizedString(forKey: "progate_daily_limit_reached_format")
        return String(format: formatter, platformName(of: core))
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

    private static func isFreeCore(_ core: EmuCoreInfoItem) -> Bool {
        guard let freeCoreId = freeCoreByPlatform[platform(of: core)] else { return true }
        return core.coreId == freeCoreId
    }

    private static func platform(of core: EmuCoreInfoItem) -> String {
        core.systemID ?? core.coreId
    }

    private static func platformName(of core: EmuCoreInfoItem) -> String {
        core.systemName ?? core.displayName
    }

    private static var usedToday: [String: TimeInterval] {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: dayKey) == today else { return [:] }
        return defaults.dictionary(forKey: usedKey) as? [String: TimeInterval] ?? [:]
    }

    private static var today: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
