//
//  GameLayoutInputBindingStore.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/17.
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
import RACoordinator

/// One layout owns all player mappings. An empty layout key identifies the built-in layout.
struct GameLayoutInputBindingStore {
    let templateId: String
    let idiom: GameOverlayLayoutIdiom
    let layoutId: String?

    static let tableName = "overlay_layout_input_binding"

    static func createTable(db: Connection) throws {
        try db.run("""
            CREATE TABLE overlay_layout_input_binding (
                template_id TEXT NOT NULL, idiom TEXT NOT NULL,
                layout_key TEXT NOT NULL, layout_id TEXT,
                profile BLOB NOT NULL, update_at TEXT NOT NULL,
                PRIMARY KEY(template_id, idiom, layout_key),
                CHECK(layout_key = coalesce(layout_id, '')),
                FOREIGN KEY(layout_id) REFERENCES overlay_layout(id) ON DELETE CASCADE
            ) WITHOUT ROWID
            """)
    }

    func read(db: Connection = RetroRomPersistence.sqlite) throws -> RAInputBindingProfile? {
        let table = SQLite.Table(Self.tableName)
        let blob = SQLite.Expression<Data>("profile")
        let query = table.filter(SQLite.Expression<String>("template_id") == templateId
            && SQLite.Expression<String>("idiom") == idiom.rawValue
            && SQLite.Expression<String>("layout_key") == (layoutId ?? ""))
        guard let row = try db.pluck(query) else { return nil }
        return try RAInputBindingProfile.decode(from: row[blob])
    }

    func write(_ profile: RAInputBindingProfile?, db: Connection = RetroRomPersistence.sqlite) throws {
        if let profile, !profile.players.isEmpty {
            let data = try profile.encodedData()
            try db.run("""
                INSERT OR REPLACE INTO overlay_layout_input_binding
                (template_id, idiom, layout_key, layout_id, profile, update_at)
                VALUES (?, ?, ?, ?, ?, strftime('%Y-%m-%dT%H:%M:%f', 'now'))
                """, templateId, idiom.rawValue, layoutId ?? "", layoutId, Blob(bytes: Array(data)))
        } else {
            try db.run("DELETE FROM overlay_layout_input_binding WHERE template_id = ? AND idiom = ? AND layout_key = ?",
                       templateId, idiom.rawValue, layoutId ?? "")
        }
    }

    /// Definitions exist only in layout JSON. Hidden controls remain valid targets.
    func runtimeProfile(data: GameOverlayLayoutData?) throws -> RAInputBindingProfile? {
        guard let profile = try read() else { return nil }
        return Self.resolve(profile, data: data, forStorage: false)
    }

    func save(_ profile: RAInputBindingProfile?, data: GameOverlayLayoutData?) throws {
        // Work on an archive copy; runtime descriptors keep their resolved definitions.
        let copy = try profile.map { try RAInputBindingProfile.decode(from: $0.encodedData()) }
        try write(copy.flatMap { Self.resolve($0, data: data, forStorage: true) })
    }

    /// An editor exports a mixed runtime profile. Persist only its own player's changes.
    func savePlayer(_ profile: RAInputBindingProfile?, port: Int, data: GameOverlayLayoutData?) throws {
        let copy = try profile.map { try RAInputBindingProfile.decode(from: $0.encodedData()) }
        copy?.players = copy?.players.filter { $0.port == port } ?? []
        let selected = copy.flatMap { Self.resolve($0, data: data, forStorage: true) }
        let db = RetroRomPersistence.sqlite
        try db.transaction {
            let stored = Self.replacingPlayer(in: try read(db: db), with: selected, port: port)
            try write(stored, db: db)
        }
    }

    static func replacingPlayer(in profile: RAInputBindingProfile?, with replacement: RAInputBindingProfile?, port: Int) -> RAInputBindingProfile? {
        let result = RAInputBindingProfile()
        result.version = 2
        result.players = (profile?.players.filter { $0.port != port } ?? [])
            + (replacement?.players.filter { $0.port == port } ?? [])
        return result.players.isEmpty ? nil : result
    }

    static func actionIdentifier(port: Int, elementId: String) -> String {
        "player:\(port):overlay:user:\(elementId)"
    }

