//
//  RetroRomPersistence+v10.swift
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

import os
import SQLite
import RACoordinator

extension RetroRomPersistence {
    /// v1.14.0 upgrades the released v1.13.1 schema (v9) directly to v10.
    /// Cleanup, geometry conversion, UUID identities and choices
    /// share one transaction; only the final schema version is published.
    static func migrationV9ToV10(db: Connection) throws {
        typealias L = GameOverlayLayoutSession
        let id = SQLite.Expression<Int64>("id")
        let legacyTemplateId = SQLite.Expression<String>("overlay_name")
        let legacyData = SQLite.Expression<String>("data")
        try db.transaction {
            try db.run("DROP TABLE IF EXISTS overlay_game_state")
            // Preserve timestamps, choices, combos and six-button
            // overrides. Leave malformed JSON intact for the existing read fallback.
            try db.run("""
                UPDATE overlay_layout SET data = json_remove(data,
                    '$.opacity',
                    '$.portrait_four_button', '$.landscape_four_button',
                    '$.portrait.elements."arcade-layout"',
                    '$.landscape.elements."arcade-layout"')
                WHERE json_valid(data)
                """)
            // Freeze retired non-fan groups into independent positions. Layout
            // JSON v1 still uses its separate frozen v1-to-v2 reader on access.
            for row in try db.prepare(L.layoutTable) {
                guard let original = try? GameOverlayLayoutData.decode(row[legacyData]), original.version == 2 else { continue }
                let config = GamePageOverlayConfig.loadOverlayConfig(row[legacyTemplateId])
                let updated = GameOverlayLayoutResolver.migrateIndependentGroups(original, config: config)
                if updated != original {
                    try db.run(L.layoutTable.filter(id == row[id]).update(legacyData <- updated.encodedString()))
                }
            }
            try db.run("CREATE TEMP TABLE overlay_layout_id_map (old_id INTEGER PRIMARY KEY, new_id TEXT NOT NULL UNIQUE)")
            for row in try db.prepare("SELECT id FROM overlay_layout ORDER BY id") {
                try db.run("INSERT INTO overlay_layout_id_map VALUES (?, ?)", row[0], UUID().uuidString.lowercased())
            }
            try db.run("""
                CREATE TABLE overlay_layout_uuid (
                    id TEXT PRIMARY KEY NOT NULL,
                    template_id TEXT NOT NULL, idiom TEXT NOT NULL,
                    name TEXT NOT NULL, data TEXT NOT NULL, position INTEGER NOT NULL,
                    create_at TEXT NOT NULL, update_at TEXT NOT NULL,
                    UNIQUE(template_id, idiom, name)
                )
                """)
            try db.run("""
                INSERT INTO overlay_layout_uuid
                SELECT m.new_id, l.overlay_name, l.idiom, l.name, l.data, l.position, l.create_at, l.update_at
                FROM overlay_layout l JOIN overlay_layout_id_map m ON m.old_id = l.id ORDER BY l.id
                """)
            try db.run("""
                CREATE TABLE overlay_layout_platform_choice_uuid (
                    template_id TEXT NOT NULL, idiom TEXT NOT NULL, layout_id TEXT NOT NULL,
                    update_at TEXT NOT NULL, PRIMARY KEY(template_id, idiom),
                    FOREIGN KEY(layout_id) REFERENCES overlay_layout_uuid(id) ON DELETE CASCADE
                ) WITHOUT ROWID
                """)
            try db.run("""
                INSERT INTO overlay_layout_platform_choice_uuid
                SELECT c.overlay_name, c.idiom, m.new_id, c.update_at
                FROM overlay_layout_platform_choice c JOIN overlay_layout_id_map m ON m.old_id = c.layout_id
                """)
            try db.run("""
                CREATE TABLE overlay_layout_game_choice_uuid (
                    rom_key TEXT NOT NULL, template_id TEXT NOT NULL, idiom TEXT NOT NULL,
                    layout_id TEXT, update_at TEXT NOT NULL, PRIMARY KEY(rom_key, template_id, idiom),
                    FOREIGN KEY(rom_key) REFERENCES romgame(key) ON DELETE CASCADE,
                    FOREIGN KEY(layout_id) REFERENCES overlay_layout_uuid(id) ON DELETE CASCADE
                ) WITHOUT ROWID
                """)
            try db.run("""
                INSERT INTO overlay_layout_game_choice_uuid
                SELECT c.rom_key, c.overlay_name, c.idiom, m.new_id, c.update_at
                FROM overlay_layout_game_choice c LEFT JOIN overlay_layout_id_map m ON m.old_id = c.layout_id
                """)
            try db.run("""
                CREATE TABLE overlay_layout_driver_choice_uuid (
                    driver_id TEXT NOT NULL, template_id TEXT NOT NULL, idiom TEXT NOT NULL,
                    layout_id TEXT, update_at TEXT NOT NULL, PRIMARY KEY(driver_id, template_id, idiom),
                    FOREIGN KEY(layout_id) REFERENCES overlay_layout_uuid(id) ON DELETE CASCADE
                ) WITHOUT ROWID
                """)
            // Drop children first so foreign key cascades cannot erase copied choices.
            for table in ["overlay_layout_platform_choice", "overlay_layout_game_choice"] {
                try db.run("DROP TABLE \(table)")
            }
            try db.run("DROP TABLE overlay_layout")
            try db.run("ALTER TABLE overlay_layout_uuid RENAME TO overlay_layout")
            for table in ["overlay_layout_platform_choice", "overlay_layout_game_choice", "overlay_layout_driver_choice"] {
                try db.run("ALTER TABLE \(table)_uuid RENAME TO \(table)")
            }
            try db.run(L.layoutTable.createIndex(L.templateId, ifNotExists: true))
            try db.run(L.gameChoiceTable.createIndex(L.optionalLayoutId, ifNotExists: true))
            try db.run(L.driverChoiceTable.createIndex(L.optionalLayoutId, ifNotExists: true))
            try db.run("DROP TABLE overlay_layout_id_map")
            try migrateLayoutInputBindings(db: db)
            try GamePlayerInputBindingSelectionStore.createTable(db: db)
            try db.run("PRAGMA user_version = 10")
        }
    }

