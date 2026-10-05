//
//  MameSetRepairer.swift
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
import ObjcHelper
import RACoordinator
import os

enum MameSetRepairError: LocalizedError {
    case notRecognized
    case missingFiles([String])
    case nameTaken(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
            case .notRecognized:
                return Bundle.localizedString(forKey: "mame_repair_error_not_recognized")
            case .missingFiles(let names):
                return String(format: Bundle.localizedString(forKey: "mame_repair_error_missing"), names.joined(separator: ", "))
            case .nameTaken(let name):
                return String(format: Bundle.localizedString(forKey: "mame_repair_error_name_taken"), name)
            case .failed(let reason):
                return reason
        }
    }
}

/// Rebuilds a Library game's archive as `<set>.zip` holding everything it had plus the
/// set's own files found in other indexed archives.
///
/// Nothing is ever dropped from the original: a merged parent zip may carry files its
/// clones need. Files merged from the parent or BIOS are not added either (split
/// layout); those stay with their own sets and are linked at launch.
///
/// The original moves to the backup folder before the new file takes its place; any
/// failure puts it back and leaves roms.db untouched. The game keeps its key, display
/// name, save states, thumbnail and settings.
///
/// Every function here blocks and must run off the main thread.
enum MameSetRepairer {
    struct Plan {
        struct Addition {
            /// Name in the rebuilt zip (the set's file name).
            let name: String
            let entry: RAArchiveEntry
            let archivePath: String
        }

        let romgameKey: String
        let setName: String
        let archivePath: String
        let archiveFileName: String
        /// Everything already in the game's archive, kept as is.
        let kept: [RAArchiveEntry]
        let additions: [Addition]

        var targetFileName: String {
            "\(setName).zip"
        }
    }

    /// Nil when the archive is already a complete `<set>.zip`; throws when the game cannot
    /// be repaired (unrecognized, or own files missing everywhere).
    static func makePlan(romgameKey: String) throws -> Plan? {
        let persistence = MameRomSetPersistence.shared
        guard let record = persistence.archiveRecord(owner: .game(romgameKey: romgameKey)),
              let (archivePath, archiveFileName) = DispatchQueue.main.sync(execute: { () -> (String, String)? in
                  guard let item = RetroRomFileManager.shared.fileItem(key: romgameKey), let path = item.entryPath else { return nil }
                  return (path, item.rawName)
              }) else {
            throw MameSetRepairError.notRecognized
        }
        let setName = record.matchedSet

        var listings: [String: [RAArchiveEntry]] = [:]
        func entries(of path: String) -> [RAArchiveEntry] {
            if let cached = listings[path] { return cached }
            let listed = (try? RAArchiveReader.entriesOfArchive(atPath: path)) ?? []
            listings[path] = listed
            return listed
        }
        func key(_ entry: RAArchiveEntry) -> MameRomKey? {
            entry.hasCRC ? MameRomKey(crc: entry.crc32, size: Int64(clamping: entry.size)) : nil
        }

        let kept = entries(of: archivePath)
        guard !kept.isEmpty else { throw MameSetRepairError.failed("Cannot read \(archiveFileName)") }
        let present = Set(kept.compactMap(key))
        var usedNames = Set(kept.map { $0.name.lowercased() })

        var additions: [Plan.Addition] = []
        var missing: [String] = []
        for (rom, optional) in persistence.ownRoms(of: setName) where !present.contains(rom.key) {
            guard !usedNames.contains(rom.name.lowercased()) else {
                // A same-named file with other content is already there; keep the user's.
                continue
            }
            var found: Plan.Addition?
            for source in persistence.archivesContaining(rom.key) {
                if case .game(let key) = source.owner, key == romgameKey { continue }
                guard let path = sourcePath(source.owner),
                      let entry = entries(of: path).first(where: { self.matches($0, rom.key) }) else { continue }
                found = Plan.Addition(name: rom.name, entry: entry, archivePath: path)
                break
            }
            if let found {
                additions.append(found)
                usedNames.insert(rom.name.lowercased())
            } else if !optional {
                missing.append(rom.name)
            }
        }
        guard missing.isEmpty else {
            throw MameSetRepairError.missingFiles(missing)
        }

        let plan = Plan(romgameKey: romgameKey, setName: setName, archivePath: archivePath,
                        archiveFileName: archiveFileName, kept: kept, additions: additions)
        let needsRepair = !additions.isEmpty || archiveFileName.lowercased() != plan.targetFileName
        return needsRepair ? plan : nil
    }

