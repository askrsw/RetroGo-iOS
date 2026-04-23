//
//  GameConfigItem.swift
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

enum GameConfigScope: String {
    case global, core, game
}

enum GameConfigItemType {
    case core, game
    case logicThread, retroArchOverlay, spritkitOverlay
    case fastForwardMultiplier
}

typealias GameConfigGetBoolValue = () -> Bool
typealias GameConfigSetBoolValue = (Bool) -> Void

enum GameConfigSegmentItem {
    case text(String)
    case image(UIImage)
}
typealias GameConfigGetSegmentArray = () -> [GameConfigSegmentItem]
typealias GameConfigGetSegmentSelectedIndex = () -> Int
typealias GameConfigSetSegmentSelectedIndex = (Int) -> Void

class GameConfigItem: NSObject {
    let type: GameConfigItemType
    unowned let session: GameConfigSession
    init(type: GameConfigItemType, session: GameConfigSession) {
        self.type    = type
        self.session = session
        super.init()
    }

    var tip: String? {
        getTipString()
    }

    var desc: String? {
        getDescString()
    }

    var title: String? {
        if type == .core {
            return session.core?.coreName
        } else if type == .game {
            return session.game?.itemName
        } else {
            return nil
        }
    }

    var enabled: Bool = true

    var getBoolValue: GameConfigGetBoolValue?
    var setBoolValue: GameConfigSetBoolValue?

    var getSegmentArray: GameConfigGetSegmentArray?
    var getSegmentSelectedIndex: GameConfigGetSegmentSelectedIndex?
    var setSegmentSelectedIndex: GameConfigSetSegmentSelectedIndex?
}

extension GameConfigItem {
    private func getTipString() -> String? {
        switch self.type {
        case .core:
            return Bundle.localizedString(forKey: "configpage_core")
        case .game:
            return Bundle.localizedString(forKey: "configpage_rom")
        case .logicThread:
            return Bundle.localizedString(forKey: "configpage_game_thread")
        case .retroArchOverlay: return "RetroArch Overlay"
        case .spritkitOverlay: return "SpriteKit Overlay"
        case .fastForwardMultiplier:
            return Bundle.localizedString(forKey: "configpage_game_fast_multiplier")
        }
    }

    private func getDescString() -> String? {
        switch self.type {
        case .logicThread:
                if let core = session.core {
                    if core.supportsLogicThread {
                        return Bundle.localizedString(forKey: "configpage_game_thread_desc")
                    } else {
                        let formatter = Bundle.localizedString(forKey: "configpage_game_thread_forbiden_desc")
                        let string = String(format: formatter, core.coreName)
                        return string
                    }
                } else {
                    return Bundle.localizedString(forKey: "configpage_game_thread_desc")
                }
        default:
            return nil
        }
    }
}
