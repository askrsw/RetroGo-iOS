//
//  GameCheatTemplateAutoBinder.swift
//  RetroGo
//
//  Created by haharsw on 2026/6/13.
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
import RACoordinator
import os

/// Launch-time best-effort binder for system cheat templates.
///
/// Binding is intentionally conservative:
/// - only installed cheat.sqlite participates; missing optional ODR never writes
///   `no_match`, so a later download still gets a first real lookup.
/// - only authoritative data is trusted: ROM CRC32 -> gamerdb English name ->
///   cheat.sqlite exact English match. User-editable ROM names are ignored.
/// - `no_match` rows are versioned by cheat.sqlite `PRAGMA user_version` and
///   retried automatically when a future catalog version ships more templates.
/// - a catalog that cannot be read never produces a binding row: a failed query
///   throws instead of looking like "no template", so it can't become a lasting
///   no-match.
/// - when the catalog version changes, automatic bindings are re-derived from
///   the ROM's CRC32 and manual ones are re-located by (platform, exact name).
///   Catalog ids are not trusted across versions.
final class GameCheatTemplateAutoBinder {
    static let shared = GameCheatTemplateAutoBinder()

    private enum BindingStatus: Int {
        case noMatch = 0
        case bound = 1
    }

    private struct Binding {
        let status: BindingStatus
        let cheatDBUserVersion: Int
        let origin: GameCheatTemplateBindingOrigin
        let catalogGameId: Int?
        let catalogPlatformId: Int?
        let catalogGroupName: String?
        let catalogGameName: String?
    }

    private init() {}

    func prepareBindingIfNeeded(game: RetroRomFileItem, core: EmuCoreInfoItem) throws {
        guard !Thread.isMainThread else { return }
        guard OnDemandResourceLoader.shared.rdbReady else { return }
        let loader = OnDemandResourceLoader.shared
        guard loader.isUsable(OnDemandResourceLoader.cheat) else {
            RetroGoLogger.cheat.debug("Auto-bind skipped: cheat catalog not installed")
            return
        }
        guard loader.isUsable(OnDemandResourceLoader.gamerdb) else { return }

        let platformIds = core.cheatCatalogPlatformIds
        guard !platformIds.isEmpty else { return }

        guard openCheatCatalog() else {
            RetroGoLogger.cheat.error("Auto-bind skipped: cheat catalog could not be opened")
            return
        }
        let version = RACheatCatalogManager.shared().currentDBVersion

        let existing = try loadBinding(romKey: game.key, coreId: core.coreId)
        if let existing {
            guard existing.cheatDBUserVersion < version else { return }
            RetroGoLogger.cheat.info("Auto-bind: catalog version \(existing.cheatDBUserVersion) -> \(version), rechecking binding status \(existing.status.rawValue)")
            if existing.status == .bound,
               existing.cheatDBUserVersion < GameCheatSession.templateStateIndexKeyVersion,
               version >= GameCheatSession.templateStateIndexKeyVersion,
               let gameId = existing.catalogGameId {
                try rekeyTemplateStates(romKey: game.key, coreId: core.coreId, gameId: gameId)
            }
            if existing.status == .bound, existing.origin == .manual {
                try refreshManualBinding(existing, romKey: game.key, coreId: core.coreId, cheatDBVersion: version)
                return
            }
        }

        _ = try game.ensureCRC32()
        let candidates = game.crc32LookupCandidates()
        guard !candidates.isEmpty else {
            // Nothing to match with: keep an existing template, moved to this
            // catalog version (its switches may have just been re-keyed).
            if let existing, existing.status == .bound, let gameId = existing.catalogGameId {
                var refreshed: RAGameEntry?
                try RACheatCatalogManager.shared().lookupGame(gameId: gameId, game: &refreshed)
                if let refreshed {
                    try saveBound(refreshed, romKey: game.key, coreId: core.coreId, cheatDBVersion: version, origin: existing.origin)
                } else {
                    try deleteBindingAndStates(romKey: game.key, coreId: core.coreId)
                }
            }
            return
        }

        let template = try matchTemplate(candidates: candidates, platformIds: platformIds)
        if let existing, existing.status == .bound,
           existing.catalogPlatformId != template?.platformId || existing.catalogGameName != template?.name {
            // The old per-cheat switches belong to another template now.
            _ = GameCheatSession.deleteTemplateStates(romKey: game.key, coreId: core.coreId)
        }
        guard let template else {
            RetroGoLogger.cheat.info("Auto-bind: no template, recorded at catalog version \(version)")
            try saveNoMatch(romKey: game.key, coreId: core.coreId, cheatDBVersion: version)
            return
        }
        RetroGoLogger.cheat.info("Auto-bind: bound catalog game \(template.gameId) \"\(template.name, privacy: .public)\"")
        try saveBound(template, romKey: game.key, coreId: core.coreId, cheatDBVersion: version)
    }

