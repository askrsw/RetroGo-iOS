//
//  GameOverlayLayoutSession.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/8.
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
import RACoordinator
import os

/// A named on-screen control layout the user made for one platform overlay.
struct GameOverlayLayoutItem: Equatable {
    let id: Int64
    let overlayName: String
    let idiom: GameOverlayLayoutIdiom
    let name: String
    let data: GameOverlayLayoutData
    let position: Int
    let createAt: Date
    let updateAt: Date
}

/// Which layout one game uses on one platform overlay.
enum GameOverlayLayoutGameChoice: Equatable {
    /// No game-level choice: the platform choice applies.
    case followPlatform
    /// The built-in layout, chosen for this game even if the platform uses a custom one.
    case builtIn
    case custom(Int64)
}

/// Where the layout a game ends up with comes from.
enum GameOverlayLayoutSource: Equatable {
    case game
    case platform
    case builtIn
}

/// Custom overlay layouts of one platform overlay (`nes`, `snes`...) on this
/// device class, and which one a game uses.
///
/// Like `GameConfigSession`, the choice cascades, but over two levels:
/// game -> platform -> built-in layout. The platform is the overlay name rather
/// than the core, so every core sharing `nes.json` shares the NES layouts. A
/// game-level choice is also kept per overlay, so a game opened in cores with
/// different overlays keeps a separate choice for each.
///
/// Tables are created by `RetroRomPersistence.migrationV8ToV9`. Deleting
/// a layout cascades to the choices that point at it, which then fall back to
/// the next level; deleting a game drops its choices and state.
final class GameOverlayLayoutSession {
    let overlayName: String
    let idiom: GameOverlayLayoutIdiom
    let game: RetroRomFileItem?

    init(overlayName: String, idiom: GameOverlayLayoutIdiom = .current, game: RetroRomFileItem?) {
        self.overlayName = overlayName
        self.idiom = idiom
        self.game = game
    }

    convenience init(core: EmuCoreInfoItem, game: RetroRomFileItem?) {
        self.init(overlayName: GamePageOverlayConfig.resolvedOverlayName(core.overlayName), game: game)
    }
}

extension GameOverlayLayoutSession {
    /// Short name of the platform the layouts belong to, for "all NES games"; nil when the overlay has none.
    var platformTitle: String? {
        switch overlayName {
        case "nes": return "NES"
        case "snes": return "SNES"
        case "gbc": return "Game Boy"
        case "gba": return "GBA"
        case "nds": return "NDS"
        case "n64": return "N64"
        case "ps": return "PlayStation"
        case "psp": return "PSP"
        case "saturn": return "Saturn"
        case "dreamcast": return "Dreamcast"
        case "genesis": return "Mega Drive"
        case "sms": return "Master System"
        default: return nil
        }
    }
}

// MARK: - Resolution

extension GameOverlayLayoutSession {
    /// The layout the game uses and where the choice comes from; nil item means the built-in layout.
    func resolvedLayout() -> (item: GameOverlayLayoutItem?, source: GameOverlayLayoutSource) {
        switch gameChoice() {
        case .builtIn:
            return (nil, .game)
        case .custom(let id):
            if let item = layout(id: id) {
                return (item, .game)
            }
        case .followPlatform:
            break
        }

        if let id = platformLayoutId(), let item = layout(id: id) {
            return (item, .platform)
        }
        return (nil, .builtIn)
    }

    func gameChoice() -> GameOverlayLayoutGameChoice {
        guard let romKey = game?.key else { return .followPlatform }
        let T = Self.self
        do {
            let query = T.gameChoiceTable.filter(T.romKey == romKey && T.overlayName == overlayName && T.idiom == idiom.rawValue)
            guard let row = try RetroRomPersistence.sqlite.pluck(query) else { return .followPlatform }
            return row[T.optionalLayoutId].map { .custom($0) } ?? .builtIn
        } catch {
            RetroGoLogger.game.error("Failed to read game overlay layout choice for \(self.overlayName, privacy: .public): \(String(describing: error))")
            return .followPlatform
        }
    }

