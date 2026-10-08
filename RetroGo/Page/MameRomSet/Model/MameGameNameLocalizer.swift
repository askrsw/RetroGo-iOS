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
import os

/// Arcade game names in the App language, from the same data as Discover: gamerdb's MAME
/// rows map `<set>.zip` to a game group, and the language pack's game_name names the group.
/// Clones without a row of their own use their parent's group. The name is used once, when a
/// game is added to the Library. Without a language pack for the App language, MAME's
/// description is used.
final class MameGameNameLocalizer {
    static let shared = MameGameNameLocalizer()

    /// gamerdb `platform.rdb_name` of the MAME list.
    private static let platformRdbName = "MAME"

    private let lock = NSLock()
    /// set name → localized group name for `namesPackPath`; nil until both databases could be read.
    private var names: [String: String]?
    private var namesPackPath: String?

    private init() {
        NotificationCenter.default.addObserver(forName: .activeLanguagePackDidChange, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.names = nil
            self.namesPackPath = nil
            self.lock.unlock()
        }
    }

    /// Library name for a recognized game: its name in the App language when the language
    /// pack has one, otherwise MAME's description.
    func displayName(for machine: MameMachineRecord) -> String? {
        localizedName(for: machine) ?? machine.description
    }

    /// Name from the language pack of the App language, nil without one. Parents get the
    /// plain name (their parenthesized part is mostly a cartridge id such as "(NGM-2560)");
    /// clones share it, so they keep the version part of MAME's description, e.g.
    /// "街头霸王II - 世界勇士 (Japan 910214)".
    func localizedName(for machine: MameMachineRecord) -> String? {
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
        guard let packPath = OnDemandResourceLoader.shared.activeLanguagePackPath else { return nil }
        lock.lock(); defer { lock.unlock() }
        if names == nil || namesPackPath != packPath {
            names = Self.load(packPath: packPath)
            namesPackPath = names == nil ? nil : packPath
        }
        return names?[setName.lowercased()]
    }

    /// Reads both databases once per language pack. Nil (retried on the next lookup) while the
    /// game database is not installed yet.
    private static func load(packPath: String) -> [String: String]? {
        let gamerdbPath = AppConfig.shared.gameRdbDatabasePath
        guard FileManager.default.fileExists(atPath: gamerdbPath), FileManager.default.fileExists(atPath: packPath) else {
            return nil
        }
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let rdb = try Connection(gamerdbPath, readonly: true)
            guard let platformId = try rdb.scalar("SELECT id FROM platform WHERE rdb_name = ?", platformRdbName) as? Int64 else {
                return nil
            }
            let pack = try Connection(packPath, readonly: true)
            var groupNames: [String: String] = [:]
            for row in try pack.prepare("SELECT group_name, name FROM game_name WHERE platform_id = ?", platformId) {
                if let group = row[0] as? String, let name = row[1] as? String, !name.isEmpty {
                    groupNames[group] = name
                }
            }
            guard !groupNames.isEmpty else { return [:] }
            var names: [String: String] = [:]
            for row in try rdb.prepare("SELECT rom_name, group_name FROM game WHERE platform_id = ? AND rom_name IS NOT NULL", platformId) {
                guard let romName = row[0] as? String, let group = row[1] as? String, let name = groupNames[group] else { continue }
                let setName = (romName as NSString).deletingPathExtension.lowercased()
                if names[setName] == nil { names[setName] = name }
            }
            RetroGoLogger.mame.info("Loaded \(names.count) localized arcade names in \(CFAbsoluteTimeGetCurrent() - start, format: .fixed(precision: 2))s")
            return names
        } catch {
            RetroGoLogger.mame.error("Failed to read localized names: \(String(describing: error))")
            return nil
        }
    }
}