    static func repair(_ plan: Plan) throws {
        let fileManager = FileManager.default
        let start = CFAbsoluteTimeGetCurrent()

        // 1. Build the new zip in a scratch folder.
        let work = fileManager.temporaryDirectory.appendingPathComponent("MameRepair-\(UUID().uuidString)")
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: work) }
        let rebuilt = work.appendingPathComponent(plan.targetFileName).path

        let writer = try RAZipWriter(path: rebuilt)
        do {
            // One batch per source archive: a solid 7z block is decompressed only once.
            try writer.add(plan.kept, fromArchiveAtPath: plan.archivePath, asNames: plan.kept.map(\.name))
            for (path, additions) in Dictionary(grouping: plan.additions, by: \.archivePath) {
                try writer.add(additions.map(\.entry), fromArchiveAtPath: path, asNames: additions.map(\.name))
            }
            try writer.finish()
        } catch {
            writer.cancel()
            throw error
        }

        let backupFolder = try install(newFile: rebuilt, romgameKey: plan.romgameKey, archivePath: plan.archivePath,
                                       archiveFileName: plan.archiveFileName, targetFileName: plan.targetFileName,
                                       setName: plan.setName, format: "zip", matchKind: .name)
        RetroGoLogger.mame.info("Repaired \(plan.archiveFileName) -> \(plan.targetFileName, privacy: .public): kept \(plan.kept.count), added \(plan.additions.count), backup \(backupFolder) (\(CFAbsoluteTimeGetCurrent() - start, format: .fixed(precision: 2))s)")
    }

    /// Replaces a Library game's archive with a more complete copy of the same set picked
    /// at import (the conflicting file). The file keeps the game's current name.
    static func replaceArchive(romgameKey: String, withFileAt sourcePath: String, match: MameArchiveMatch) throws {
        let fileManager = FileManager.default
        guard let (archivePath, archiveFileName) = DispatchQueue.main.sync(execute: { () -> (String, String)? in
            guard let item = RetroRomFileManager.shared.fileItem(key: romgameKey), let path = item.entryPath else { return nil }
            return (path, item.rawName)
        }) else {
            throw MameSetRepairError.notRecognized
        }
        let work = fileManager.temporaryDirectory.appendingPathComponent("MameReplace-\(UUID().uuidString)")
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: work) }
        let staged = work.appendingPathComponent(archiveFileName).path
        try fileManager.copyItem(atPath: sourcePath, toPath: staged)

        let backupFolder = try install(newFile: staged, romgameKey: romgameKey, archivePath: archivePath,
                                       archiveFileName: archiveFileName, targetFileName: archiveFileName,
                                       setName: match.machine.name, format: match.formatName, matchKind: match.kind)
        RetroGoLogger.mame.notice("Replaced \(archiveFileName) with a more complete copy, backup \(backupFolder)")
    }

    /// Puts `newFile` in place of the game's archive: original to the backup folder, new
    /// file under `targetFileName`, roms.db, the romset index and the in-memory Library
    /// item updated. Any failure restores the original. Returns the backup folder.
    private static func install(newFile: String, romgameKey: String, archivePath: String, archiveFileName: String,
                                targetFileName: String, setName: String, format: String,
                                matchKind: MameArchiveMatch.Kind) throws -> String {
        let fileManager = FileManager.default
        // 1. Swap the files, original to the backup folder.
        let folder = (archivePath as NSString).deletingLastPathComponent
        let target = (folder as NSString).appendingPathComponent(targetFileName)
        if target != archivePath && fileManager.fileExists(atPath: target) {
            throw MameSetRepairError.nameTaken(targetFileName)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupFolder = (AppConfig.shared.mameRepairBackupFolder as NSString)
            .appendingPathComponent("\(formatter.string(from: Date()))-\(setName)")
        try fileManager.createDirectory(atPath: backupFolder, withIntermediateDirectories: true)
        let backup = (backupFolder as NSString).appendingPathComponent(archiveFileName)

        try fileManager.moveItem(atPath: archivePath, toPath: backup)
        func restoreOriginal() {
            try? fileManager.removeItem(atPath: target)
            try? fileManager.moveItem(atPath: backup, toPath: archivePath)
        }
        do {
            try fileManager.moveItem(atPath: newFile, toPath: target)
        } catch {
            restoreOriginal()
            throw error
        }

        // 2. Point the Library entry at the new file.
        let targetURL = URL(fileURLWithPath: target) as NSURL
        let size = (try? fileManager.attributesOfItem(atPath: target)[.size] as? NSNumber)?.intValue ?? 0
        let crc32 = try? targetURL.computeCRC32String()
        guard let sha256 = try? targetURL.computeSHA256String(),
              RetroRomPersistence.shared.replaceSingleFile(key: romgameKey, oldRawName: archiveFileName,
                                                           newRawName: targetFileName, sha256: sha256,
                                                           crc32: crc32, fileSize: size) else {
            restoreOriginal()
            throw MameSetRepairError.failed(Bundle.localizedString(forKey: "mame_repair_error_database"))
        }

        // 3. Index the new archive and update the Library item in place, so views holding
        //    it launch the new file without an app restart.
        if let entries = try? RAArchiveReader.entriesOfArchive(atPath: target) {
            MameRomSetPersistence.shared.storeArchive(owner: .game(romgameKey: romgameKey), format: format,
                                                      matchedSet: setName, matchKind: matchKind.rawValue, entries: entries)
        }
        DispatchQueue.main.sync {
            RetroRomFileManager.shared.fileItem(key: romgameKey)?
                .applyReplacedSingleFile(rawName: targetFileName, sha256: sha256, crc32: crc32, fileSize: size)
            NotificationCenter.default.post(name: .romCountChanged, object: nil)
        }
        return backupFolder
    }

    // MARK: - Helpers

    private static func matches(_ entry: RAArchiveEntry, _ key: MameRomKey) -> Bool {
        entry.hasCRC && entry.crc32 == key.crc && Int64(clamping: entry.size) == key.size
    }

    private static func sourcePath(_ owner: MameArchiveOwner) -> String? {
        switch owner {
            case .game(let key):
                return DispatchQueue.main.sync { RetroRomFileManager.shared.fileItem(key: key)?.entryPath }
            case .bios(let fileName):
                return DispatchQueue.main.sync { () -> String? in
                    guard let core = RetroArchX.shared().allCores.first(where: { $0.coreId == MameImportScreener.mameCoreId }) else {
                        return nil
                    }
                    return MameBiosFolder(core: core)?.filePath(fileName)
                }
        }
    }
}
