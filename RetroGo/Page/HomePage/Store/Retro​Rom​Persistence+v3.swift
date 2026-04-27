//
//  Retro​Rom​Persistence+v3.swift
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

extension Retro​Rom​Persistence {
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

extension Retro​Rom​Persistence {
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

        try db.run("PRAGMA user_version = \(4)")
    }

    private static func addColumnIfNeeded(db: Connection, table: String, column: String, type: String) throws {
        let sql = "SELECT COUNT(*) FROM pragma_table_info('" + table + "') WHERE name = ?"
        let count = try db.scalar(sql, column) as? Int64 ?? 0
        if count == 0 {
            try db.run("ALTER TABLE " + table + " ADD COLUMN " + column + " " + type)
        }
    }
}
