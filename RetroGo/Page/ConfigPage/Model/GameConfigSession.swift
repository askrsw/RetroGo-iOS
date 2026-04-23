//
//  GameConfigSession.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/17.
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
import RACoordinator

final class GameConfigSession {
    let scope: GameConfigScope
    let core: EmuCoreInfoItem?
    let game: RetroRomFileItem?
    private(set) var config: RetroArchConfig!

    init(scope: GameConfigScope, core: EmuCoreInfoItem?, game: RetroRomFileItem?) {
        self.scope  = scope
        self.core   = core
        self.game   = game
        self.config = getConfig()
    }

    func configRetroArch() {
        RetroArchX.shared().config(config)
    }
}

extension GameConfigSession {
    func getLogicThreadEnabled() -> Bool {
        config.logicThread
    }

    @discardableResult
    func setLogicThreadEnabled(value: Bool) -> Bool {
        config.logicThread = value
        return setOptionalValue(column: Self.threadEnabled, value: value)
    }

    func getFastForwardMultiplier() -> Double {
        config.fastForwardMultiplier
    }

    @discardableResult
    func setFastForwardMultiplier(value: Double) -> Bool {
        config.fastForwardMultiplier = value
        return setOptionalValue(column: Self.fastForwardMultiplier, value: value)
    }
}

private extension GameConfigSession {
    func getConfig() -> RetroArchConfig {
        let pairs = makeConfigScopeKeyPairs()
        var cfg   = makeDefaultConfig()

        do {
            let db = Retro​Rom​Persistence.sqlite
            for pair in pairs {
                let alice = Self.romConfigTable.filter(Self.configScope == pair.scope && Self.key == pair.key)
                if let row = try db.pluck(alice) {
                    apply(row: row, to: &cfg)
                }
            }
        } catch {
        #if DEBUG
            fatalError(error.localizedDescription)
        #else
            return cfg
        #endif
        }

        return cfg
    }

    func makeConfigScopeKeyPairs() -> [(scope: String, key: String)] {
        var pairs: [(scope: String, key: String)] = [
            (scope: GameConfigScope.global.rawValue, key: "global"),
        ]
        if let core = core {
            pairs.append((scope: GameConfigScope.core.rawValue, key: core.coreId))
        }
        if let game = game {
            pairs.append((scope: GameConfigScope.game.rawValue, key: game.key))
        }
        return pairs
    }

    func makeDefaultConfig() -> RetroArchConfig {
        return .init(logicThread: core?.supportsLogicThread ?? false, fastForwardMultiplier: 2.0)
    }

    func apply(row: Row, to config: inout RetroArchConfig) {
        if let v = row[Self.threadEnabled] {
            config.logicThread = v
        }
        if let v = row[Self.fastForwardMultiplier] {
            config.fastForwardMultiplier = v
        }
    }
}

private extension GameConfigSession {
    func resolveKey() -> String? {
        switch scope {
        case .global: return "global"
        case .core: return core?.coreId
        case .game: return game?.key
        }
    }

    func query(scope: GameConfigScope, key: String) -> SQLite.Table {
        Self.romConfigTable.filter(Self.configScope == scope.rawValue && Self.key == key)
    }

    func getOptionalValue<T: Value>(column: SQLite.Expression<T?>) -> T? {
        guard let key = resolveKey() else {
            return nil
        }

        let db = Retro​Rom​Persistence.sqlite
        let alice = query(scope: scope, key: key)
        do {
            return try db.pluck(alice)?[column]
        } catch {
        #if DEBUG
            fatalError(error.localizedDescription)
        #else
            return nil
        #endif
        }
    }

    @discardableResult
    func setOptionalValue<T: Value>(column: SQLite.Expression<T?>, value: T?) -> Bool {
        guard let key = resolveKey() else {
            return false
        }

        let db = Retro​Rom​Persistence.sqlite
        let alice = query(scope: scope, key: key)
        do {
            if try db.pluck(alice) != nil {
                let sql = alice.update(
                    Self.updateAt <- Date(),
                    column <- value
                )
                try db.run(sql)
            } else {
                let sql = Self.romConfigTable.insert(
                    Self.key <- key,
                    Self.configScope <- scope.rawValue,
                    Self.updateAt <- Date(),
                    column <- value
                )
                try db.run(sql)
            }
            return true
        } catch {
        #if DEBUG
            fatalError(error.localizedDescription)
        #else
            return false
        #endif
        }
    }
}

extension GameConfigSession {
    static let key              = Retro​Rom​Persistence.key
    static let updateAt         = Retro​Rom​Persistence.updateAt
    static let configScope      = SQLite.Expression<String>("scope")
    static let threadEnabled    = SQLite.Expression<Bool?>("thread_enabled")
    static let fastForwardMultiplier = SQLite.Expression<Double?>("fast​_forward​_multiplier")

    /*
     * (key, configScope, updateAt, threadEnabled, fastForwardMultiplier)
     */
    static let romConfigTable   = SQLite.Table("romconfig")

    static func deleteGameConfig(_ key: String) throws {
        let db = Retro​Rom​Persistence.sqlite
        let alice = Self.romConfigTable.filter(Self.key == key && Self.configScope == "game")
        try db.run(alice.delete())
    }
}
