//
//  MameGameNameLocalizer.swift
//  RetroGo
//
//  Created by haharsw on 2026/9/28.
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

import SQLite
import Foundation
import ObjcHelper

/// Chinese names for arcade games, from the same data as Discover: gamerdb's MAME rows map
/// `<set>.zip` to a game group, and gameloc names the group. Clones without a row of their
/// own use their parent's group. The name is used once, when a game is added to the Library.
final class MameGameNameLocalizer {
    static let shared = MameGameNameLocalizer()

    /// gamerdb `platform.rdb_name` of the MAME list.
    private static let platformRdbName = "MAME"

    private let lock = NSLock()
    /// set name → localized group name; nil until both databases could be read.
    private var names: [String: String]?

    private init() { }

    /// Library name for a recognized game: the Chinese name in a Chinese app, otherwise (or
    /// without one) MAME's description.
    func displayName(for machine: MameMachineRecord) -> String? {
        guard Bundle.currentSimpleLanguageKey() == "zh" else { return machine.description }
        return chineseName(for: machine) ?? machine.description
    }

    /// Chinese name whatever the app language. Parents get the plain name (their parenthesized
    /// part is mostly a cartridge id such as "(NGM-2560)"); clones share it, so they keep the
    /// version part of MAME's description, e.g. "街头霸王II - 世界勇士 (Japan 910214)".
    func chineseName(for machine: MameMachineRecord) -> String? {
        guard let localized = localizedName(ofSet: machine.name) ?? machine.cloneOf.flatMap(localizedName(ofSet:)) else {
            return nil
        }
        guard machine.cloneOf != nil, let english = machine.description,
              let open = english.firstIndex(of: "("), english.hasSuffix(")") else {
            return localized
        }
        return "\(localized) \(english[open...])"
    }

    private func localizedName(ofSet setName: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if names == nil {
            names = Self.load()
        }
        return names?[setName.lowercased()]
    }

    /// Reads both databases once. Nil (retried on the next lookup) while either on-demand
    /// resource is not installed yet.
    private static func load() -> [String: String]? {
        let gamerdbPath = AppConfig.shared.gameRdbDatabasePath
        guard let gameloc = OnDemandResourceLoader.resource(id: "gameloc") else { return nil }
        let gamelocPath = OnDemandResourceLoader.shared.targetPath(gameloc)
        guard FileManager.default.fileExists(atPath: gamerdbPath), FileManager.default.fileExists(atPath: gamelocPath) else {
            return nil
        }
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let rdb = try Connection(gamerdbPath, readonly: true)
            guard let platformId = try rdb.scalar("SELECT id FROM platform WHERE rdb_name = ?", platformRdbName) as? Int64 else {
                return nil
            }
            let loc = try Connection(gamelocPath, readonly: true)
            var groupNames: [String: String] = [:]
            for row in try loc.prepare("SELECT group_name, name FROM name_loc WHERE platform_id = ? AND lang = 'zh' AND is_primary = 1", platformId) {
                if let group = row[0] as? String, let name = row[1] as? String, !name.isEmpty {
                    groupNames[group] = name
                }
            }
            guard !groupNames.isEmpty else { return nil }
            var names: [String: String] = [:]
            for row in try rdb.prepare("SELECT rom_name, group_name FROM game WHERE platform_id = ? AND rom_name IS NOT NULL", platformId) {
                guard let romName = row[0] as? String, let group = row[1] as? String, let name = groupNames[group] else { continue }
                let setName = (romName as NSString).deletingPathExtension.lowercased()
                if names[setName] == nil { names[setName] = name }
            }
            NSLog("[MameNames] Loaded %d localized arcade names in %.2fs", names.count, CFAbsoluteTimeGetCurrent() - start)
            return names
        } catch {
            NSLog("[MameNames] Failed to read localized names: %@", "\(error)")
            return nil
        }
    }
}