    /// CRC32 -> gamerdb -> catalog. Throws when either database query fails, so
    /// a read failure is never mistaken for "no template".
    private func matchTemplate(candidates: [String], platformIds: [NSNumber]) throws -> RAGameEntry? {
        for crc32 in candidates {
            var entry: RAGameEntry?
            try RAGameRDBManager.shared().lookupGame(byCRC32: crc32, game: &entry)
            guard let entry else {
                RetroGoLogger.cheat.debug("Auto-bind: CRC32 \(crc32, privacy: .public) not in gamerdb")
                continue
            }
            let entryPlatformIds: [NSNumber]
            if platformIds.contains(where: { $0.intValue == entry.platformId }) {
                entryPlatformIds = [NSNumber(value: entry.platformId)]
            } else {
                entryPlatformIds = platformIds
            }
            var template: RAGameEntry?
            try RACheatCatalogManager.shared().lookupGame(
                forPlatformIds: entryPlatformIds,
                englishName: entry.name,
                game: &template
            )
            if let template {
                return template
            }
            RetroGoLogger.cheat.debug("Auto-bind: no template for \"\(entry.name, privacy: .public)\" on platforms \(entryPlatformIds, privacy: .public)")
        }
        return nil
    }

    /// Switches saved before catalog v5 are keyed by cheat id. The v5 catalog
    /// keeps the v4 ids (checked when it is built), so it can translate them to
    /// cht indexes, which stay valid when later catalogs renumber.
    private func rekeyTemplateStates(romKey: String, coreId: String, gameId: Int) throws {
        let cheatIds = Array(GameCheatSession.loadTemplateStates(romKey: romKey, coreId: coreId).keys)
        guard !cheatIds.isEmpty else { return }
        let indexes = try RACheatCatalogManager.shared().cheatIndexes(
            forCheatIds: cheatIds.map { NSNumber(value: $0) }, gameId: gameId)
        let mapping = Dictionary(uniqueKeysWithValues: indexes.map { ($0.key.intValue, $0.value.intValue) })
        try GameCheatSession.rekeyTemplateStates(romKey: romKey, coreId: coreId, cheatIndexById: mapping)
        RetroGoLogger.cheat.info("Auto-bind: re-keyed \(mapping.count) of \(cheatIds.count) template switches by cheat index")
    }

    /// A user's own choice survives catalog rebuilds by name, not by id: ids
    /// shift when platforms are added or removed.
    private func refreshManualBinding(_ binding: Binding, romKey: String, coreId: String, cheatDBVersion: Int) throws {
        var refreshed: RAGameEntry?
        if let platformId = binding.catalogPlatformId, let name = binding.catalogGameName {
            try RACheatCatalogManager.shared().lookupGame(platformId: platformId, exactName: name, game: &refreshed)
        }
        guard let refreshed else {
            RetroGoLogger.cheat.notice("Auto-bind: manually bound template is gone from the catalog, unbinding")
            try deleteBindingAndStates(romKey: romKey, coreId: coreId)
            return
        }
        // Same template by name; its switches are keyed by cht index and stay.
        try saveBound(refreshed, romKey: romKey, coreId: coreId, cheatDBVersion: cheatDBVersion, origin: .manual)
    }

