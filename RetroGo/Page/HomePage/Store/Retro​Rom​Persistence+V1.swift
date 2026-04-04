//
//  Retro​Rom​Persistence+v1.swift
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
    // deprecated
    static let romInfoTable    = SQLite.Table("rominfo")
    static let folderInfoTable = SQLite.Table("folderinfo")
    static let tagInfoTable    = SQLite.Table("taginfo")
    static let romTagInfoTable = SQLite.Table("romtaginfo")
    static let stateInfoTable  = SQLite.Table("stateinfo")

    // app version 1.0
    static func databaseV1(db: Connection) throws {
        let preferSystem = SQLite.Expression<String?>("prefer_system")

        try db.run(Self.folderInfoTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
            t.column(Self.key, primaryKey: true)
            t.column(Self.rawName)
            t.column(Self.showName)
            t.column(Self.parent)
            t.column(Self.createAt)
            t.column(Self.updateAt)
            t.column(preferSystem)
            t.column(Self.preferCore)
            t.column(Self.preferIcon)

            t.foreignKey(Self.parent, references: Self.folderInfoTable, Self.key, delete: .restrict)
        }))
        try db.run(Self.folderInfoTable.createIndex(Self.parent, unique: false, ifNotExists: true))

        try db.run(Self.romInfoTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
            t.column(Self.key, primaryKey: true)
            t.column(Self.rawName)
            t.column(Self.showName)
            t.column(Self.parent)
            t.column(Self.createAt)
            t.column(Self.updateAt)
            t.column(Self.fileSize)
            t.column(Self.sha256)
            t.column(Self.lastPlayAt)
            t.column(Self.playTime)
            t.column(preferSystem)
            t.column(Self.preferCore)
            t.column(Self.preferIcon)

            t.foreignKey(Self.parent, references: Self.folderInfoTable, Self.key, delete: .restrict)
        }))
        try db.run(Self.romInfoTable.createIndex(Self.parent, unique: false, ifNotExists: true))

        try db.run(Self.folderInfoTable.insert(or: .replace,
            Self.key <- "root",
            Self.rawName <- "root",
            Self.showName <- "Retro Go",
            Self.parent <- "root",
            Self.createAt <- Date(),
            Self.updateAt <- Date(),
            preferSystem <- nil,
            Self.preferCore <- nil,
            Self.preferIcon <- nil,
        ))

        try db.run(Self.stateInfoTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
            t.column(Self.rawName)
            t.column(Self.coreId)
            t.column(Self.showName)
            t.column(Self.romKey)
            t.column(Self.sha256)
            t.column(Self.createAt)
            t.foreignKey(Self.romKey, references: Self.romInfoTable, Self.key, delete: .restrict)
            t.primaryKey(Self.rawName, Self.coreId)
        }))
        try db.run(Self.stateInfoTable.createIndex(Self.rawName, ifNotExists: true))
        try db.run(Self.stateInfoTable.createIndex(Self.createAt, ifNotExists: true))

        try db.run(Self.tagInfoTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
            t.column(Self.id, primaryKey: true)
            t.column(Self.title)
            t.column(Self.colorArgb)
            t.column(Self.createAt)
            t.column(Self.isHidden, defaultValue: false)
        }))

        for i in 1 ..< 8 {
            try db.run(
                Self.tagInfoTable.insert(or: .replace,
                    Self.id <- i,
                    Self.title <- nil,
                    Self.colorArgb <- nil,
                    Self.createAt <- Date()
                )
            )
        }

        try db.run(Self.romTagInfoTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
            t.column(Self.key)
            t.column(Self.id)
            t.column(Self.createAt)
            t.primaryKey(Self.key, Self.id)
            t.foreignKey(Self.key, references: Self.romInfoTable, Self.key, delete: .cascade)
            t.foreignKey(Self.id, references: Self.tagInfoTable, Self.id, delete: .cascade)
        }))
        try db.run(Self.romTagInfoTable.createIndex(Self.key, ifNotExists: true))
        try db.run(Self.romTagInfoTable.createIndex(Self.id, ifNotExists: true))

        let romTagInfoViewSql = """
            CREATE VIEW IF NOT EXISTS romtaginfoview AS
                SELECT 
                    rominfo.key AS key,
                    rominfo.raw_name AS raw_name,
                    rominfo.show_name AS show_name,
                    rominfo.parent AS parent,
                    rominfo.create_at AS create_at,
                    rominfo.update_at AS update_at,
                    rominfo.file_size AS file_size,
                    rominfo.sha256 AS sha256,
                    rominfo.last_play_at AS last_play_at,
                    rominfo.play_time AS play_time,
                    rominfo.prefer_system AS prefer_system,
                    rominfo.prefer_core AS prefer_core,
                    rominfo.prefer_icon AS prefer_icon,
                    GROUP_CONCAT(romtaginfo.id) AS tag_ids_text
                FROM rominfo
                LEFT JOIN romtaginfo ON rominfo.key = romtaginfo.key
                GROUP BY rominfo.key;
            """
        try db.run(romTagInfoViewSql)

        let folderChildrenInfoViewSql = """
            CREATE VIEW IF NOT EXISTS folderchildreninfoview AS
                SELECT 
                    folderinfo.key AS key,
                    folderinfo.raw_name AS raw_name,
                    folderinfo.show_name AS show_name,
                    folderinfo.parent AS parent,
                    folderinfo.create_at AS create_at,
                    folderinfo.update_at AS update_at,
                    folderinfo.prefer_system AS prefer_system,
                    folderinfo.prefer_core AS prefer_core,
                    folderinfo.prefer_icon AS prefer_icon,
                    GROUP_CONCAT(folders.key, '|') AS folder_children,
                    GROUP_CONCAT(roms.key, '|') AS file_children
                FROM folderinfo
                LEFT JOIN folderinfo AS folders ON folders.parent = folderinfo.key AND folders.key != 'root'
                LEFT JOIN rominfo AS roms ON roms.parent = folderinfo.key
                GROUP BY folderinfo.key;
            """
        try db.run(folderChildrenInfoViewSql)

        try db.run("PRAGMA user_version = \(1)")
    }
}
