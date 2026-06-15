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

/// Launch-time best-effort binder for system cheat templates.
///
/// Binding is intentionally conservative:
/// - only installed cheat.sqlite participates; missing optional ODR never writes
///   `no_match`, so a later download still gets a first real lookup.
/// - only authoritative data is trusted: ROM CRC32 -> gamerdb English name ->
///   cheat.sqlite exact English match. User-editable ROM names are ignored.
/// - `no_match` rows are versioned by cheat.sqlite `PRAGMA user_version` and
///   retried automatically when a future catalog version ships more templates.
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
    }

    private init() {}

    func prepareBindingIfNeeded(game: RetroRomFileItem, core: EmuCoreInfoItem) throws {
        guard !Thread.isMainThread else { return }
        guard OnDemandResourceLoader.shared.rdbReady else { return }
        guard let cheatResource = OnDemandResourceLoader.resource(id: "cheat"),
              isInstalled(cheatResource) else {
            return
        }
        guard let gamerdbResource = OnDemandResourceLoader.resource(id: "gamerdb"),
              isInstalled(gamerdbResource) else {
            return
        }

        let platformIds = core.cheatCatalogPlatformIds
        guard !platformIds.isEmpty else { return }

        var cheatDBVersion: Int?
        if let binding = try loadBinding(romKey: game.key, coreId: core.coreId) {
            initializeCheatCatalog(cheatResource: cheatResource)
            let version = RACheatCatalogManager.shared().currentDBUserVersion
            cheatDBVersion = version
            switch binding.status {
            case .bound:
                guard binding.cheatDBUserVersion < version else {
                    return
                }
                if let refreshed = refreshedTemplate(for: binding) {
                    try saveBound(refreshed, romKey: game.key, coreId: core.coreId, cheatDBVersion: version, origin: binding.origin)
                    return
                }
                try deleteBindingAndStates(romKey: game.key, coreId: core.coreId)
            case .noMatch:
                guard binding.cheatDBUserVersion < version else {
                    return
                }
                try deleteBindingAndStates(romKey: game.key, coreId: core.coreId)
            }
        }

        if cheatDBVersion == nil {
            initializeCheatCatalog(cheatResource: cheatResource)
            cheatDBVersion = RACheatCatalogManager.shared().currentDBUserVersion
        }
        guard let cheatDBVersion else { return }
        guard RACheatCatalogManager.shared().isDatabaseReady else { return }

        _ = try game.ensureCRC32()
        let candidates = game.crc32LookupCandidates()
        guard !candidates.isEmpty else { return }

        for crc32 in candidates {
            guard let entry = RAGameRDBManager.shared().findGame(byCRC32: crc32) else {
                continue
            }
            let entryPlatformIds: [NSNumber]
            if platformIds.contains(where: { $0.intValue == entry.platformId }) {
                entryPlatformIds = [NSNumber(value: entry.platformId)]
            } else {
                entryPlatformIds = platformIds
            }
            guard let template = RACheatCatalogManager.shared().findGame(
                forPlatformIds: entryPlatformIds,
                englishName: entry.name
            ) else {
                continue
            }
            try saveBound(template, romKey: game.key, coreId: core.coreId, cheatDBVersion: cheatDBVersion)
            return
        }

        try saveNoMatch(romKey: game.key, coreId: core.coreId, cheatDBVersion: cheatDBVersion)
    }

    private func initializeCheatCatalog(cheatResource: ODRResource) {
        let loader = OnDemandResourceLoader.shared
        let cheatPath = loader.targetPath(cheatResource)
        let localizationPath = OnDemandResourceLoader.resource(id: "gameloc").map { loader.targetPath($0) }
        let semaphore = DispatchSemaphore(value: 0)

        RACheatCatalogManager.shared().initialize(
            withCheatPath: cheatPath,
            localizationPath: localizationPath
        ) {
            semaphore.signal()
        }
        semaphore.wait()
    }

    private func isInstalled(_ resource: ODRResource) -> Bool {
        let installed = UserDefaults.standard.integer(forKey: resource.installedVersionKey)
        return installed >= resource.bundledVersion &&
            FileManager.default.fileExists(atPath: OnDemandResourceLoader.shared.targetPath(resource))
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
            catalogGroupName: row[GameCheatSession.catalogGroupName]
        )
    }

    private func refreshedTemplate(for binding: Binding) -> RAGameEntry? {
        guard let gameId = binding.catalogGameId else {
            return nil
        }
        return RACheatCatalogManager.shared().findGame(gameId: gameId)
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
