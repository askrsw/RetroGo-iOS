//
//  GameShaderStore.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/19.
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
import SQLite
import RACoordinator

enum GameShaderStore {
    static let column = SQLite.Expression<String?>("shader_config")

    static func key(_ settings: GameConfigSession) -> String? {
        switch settings.scope {
        case .global: return "global"
        case .core: return settings.core?.coreId
        case .game: return settings.game?.key
        }
    }

    static func query(_ scope: GameConfigScope, _ key: String) -> Table {
        GameConfigSession.romConfigTable.filter(GameConfigSession.configScope == scope.rawValue && GameConfigSession.key == key)
    }

    static func own(_ settings: GameConfigSession) throws -> GameShaderSelection? {
        guard let key = key(settings) else { throw GameShaderError.storage }
        return try read(settings.scope, key)
    }

    private static func read(_ scope: GameConfigScope, _ key: String) throws -> GameShaderSelection? {
        guard let row = try RetroRomPersistence.sqlite.pluck(query(scope, key).select(column)) else { return nil }
        let selection = available(try decode(row.get(column)))
        guard let preset = selection?.preset, preset.isLibrary else { return selection }
        // Legacy library choices can inherit when their preset is no longer bundled.
        let path = preset.path == "edge-smoothing/fsr/fsr.slangp" ? "edge-smoothing/fsr/retrogo-fsr.slangp" : preset.path
        guard var featured = try GameShaderCatalog.builtins().first(where: { $0.path == path }) else { return nil }
        featured.parameters = preset.parameters
        return GameShaderSelection(preset: featured)
    }

    static func resolved(_ settings: GameConfigSession, replacing: GameShaderSelection?? = nil, at overrideSettings: GameConfigSession? = nil) throws -> GameShaderSelection {
        var pairs: [(GameConfigScope, String)] = [(.global, "global")]
        if settings.scope != .global, let core = settings.core { pairs.append((.core, core.coreId)) }
        if settings.scope == .game, let game = settings.game { pairs.append((.game, game.key)) }
        var result = GameShaderSelection.off
        for (scope, key) in pairs {
            let value: GameShaderSelection?
            let target = overrideSettings ?? settings
            if scope == target.scope, key == self.key(target), let replacement = replacing {
                value = available(replacement)
            } else {
                value = try read(scope, key)
            }
            if let value { result = value }
        }
        return result
    }

    static func save(_ value: GameShaderSelection?, settings: GameConfigSession) throws {
        guard value?.preset?.isLibrary != true, available(value) == value else { throw GameShaderError.resource }
        guard let key = key(settings) else { throw GameShaderError.storage }
        let raw = try value.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
        let db = RetroRomPersistence.sqlite
        let row = query(settings.scope, key)
        if try db.pluck(row) != nil {
            try db.run(row.update(column <- raw, GameConfigSession.updateAt <- Date()))
        } else {
            try db.run(GameConfigSession.romConfigTable.insert(
                GameConfigSession.key <- key, GameConfigSession.configScope <- settings.scope.rawValue,
                GameConfigSession.updateAt <- Date(), column <- raw))
        }
    }

    private static func decode(_ raw: String?) throws -> GameShaderSelection? {
        guard let raw else { return nil }
        return try JSONDecoder().decode(GameShaderSelection.self, from: Data(raw.utf8))
    }

    static func available(_ selection: GameShaderSelection?) -> GameShaderSelection? {
        guard let preset = selection?.preset, preset.imported else { return selection }
        return (try? GameShaderCatalog.url(for: preset)) == nil ? nil : selection
    }

    static var imports: URL { URL(fileURLWithPath: AppConfig.shared.shaderImportsFolder, isDirectory: true) }
}
