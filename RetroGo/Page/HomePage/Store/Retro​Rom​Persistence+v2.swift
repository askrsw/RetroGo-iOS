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
