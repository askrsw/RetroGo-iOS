// Copyright © 2026 haharsw. Part of RetroGo, GPL-3.0-or-later.
import Foundation
import SQLite
import os

enum GameOverlayMacroStore {
    enum SaveError: Error { case invalidDefinition, platformMismatch }
    private static let table = Table("overlay_macro")
    private static let id = Expression<String>("id")
    private static let payload = Expression<String>("data")
    private static let scope = Expression<String>("overlay_name")

    static func load(ids: [String]) -> [GameOverlayMacro] {
        do {
            let decoder = JSONDecoder()
            return try Set(ids).sorted().compactMap { key in
                guard let row = try RetroRomPersistence.sqlite.pluck(table.filter(id == key)),
                      let data = row[payload].data(using: .utf8),
                      let macro = try? decoder.decode(GameOverlayMacro.self, from: data), macro.isValid, macro.id == key else { return nil }
                return macro
            }
        } catch {
            RetroGoLogger.game.error("Failed to read overlay macros: \(String(describing: error))")
            return []
        }
    }

    /// Called in the same transaction as the layout save, never by a draft editor.
    static func save(_ macros: [GameOverlayMacro], overlayName: String, db: Connection) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for macro in macros {
            guard macro.isValid else { throw SaveError.invalidDefinition }
            if let existing = try db.pluck(table.filter(id == macro.id)), existing[scope] != overlayName {
                throw SaveError.platformMismatch
            }
            let json = String(decoding: try encoder.encode(macro), as: UTF8.self)
            try db.run("""
                INSERT INTO overlay_macro(id, overlay_name, data, create_at, update_at) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET data = excluded.data, update_at = excluded.update_at
                WHERE overlay_macro.overlay_name = excluded.overlay_name
                """, macro.id, overlayName, json, Date().timeIntervalSince1970, Date().timeIntervalSince1970)
        }
    }
}
