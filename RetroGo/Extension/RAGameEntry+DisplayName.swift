//
//  RAGameEntry+DisplayName.swift
//  RetroGo
//
//  Created by haharsw on 2026/6/11.
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

import Foundation
import ObjcHelper
import RACoordinator

extension RAGameEntry {

    /// English RDB/No-Intro name remains the canonical name for matching,
    /// cover cache keys and ROM metadata. Only UI labels should use this value.
    var localizedDisplayName: String {
        guard Bundle.currentSimpleLanguageKey() == "zh",
              let localizedName,
              !localizedName.isEmpty
        else {
            return name
        }
        return localizedName
    }

    /// Variant rows share one localized group name in gameloc.sqlite. When a
    /// concrete variant is shown, preserve the authoritative RDB suffix so
    /// "(USA) (Proto) (Level 3)" and similar variants remain distinguishable.
    var localizedDisplayNameWithVariantSuffix: String {
        let displayName = localizedDisplayName
        guard displayName != name,
              let groupName,
              !groupName.isEmpty,
              name.hasPrefix(groupName)
        else {
            return displayName
        }

        let suffix = String(name.dropFirst(groupName.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suffix.isEmpty else { return displayName }
        return "\(displayName) \(suffix)"
    }

    /// Secondary title for detail surfaces. Chinese UI shows the authoritative
    /// English name when the primary title has been localized.
    var authoritativeEnglishNameForDisplay: String? {
        guard localizedDisplayName != name else { return nil }
        return name
    }
}
