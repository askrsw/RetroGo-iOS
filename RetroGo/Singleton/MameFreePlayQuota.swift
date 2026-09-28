//
//  MameFreePlayQuota.swift
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

/// Running the MAME core is a Pro feature as a whole. Free users get a daily
/// play allowance; the counter resets at local midnight.
@MainActor
enum MameFreePlayQuota {
    static let dailyAllowance: TimeInterval = 10 * 60

    private static let dayKey = "mame_free_play_day"
    private static let usedKey = "mame_free_play_used_seconds"

    static func isMame(_ core: EmuCoreInfoItem) -> Bool {
        core.coreId == MameImportScreener.mameCoreId
    }

    static var isUnlimited: Bool {
        AppStoreProFeatureGate.shared.isProUnlocked
    }

    static var usedToday: TimeInterval {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: dayKey) == today else { return 0 }
        return defaults.double(forKey: usedKey)
    }

    static var remainingToday: TimeInterval {
        max(0, dailyAllowance - usedToday)
    }

    static var isExhausted: Bool {
        !isUnlimited && remainingToday <= 0
    }

    static func consume(_ seconds: TimeInterval) {
        guard seconds > 0, !isUnlimited else { return }
        let defaults = UserDefaults.standard
        let used = min(dailyAllowance, usedToday + seconds)
        defaults.set(today, forKey: dayKey)
        defaults.set(used, forKey: usedKey)
    }

    /// Launch check: returns true when the game may start. Otherwise shows the
    /// "time is up" alert on the current page.
    static func allowLaunch(core: EmuCoreInfoItem) -> Bool {
        guard isMame(core), isExhausted else { return true }
        let alert = UIAlertController(
            title: Bundle.localizedString(forKey: "progate_alert_title"),
            message: Bundle.localizedString(forKey: "progate_mame_daily_limit_reached"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "progate_unlock_pro"), style: .default) { _ in
            AppStoreProFeatureGate.shared.presentPurchasePage()
        })
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "progate_not_now"), style: .cancel))
        UIViewController.currentActive()?.present(alert, animated: true)
        return false
    }

    private static var today: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