    static func databaseV10(db: Connection) throws {
        try databaseV9(db: db)
        try migrationV9ToV10(db: db)
    }
}

/// One-time v9 compatibility. Runtime code never reads the retired romconfig column.
extension RetroRomPersistence {
    static func migrateLayoutInputBindings(db: Connection, templates suppliedTemplates: [String: String]? = nil) throws {
        try GameLayoutInputBindingStore.createTable(db: db)
        // Migration can run before RetroArch finishes initializing. Read only bundled metadata.
        let templates = try suppliedTemplates ?? legacyCoreTemplates()
        let legacyProfile = SQLite.Expression<Data?>("input_binding_profile")
        let config = SQLite.Table("romconfig")
        let scope = SQLite.Expression<String>("scope")
        let key = SQLite.Expression<String>("key")
        let updated = SQLite.Expression<Date>("update_at")
        // Core overrides win; within a scope the newest row wins, with a stable key tie-break.
        let rows = try db.prepare(config.filter(legacyProfile != nil)
            .order(scope.asc, updated.desc, key.asc))
        var chosen = Set<String>()
        var migrated = 0
        var discarded = 0
        for row in rows {
            let template: String?
            switch row[scope] {
            case "core": template = templates[row[key]]
            case "game": template = try legacyGameTemplate(key: row[key], db: db, templates: templates)
            default: template = nil // There was no global controller mapping UI.
            }
            guard let template, !chosen.contains(template), let blob = row[legacyProfile] else { discarded += 1; continue }
            let profile: RAInputBindingProfile
            do { profile = try RAInputBindingProfile.decode(from: blob) }
            catch { discarded += 1; continue }
            guard !profile.players.isEmpty else { continue }
            for idiom in [GameOverlayLayoutIdiom.phone, .pad] {
                try GameLayoutInputBindingStore(templateId: template, idiom: idiom, layoutId: nil).write(profile, db: db)
            }
            chosen.insert(template)
            migrated += 1
        }
        // DROP COLUMN is available on the supported iOS 15+ SQLite runtime.
        try db.run("ALTER TABLE romconfig DROP COLUMN input_binding_profile")
        RetroGoLogger.database.info("Migrated controller mappings to layouts: retained \(migrated, privacy: .public), discarded \(discarded, privacy: .public)")
    }

    private static func legacyCoreTemplates() throws -> [String: String] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Data/jsons/core") ?? []
        var templates: [String: String] = [:]
        for url in urls where url.deletingPathExtension().lastPathComponent.hasSuffix("_extra") {
            let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            let id = String(url.deletingPathExtension().lastPathComponent.dropLast(6))
            templates[id] = GamePageOverlayConfig.resolvedOverlayName(metadata?["overlay"] as? String)
        }
        guard !templates.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        return templates
    }

    private static func legacyGameTemplate(key: String, db: Connection, templates: [String: String]) throws -> String? {
        guard let game = try db.pluck(romGameTable.filter(Self.key == key)) else { return nil }
        var preferred = game[preferCore]
        var parentKey = game[parent]
        var visited = Set<String>()
        while preferred == nil && visited.insert(parentKey).inserted {
            guard let folder = try db.pluck(romFolderTable.filter(Self.key == parentKey)) else { break }
            preferred = folder[preferCore]
            if parentKey == "root" { break }
            parentKey = folder[parent]
        }
        if let preferred, let template = templates[preferred] { return template }
        // A previous explicit layout choice is more reliable than guessing an ambiguous archive.
        let choices = try db.prepare("SELECT DISTINCT template_id FROM overlay_layout_game_choice WHERE rom_key = ? ORDER BY template_id", key)
            .compactMap { $0[0] as? String }
        if choices.count == 1 { return choices[0] }
        // Conservative fallback for unassigned files. Ambiguous archives are discarded.
        let ext = (game[entryFileKey] as NSString).pathExtension.lowercased()
        return ["nes": "nes", "fds": "nes", "sfc": "snes", "smc": "snes",
                "gb": "gbc", "gbc": "gbc", "gba": "gba", "nds": "nds",
                "n64": "n64", "z64": "n64", "v64": "n64", "psp": "psp",
                "md": "genesis", "gen": "genesis", "sms": "sms", "gg": "sms"][ext]
    }
}
