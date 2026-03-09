//
//  AppSettings.swift
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

import Defaults
import Foundation

final class AppSettings {
    static let shared = AppSettings()
    private init() {
        self.systemHomePage       = Defaults[.systemHomePage] ?? false
        self.languageFollowSystem = Defaults[.languageFollowSystem] ?? true
        self.autoSaveLoadState    = Defaults[.autoSaveLoadState] ?? true
        self.isUIFeedbackEnabled  = Defaults[.isUIFeedbackEnabled] ?? true
    }

    var systemHomePage: Bool {
        didSet {
            Defaults[.systemHomePage] = systemHomePage
        }
    }

    var languageFollowSystem: Bool {
        didSet {
            Defaults[.languageFollowSystem] = languageFollowSystem
        }
    }

    var autoSaveLoadState: Bool {
        didSet {
            Defaults[.autoSaveLoadState] = autoSaveLoadState
        }
    }

    var isUIFeedbackEnabled: Bool {
        didSet {
            Defaults[.isUIFeedbackEnabled] = isUIFeedbackEnabled
        }
    }

    func checkAndMarkRatingRequest() -> Bool {
        let now = Date()
        if let lastRateTime = Defaults[.lastRateTime] {
            if now.timeIntervalSince(lastRateTime) < 3600 * 24 {
                return false
            }
        }
        Defaults[.lastRateTime] = now
        return true
    }
}
