//
//  GameConfigSection.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/18.
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

import ObjcHelper
import RACoordinator

enum GameConfigSection: Hashable {
    case title
    case restartRequired
    case overlay
}

extension GameConfigSection {
    func getSectionFooterText(session: GameConfigSession) -> String? {
        switch self {
        case .title:
            if session.scope == .core, let core = session.core {
                let formatter = Bundle.localizedString(forKey: "configpage_title_section_core_footer")
                return String(format: formatter, core.coreName)
            } else if session.scope == .game, let game = session.game {
                let formatter = Bundle.localizedString(forKey: "configpage_title_section_game_footer")
                return String(format: formatter, game.itemName)
            }
        case .restartRequired:
            return Bundle.localizedString(forKey: "configpage_restart_required_section_footer")
        default:
            return nil
        }
        return nil
    }
}
