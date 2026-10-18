//
//  GameOverlayLayoutV1Migration.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/13.
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

/// A frozen compatibility boundary. Current templates and runtime controls must
/// not affect how an old layout is interpreted. Only this reader knows v1 fields.
enum GameOverlayLayoutV1Migration {
    private struct LegacyFields: Decodable {
        var presetComboTurbo: [String: Bool]?
    }

    private struct Preset {
        let id: String
        let binds: [String]
        var turbo: Bool = false
    }

    /// Keys are overlay resource names, not platform IDs. Arrays preserve the
    /// original preset order, while the IDs preserve saved orientation overrides.
    private static let v1Legacy: [String: [Preset]] = [
        "nes": [.init(id: "a-b", binds: ["A", "B"], turbo: true)],
        "gbc": [.init(id: "a-b", binds: ["A", "B"], turbo: true)],
        "gba": [.init(id: "a-b", binds: ["A", "B"], turbo: true)],
        "snes": [.init(id: "a-b", binds: ["A", "B"], turbo: true)],
        "sms": [.init(id: "a-b", binds: ["B", "A"], turbo: true)],
        "genesis": [
            .init(id: "combo-abc", binds: ["Y", "B", "A"]),
            .init(id: "combo-xyz", binds: ["L1", "X", "R1"])
        ],
        "saturn": [
            .init(id: "combo-abc", binds: ["B", "A", "R1"]),
            .init(id: "combo-xyz", binds: ["Y", "X", "L1"])
        ],
        "mame": [
            .init(id: "combo-ba", binds: ["B", "A"]),
            .init(id: "combo-yb", binds: ["Y", "B"]),
            .init(id: "combo-xa", binds: ["X", "A"]),
            .init(id: "combo-ybx", binds: ["Y", "B", "X"]),
            .init(id: "combo-yxl", binds: ["Y", "X", "L1"]),
            .init(id: "combo-bar", binds: ["B", "A", "R1"])
        ]
    ]

    /// Upgrades decoded v1 data using its original JSON for legacy-only fields.
    /// The result is self-contained: no preset lookup is needed to render it or
    /// encode it again. Newer versions are never rewritten by this migration.
    static func upgrade(_ layout: GameOverlayLayoutData, source: String,
                        overlayName: String) throws -> GameOverlayLayoutData {
        guard layout.version == 1 else { return layout }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let legacy = try decoder.decode(LegacyFields.self, from: Data(source.utf8))
        var result = layout
        var combos = result.combos ?? []
        for preset in v1Legacy[overlayName] ?? [] {
            let hasSavedState = result.portrait?.elements[preset.id] != nil
                || result.landscape?.elements[preset.id] != nil
                || legacy.presetComboTurbo?[preset.id] != nil
            guard hasSavedState, !combos.contains(where: { $0.id == preset.id }) else { continue }
            combos.append(.init(id: preset.id, binds: preset.binds,
                                turbo: legacy.presetComboTurbo?[preset.id] ?? preset.turbo))
        }
        result.combos = combos.isEmpty ? nil : combos
        result.version = 2
        return result
    }
}
