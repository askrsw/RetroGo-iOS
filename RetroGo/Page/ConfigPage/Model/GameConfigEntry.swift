//
//  GameConfigEntry.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/24.
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

enum GameConfigEntryType {
    case bool, string, int, double
}

enum GameConfigEntryUIType {
    case label, `switch`, segmentcontrol, list
}

typealias GameConfigGetStringValue = () -> String

typealias GameConfigGetBoolValue = () -> Bool
typealias GameConfigSetBoolValue = (Bool) -> Void

enum GameConfigSegmentItem {
    case text(String)
    case image(UIImage)
}
typealias GameConfigGetSegmentArray = () -> [GameConfigSegmentItem]
typealias GameConfigGetSegmentSelectedIndex = () -> Int
typealias GameConfigSetSegmentSelectedIndex = (Int) -> Void

typealias GameConfigGetListArray = () -> (list: [(title: String, value: AnyHashable)], selected: Int?)
typealias GameConfigGetListSelectedTitle = () -> String?
typealias GameConfigSetListSelectedValue = (AnyHashable) -> Void

final class GameConfigEntry: NSObject {
    let type: GameConfigEntryType
    let ui: GameConfigEntryUIType
    let title: String

    init(type: GameConfigEntryType, ui: GameConfigEntryUIType, title: String) {
        self.type  = type
        self.ui    = ui
        self.title = title
    }

    var enabled: Bool = true
    var desc: String?
    @objc dynamic var refresh: Bool = false

    var getStringValue: GameConfigGetStringValue?

    var getBoolValue: GameConfigGetBoolValue?
    var setBoolValue: GameConfigSetBoolValue?

    var getSegmentArray: GameConfigGetSegmentArray?
    var getSegmentSelectedIndex: GameConfigGetSegmentSelectedIndex?
    var setSegmentSelectedIndex: GameConfigSetSegmentSelectedIndex?

    var getListArray: GameConfigGetListArray?
    var getListSelectedTitle: GameConfigGetListSelectedTitle?
    var setListSelectedValue: GameConfigSetListSelectedValue?
}

extension GameConfigSession {
    func makeOverlayConfigEntries() -> [GameConfigEntry] {
        var entries: [GameConfigEntry] = []
        do {
            let title = Bundle.localizedString(forKey: "configpage_game_fast_multiplier")
            let array: [(GameConfigSegmentItem, Double)] = [ (.text(" 2x "), 2.0), (.text(" 3x "), 3.0), (.text(" 4x "), 4.0), (.text(" 6x "), 6.0) ]
            let entry = GameConfigEntry(type: .double, ui: .segmentcontrol, title: title)
            entry.getSegmentArray = {
                array.map({ $0.0 })
            }
            entry.getSegmentSelectedIndex = { [weak self] in
                guard let self = self else { return 0 }
                let value = getFastForwardMultiplier()
                return array.firstIndex(where: { abs($0.1 - value) < 0.001 }) ?? 0
            }
            entry.setSegmentSelectedIndex = { [weak self] index in
                guard let self = self else { return }
                let v = array[index].1
                RetroArchX.shared().setFastForwardMultiplier(v)
                setFastForwardMultiplier(value: v)
            }
            entries.append(entry)
        }

        do {
            let title = Bundle.localizedString(forKey: "configpage_game_mute_when_fast")
            let entry = GameConfigEntry(type: .bool, ui: .switch, title: title)
            entry.getBoolValue = { [weak self] in
                self?.getMuteOnFastForward() ?? false
            }
            entry.setBoolValue = { [weak self] value in
                RetroArchX.shared().setMuteOnFastForward(value)
                self?.setMuteOnFastForward(value: value)
            }
            entries.append(entry)
        }
        return entries
    }

