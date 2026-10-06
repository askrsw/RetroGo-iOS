//
//  MameLaunchCheck.swift
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
import os

/// Runs before a Library game starts in MAME. When the set is missing files, needs a
/// CHD or is known not to work, the user sees what is wrong and can still launch;
/// otherwise the game starts right away. Anything that cannot be checked (unrecognized
/// archive, catalog unavailable) launches as before.
enum MameLaunchCheck {
    /// File names listed per group before "…".
    private static let listedFileLimit = 3
    /// Files taken out of other archives for the next session; replaced on every launch.
    private static let extractionDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MameExtract")

    private static var checking = false

    /// Call on the main thread; `launch` runs on the main thread.
    static func run(game: RetroRomFileItem, core: EmuCoreInfoItem, launch: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard core.coreId == MameImportScreener.mameCoreId, game.fileGroupType == .single else {
            launch()
            return
        }
        // A second tap while checking must not start the game twice.
        guard !checking else { return }
        checking = true

        let romgameKey = game.key
        let archiveFileName = game.rawName
        DispatchQueue.global(qos: .userInitiated).async {
            let audit = check(romgameKey: romgameKey, archiveFileName: archiveFileName, core: core)
            DispatchQueue.main.async {
                guard let audit else {
                    checking = false
                    // Unrecognized archive: MAME runs it under its own file name.
                    let name = (archiveFileName as NSString).deletingPathExtension
                    MameCheatLibrary.shared.prepareLaunch(romKey: romgameKey, setName: name)
                    launch()
                    return
                }
                // Archive paths come from the Library cache, which lives on the main thread.
                let sources = sourcePaths(for: audit, core: core)
                DispatchQueue.global(qos: .userInitiated).async {
                    let extracted = extractFiles(audit.extractions, sources: sources)
                    DispatchQueue.main.async {
                        checking = false
                        prepareSession(audit, sources: sources, extracted: extracted, core: core)
                        MameCheatLibrary.shared.prepareLaunch(romKey: romgameKey, setName: audit.machine.name)
                        guard audit.needsAttention else {
                            launch()
                            return
                        }
                        present(audit, gameName: game.itemName, launch: launch) {
                            core.pendingMameSessionLinks = nil
                            core.pendingMameSessionGameName = nil
                            MameCheatLibrary.shared.cancelLaunch()
                        }
                    }
                }
            }
        }
    }

    private static func check(romgameKey: String, archiveFileName: String, core: EmuCoreInfoItem) -> MameSetAudit? {
        guard MameCatalogBuilder.shared.waitUntilReady() else {
            RetroGoLogger.mame.notice("Catalog unavailable; launching \(archiveFileName) without a check")
            return nil
        }
        guard let biosFolder = MameBiosFolder(core: core) else { return nil }

        let start = CFAbsoluteTimeGetCurrent()
        guard let audit = MameSetAuditor.audit(romgameKey: romgameKey, archiveFileName: archiveFileName, biosFolder: biosFolder) else {
            RetroGoLogger.mame.info("Launch check: \(archiveFileName) is not a recognized set; launching without a check")
            return nil
        }
        RetroGoLogger.mame.info("Launch check: \(archiveFileName) -> \(audit.machine.name, privacy: .public)\(audit.gameStagedName.map { " (staged as \($0))" } ?? "", privacy: .public): \(String(describing: audit.verdict), privacy: .public), \(audit.problems.count) missing, \(audit.links.count) links, \(audit.extractions.count) extractions, \(audit.requiredDisks.count) CHDs, driver \(audit.machine.driverStatus ?? "-", privacy: .public) (\(CFAbsoluteTimeGetCurrent() - start, format: .fixed(precision: 3))s)")
        for problem in audit.problems {
            RetroGoLogger.mame.debug("Launch check missing \(problem.fileName, privacy: .public) (\(String(describing: problem.source), privacy: .public))")
        }
        return audit
    }

    // MARK: - Session

    /// Paths of the archives the session links or extracts from, by owner.
    private static func sourcePaths(for audit: MameSetAudit, core: EmuCoreInfoItem) -> [String: String] {
        let biosFolder = MameBiosFolder(core: core)
        var paths: [String: String] = [:]
        func resolve(_ owner: MameArchiveOwner) {
            let id = sourceId(owner)
            guard paths[id] == nil else { return }
            switch owner {
                case .game(let key): paths[id] = RetroRomFileManager.shared.fileItem(key: key)?.entryPath
                case .bios(let fileName): paths[id] = biosFolder?.filePath(fileName)
            }
        }
        audit.links.forEach { resolve(.game(romgameKey: $0.romgameKey)) }
        audit.extractions.forEach { resolve($0.source) }
        return paths
    }

    private static func sourceId(_ owner: MameArchiveOwner) -> String {
        switch owner {
            case .game(let key): return "game:" + key
            case .bios(let fileName): return "bios:" + fileName
        }
    }

    /// Takes the planned files out of their archives, one pass per archive (a solid 7z
    /// block is decompressed once). Returns staged path -> extracted file.
    private static func extractFiles(_ extractions: [MameSetAudit.Extraction], sources: [String: String]) -> [String: String] {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: extractionDirectory)
        guard !extractions.isEmpty else { return [:] }