    static func descriptor(elementId: String, port: Int, data: GameOverlayLayoutData?) -> RAInputActionDescriptor? {
        let identifier = actionIdentifier(port: port, elementId: elementId)
        if let macro = data?.macros?.first(where: { $0.id == elementId }), macro.isValid {
            return .macroAction(withIdentifier: identifier, displayName: macro.name,
                steps: macro.steps.map { RAMacroInputStep(buttons: GameOverlayMacroPlayer.mask($0.binds), frames: UInt($0.frames)) })
        }
        if let combo = data?.combos?.first(where: { $0.id == elementId }) {
            let codes = combo.binds.map { GamePageOverlayAction($0).code.rawValue }
            guard !codes.isEmpty, codes.allSatisfy({ (0..<16).contains($0) }) else { return nil }
            return .joypadOutputAction(withIdentifier: identifier, displayName: combo.binds.joined(separator: "+"),
                outputJoypadCodes: codes.map(NSNumber.init(value:)), turboEnabled: combo.turbo)
        }
        return nil
    }

    /// Also used when editing a layout, to remove references to deleted definitions.
    static func resolve(_ profile: RAInputBindingProfile, data: GameOverlayLayoutData?, forStorage: Bool) -> RAInputBindingProfile? {
        for player in profile.players {
            let prefix = actionIdentifier(port: player.port, elementId: "")
            player.entries = player.entries.compactMap { entry in
                guard entry.actionId.hasPrefix(prefix) else { return entry }
                let localId = String(entry.actionId.dropFirst(prefix.count))
                guard let descriptor = descriptor(elementId: localId, port: player.port, data: data) else { return nil }
                let target = RAInputBindingTarget()
                target.targetKind = descriptor.kind == .macro ? .macro : .joypadComposite
                target.joypadCodes = forStorage ? [] : descriptor.outputJoypadCodes
                target.macroSteps = forStorage ? [] : descriptor.macroSteps
                target.turboEnabled = !forStorage && descriptor.turboEnabled
                target.displayName = forStorage ? "" : descriptor.displayName
                entry.target = target
                return entry
            }
        }
        profile.players = profile.players.filter { !$0.entries.isEmpty }
        return profile.players.isEmpty ? nil : profile
    }
}

/// A player's mapping layout is independent of the shared touch overlay choice.
struct GamePlayerInputBindingSelectionStore {
    let templateId: String
    let idiom: GameOverlayLayoutIdiom

    static func createTable(db: Connection) throws {
        try db.run("""
            CREATE TABLE IF NOT EXISTS input_binding_layout_choice (
                scope TEXT NOT NULL CHECK(scope IN ('core', 'game')), scope_key TEXT NOT NULL,
                template_id TEXT NOT NULL, idiom TEXT NOT NULL,
                port INTEGER NOT NULL CHECK(port BETWEEN 0 AND 3), layout_id TEXT,
                PRIMARY KEY(scope, scope_key, template_id, idiom, port),
                FOREIGN KEY(scope_key, scope) REFERENCES romconfig(key, scope) ON DELETE CASCADE,
                FOREIGN KEY(layout_id) REFERENCES overlay_layout(id) ON DELETE CASCADE
            ) WITHOUT ROWID
            """)
    }

    /// An explicit NULL selects the built-in layout; a missing row inherits the next scope.
    func layoutId(port: Int, scopes: [(scope: String, key: String)], db: Connection = RetroRomPersistence.sqlite) throws -> String? {
        for scope in scopes {
            let query = SQLite.Table("input_binding_layout_choice").filter(
                SQLite.Expression<String>("scope") == scope.scope && SQLite.Expression<String>("scope_key") == scope.key
                    && SQLite.Expression<String>("template_id") == templateId && SQLite.Expression<String>("idiom") == idiom.rawValue
                    && SQLite.Expression<Int>("port") == port)
            if let row = try db.pluck(query) {
                return row[SQLite.Expression<String?>("layout_id")]
            }
        }
        return nil
    }

    func choose(layoutId: String?, port: Int, scope: String, key: String, db: Connection = RetroRomPersistence.sqlite) throws {
        try db.transaction {
            try db.run("INSERT OR IGNORE INTO romconfig (key, scope, update_at) VALUES (?, ?, strftime('%Y-%m-%dT%H:%M:%f', 'now'))", key, scope)
            try db.run("""
                INSERT OR REPLACE INTO input_binding_layout_choice
                (scope, scope_key, template_id, idiom, port, layout_id) VALUES (?, ?, ?, ?, ?, ?)
                """, scope, key, templateId, idiom.rawValue, port, layoutId)
        }
    }
}
