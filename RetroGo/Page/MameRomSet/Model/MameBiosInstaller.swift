//
//  MameBiosInstaller.swift
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

import Foundation
import RACoordinator

struct MameBiosInstallResult {
    enum Outcome {
        /// Copied into the MAME BIOS folder (new, or replacing a less complete copy).
        case installed
        /// Each copy had required files the other lacked: the installed copy was rebuilt
        /// with the new copy's extra files added (`addedFiles`).
        case merged
        /// The folder already has a copy covering at least the same required files.
        case keptExisting
        case failed
    }

    /// The user's file name, e.g. "neogeo_v2.zip".
    let sourceName: String
    /// The name in the MAME BIOS folder, always the set name, e.g. "neogeo.zip".
    let installedName: String
    let outcome: Outcome
    var addedFiles = 0
}

/// Installs BIOS/device archives into the MAME system folder, where every file is
/// linked into each MAME session.
///
/// BIOS zips come in many variants (other MAME versions, FBNeo, partial rebuilds), so
/// copies are compared by which of the set's required files they contain, never by
/// file hash. A new copy replaces the installed one only when it holds everything the
/// installed one does plus at least one more file, so no BIOS option that worked
/// before can break. When each copy has required files the other lacks, they are
/// merged into one zip: the installed copy stays as is and the new copy's extra
/// required files are added; the previous file goes to the repair backup folder.
final class MameBiosInstaller {
    private let core: EmuCoreInfoItem
    private let folder: MameBiosFolder

    /// `core` must be the MAME core. Nil when its system folder cannot be created.
    init?(core: EmuCoreInfoItem) {
        guard let folder = MameBiosFolder(core: core) else { return nil }
        self.core = core
        self.folder = folder
    }

    func install(_ match: MameArchiveMatch, sourceURL: URL, sourceName: String) -> MameBiosInstallResult {
        let setName = match.machine.name
        let targetName = "\(setName).\(match.formatName)"
        let persistence = MameRomSetPersistence.shared
        let required = persistence.romKeys(of: setName, filter: .required)
        let newCoverage = required.intersection(match.entryKeys)

        // The set may already be installed as zip or 7z; MAME accepts either.
        let installedNames = folder.installedFileNames(ofSet: setName)
        let bestInstalled = installedNames.map { ($0, required.intersection(folder.entryKeys(fileName: $0))) }
            .max { $0.1.count < $1.1.count }
        if let (baseName, baseCoverage) = bestInstalled, !newCoverage.isStrictSuperset(of: baseCoverage) {
            let extra = newCoverage.subtracting(baseCoverage)
            if !extra.isEmpty {
                return merge(match, sourceURL: sourceURL, sourceName: sourceName, baseName: baseName,
                             extraKeys: extra, installedNames: installedNames, requiredCount: required.count)
            }
            NSLog("[MameBios] Kept installed %@ (%d/%d required files); %@ has %d",
                  setName, baseCoverage.count, required.count, sourceName, newCoverage.count)
            return MameBiosInstallResult(sourceName: sourceName, installedName: targetName, outcome: .keptExisting)
        }

        guard copyIntoSystemFolder(sourceURL: sourceURL, targetName: targetName) else {
            return MameBiosInstallResult(sourceName: sourceName, installedName: targetName, outcome: .failed)
        }
        // Drop a copy in the other format so only the most complete one remains.
        for name in installedNames where name != targetName {
            removeFromSystemFolder(fileName: name)
        }
        for name in installedNames {
            persistence.deleteArchive(owner: .bios(fileName: name))
        }
        persistence.storeArchive(owner: .bios(fileName: targetName), format: match.formatName,
                                 matchedSet: setName, matchKind: match.kind.rawValue, entries: match.entries)

        NSLog("[MameBios] Installed %@ as %@ (%d/%d required files)", sourceName, targetName, newCoverage.count, required.count)
        return MameBiosInstallResult(sourceName: sourceName, installedName: targetName, outcome: .installed)
    }

