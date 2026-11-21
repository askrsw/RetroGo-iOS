//
//  RetroRomPersistence+v11.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/23.
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

extension RetroRomPersistence {
    /// Add per-scope Shader selections and video stretch preferences.
    static func migrationV10ToV11(db: Connection) throws {
        try db.transaction {
            let version = (try db.scalar("PRAGMA user_version") as? Int64) ?? 0
            guard version < 11 else { return }
            let columns = try db.prepare("PRAGMA table_info(romconfig)").map { $0[1] as? String }
            if !columns.contains("shader_config") {
                try db.run(GameConfigSession.romConfigTable.addColumn(GameShaderStore.column))
            }
            if !columns.contains("stretch_video_to_fill") {
                try db.run(GameConfigSession.romConfigTable.addColumn(GameConfigSession.stretchVideoToFill))
            }
            try db.run("PRAGMA user_version = 11")
        }
    }

    static func databaseV11(db: Connection) throws {
        try databaseV10(db: db)
        try migrationV10ToV11(db: db)
    }
}