    func makeRestartRequiredConfigEntries() -> [GameConfigEntry] {
        var entries: [GameConfigEntry] = []
        if scope != .global {
            let title = Bundle.localizedString(forKey: "configpage_game_thread")
            let entry = GameConfigEntry(type: .bool, ui: .switch, title: title)
            entry.getBoolValue = { [weak self] in
                guard let self = self else { return false }
                return self.getLogicThreadEnabled()
            }
            entry.setBoolValue = { [weak self] v in
                guard let self = self else { return }
                setLogicThreadEnabled(value: v)
            }
            if let core {
                if core.supportsLogicThread {
                    entry.desc = Bundle.localizedString(forKey: "configpage_game_thread_desc")
                } else {
                    let formatter = Bundle.localizedString(forKey: "configpage_game_thread_forbiden_desc")
                    let string = String(format: formatter, core.coreName)
                    entry.desc = string
                    entry.enabled = false
                }
            } else {
                entry.desc = Bundle.localizedString(forKey: "configpage_game_thread_desc")
            }
            entries.append(entry)
        }

        do {
            let title = Bundle.localizedString(forKey: "configpage_video_driver")
            let entry = GameConfigEntry(type: .string, ui: .list, title: title)
            entry.getListArray = { [weak self] in
                guard let self = self else { return (list: [], selected: nil) }
                return getAvailableVideoDrivers()
            }
            entry.getListSelectedTitle = { [weak self] in
                return self?.getVideoDriverTitle()
            }
            entry.setListSelectedValue = { [weak self] value in
                guard let self = self, let driver = value as? String else { return }
                setVideoDriver(value: driver)
            }
            if let core {
                if core.isHWRender {
                    let formatter = Bundle.localizedString(forKey: "configpage_video_driver_forbiden_desc")
                    entry.desc = String(format: formatter, core.coreName)
                    entry.enabled = false
                } else {
                    entry.desc = Bundle.localizedString(forKey: "configpage_video_driver_desc")
                }
            } else {
                entry.desc = Bundle.localizedString(forKey: "configpage_video_driver_desc")
            }
            entries.append(entry)
        }

        do {
            let title = Bundle.localizedString(forKey: "configpage_audio_driver")
            let entry = GameConfigEntry(type: .string, ui: .list, title: title)
            entry.getListArray = { [weak self] in
                guard let self = self else { return (list: [], selected: nil) }
                return getAvailableAudioDrivers()
            }
            entry.getListSelectedTitle = { [weak self] in
                return self?.getAudioDriverTitle()
            }
            entry.setListSelectedValue = { [weak self] value in
                guard let self = self, let driver = value as? String else { return }
                setAudioDriver(value: driver)
            }
            entries.append(entry)
        }

        return entries
    }

    func makeTitleConfigEntries() -> [GameConfigEntry] {
        var entries: [GameConfigEntry] = []
        if scope == .game {
            let gameTitle = Bundle.localizedString(forKey: "configpage_rom")
            let gameEntry = GameConfigEntry(type: .string, ui: .label, title: gameTitle)
            gameEntry.getStringValue = { [weak self] in
                guard let game = self?.game else { return "" }
                return game.itemName
            }
            entries.append(gameEntry)

            if core != nil {
                let coreTitle = Bundle.localizedString(forKey: "configpage_core")
                let coreEntry = GameConfigEntry(type: .string, ui: .label, title: coreTitle)
                coreEntry.getStringValue = { [weak self] in
                    guard let core = self?.core else { return "" }
                    return core.coreName
                }
                entries.append(coreEntry)
            }
        } else if scope == .core {
            let coreTitle = Bundle.localizedString(forKey: "configpage_core")
            let coreEntry = GameConfigEntry(type: .string, ui: .label, title: coreTitle)
            coreEntry.getStringValue = { [weak self] in
                guard let core = self?.core else { return "" }
                return core.coreName
            }
            entries.append(coreEntry)
        }
        return entries
    }
}

extension GameConfigSession {
    private func getAvailableVideoDrivers() -> (list: [(title: String, value: AnyHashable)], selected: Int?) {
        let drivers = RetroArchX.shared().availableVideoDrivers()
        var list: [(title: String, value: String)] = []
        for driver in drivers {
            switch driver {
            case "vulkan": list.append((title: "Vulkan", value: driver))
            case "gl": list.append((title: "GL", value: driver))
            case "metal": list.append((title: "Metal", value: driver))
            default: break
            }
        }
        let selected = drivers.firstIndex(of: getVideoDriver())
        return (list, selected)
    }

    private func getVideoDriverTitle() -> String? {
        switch getVideoDriver() {
        case "vulkan": return "Vulkan"
        case "gl": return "GL"
        case "metal": return "Metal"
        default: return nil
        }
    }

    private func getAvailableAudioDrivers() -> (list: [(title: String, value: AnyHashable)], selected: Int?) {
        let drivers = RetroArchX.shared().availableAudioDrivers()
        var list: [(title: String, value: String)] = []
        for driver in drivers {
            switch driver {
            case "coreaudio": list.append((title: "Core Audio", value: driver))
            case "openal": list.append((title: "OpenAL", value: driver))
            case "null": list.append((title: "Null", value: driver))
            default: break
            }
        }
        let selected = drivers.firstIndex(of: getAudioDriver())
        return (list, selected)
    }

    private func getAudioDriverTitle() -> String? {
        switch getAudioDriver() {
        case "coreaudio": return "Core Audio"
        case "openal": return "OpenAL"
        case "null": return "Null"
        default: return nil
        }
    }
}
