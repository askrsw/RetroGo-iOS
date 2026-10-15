//
//  RetroRomPersistence+v9.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/8.
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

extension RetroRomPersistence {
    /// v9 adds the user's on-screen control layouts, which one a platform or a
    /// game uses, per game which arcade layout (four or six buttons) the
    /// controls last showed (see `GameOverlayLayoutSession`), and three config
    /// columns: the haptic level of the controls, whether the phone rumbles
    /// when the game asks for it, and the controller type of the core's ports.
    static func migrationV8ToV9(db: Connection) throws {
        typealias L = GameOverlayLayoutSession
        try db.transaction {
            try db.run(L.layoutTable.create(temporary: false, ifNotExists: true, block: { t in
                t.column(L.id, primaryKey: .autoincrement)
                t.column(L.overlayName)
                t.column(L.idiom)
                t.column(L.name)
                t.column(L.data)
                t.column(L.position)
                t.column(L.createAt)
                t.column(L.updateAt)
                t.unique(L.overlayName, L.idiom, L.name)
            }))
            try db.run(L.platformChoiceTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
                t.column(L.overlayName)
                t.column(L.idiom)
                t.column(L.layoutId)
                t.column(L.updateAt)
                t.primaryKey(L.overlayName, L.idiom)
                t.foreignKey(L.layoutId, references: L.layoutTable, L.id, delete: .cascade)
            }))
            try db.run(L.gameChoiceTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
                t.column(L.romKey)
                t.column(L.overlayName)
                t.column(L.idiom)
                t.column(L.optionalLayoutId)
                t.column(L.updateAt)
                t.primaryKey(L.romKey, L.overlayName, L.idiom)
                t.foreignKey(L.romKey, references: Self.romGameTable, Self.key, delete: .cascade)
                t.foreignKey(L.optionalLayoutId, references: L.layoutTable, L.id, delete: .cascade)
            }))
            // Usage counts look choices up by layout.
            try db.run(L.gameChoiceTable.createIndex(L.optionalLayoutId, ifNotExists: true))
            // Retain the historical v9 schema; v10 removes this obsolete table.
            let legacyGameStateTable = SQLite.Table("overlay_game_state")
            let legacyFourButtonLayout = SQLite.Expression<Bool>("four_button_layout")
            try db.run(legacyGameStateTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
                t.column(L.romKey)
                t.column(L.overlayName)
                t.column(legacyFourButtonLayout)
                t.column(L.updateAt)
                t.primaryKey(L.romKey, L.overlayName)
                t.foreignKey(L.romKey, references: Self.romGameTable, Self.key, delete: .cascade)
            }))
            try addColumnIfNeeded(db: db, table: "romconfig", column: "overlay_haptic_level", type: "INTEGER")
            try addColumnIfNeeded(db: db, table: "romconfig", column: "game_rumble_enabled", type: "INTEGER")
            try addColumnIfNeeded(db: db, table: "romconfig", column: "port_device", type: "TEXT")
            try db.run("PRAGMA user_version = 9")
        }
    }

    static func databaseV9(db: Connection) throws {
        try databaseV8(db: db)
        try migrationV8ToV9(db: db)
    }

    /// v1.14.0 upgrades the released v9 schema directly to v10. Schema changes,
    /// layout cleanup and geometry migration share one transaction.
    static func migrationV9ToV10(db: Connection) throws {
        typealias L = GameOverlayLayoutSession
        try db.transaction {
            // Macro definitions are independent assets referenced by layout UUIDs.
            try db.run("""
                CREATE TABLE IF NOT EXISTS overlay_macro (
                    id TEXT PRIMARY KEY NOT NULL,
                    overlay_name TEXT NOT NULL,
                    data TEXT NOT NULL,
                    create_at REAL NOT NULL,
                    update_at REAL NOT NULL
                )
                """)
            try db.run("DROP TABLE IF EXISTS overlay_game_state")
            // Preserve layout ids, timestamps, choices, combos and six-button
            // overrides. Leave malformed JSON intact for the existing read fallback.
            try db.run("""
                UPDATE overlay_layout SET data = json_remove(data,
                    '$.opacity',
                    '$.portrait_four_button', '$.landscape_four_button',
                    '$.portrait.elements."arcade-layout"',
                    '$.landscape.elements."arcade-layout"')
                WHERE json_valid(data)
                """)
            // Freeze retired non-fan groups into independent positions. Layout
            // JSON v1 still uses its separate frozen v1-to-v2 reader on access.
            for row in try db.prepare(L.layoutTable) {
                guard let original = try? GameOverlayLayoutData.decode(row[L.data]), original.version == 2 else { continue }
                let config = GamePageOverlayConfig.loadOverlayConfig(row[L.overlayName])
                let updated = GameOverlayLayoutResolver.migrateIndependentGroups(original, config: config)
                if updated != original {
                    try db.run(L.layoutTable.filter(L.id == row[L.id]).update(L.data <- updated.encodedString()))
                }
            }
            try db.run("PRAGMA user_version = 10")
        }
    }

    static func databaseV10(db: Connection) throws {
        try databaseV9(db: db)
        try migrationV9ToV10(db: db)
    }
}
