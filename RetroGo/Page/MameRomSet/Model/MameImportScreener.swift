//
//  MameImportScreener.swift
//  RetroGo
//
//  Created by haharsw on 2026/9/26.
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

import UIKit
import ObjcHelper
import RACoordinator

/// MAME handling shared by the file and folder importers, run on their worker thread
/// after grouping and before any file is copied:
///
/// - BIOS/device archives never enter the Library; they are installed into the MAME
///   BIOS folder and reported in the import result.
/// - Recognized games are imported as usual, with the set's official name as display
///   name and MAME as preferred core; once stored, they are added to the romset index.
/// - Anything unrecognized, or everything when the catalog is unavailable, is imported
///   exactly as before.
final class MameImportScreener {
    struct Result {
        /// Groups to import into the Library (BIOS/device archives removed).
        var groups: [RetroRomImportGroupBuilder.Group] = []
        /// Recognized games, keyed by group entry path.
        var gameMatches: [String: MameArchiveMatch] = [:]
        var biosResults: [MameBiosInstallResult] = []
    }

    static let mameCoreId = "mame"

    private let installer: MameBiosInstaller?

    private init(installer: MameBiosInstaller?) {
        self.installer = installer
    }

    /// Nil when there is nothing to screen or the catalog/MAME core is unavailable.
    static func make(for groups: [RetroRomImportGroupBuilder.Group]) -> MameImportScreener? {
        guard groups.contains(where: isCandidate) else { return nil }
        guard MameCatalogBuilder.shared.waitUntilReady() else {
            NSLog("[MameImport] Catalog unavailable; importing archives without recognition")
            MameLibraryScanner.markPending()
            return nil
        }
        let core = DispatchQueue.main.sync {
            RetroArchX.shared().allCores.first { $0.coreId == mameCoreId }
        }
        guard let core else {
            NSLog("[MameImport] MAME core not found; importing archives without recognition")
            return nil
        }
        return MameImportScreener(installer: MameBiosInstaller(core: core))
    }

    func screen(_ groups: [RetroRomImportGroupBuilder.Group],
                fileMap: [String: RetroRomImportGroupBuilder.SourceFile],
                progress: (String) -> Void) -> Result {
        let start = CFAbsoluteTimeGetCurrent()
        var result = Result()
        var candidateCount = 0

        for group in groups {
            guard Self.isCandidate(group), let source = fileMap[group.entryPath] else {
                result.groups.append(group)
                continue
            }
            candidateCount += 1
            let fileName = (group.entryPath as NSString).lastPathComponent
            progress(fileName)

            let accessing = source.url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    source.url.stopAccessingSecurityScopedResource()
                }
            }

            let path = source.url.path(percentEncoded: false)
            guard let match = MameArchiveIdentifier.identify(archiveAtPath: path, fileName: fileName) else {
                result.groups.append(group)
                continue
            }
            NSLog("[MameImport] %@ -> %@ (%@, %@%@)", fileName, match.machine.name, match.kind.rawValue,
                  match.machine.isBios ? "bios" : (match.machine.isDevice ? "device" : "game"),
                  match.machine.cloneOf.map { ", clone of \($0)" } ?? "")

