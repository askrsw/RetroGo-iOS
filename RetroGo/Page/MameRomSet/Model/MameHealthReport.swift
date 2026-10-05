//
//  MameHealthReport.swift
//  RetroGo
//
//  Created by haharsw on 2026/9/27.
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
import RACoordinator
import os

/// State of every recognized arcade game in the Library plus the BIOS/device files in
/// the MAME BIOS folder, computed with the same audit the launch check uses.
struct MameHealthReport {
    enum Status: Int, CaseIterable {
        case missingFiles
        case needsCHD
        case mayNotRun
        case complete
    }

    struct Game {
        let key: String
        let name: String
        let archiveFileName: String
        let audit: MameSetAudit

        var status: Status {
            if !audit.problems.isEmpty { return .missingFiles }
            if !audit.requiredDisks.isEmpty { return .needsCHD }
            if audit.mayNotRun { return .mayNotRun }
            return .complete
        }
    }

    struct Bios {
        let fileName: String
        let setName: String
        let description: String?
        /// Required files of the set present in the file.
        let covered: Int
        let required: Int
    }

    /// A game whose repair would add missing files (not merely rename or convert it).
    struct Repairable {
        let game: Game
        let plan: MameSetRepairer.Plan
    }

    let games: [Status: [Game]]
    let bios: [Bios]
    let repairable: [Repairable]
    /// Originals kept by earlier repairs.
    let backupFileCount: Int
    let backupBytes: Int64

    var gameCount: Int {
        games.values.reduce(0) { $0 + $1.count }
    }

    /// Call on the main thread; `completion` runs on the main thread.
    static func build(core: EmuCoreInfoItem, completion: @escaping (MameHealthReport) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        // Library items live on the main thread; the audits run in the background.
        let candidates = RetroRomItemTraversal.allFiles(under: "root").compactMap { item -> (String, String, String)? in
            guard item.fileGroupType == .single,
                  RAArchiveReader.formatOfArchive(atPath: item.rawName) != .unknown else { return nil }
            return (item.key, item.rawName, item.itemName)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let start = CFAbsoluteTimeGetCurrent()
            var games: [Status: [Game]] = [:]
            var bios: [Bios] = []
            var repairable: [Repairable] = []
            if MameCatalogBuilder.shared.waitUntilReady(), let folder = MameBiosFolder(core: core) {
                for (key, fileName, name) in candidates {
                    guard let audit = MameSetAuditor.audit(romgameKey: key, archiveFileName: fileName, biosFolder: folder) else {
                        continue
                    }
                    let game = Game(key: key, name: name, archiveFileName: fileName, audit: audit)
                    games[game.status, default: []].append(game)
                }
                for key in games.keys {
                    games[key]?.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }
                bios = biosEntries(folder: folder)
                for game in Status.allCases.flatMap({ games[$0] ?? [] }) {
                    if let plan = try? MameSetRepairer.makePlan(romgameKey: game.key), !plan.additions.isEmpty {
                        repairable.append(Repairable(game: game, plan: plan))
                    }
                }
            }
            let backup = backupUsage()
            let report = MameHealthReport(games: games, bios: bios, repairable: repairable,
                                          backupFileCount: backup.count, backupBytes: backup.bytes)
            RetroGoLogger.mame.info("Health report: \(report.gameCount) games (\(Status.allCases.map { "\($0): \(games[$0]?.count ?? 0)" }.joined(separator: ", "), privacy: .public)), \(bios.count) BIOS files in \(CFAbsoluteTimeGetCurrent() - start, format: .fixed(precision: 3))s")
            DispatchQueue.main.async {
                completion(report)
            }
        }
    }

    static func backupUsage() -> (count: Int, bytes: Int64) {
        let folder = URL(fileURLWithPath: AppConfig.shared.mameRepairBackupFolder)
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else {
            return (0, 0)
        }
        var count = 0
        var bytes: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                count += 1
                bytes += Int64(values?.fileSize ?? 0)
            }
        }
        return (count, bytes)
    }

    /// Removes every repair backup.
    static func clearBackups() {
        let folder = AppConfig.shared.mameRepairBackupFolder
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] {
            try? FileManager.default.removeItem(atPath: (folder as NSString).appendingPathComponent(name))
        }
        RetroGoLogger.mame.info("Cleared repair backups")
    }

    /// Archives in the BIOS folder named after a BIOS or device set.
    private static func biosEntries(folder: MameBiosFolder) -> [Bios] {
        let persistence = MameRomSetPersistence.shared
        let fileNames = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return fileNames.sorted().compactMap { fileName in
            guard MameBiosFolder.archiveExtensions.contains((fileName as NSString).pathExtension.lowercased()) else {
                return nil
            }
            let setName = (fileName as NSString).deletingPathExtension.lowercased()
            guard let machine = persistence.machine(named: setName), machine.isSupportSet else { return nil }
            let required = persistence.romKeys(of: setName, filter: .required)
            let covered = required.intersection(folder.entryKeys(fileName: fileName)).count
            return Bios(fileName: fileName, setName: setName, description: machine.description,
                        covered: covered, required: required.count)
        }
    }
}
