//
//  DefaultKeys.swift
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

extension Defaults.Keys {
    static let systemHomePage = Key<Bool?>("system_home_page")
    static let languageFollowSystem = Key<Bool?>("language_follow_system")
    static let homeFileSortType = Key<Int?>("home_file_sort_type")
    static let homeCurrentFolder = Key<String?>("home_current_folder")
    static let homeBrowserType = Key<Int?>("home_browser_type")
    static let homeOrganizeType = Key<Int?>("home_organize_type")
    static let autoSaveLoadState = Key<Bool?>("auto_save_load_state")
    static let lastRateTime = Key<Date?>("last_rate_time")
    static let isUIFeedbackEnabled = Key<Bool?>("is_ui_feedback_enabled")
}