            if match.machine.isSupportSet {
                if let installer {
                    result.biosResults.append(installer.install(match, sourceURL: source.url, sourceName: fileName))
                } else {
                    // No usable BIOS folder: keep the file rather than lose it.
                    result.groups.append(group)
                }
                continue
            }
            result.groups.append(group)
            result.gameMatches[group.entryPath] = match
        }

        NSLog("[MameImport] Screened %d archives in %.2fs: %d games, %d BIOS/device files",
              candidateCount, CFAbsoluteTimeGetCurrent() - start, result.gameMatches.count, result.biosResults.count)
        return result
    }

    /// Applies the recognized set to an item that has not been stored yet.
    static func prepare(_ item: RetroRomFileItem, with match: MameArchiveMatch) {
        item.prepareForImport(showName: match.machine.description ?? item.showName, preferCore: mameCoreId)
    }

    /// How many of the set's own required files the archive holds; compares two copies
    /// of the same set.
    static func ownFileCount(_ match: MameArchiveMatch) -> Int {
        MameRomSetPersistence.shared.ownRoms(of: match.machine.name)
            .filter { !$0.optional && match.entryKeys.contains($0.rom.key) }.count
    }

    // MARK: - Replacing a less complete copy already in the Library

    enum ConflictChoice {
        case replace, skip, cancel
    }

    /// A more complete copy found at import for a game already in the Library.
    struct Replacement {
        let romgameKey: String
        let source: URL
        let match: MameArchiveMatch
    }

    /// The Library game at `parentKey`/`rawName` when it is the same MAME set as `match`
    /// and holds fewer of the set's own required files; nil otherwise.
    static func replacementTarget(parentKey: String, rawName: String, match: MameArchiveMatch) -> String? {
        let persistence = MameRomSetPersistence.shared
        guard let existing = RetroRomFileManager.shared.folderItem(key: parentKey)?.subItems
                .compactMap({ $0 as? RetroRomFileItem })
                .first(where: { $0.fileGroupType == .single && $0.rawName == rawName }),
              let record = persistence.archiveRecord(owner: .game(romgameKey: existing.key)),
              record.matchedSet == match.machine.name else {
            return nil
        }
        let ownKeys = Set(persistence.ownRoms(of: match.machine.name).filter { !$0.optional }.map(\.rom.key))
        let existingCount = ownKeys.intersection(persistence.archiveEntryKeys(owner: .game(romgameKey: existing.key)) ?? []).count
        return ownFileCount(match) > existingCount ? existing.key : nil
    }

    /// Conflict alert offering to replace the Library copy; `completion` runs on the main thread.
    static func promptReplacement(gameName: String, completion: @escaping (ConflictChoice) -> Void) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: Bundle.localizedString(forKey: "homepage_import_file_exists"),
                                          message: String(format: Bundle.localizedString(forKey: "mame_import_replace_message"), gameName),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "mame_import_replace_action"), style: .default) { _ in
                completion(.replace)
            })
            alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "skip"), style: .default) { _ in
                completion(.skip)
            })
            alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel) { _ in
                completion(.cancel)
            })
            UIViewController.currentActive()?.present(alert, animated: true)
        }
    }

    /// Runs after the import stored its new games. Returns how many games were replaced.
    static func performReplacements(_ replacements: [Replacement]) -> Int {
        var replaced = 0
        for replacement in replacements {
            let accessing = replacement.source.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    replacement.source.stopAccessingSecurityScopedResource()
                }
            }
            do {
                try MameSetRepairer.replaceArchive(romgameKey: replacement.romgameKey,
                                                   withFileAt: replacement.source.path(percentEncoded: false),
                                                   match: replacement.match)
                replaced += 1
            } catch {
                NSLog("[MameImport] Replacing %@ failed: %@", replacement.source.lastPathComponent, error.localizedDescription)
            }
        }
        return replaced
    }

    /// Appends the replacement count, if any, to an import result message.
    static func message(_ message: String, replaced: Int) -> String {
        guard replaced > 0 else { return message }
        return message + "\n\n" + String(format: Bundle.localizedString(forKey: "mame_import_replaced"), replaced)
    }

    /// Adds games to the romset index once they are stored in roms.db.
    static func recordImportedGames(_ games: [(romgameKey: String, match: MameArchiveMatch)]) {
        guard !games.isEmpty else { return }
        let persistence = MameRomSetPersistence.shared
        var stored = 0
        for game in games {
            let match = game.match
            if persistence.storeArchive(owner: .game(romgameKey: game.romgameKey), format: match.formatName,
                                        matchedSet: match.machine.name, matchKind: match.kind.rawValue,
                                        entries: match.entries) {
                stored += 1
            }
        }
        NSLog("[MameImport] Indexed %d of %d imported games", stored, games.count)
    }

    /// One line per BIOS/device set, for the import result message.
    static func noticeText(_ results: [MameBiosInstallResult]) -> String? {
        guard !results.isEmpty else { return nil }

        var order: [String] = []
        var grouped: [String: [MameBiosInstallResult]] = [:]
        for result in results {
            if grouped[result.installedName] == nil {
                order.append(result.installedName)
            }
            grouped[result.installedName, default: []].append(result)
        }

        let lines = order.map { installedName -> String in
            let group = grouped[installedName] ?? []
            let sourceNames = Set(group.map(\.sourceName))
            let label: String
            if sourceNames.count == 1, let sourceName = sourceNames.first, sourceName != installedName {
                label = "\(sourceName) → \(installedName)"
            } else {
                label = installedName
            }

            let added = group.filter { $0.outcome == .merged }.reduce(0) { $0 + $1.addedFiles }
            if added > 0 {
                return String(format: Bundle.localizedString(forKey: "mame_import_bios_merged"), label, added)
            }
            let key: String
            if group.contains(where: { $0.outcome == .installed }) {
                key = "mame_import_bios_saved"
            } else if group.contains(where: { $0.outcome == .keptExisting }) {
                key = "mame_import_bios_kept"
            } else {
                key = "mame_import_bios_failed"
            }
            return String(format: Bundle.localizedString(forKey: key), label)
        }
        return lines.joined(separator: "\n")
    }

    /// Appends the BIOS notice, if any, to an import result message.
    static func message(_ message: String, appending results: [MameBiosInstallResult]) -> String {
        guard let notice = noticeText(results) else { return message }
        return message + "\n\n" + notice
    }

    private static func isCandidate(_ group: RetroRomImportGroupBuilder.Group) -> Bool {
        group.type == .single && RAArchiveReader.formatOfArchive(atPath: group.entryPath) != .unknown
    }
}
