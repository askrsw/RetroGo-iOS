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

extension GameConfigSection {
    static func makeConfigData(session: GameConfigSession) -> (sections: [GameConfigSection], items: [[GameConfigItem]]) {
        var sections: [GameConfigSection] = []
        var items: [[GameConfigItem]] = []

        let titleItems = makeTitleItems(session: session)
        if titleItems.count > 0 {
            sections.append(.title)
            items.append(titleItems)
        }

        let restartRequiredItems = makeRestartRequiredItems(session: session)
        if restartRequiredItems.count > 0 {
            sections.append(.restartRequired)
            items.append(restartRequiredItems)
        }

        let overlayItems = makeOverlayItems(session: session)
        if overlayItems.count > 0 {
            sections.append(.overlay)
            items.append(overlayItems)
        }

        return (sections: sections, items: items)
    }

    private static func makeTitleItems(session: GameConfigSession) -> [GameConfigItem] {
        switch session.scope {
            case .game:
                return [
                    GameConfigItem(type: .game, session: session),
                    GameConfigItem(type: .core, session: session)
                ]
            case .core:
                return [ GameConfigItem(type: .core, session: session) ]
            case .global:
                return []
        }
    }

    private static func makeRestartRequiredItems(session: GameConfigSession) -> [GameConfigItem] {
        var items = [GameConfigItem]()

        if session.scope != .global {
            let item = makeBoolItem(type: .logicThread, session: session, get: {
                session.getLogicThreadEnabled()
            }, set: { v in
                session.setLogicThreadEnabled(value: v)
            }, enabled: session.core?.supportsLogicThread ?? true)
            items.append(item)
        }

        if false, session.scope == .game {
            let item1 = makeBoolItem(type: .retroArchOverlay, session: session) {
                GamePageViewController.instance?.useRetroArchOverlay ?? false
            } set: { v in
                GamePageViewController.instance?.useRetroArchOverlay = v
            }
            items.append(item1)

            let item2 = makeBoolItem(type: .spritkitOverlay, session: session) {
                GamePageViewController.instance?.useSpriteKitOverlay ?? false
            } set: { v in
                GamePageViewController.instance?.useSpriteKitOverlay = v
            }
            items.append(item2)
        }

        return items
    }

    private static func makeOverlayItems(session: GameConfigSession) -> [GameConfigItem] {
        var items = [GameConfigItem]()

        do {
            let array: [(GameConfigSegmentItem, Double)] = [ (.text(" 2x "), 2.0), (.text(" 3x "), 3.0), (.text(" 4x "), 4.0), (.text(" 6x "), 6.0) ]
            let item = makeSegmentItem(type: .fastForwardMultiplier, session: session, getArray: {
                array.map({ $0.0 })
            }, get: {
                let value = session.getFastForwardMultiplier()
                return array.firstIndex(where: { abs($0.1 - value) < 0.001 }) ?? 0
            }, set: { index in
                let v = array[index].1
                RetroArchX.shared().setFastForwardMultiplier(v)
                session.setFastForwardMultiplier(value: v)
            })
            items.append(item)
        }

        return items
    }
}

extension GameConfigSection {
    private static func makeBoolItem(type: GameConfigItemType, session: GameConfigSession, get: @escaping GameConfigGetBoolValue, set: @escaping GameConfigSetBoolValue, enabled: Bool = true) -> GameConfigItem {
        let item = GameConfigItem(type: type, session: session)
        item.getBoolValue = get
        item.setBoolValue = set
        item.enabled      = enabled
        return item
    }

    private static func makeSegmentItem(type: GameConfigItemType, session: GameConfigSession, getArray: @escaping GameConfigGetSegmentArray, get: @escaping GameConfigGetSegmentSelectedIndex, set: @escaping GameConfigSetSegmentSelectedIndex, enabled: Bool = true) -> GameConfigItem {
        let item = GameConfigItem(type: type, session: session)
        item.getSegmentArray = getArray
        item.getSegmentSelectedIndex = get
        item.setSegmentSelectedIndex = set
        item.enabled                 = enabled
        return item
    }
}