    /// Custom layout chosen for the whole platform; nil means the built-in layout.
    func platformLayoutId() -> Int64? {
        let T = Self.self
        do {
            let query = T.platformChoiceTable.filter(T.overlayName == overlayName && T.idiom == idiom.rawValue)
            return try RetroRomPersistence.sqlite.pluck(query)?[T.layoutId]
        } catch {
            RetroGoLogger.game.error("Failed to read platform overlay layout choice for \(self.overlayName, privacy: .public): \(String(describing: error))")
            return nil
        }
    }

    /// Uses a layout (nil = built-in) for this game, or for the whole platform.
    ///
    /// Applying to the platform also drops this game's own choice, so the game
    /// visibly switches too; other games keep their game-level choices.
    @discardableResult
    func choose(layoutId: Int64?, applyToPlatform: Bool) -> Bool {
        let T = Self.self
        let db = RetroRomPersistence.sqlite
        do {
            try db.transaction {
                if applyToPlatform {
                    let platformRow = T.platformChoiceTable.filter(T.overlayName == overlayName && T.idiom == idiom.rawValue)
                    if let layoutId {
                        try db.run(T.platformChoiceTable.insert(or: .replace,
                            T.overlayName <- overlayName,
                            T.idiom <- idiom.rawValue,
                            T.layoutId <- layoutId,
                            T.updateAt <- Date()
                        ))
                    } else {
                        try db.run(platformRow.delete())
                    }
                    if let romKey = game?.key {
                        try db.run(gameChoiceRow(romKey: romKey).delete())
                    }
                } else {
                    guard let romKey = game?.key else { return }
                    try db.run(T.gameChoiceTable.insert(or: .replace,
                        T.romKey <- romKey,
                        T.overlayName <- overlayName,
                        T.idiom <- idiom.rawValue,
                        T.optionalLayoutId <- layoutId,
                        T.updateAt <- Date()
                    ))
                }
            }
            RetroGoLogger.game.info("Overlay layout \(layoutId.map { String($0) } ?? "built-in", privacy: .public) chosen for \(self.overlayName, privacy: .public) \(applyToPlatform ? "platform" : "game", privacy: .public)")
            postChange()
            return true
        } catch {
            RetroGoLogger.game.error("Failed to choose overlay layout for \(self.overlayName, privacy: .public): \(String(describing: error))")
            return false
        }
    }

    /// Drops this game's own choice so the platform choice applies again.
    @discardableResult
    func followPlatform() -> Bool {
        guard let romKey = game?.key else { return false }
        do {
            try RetroRomPersistence.sqlite.run(gameChoiceRow(romKey: romKey).delete())
            postChange()
            return true
        } catch {
            RetroGoLogger.game.error("Failed to reset game overlay layout choice for \(self.overlayName, privacy: .public): \(String(describing: error))")
            return false
        }
    }

    private func gameChoiceRow(romKey: String) -> SQLite.Table {
        let T = Self.self
        return T.gameChoiceTable.filter(T.romKey == romKey && T.overlayName == overlayName && T.idiom == idiom.rawValue)
    }
}

// MARK: - Arcade 4/6 buttons

extension GameOverlayLayoutSession {
    /// Whether the game last showed the arcade four-button layout; six buttons by default.
    /// Kept per game and overlay, not per device, like a choice made in the game itself.
    func savedFourButtonLayout() -> Bool {
        guard let romKey = game?.key else { return false }
        let T = Self.self
        do {
            let query = T.gameStateTable.filter(T.romKey == romKey && T.overlayName == overlayName)
            return try RetroRomPersistence.sqlite.pluck(query)?[T.fourButtonLayout] ?? false
        } catch {
            RetroGoLogger.game.error("Failed to read the arcade layout of \(self.overlayName, privacy: .public): \(String(describing: error))")
            return false
        }
    }

    func saveFourButtonLayout(_ fourButtons: Bool) {
        guard let romKey = game?.key else { return }
        let T = Self.self
        do {
            try RetroRomPersistence.sqlite.run(T.gameStateTable.insert(or: .replace,
                T.romKey <- romKey,
                T.overlayName <- overlayName,
                T.fourButtonLayout <- fourButtons,
                T.updateAt <- Date()
            ))
        } catch {
            RetroGoLogger.game.error("Failed to save the arcade layout of \(self.overlayName, privacy: .public): \(String(describing: error))")
        }
    }
}

