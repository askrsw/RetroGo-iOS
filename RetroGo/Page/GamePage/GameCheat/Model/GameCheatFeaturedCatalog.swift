//
//  GameCheatFeaturedCatalog.swift
//  RetroGo
//
//  Created by haharsw on 2026/6/16.
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

/// Curated "popular games" used by the cheat catalog browser's featured
/// section. The bundled JSON is keyed by cheat.sqlite platform_id and holds, in
/// display (fame) order, the exact game_name of one typical variant per classic
/// title. Built offline by `Tools/cheat_db/build_featured_games.py`.
enum GameCheatFeaturedCatalog {

    /// The primary (first) platform contributes up to this many entries before
    /// secondary compat platforms fill the remaining slots.
    private static let primaryQuota = 10
    /// Hard cap on the featured section regardless of how many platforms a core
    /// spans, so the highlight stays concise.
    private static let displayCap = 15

    private struct Payload: Decodable {
        let platforms: [String: [String]]
    }

    private static let payload: Payload? = {
        guard let url = Bundle.main.url(forResource: "featured_cheat_games",
                                        withExtension: "json",
                                        subdirectory: "Data/jsons/cheat") else {
            print("[CheatCatalog] featured_cheat_games.json not found in bundle")
            return nil
        }
        do {
            return try JSONDecoder().decode(Payload.self, from: Data(contentsOf: url))
        } catch {
            print("[CheatCatalog] failed to decode featured games: \(error)")
            return nil
        }
    }()

    /// Builds the ordered exact game_name list to show for a core's platform
    /// set: the primary platform leads with up to `primaryQuota` titles, then the
    /// remaining platforms fill the rest round-robin, capped at `displayCap`.
    /// A single-platform core simply takes its top `displayCap`.
    static func featuredGameNames(forPlatformIds platformIds: [NSNumber]) -> [String] {
        guard let payload, let primary = platformIds.first else { return [] }
        func list(for pid: NSNumber) -> [String] {
            payload.platforms[pid.stringValue] ?? []
        }

        let isSingle = platformIds.count == 1
        var result = Array(list(for: primary).prefix(isSingle ? displayCap : primaryQuota))

        if !isSingle {
            let restLists = platformIds.dropFirst().map { list(for: $0) }
            var index = 0
            fill: while result.count < displayCap {
                var advanced = false
                for list in restLists where index < list.count {
                    result.append(list[index])
                    advanced = true
                    if result.count >= displayCap { break fill }
                }
                if !advanced { break }
                index += 1
            }
        }
        return Array(result.prefix(displayCap))
    }
}
