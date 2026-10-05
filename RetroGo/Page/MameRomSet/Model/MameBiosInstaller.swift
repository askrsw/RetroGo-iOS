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
import ObjcHelper
import RACoordinator
import os

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
    /// Required files the set still lacks in the BIOS folder after this import.
    var missingFiles: [String] = []
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
        var result = installArchive(match, sourceURL: sourceURL, sourceName: sourceName)
        if result.outcome != .failed {
            result.missingFiles = folder.missingFiles(ofSet: match.machine.name) ?? []
        }
        return result
    }

    private func installArchive(_ match: MameArchiveMatch, sourceURL: URL, sourceName: String) -> MameBiosInstallResult {
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
            RetroGoLogger.mame.info("Kept installed BIOS \(setName, privacy: .public) (\(baseCoverage.count)/\(required.count) required files); \(sourceName) has \(newCoverage.count)")
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

        RetroGoLogger.mame.info("Installed BIOS \(sourceName) as \(targetName, privacy: .public) (\(newCoverage.count)/\(required.count) required files)")
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
            RetroGoLogger.mame.error("Cannot read installed BIOS \(baseName, privacy: .public)")
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
            RetroGoLogger.mame.notice("Kept installed BIOS \(baseName, privacy: .public); the extra files of \(sourceName) clash with existing names")
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
            RetroGoLogger.mame.error("Merging \(sourceName) into BIOS \(baseName, privacy: .public) failed: \(error.localizedDescription)")
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
        RetroGoLogger.mame.info("Merged \(sourceName) into BIOS \(targetName, privacy: .public): added \(additions.count) files, now \(coverage)/\(requiredCount) required")
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
            RetroGoLogger.mame.error("Failed to stage BIOS \(targetName, privacy: .public): \(error.localizedDescription)")
            return false
        }

        let core = self.core
        let imported = DispatchQueue.main.sync {
            core.importFirmwareFile(stagedURL) != nil
        }
        if !imported {
            RetroGoLogger.mame.error("Failed to copy \(targetName, privacy: .public) into the MAME BIOS folder")
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

// MARK: - Importing from the MAME core page

extension MameBiosInstaller {
    /// Imports files picked on the MAME core page (one file, or the files directly inside
    /// a folder) into the BIOS folder. Recognized BIOS/device archives go through the
    /// installer exactly like a Library import: named after their set, merged with the
    /// installed copy and indexed. Anything else is copied as is, replacing a file of the
    /// same name. Call off the main thread; returns the result message.
    static func importPicked(_ url: URL, core: EmuCoreInfoItem, progress: (String) -> Void) -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) else {
            return Bundle.localizedString(forKey: "coreinfo_firmware_import_zero")
        }
        let files: [URL]
        if isDirectory.boolValue {
            let contents = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                                 options: [.skipsHiddenFiles])) ?? []
            files = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } else {
            files = [url]
        }

        let isArchive: (URL) -> Bool = { MameBiosFolder.archiveExtensions.contains($0.pathExtension.lowercased()) }
        let catalogReady = files.contains(where: isArchive) && MameCatalogBuilder.shared.waitUntilReady()
        let installer = catalogReady ? MameBiosInstaller(core: core) : nil

        var biosResults: [MameBiosInstallResult] = []
        var copied = 0
        for file in files {
            let fileName = file.lastPathComponent
            progress(fileName)
            if let installer, isArchive(file),
               let match = MameArchiveIdentifier.identify(archiveAtPath: file.path(percentEncoded: false), fileName: fileName),
               match.machine.isSupportSet {
                biosResults.append(installer.install(match, sourceURL: file, sourceName: fileName))
                continue
            }
            let imported = DispatchQueue.main.sync { core.importFirmwareFile(file) }
            if let imported {
                // Copied as is: the romset index no longer describes this file.
                MameRomSetPersistence.shared.deleteArchive(owner: .bios(fileName: imported.name))
                copied += 1
            }
        }
        RetroGoLogger.mame.info("Core page import: \(biosResults.count) BIOS/device archives, \(copied) files copied as is")

        var paragraphs: [String] = []
        if copied > 0 {
            paragraphs.append(String(format: Bundle.localizedString(forKey: "coreinfo_firmware_import_success"), copied))
        }
        if let notice = MameImportScreener.noticeText(biosResults) {
            paragraphs.append(notice)
        }
        return paragraphs.isEmpty ? Bundle.localizedString(forKey: "coreinfo_firmware_import_zero")
                                  : paragraphs.joined(separator: "\n\n")
    }
}
