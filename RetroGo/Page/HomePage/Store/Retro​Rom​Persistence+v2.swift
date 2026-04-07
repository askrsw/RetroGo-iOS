//
//  Retro​Rom​Persistence+v2.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/4.
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
    static func migrationV1ToV2(db: Connection) throws {
        try db.transaction {
            // 1. delete view
            try db.run("DROP VIEW IF EXISTS romtaginfoview")
            try db.run("DROP VIEW IF EXISTS folderchildreninfoview")

            // 2. build&migrate folder table
            try db.run(Self.romFolderTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
                t.column(Self.key, primaryKey: true)
                t.column(Self.rawName)
                t.column(Self.showName)
                t.column(Self.parent)
                t.column(Self.createAt)
                t.column(Self.updateAt)
                t.column(Self.preferCore)
                t.column(Self.preferIcon)
                t.foreignKey(Self.parent, references: Self.romFolderTable, Self.key, delete: .restrict)
            }))
            try db.run(Self.romFolderTable.createIndex(Self.parent, unique: false, ifNotExists: true))

            try db.run("""
                INSERT INTO  romfolder (key, raw_name, show_name, parent, create_at, update_at, prefer_core, prefer_icon)
                SELECT key, raw_name, show_name, parent, create_at, update_at, prefer_core, prefer_icon FROM folderinfo
            """)

            // 3. build&migrate game&file table
            try db.run(Self.romGameTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
                t.column(Self.key, primaryKey: true)
                t.column(Self.parent)
                t.column(Self.entryFileKey)
                t.column(Self.showName)
                t.column(Self.createAt)
                t.column(Self.updateAt)
                t.column(Self.lastPlayAt)
                t.column(Self.playTime)
                t.column(Self.preferCore)
                t.column(Self.preferIcon)
                t.column(Self.fileGroupType)
                t.column(Self.sha256)
                t.foreignKey(Self.parent, references: Self.romFolderTable, Self.key, delete: .restrict)
            }))
            try db.run(Self.romGameTable.createIndex(Self.parent, unique: false, ifNotExists: true))

            try db.run(Self.romGameFileTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
                t.column(Self.key)
                t.column(Self.rawName)
                t.column(Self.fileRole)
                t.column(Self.sha256)
                t.column(Self.fileSize)
                t.column(Self.sortIndex)
                t.primaryKey(Self.key, Self.rawName)
                t.foreignKey(Self.key, references: Self.romGameTable, Self.key, delete: .restrict)
            }))

            try db.run("""
                INSERT INTO  romgame (key, parent, entry_file_key, show_name, create_at, update_at, last_play_at, play_time, prefer_core, prefer_icon, file_group_type, sha256)
                SELECT key, parent, raw_name, show_name, create_at, update_at, last_play_at, play_time, prefer_core, prefer_icon, "single", sha256 FROM rominfo
            """)
            try db.run("""
                INSERT INTO  romgamefile (key, raw_name, file_role, sha256, file_size, sort_index)
                SELECT key, raw_name, "entry", sha256, file_size, 0 FROM rominfo
            """)

            // 4. build&migrate tag table
            try db.run(Self.romTagTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
                t.column(Self.id, primaryKey: true)
                t.column(Self.title)
                t.column(Self.colorArgb)
                t.column(Self.createAt)
                t.column(Self.isHidden, defaultValue: false)
            }))

            try db.run(Self.romGameTagTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
                t.column(Self.key)
                t.column(Self.id)
                t.column(Self.createAt)
                t.primaryKey(Self.key, Self.id)
                t.foreignKey(Self.key, references: Self.romGameTable, Self.key, delete: .cascade)
                t.foreignKey(Self.id, references: Self.romTagTable, Self.id, delete: .cascade)
            }))
            try db.run(Self.romGameTagTable.createIndex(Self.key, ifNotExists: true))
            try db.run(Self.romGameTagTable.createIndex(Self.id, ifNotExists: true))

            try db.run("""
                INSERT INTO  romtag (id, title, color_argb, create_at, is_hidden)
                SELECT id, title, color_argb, create_at, is_hidden FROM taginfo
            """)
            try db.run("""
                INSERT INTO  romgametag (key, id, create_at)
                SELECT key, id, create_at FROM romtaginfo
            """)

            // 5. build&migrate state table
            try db.run(Self.romStateTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
                t.column(Self.rawName)
                t.column(Self.coreId)
                t.column(Self.showName)
                t.column(Self.romKey)
                t.column(Self.sha256)
                t.column(Self.createAt)
                t.foreignKey(Self.romKey, references: Self.romGameTable, Self.key, delete: .restrict)
                t.primaryKey(Self.rawName, Self.coreId)
            }))
            try db.run(Self.romStateTable.createIndex(Self.rawName, ifNotExists: true))
            try db.run(Self.romStateTable.createIndex(Self.createAt, ifNotExists: true))
            try db.run(Self.romStateTable.createIndex(Self.romKey, ifNotExists: true))

            try db.run("""
                INSERT INTO  romstate (raw_name, core_id, show_name, rom_key, sha256, create_at)
                SELECT raw_name, core_id, show_name, rom_key, sha256, create_at FROM stateinfo
            """)

            // 6. build view
            let romTagInfoViewSql = """
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
                """
            try db.run(romTagInfoViewSql)

            let folderChildrenInfoViewSql = """
                CREATE VIEW IF NOT EXISTS folderchildreninfoview AS
                    SELECT
                        romfolder.key AS key,
                        romfolder.raw_name AS raw_name,
                        romfolder.show_name AS show_name,
                        romfolder.parent AS parent,
                        romfolder.create_at AS create_at,
                        romfolder.update_at AS update_at,
                        romfolder.prefer_core AS prefer_core,
                        romfolder.prefer_icon AS prefer_icon,
                        (
                            SELECT GROUP_CONCAT(child_folder.key, '|')
                            FROM romfolder AS child_folder
                            WHERE child_folder.parent = romfolder.key
                              AND child_folder.key != 'root'
                        ) AS folder_children,
                        (
                            SELECT GROUP_CONCAT(child_game.key, '|')
                            FROM romgame AS child_game
                            WHERE child_game.parent = romfolder.key
                        ) AS file_children
                    FROM romfolder;
                """
            try db.run(folderChildrenInfoViewSql)

            // 7. set database version
            try db.run("PRAGMA user_version = \(2)")
        }

        // 8. delete legacy tables after transaction committed
        try db.run("PRAGMA foreign_keys = OFF")

        try db.run(Self.stateInfoTable.dropIndex(Self.rawName, ifExists: true))
        try db.run(Self.stateInfoTable.dropIndex(Self.createAt, ifExists: true))
        try db.run(Self.stateInfoTable.drop(ifExists: true))

        try db.run(Self.romInfoTable.dropIndex(Self.parent, ifExists: true))
        try db.run(Self.romInfoTable.drop(ifExists: true))

        try db.run(Self.folderInfoTable.dropIndex(Self.parent, ifExists: true))
        try db.run(Self.folderInfoTable.drop(ifExists: true))

        try db.run(Self.romTagInfoTable.dropIndex(Self.key, ifExists: true))
        try db.run(Self.romTagInfoTable.dropIndex(Self.id, ifExists: true))
        try db.run(Self.romTagInfoTable.drop(ifExists: true))

        try db.run(Self.tagInfoTable.drop(ifExists: true))

        try db.run("PRAGMA foreign_keys = ON")
    }

    // app version 1.1.0
    static func databaseV2(db: Connection) throws {
        try db.run(Self.romFolderTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
            t.column(Self.key, primaryKey: true)
            t.column(Self.rawName)
            t.column(Self.showName)
            t.column(Self.parent)
            t.column(Self.createAt)
            t.column(Self.updateAt)
            t.column(Self.preferCore)
            t.column(Self.preferIcon)
            t.foreignKey(Self.parent, references: Self.romFolderTable, Self.key, delete: .restrict)
        }))
        try db.run(Self.romFolderTable.createIndex(Self.parent, unique: false, ifNotExists: true))

        try db.run(Self.romGameTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
            t.column(Self.key, primaryKey: true)
            t.column(Self.parent)
            t.column(Self.entryFileKey)
            t.column(Self.showName)
            t.column(Self.createAt)
            t.column(Self.updateAt)
            t.column(Self.lastPlayAt)
            t.column(Self.playTime)
            t.column(Self.preferCore)
            t.column(Self.preferIcon)
            t.column(Self.fileGroupType)
            t.column(Self.sha256)
            t.foreignKey(Self.parent, references: Self.romFolderTable, Self.key, delete: .restrict)
        }))
        try db.run(Self.romGameTable.createIndex(Self.parent, unique: false, ifNotExists: true))

        try db.run(Self.romGameFileTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
            t.column(Self.key)
            t.column(Self.rawName)
            t.column(Self.fileRole)
            t.column(Self.sha256)
            t.column(Self.fileSize)
            t.column(Self.sortIndex)
            t.primaryKey(Self.key, Self.rawName)
            t.foreignKey(Self.key, references: Self.romGameTable, Self.key, delete: .restrict)
        }))

        try db.run(Self.romFolderTable.insert(or: .replace,
            Self.key <- "root",
            Self.rawName <- "root",
            Self.showName <- "Retro Go",
            Self.parent <- "root",
            Self.createAt <- Date(),
            Self.updateAt <- Date(),
            Self.preferCore <- nil,
            Self.preferIcon <- nil,
        ))

        try db.run(Self.romTagTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
            t.column(Self.id, primaryKey: true)
            t.column(Self.title)
            t.column(Self.colorArgb)
            t.column(Self.createAt)
            t.column(Self.isHidden, defaultValue: false)
        }))

        for i in 1 ..< 8 {
            try db.run(
                Self.romTagTable.insert(or: .replace,
                    Self.id <- i,
                    Self.title <- nil,
                    Self.colorArgb <- nil,
                    Self.createAt <- Date()
                )
            )
        }

        try db.run(Self.romGameTagTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
            t.column(Self.key)
            t.column(Self.id)
            t.column(Self.createAt)
            t.primaryKey(Self.key, Self.id)
            t.foreignKey(Self.key, references: Self.romGameTable, Self.key, delete: .cascade)
            t.foreignKey(Self.id, references: Self.romTagTable, Self.id, delete: .cascade)
        }))
        try db.run(Self.romGameTagTable.createIndex(Self.key, ifNotExists: true))
        try db.run(Self.romGameTagTable.createIndex(Self.id, ifNotExists: true))

        try db.run(Self.romStateTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
            t.column(Self.rawName)
            t.column(Self.coreId)
            t.column(Self.showName)
            t.column(Self.romKey)
            t.column(Self.sha256)
            t.column(Self.createAt)
            t.foreignKey(Self.romKey, references: Self.romGameTable, Self.key, delete: .restrict)
            t.primaryKey(Self.rawName, Self.coreId)
        }))
        try db.run(Self.romStateTable.createIndex(Self.rawName, ifNotExists: true))
        try db.run(Self.romStateTable.createIndex(Self.createAt, ifNotExists: true))
        try db.run(Self.romStateTable.createIndex(Self.romKey, ifNotExists: true))

        let romTagInfoViewSql = """
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
            """
        try db.run(romTagInfoViewSql)

        let folderChildrenInfoViewSql = """
            CREATE VIEW IF NOT EXISTS folderchildreninfoview AS
                SELECT
                    romfolder.key AS key,
                    romfolder.raw_name AS raw_name,
                    romfolder.show_name AS show_name,
                    romfolder.parent AS parent,
                    romfolder.create_at AS create_at,
                    romfolder.update_at AS update_at,
                    romfolder.prefer_core AS prefer_core,
                    romfolder.prefer_icon AS prefer_icon,
                    (
                        SELECT GROUP_CONCAT(child_folder.key, '|')
                        FROM romfolder AS child_folder
                        WHERE child_folder.parent = romfolder.key
                          AND child_folder.key != 'root'
                    ) AS folder_children,
                    (
                        SELECT GROUP_CONCAT(child_game.key, '|')
                        FROM romgame AS child_game
                        WHERE child_game.parent = romfolder.key
                    ) AS file_children
                FROM romfolder;
            """
        try db.run(folderChildrenInfoViewSql)

        try db.run("PRAGMA user_version = \(2)")
    }
}
