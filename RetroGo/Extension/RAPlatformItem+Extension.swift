//
//  RAPlatformItem+Extension.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/22.
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

import RACoordinator

extension RAPlatformItem {
    /// Explicit mapping from the RDB file basename to a UI icon key. Keys
    /// must match the file names under `Resources/OnDemandRDBs/` (without
    /// the `.rdb` extension); no fuzzy matching on display name.
    var platformIcon: IconRender.PlatformIconKey? {
        switch rdbName {
        case "DOS":                                              return .dos
        case "MAME":                                             return .mame
        case "Nintendo - Family Computer Disk System":           return .fds
        case "Nintendo - Game Boy":                              return .gb
        case "Nintendo - Game Boy Advance":                      return .gba
        case "Nintendo - Game Boy Color":                        return .gbc
        case "Nintendo - Nintendo 64":                           return .n64
        case "Nintendo - Nintendo DS":                           return .ds
        case "Nintendo - Nintendo Entertainment System":         return .nes
        case "Nintendo - Super Nintendo Entertainment System":   return .snes
        case "Sega - Saturn":                                    return .saturn
        case "Sony - PlayStation":                               return .psx
        case "Sony - PlayStation Portable":                      return .psp
        default:                                                 return nil
        }
    }
}
