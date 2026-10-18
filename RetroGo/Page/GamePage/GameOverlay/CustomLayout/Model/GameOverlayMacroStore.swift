//
//  GameOverlayMacroStore.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/16.
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

import Foundation
import SQLite
import os

/// Read-only copy candidates. Macro definitions are owned by layout JSON.
enum GameOverlayMacroStore {
    struct Candidate {
        let layoutId: String
        let layoutName: String
        let idiom: GameOverlayLayoutIdiom
        let macro: GameOverlayMacro
    }

    static func candidates(templateId: String, excluding layoutId: String?) -> [Candidate] {
        typealias L = GameOverlayLayoutSession
        do {
            let query = L.layoutTable.filter(L.templateId == templateId)
                .order(L.createAt.asc, SQLite.Expression<Int64>("rowid").asc)
            var result: [Candidate] = []
            for row in try RetroRomPersistence.sqlite.prepare(query) where row[L.id] != layoutId {
                guard let data = try? GameOverlayLayoutData.decode(row[L.data]), data.hasValidMacros,
                      let idiom = GameOverlayLayoutIdiom(rawValue: row[L.idiom]) else { continue }
                for macro in data.macros ?? [] where macro.isValid && !macro.id.isEmpty {
                    result.append(Candidate(layoutId: row[L.id], layoutName: row[L.name], idiom: idiom, macro: macro))
                }
            }
            return result
        } catch {
            RetroGoLogger.game.error("Failed to read layout macro copy candidates: \(String(describing: error))")
            return []
        }
    }
}
