//
//  RetroRomPersistence+v6.swift
//  RetroGo
//
//  Created by haharsw on 2026/6/6.
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
    static func migrationV5ToV6(db: Connection) throws {
        try commonV6(db: db)
    }

    // app version 1.6.0
    static func databaseV6(db: Connection) throws {
        try Self.databaseV5(db: db)
        try Self.commonV6(db: db)
    }

    /// v6 adds the user-created cheat library, the built-in cheat-template
    /// binding cache, and CRC32 fields used by ROM-database matching. v6 is still
    /// unreleased, so the former v7 schema is intentionally folded in here.
    private static func commonV6(db: Connection) throws {
        try db.transaction {
            try addColumnIfNeeded(db: db, table: "romgame", column: "crc32", type: "TEXT")
            try addColumnIfNeeded(db: db, table: "romgamefile", column: "crc32", type: "TEXT")
            try addColumnIfNeeded(db: db, table: "romconfig", column: "auto_enable_cheats", type: "INTEGER")

            try db.run(Self.romGameTable.createIndex(Self.crc32, unique: false, ifNotExists: true))
            try db.run(Self.romGameFileTable.createIndex(Self.crc32, unique: false, ifNotExists: true))

            try db.run(GameCheatSession.romCheatTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
                t.column(GameCheatSession.cheatId, primaryKey: true)
                t.column(GameCheatSession.romKey)
                t.column(GameCheatSession.coreId)
                t.column(GameCheatSession.kind, defaultValue: GameCheatKind.numeric.rawValue)
                t.column(GameCheatSession.desc)
                t.column(GameCheatSession.code)
                t.column(GameCheatSession.enabled)
                t.column(GameCheatSession.sortIndex)
                // RETRO structured fields
                t.column(GameCheatSession.cheatType)
                t.column(GameCheatSession.memorySearchSize)
                t.column(GameCheatSession.address)
                t.column(GameCheatSession.value)
                t.column(GameCheatSession.addressMask)
                t.column(GameCheatSession.bigEndian)
                t.column(GameCheatSession.repeatCount)
                t.column(GameCheatSession.repeatAddToValue)
                t.column(GameCheatSession.repeatAddToAddress)
                // Reserved rumble config (one JSON blob; not used in 1.6.0)
                t.column(GameCheatSession.rumbleConfigBlob)
                t.column(GameCheatSession.createAt)
                t.column(GameCheatSession.updateAt)
            }))

            try db.run(GameCheatSession.romCheatTable.createIndex(GameCheatSession.romKey, ifNotExists: true))
            try db.run(GameCheatSession.romCheatTable.createIndex(GameCheatSession.coreId, ifNotExists: true))

            try db.run(GameCheatSession.templateBindingTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
                t.column(GameCheatSession.romKey)
                t.column(GameCheatSession.coreId)
                t.column(GameCheatSession.templateStatus)
                t.column(GameCheatSession.templateBindingOrigin, defaultValue: GameCheatTemplateBindingOrigin.automatic.rawValue)
                t.column(GameCheatSession.catalogGameId)
                t.column(GameCheatSession.catalogPlatformId)
                t.column(GameCheatSession.catalogGroupName)
                t.column(GameCheatSession.catalogGameName)
                t.column(GameCheatSession.cheatDBUserVersion)
                t.column(GameCheatSession.createAt)
                t.column(GameCheatSession.updateAt)
                t.primaryKey(GameCheatSession.romKey, GameCheatSession.coreId)
                t.foreignKey(GameCheatSession.romKey, references: Self.romGameTable, Self.key, delete: .cascade)
            }))
            try db.run(GameCheatSession.templateBindingTable.createIndex(GameCheatSession.templateStatus, ifNotExists: true))
            try db.run(GameCheatSession.templateBindingTable.createIndex(GameCheatSession.catalogGameId, ifNotExists: true))

            try db.run(GameCheatSession.templateStateTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
                t.column(GameCheatSession.romKey)
                t.column(GameCheatSession.coreId)
                t.column(GameCheatSession.catalogCheatId)
                t.column(GameCheatSession.enabled)
                t.column(GameCheatSession.createAt)
                t.column(GameCheatSession.updateAt)
                t.primaryKey(GameCheatSession.romKey, GameCheatSession.coreId, GameCheatSession.catalogCheatId)
                t.foreignKey(GameCheatSession.romKey, references: Self.romGameTable, Self.key, delete: .cascade)
            }))
            try db.run(GameCheatSession.templateStateTable.createIndex(GameCheatSession.catalogCheatId, ifNotExists: true))

            try db.run("DROP VIEW IF EXISTS romtaginfoview")
            try db.run("""
                CREATE VIEW IF NOT EXISTS romtaginfoview AS
                    SELECT
                        romgame.key AS key,
                        entry.raw_name AS raw_name,
                        romgame.show_name AS show_name,
                        romgame.parent AS parent,
                        romgame.create_at AS create_at,
                        romgame.update_at AS update_at,
                        (
                            SELECT COALESCE(SUM(file.file_size), 0)
                            FROM romgamefile AS file
                            WHERE file.key = romgame.key
                        ) AS file_size,
                        romgame.sha256 AS sha256,
                        romgame.crc32 AS crc32,
                        romgame.last_play_at AS last_play_at,
                        romgame.play_time AS play_time,
                        romgame.prefer_core AS prefer_core,
                        romgame.prefer_icon AS prefer_icon,
                        romgame.file_group_type AS file_group_type,
                        (
                            SELECT GROUP_CONCAT(tag.id)
                            FROM romgametag AS tag
                            WHERE tag.key = romgame.key
                        ) AS tag_ids_text
                    FROM romgame
                    LEFT JOIN romgamefile AS entry
                        ON entry.key = romgame.key
                       AND entry.raw_name = romgame.entry_file_key;
                """)

            try db.run("PRAGMA user_version = \(6)")
        }
    }
}
