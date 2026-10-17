// Copyright © 2026 haharsw. Part of RetroGo, GPL-3.0-or-later.
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