// MARK: - Layouts

extension GameOverlayLayoutSession {
    func layouts() -> [GameOverlayLayoutItem] {
        let T = Self.self
        do {
            let query = T.layoutTable
                .filter(T.overlayName == overlayName && T.idiom == idiom.rawValue)
                .order(T.position.asc, T.id.asc)
            return try RetroRomPersistence.sqlite.prepare(query).compactMap(makeItem)
        } catch {
            RetroGoLogger.game.error("Failed to load overlay layouts for \(self.overlayName, privacy: .public): \(String(describing: error))")
            return []
        }
    }

    func layout(id: Int64) -> GameOverlayLayoutItem? {
        let T = Self.self
        do {
            // Scoped to this overlay and idiom so a stale id never brings in another platform's layout.
            let query = T.layoutTable.filter(T.id == id && T.overlayName == overlayName && T.idiom == idiom.rawValue)
            return try RetroRomPersistence.sqlite.pluck(query).flatMap(makeItem)
        } catch {
            RetroGoLogger.game.error("Failed to load overlay layout \(id, privacy: .public): \(String(describing: error))")
            return nil
        }
    }

    /// Whether another layout of this platform already has the name (trimmed, case-insensitive).
    func isNameTaken(_ name: String, excluding id: Int64? = nil) -> Bool {
        let key = Self.nameKey(name)
        return layouts().contains { $0.id != id && Self.nameKey($0.name) == key }
    }

    /// First "<prefix> N" name not used yet, e.g. "Layout 3".
    func suggestedName(prefix: String) -> String {
        let taken = Set(layouts().map { Self.nameKey($0.name) })
        var number = 1
        while taken.contains(Self.nameKey("\(prefix) \(number)")) {
            number += 1
        }
        return "\(prefix) \(number)"
    }

    /// Adds a layout at the end of the list; nil when the name is empty or taken, or saving fails.
    func createLayout(name: String, data: GameOverlayLayoutData) -> GameOverlayLayoutItem? {
        let T = Self.self
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isNameTaken(name) else { return nil }

        let db = RetroRomPersistence.sqlite
        do {
            let json = try data.encodedString()
            let scope = T.layoutTable.filter(T.overlayName == overlayName && T.idiom == idiom.rawValue)
            let position = (try db.scalar(scope.select(T.position.max)) ?? -1) + 1
            let now = Date()
            let id = try db.run(T.layoutTable.insert(
                T.overlayName <- overlayName,
                T.idiom <- idiom.rawValue,
                T.name <- name,
                T.data <- json,
                T.position <- position,
                T.createAt <- now,
                T.updateAt <- now
            ))
            RetroGoLogger.game.info("Created overlay layout \(id, privacy: .public) for \(self.overlayName, privacy: .public)")
            postChange()
            return layout(id: id)
        } catch {
            RetroGoLogger.game.error("Failed to create overlay layout for \(self.overlayName, privacy: .public): \(String(describing: error))")
            return nil
        }
    }

    @discardableResult
    func updateLayout(id: Int64, data: GameOverlayLayoutData) -> Bool {
        let T = Self.self
        do {
            let json = try data.encodedString()
            let changes = try RetroRomPersistence.sqlite.run(layoutRow(id: id).update(T.data <- json, T.updateAt <- Date()))
            guard changes > 0 else { return false }
            postChange()
            return true
        } catch {
            RetroGoLogger.game.error("Failed to update overlay layout \(id, privacy: .public): \(String(describing: error))")
            return false
        }
    }

    /// False when the name is empty or used by another layout of this platform.
    @discardableResult
    func renameLayout(id: Int64, name: String) -> Bool {
        let T = Self.self
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isNameTaken(name, excluding: id) else { return false }
        do {
            let changes = try RetroRomPersistence.sqlite.run(layoutRow(id: id).update(T.name <- name, T.updateAt <- Date()))
            guard changes > 0 else { return false }
            postChange()
            return true
        } catch {
            RetroGoLogger.game.error("Failed to rename overlay layout \(id, privacy: .public): \(String(describing: error))")
            return false
        }
    }

