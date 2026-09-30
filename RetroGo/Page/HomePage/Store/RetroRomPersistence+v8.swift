//
//  RetroRomPersistence+v8.swift
//  RetroGo
//
//  Created by haharsw on 2026/9/27.
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
    /// v8 adds the per-game on/off and parameter state of MAME's native cheats.
    static func migrationV7ToV8(db: Connection) throws {
        try db.transaction {
            try db.run(MameCheatSession.stateTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
                t.column(MameCheatSession.romKey)
                t.column(MameCheatSession.cheatIndex)
                t.column(MameCheatSession.cheatDesc)
                t.column(MameCheatSession.enabled)
                t.column(MameCheatSession.position)
                t.column(MameCheatSession.createAt)
                t.column(MameCheatSession.updateAt)
                t.primaryKey(MameCheatSession.romKey, MameCheatSession.cheatIndex)
                t.foreignKey(MameCheatSession.romKey, references: Self.romGameTable, Self.key, delete: .cascade)
            }))
            try db.run("PRAGMA user_version = 8")
        }
    }

    static func databaseV8(db: Connection) throws {
        try databaseV7(db: db)
        try migrationV7ToV8(db: db)
    }
}