    /// Rebuilds `<set>.zip` from every entry of the installed copy plus the new copy's
    /// required files the installed one lacks. Entries whose name is already taken keep
    /// the installed file.
    private func merge(_ match: MameArchiveMatch, sourceURL: URL, sourceName: String, baseName: String,
                       extraKeys: Set<MameRomKey>, installedNames: [String], requiredCount: Int) -> MameBiosInstallResult {
        let setName = match.machine.name
        let targetName = "\(setName).zip"
        let failed = MameBiosInstallResult(sourceName: sourceName, installedName: targetName, outcome: .failed)
        let basePath = folder.filePath(baseName)
        guard let baseEntries = try? RAArchiveReader.entriesOfArchive(atPath: basePath) else {
            NSLog("[MameBios] Cannot read installed %@", baseName)
            return failed
        }

        var usedNames = Set(baseEntries.map { $0.name.lowercased() })
        var additions: [RAArchiveEntry] = []
        for entry in match.entries where entry.hasCRC {
            let key = MameRomKey(crc: entry.crc32, size: Int64(clamping: entry.size))
            guard extraKeys.contains(key), !usedNames.contains(entry.name.lowercased()) else { continue }
            additions.append(entry)
            usedNames.insert(entry.name.lowercased())
        }
        guard !additions.isEmpty else {
            NSLog("[MameBios] Kept installed %@; the extra files of %@ clash with existing names", baseName, sourceName)
            return MameBiosInstallResult(sourceName: sourceName, installedName: targetName, outcome: .keptExisting)
        }

        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory.appendingPathComponent("MameBiosMerge-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: work) }
        let merged = work.appendingPathComponent(targetName)
        do {
            try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
            let writer = try RAZipWriter(path: merged.path)
            do {
                try writer.add(baseEntries, fromArchiveAtPath: basePath, asNames: baseEntries.map(\.name))
                try writer.add(additions, fromArchiveAtPath: sourceURL.path, asNames: additions.map(\.name))
                try writer.finish()
            } catch {
                writer.cancel()
                throw error
            }
            // Keep the previous copy with the repair backups before it is replaced.
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let backupFolder = (AppConfig.shared.mameRepairBackupFolder as NSString)
                .appendingPathComponent("\(formatter.string(from: Date()))-\(setName)-bios")
            try fileManager.createDirectory(atPath: backupFolder, withIntermediateDirectories: true)
            try fileManager.copyItem(atPath: basePath, toPath: (backupFolder as NSString).appendingPathComponent(baseName))
        } catch {
            NSLog("[MameBios] Merging %@ into %@ failed: %@", sourceName, baseName, error.localizedDescription)
            return failed
        }

        guard copyIntoSystemFolder(sourceURL: merged, targetName: targetName) else {
            return failed
        }
        let persistence = MameRomSetPersistence.shared
        for name in installedNames where name != targetName {
            removeFromSystemFolder(fileName: name)
        }
        for name in installedNames {
            persistence.deleteArchive(owner: .bios(fileName: name))
        }
        if let entries = try? RAArchiveReader.entriesOfArchive(atPath: folder.filePath(targetName)) {
            persistence.storeArchive(owner: .bios(fileName: targetName), format: "zip", matchedSet: setName,
                                     matchKind: match.kind.rawValue, entries: entries)
        }

        let coverage = persistence.romKeys(of: setName, filter: .required)
            .intersection(folder.entryKeys(fileName: targetName)).count
        NSLog("[MameBios] Merged %@ into %@: added %d files, now %d/%d required", sourceName, targetName,
              additions.count, coverage, requiredCount)
        var result = MameBiosInstallResult(sourceName: sourceName, installedName: targetName, outcome: .merged)
        result.addedFiles = additions.count
        return result
    }

    /// Goes through the core's firmware list so the new file is linked into MAME sessions
    /// without restarting the app. The list is UI state, hence the main thread.
    private func copyIntoSystemFolder(sourceURL: URL, targetName: String) -> Bool {
        let fileManager = FileManager.default
        let stagingDirectory = fileManager.temporaryDirectory.appendingPathComponent("MameBios-\(UUID().uuidString)")
        let stagedURL = stagingDirectory.appendingPathComponent(targetName)
        defer {
            try? fileManager.removeItem(at: stagingDirectory)
        }
        do {
            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceURL, to: stagedURL)
        } catch {
            NSLog("[MameBios] Failed to stage %@: %@", targetName, error.localizedDescription)
            return false
        }

        let core = self.core
        let imported = DispatchQueue.main.sync {
            core.importFirmwareFile(stagedURL) != nil
        }
        if !imported {
            NSLog("[MameBios] Failed to copy %@ into the MAME BIOS folder", targetName)
        }
        return imported
    }

    private func removeFromSystemFolder(fileName: String) {
        let core = self.core
        DispatchQueue.main.sync {
            if let firmware = core.firmwares?.first(where: { $0.name == fileName }) {
                _ = core.deleteFirmware(firmware)
            } else {
                try? FileManager.default.removeItem(atPath: folder.filePath(fileName))
            }
        }
    }
}