    func duplicateLayout(id: Int64, name: String) -> GameOverlayLayoutItem? {
        guard let source = layout(id: id) else { return nil }
        return createLayout(name: name, data: source.data)
    }

    /// Choices pointing at the layout fall back to the next level (cascade delete).
    @discardableResult
    func deleteLayout(id: Int64) -> Bool {
        do {
            let changes = try RetroRomPersistence.sqlite.run(layoutRow(id: id).delete())
            guard changes > 0 else { return false }
            RetroGoLogger.game.info("Deleted overlay layout \(id, privacy: .public) for \(self.overlayName, privacy: .public)")
            postChange()
            return true
        } catch {
            RetroGoLogger.game.error("Failed to delete overlay layout \(id, privacy: .public): \(String(describing: error))")
            return false
        }
    }

    /// Who uses the layout: games that chose it, and whether it is the platform choice.
    func usage(of id: Int64) -> (games: Int, platform: Bool) {
        let T = Self.self
        do {
            let db = RetroRomPersistence.sqlite
            let games = try db.scalar(T.gameChoiceTable.filter(T.optionalLayoutId == id).count)
            return (games, platformLayoutId() == id)
        } catch {
            RetroGoLogger.game.error("Failed to count overlay layout \(id, privacy: .public) usage: \(String(describing: error))")
            return (0, false)
        }
    }

    private func layoutRow(id: Int64) -> SQLite.Table {
        let T = Self.self
        return T.layoutTable.filter(T.id == id && T.overlayName == overlayName && T.idiom == idiom.rawValue)
    }

    private func makeItem(_ row: Row) -> GameOverlayLayoutItem? {
        let T = Self.self
        let id = row[T.id]
        let data: GameOverlayLayoutData
        do {
            data = try GameOverlayLayoutData.decode(row[T.data])
        } catch {
            // Keep the layout listed (so it can still be deleted or renamed) but without changes.
            RetroGoLogger.game.notice("Overlay layout \(id, privacy: .public) has unreadable data, using the built-in positions: \(String(describing: error))")
            data = GameOverlayLayoutData()
        }
        return GameOverlayLayoutItem(
            id: id,
            overlayName: row[T.overlayName],
            idiom: GameOverlayLayoutIdiom(rawValue: row[T.idiom]) ?? idiom,
            name: row[T.name],
            data: data,
            position: row[T.position],
            createAt: row[T.createAt],
            updateAt: row[T.updateAt]
        )
    }

    private static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func postChange() {
        NotificationCenter.default.post(name: .overlayLayoutChanged, object: overlayName)
    }
}

// MARK: - Schema

extension GameOverlayLayoutSession {
    static let layoutTable         = SQLite.Table("overlay_layout")
    static let platformChoiceTable = SQLite.Table("overlay_layout_platform_choice")
    static let gameChoiceTable     = SQLite.Table("overlay_layout_game_choice")
    /// Per-game overlay state that is not a layout choice: the arcade 4/6-button layout.
    static let gameStateTable      = SQLite.Table("overlay_game_state")

    static let id               = SQLite.Expression<Int64>("id")
    static let overlayName      = SQLite.Expression<String>("overlay_name")
    static let idiom            = SQLite.Expression<String>("idiom")
    static let name             = SQLite.Expression<String>("name")
    static let data             = SQLite.Expression<String>("data")
    static let position         = SQLite.Expression<Int>("position")
    static let romKey           = SQLite.Expression<String>("rom_key")
    static let layoutId         = SQLite.Expression<Int64>("layout_id")
    /// Game-level `layout_id`: NULL is an explicit choice of the built-in layout.
    static let optionalLayoutId = SQLite.Expression<Int64?>("layout_id")
    static let fourButtonLayout = SQLite.Expression<Bool>("four_button_layout")
    static let createAt         = SQLite.Expression<Date>("create_at")
    static let updateAt         = SQLite.Expression<Date>("update_at")
}
