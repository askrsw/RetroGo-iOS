//
//  RetroRomPersistence+v3.swift
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
import Foundation

extension RetroRomPersistence {
    static func migrationV2ToV3(db: Connection) throws {
        try commonV3(db: db)
    }

    // app version 1.2.0
    static func databaseV3(db: Connection) throws {
        try Self.databaseV2(db: db)
        try Self.commonV3(db: db)
    }

    private static func commonV3(db: Connection) throws {
        try db.run(GameConfigSession.romConfigTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
            t.column(GameConfigSession.key)
            t.column(GameConfigSession.configScope)
            t.column(GameConfigSession.updateAt)
            t.column(GameConfigSession.threadEnabled)
            t.column(GameConfigSession.fastForwardMultiplier)
            t.primaryKey(GameConfigSession.key, GameConfigSession.configScope)
        }))

        try db.run("PRAGMA user_version = \(3)")
    }
}

extension RetroRomPersistence {
    static func migrationV3ToV4(db: Connection) throws {
        try commonV4(db: db)
    }

    // app version 1.3.0
    static func databaseV4(db: Connection) throws {
        try Self.databaseV3(db: db)
        try Self.commonV4(db: db)
    }

    private static func commonV4(db: Connection) throws {
        try addColumnIfNeeded(db: db, table: "romconfig", column: "video_driver", type: "TEXT")
        try addColumnIfNeeded(db: db, table: "romconfig", column: "audio_driver", type: "TEXT")
        try addColumnIfNeeded(db: db, table: "romconfig", column: "mute_on_fastforward", type: "INTEGER")
        try addColumnIfNeeded(db: db, table: "romconfig", column: "overlay_touch_player", type: "INTEGER")
        try addColumnIfNeeded(db: db, table: "romconfig", column: "input_binding_profile", type: "BLOB")

        try db.run("PRAGMA user_version = \(4)")
    }

    static func addColumnIfNeeded(db: Connection, table: String, column: String, type: String) throws {
        let sql = "SELECT COUNT(*) FROM pragma_table_info('" + table + "') WHERE name = ?"
        let count = try db.scalar(sql, column) as? Int64 ?? 0
        if count == 0 {
            try db.run("ALTER TABLE " + table + " ADD COLUMN " + column + " " + type)
        }
    }
}

extension RetroRomPersistence {
    static func migrationV4ToV5(db: Connection) throws {
        try commonV5(db: db)
    }

    // app version 1.5.0
    static func databaseV5(db: Connection) throws {
        try Self.databaseV4(db: db)
        try Self.commonV5(db: db)
    }

    private static func commonV5(db: Connection) throws {
        // In-game top toolbar layout (global scope only) — a single JSON blob so
        // future toolbar settings need no further columns/migrations.
        try addColumnIfNeeded(db: db, table: "romconfig", column: "toolbar_layout", type: "BLOB")

        // Overlay X/Y turbo "tap to latch" preference (cascade scope). nil/0 = off
        // (pure hold-to-burst); 1 = the 0.15s tap latch is allowed. Folded into the
        // still-unreleased v5 so it costs no extra schema version.
        try addColumnIfNeeded(db: db, table: "romconfig", column: "overlay_turbo_tap_latch", type: "INTEGER")

        // Turbo speed tier (cascade scope) — stores a TurboSpeed raw value, not the
        // raw period/duty frames. nil = the default medium tier. Folded into the
        // still-unreleased v5 so it costs no extra schema version.
        try addColumnIfNeeded(db: db, table: "romconfig", column: "overlay_turbo_speed", type: "INTEGER")

        // The v3 schema created `fast_forward_multiplier` with U+200B zero-width
        // spaces in its name (copy-paste contamination). Rename it to the clean
        // name so existing users keep their stored value. Fresh installs already
        // create the clean column, so this is a no-op there.
        try renameColumnIfNeeded(
            db: db,
            table: "romconfig",
            from: "fast\u{200B}_forward\u{200B}_multiplier",
            to: "fast_forward_multiplier"
        )

        try db.run("PRAGMA user_version = \(5)")
    }

    private static func renameColumnIfNeeded(db: Connection, table: String, from: String, to: String) throws {
        let info = "SELECT COUNT(*) FROM pragma_table_info('" + table + "') WHERE name = ?"
        let toExists = (try db.scalar(info, to) as? Int64 ?? 0) > 0
        if toExists { return }
        let fromExists = (try db.scalar(info, from) as? Int64 ?? 0) > 0
        guard fromExists else { return }
        try db.run("ALTER TABLE \"" + table + "\" RENAME COLUMN \"" + from + "\" TO \"" + to + "\"")
    }
}