    /// Blocks the calling (background) thread until the catalog is open.
    private func openCheatCatalog() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var ready = false
        OnDemandResourceLoader.shared.openCheatCatalog { isReady in
            ready = isReady
            semaphore.signal()
        }
        semaphore.wait()
        return ready
    }

    private func loadBinding(romKey: String, coreId: String) throws -> Binding? {
        let query = GameCheatSession.templateBindingTable
            .filter(GameCheatSession.romKey == romKey && GameCheatSession.coreId == coreId)
            .limit(1)
        guard let row = try RetroRomPersistence.sqlite.pluck(query) else {
            return nil
        }
        guard let status = BindingStatus(rawValue: row[GameCheatSession.templateStatus]) else {
            return nil
        }
        return Binding(
            status: status,
            cheatDBUserVersion: row[GameCheatSession.cheatDBUserVersion],
            origin: GameCheatTemplateBindingOrigin(rawValue: row[GameCheatSession.templateBindingOrigin]) ?? .automatic,
            catalogGameId: row[GameCheatSession.catalogGameId],
            catalogPlatformId: row[GameCheatSession.catalogPlatformId],
            catalogGroupName: row[GameCheatSession.catalogGroupName],
            catalogGameName: row[GameCheatSession.catalogGameName]
        )
    }

    private func deleteBindingAndStates(romKey: String, coreId: String) throws {
        let binding = GameCheatSession.templateBindingTable
            .filter(GameCheatSession.romKey == romKey && GameCheatSession.coreId == coreId)
        let states = GameCheatSession.templateStateTable
            .filter(GameCheatSession.romKey == romKey && GameCheatSession.coreId == coreId)
        try RetroRomPersistence.sqlite.transaction {
            try RetroRomPersistence.sqlite.run(states.delete())
            try RetroRomPersistence.sqlite.run(binding.delete())
        }
    }

    private func saveNoMatch(romKey: String, coreId: String, cheatDBVersion: Int) throws {
        try saveBinding(
            romKey: romKey,
            coreId: coreId,
            status: .noMatch,
            catalogGameId: nil,
            catalogPlatformId: nil,
            catalogGroupName: nil,
            catalogGameName: nil,
            cheatDBVersion: cheatDBVersion
        )
    }

    private func saveBound(_ template: RAGameEntry,
                           romKey: String,
                           coreId: String,
                           cheatDBVersion: Int,
                           origin: GameCheatTemplateBindingOrigin = .automatic) throws {
        try saveBinding(
            romKey: romKey,
            coreId: coreId,
            status: .bound,
            catalogGameId: template.gameId,
            catalogPlatformId: template.platformId,
            catalogGroupName: template.groupName,
            catalogGameName: template.name,
            cheatDBVersion: cheatDBVersion,
            origin: origin
        )
    }

    private func saveBinding(romKey: String,
                             coreId: String,
                             status: BindingStatus,
                             catalogGameId: Int?,
                             catalogPlatformId: Int?,
                             catalogGroupName: String?,
                             catalogGameName: String?,
                             cheatDBVersion: Int,
                             origin: GameCheatTemplateBindingOrigin = .automatic) throws {
        if status == .bound,
           let catalogGameId,
           let catalogPlatformId,
           let catalogGroupName,
           let catalogGameName {
            guard GameCheatSession.upsertTemplateBinding(
                romKey: romKey,
                coreId: coreId,
                origin: origin,
                catalogGameId: catalogGameId,
                catalogPlatformId: catalogPlatformId,
                catalogGroupName: catalogGroupName,
                catalogGameName: catalogGameName,
                cheatDBVersion: cheatDBVersion
            ) else {
                throw NSError(
                    domain: "GameCheatTemplateAutoBinder",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "save automatic template binding failed"])
            }
            return
        }

        let now = Date()
        try RetroRomPersistence.sqlite.run(GameCheatSession.templateBindingTable.insert(or: .replace,
            GameCheatSession.romKey <- romKey,
            GameCheatSession.coreId <- coreId,
            GameCheatSession.templateStatus <- status.rawValue,
            GameCheatSession.templateBindingOrigin <- GameCheatTemplateBindingOrigin.automatic.rawValue,
            GameCheatSession.catalogGameId <- catalogGameId,
            GameCheatSession.catalogPlatformId <- catalogPlatformId,
            GameCheatSession.catalogGroupName <- catalogGroupName,
            GameCheatSession.catalogGameName <- catalogGameName,
            GameCheatSession.cheatDBUserVersion <- cheatDBVersion,
            GameCheatSession.createAt <- now,
            GameCheatSession.updateAt <- now
        ))
    }
}

extension RetroRomFileItem {
    /// Auto-binding needs real file CRC32 values. For multi-file games the row's
    /// `crc32` is an internal aggregate used by the library, so try the entry
    /// file first and then the remaining files.
    func crc32LookupCandidates() -> [String] {
        var values: [String] = []
        if fileGroupType == .single {
            values.appendIfPresent(crc32)
        } else {
            values.appendIfPresent(subItems.first(where: { $0.fileRole == .entry })?.crc32)
            for item in subItems where item.fileRole != .entry {
                values.appendIfPresent(item.crc32)
            }
        }
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard normalized.count == 8, seen.insert(normalized).inserted else {
                return nil
            }
            return normalized
        }
    }
}

private extension Array where Element == String {
    mutating func appendIfPresent(_ value: String?) {
        guard let value, !value.isEmpty else { return }
        append(value)
    }
}