        let start = CFAbsoluteTimeGetCurrent()
        var result: [String: String] = [:]
        let byArchive = Dictionary(grouping: extractions) { sourceId($0.source) }
        for (id, items) in byArchive {
            guard let archivePath = sources[id] else {
                RetroGoLogger.mame.notice("Launch check: source of \(items.count) files no longer exists (\(id, privacy: .public))")
                continue
            }
            var destinations: [String: String] = [:]
            for item in items where destinations[item.entryName] == nil {
                destinations[item.entryName] = extractionDirectory.appendingPathComponent(item.stagedPath).path
            }
            do {
                try RAArchiveReader.extractEntries(destinations, fromArchiveAtPath: archivePath)
                for item in items {
                    if let path = destinations[item.entryName] {
                        result[item.stagedPath] = path
                    }
                }
            } catch {
                RetroGoLogger.mame.error("Extraction from \((archivePath as NSString).lastPathComponent) failed: \(error.localizedDescription)")
            }
        }
        RetroGoLogger.mame.info("Launch check extracted \(result.count) of \(extractions.count) files in \(CFAbsoluteTimeGetCurrent() - start, format: .fixed(precision: 2))s")
        return result
    }

    /// Hands the session plan to the core, which applies it when it stages the session.
    private static func prepareSession(_ audit: MameSetAudit, sources: [String: String], extracted: [String: String],
                                       core: EmuCoreInfoItem) {
        var links = extracted
        for link in audit.links {
            if let path = sources[sourceId(.game(romgameKey: link.romgameKey))] {
                links[link.stagedName] = path
            }
        }
        core.pendingMameSessionLinks = links.isEmpty ? nil : links
        core.pendingMameSessionGameName = audit.gameStagedName
        if !links.isEmpty {
            RetroGoLogger.mame.debug("Launch check session links: \(links.keys.sorted().joined(separator: ", "), privacy: .public)")
        }
    }

    // MARK: - Report

    private static func present(_ audit: MameSetAudit, gameName: String, launch: @escaping () -> Void,
                                cancel: @escaping () -> Void) {
        let title: String
        if !audit.problems.isEmpty {
            title = Bundle.localizedString(forKey: "mame_check_title_missing")
        } else if !audit.requiredDisks.isEmpty {
            title = Bundle.localizedString(forKey: "mame_check_title_chd")
        } else {
            title = Bundle.localizedString(forKey: "mame_check_title_warning")
        }

        let alert = UIAlertController(title: title, message: message(for: audit, gameName: gameName), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel) { _ in
            cancel()
        })
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "mame_check_launch_anyway"), style: .default) { _ in
            launch()
        })
        UIViewController.currentActive()?.present(alert, animated: true)
    }

    private static func message(for audit: MameSetAudit, gameName: String) -> String {
        var paragraphs: [String] = []

        if !audit.problems.isEmpty {
            var order: [MameSetAudit.Source] = []
            var files: [MameSetAudit.Source: [String]] = [:]
            for problem in audit.problems {
                if files[problem.source] == nil {
                    order.append(problem.source)
                }
                files[problem.source, default: []].append(problem.fileName)
            }
            let lines = order.map { source -> String in
                let names = files[source] ?? []
                let list = fileList(names)
                switch source {
                    case .game:
                        return String(format: Bundle.localizedString(forKey: "mame_check_missing_game"), names.count, list)
                    case .parent(let set):
                        return String(format: Bundle.localizedString(forKey: "mame_check_missing_parent"), set, names.count, list)
                    case .bios(let set):
                        return String(format: Bundle.localizedString(forKey: "mame_check_missing_bios"), set, names.count, list)
                    case .device(let set):
                        return String(format: Bundle.localizedString(forKey: "mame_check_missing_device"), set, names.count, list)
                }
            }
            paragraphs.append(String(format: Bundle.localizedString(forKey: "mame_check_intro"), gameName)
                              + "\n" + lines.joined(separator: "\n"))

            // A broken BIOS blocks every game on that board, which users read as
            // "nothing works"; spell out that it's shared and what fixes it.
            let biosSets = order.compactMap { source -> String? in
                if case .bios(let set) = source { return set }
                return nil
            }
            if !biosSets.isEmpty {
                paragraphs.append(String(format: Bundle.localizedString(forKey: "mame_check_bios_hint"),
                                         biosSets.joined(separator: ", "),
                                         biosSets.map { "\($0).zip" }.joined(separator: ", ")))
            }
        }

        if !audit.requiredDisks.isEmpty {
            paragraphs.append(String(format: Bundle.localizedString(forKey: "mame_check_chd"),
                                     audit.requiredDisks.map { "\($0).chd" }.joined(separator: ", ")))
        }
        if audit.mayNotRun {
            paragraphs.append(Bundle.localizedString(forKey: "mame_check_driver_warning"))
        }
        return paragraphs.joined(separator: "\n\n")
    }

    private static func fileList(_ names: [String]) -> String {
        let listed = names.prefix(listedFileLimit).joined(separator: ", ")
        return names.count > listedFileLimit ? listed + ", …" : listed
    }
}
