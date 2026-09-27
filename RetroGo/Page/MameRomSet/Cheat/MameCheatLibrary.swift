//
//  MameCheatLibrary.swift
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

import SQLite
import Foundation
import ObjcHelper
import RACoordinator

/// Cheat XMLs for the sets of the MAME core, imported from Pugsy's cheat.7z by the user.
///
/// MAME's own cheat engine runs them: before a launch the file of the running set (or of
/// its parent) is written to `<MAME system folder>/mame/cheat/<staged name>.xml`, the only
/// name the engine looks for. The engine does not fall back to parent sets on its own.
final class MameCheatLibrary {
    static let shared = MameCheatLibrary()

    static let sourceName = "Pugsy's MAME Cheat Collection"
    static let sourceURL = URL(string: "https://www.mamecheat.co.uk")!

    enum ImportError: LocalizedError {
        case catalogUnavailable
        case noCheatFiles
        case extractFailed(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .catalogUnavailable:
                return Bundle.localizedString(forKey: "mame_cheat_import_error_catalog")
            case .noCheatFiles:
                return Bundle.localizedString(forKey: "mame_cheat_import_error_empty")
            case .extractFailed(let reason), .writeFailed(let reason):
                return reason
            }
        }
    }

    struct Info {
        let setCount: Int
        let fileCount: Int
        let sourceFileName: String?
        let importedAt: Date?
    }

    /// The cheat file written for the game about to run.
    struct SessionFile {
        let romKey: String
        /// Name MAME runs the game under, and so the XML's file name.
        let runName: String
        /// Set whose XML was used: the game's own set or its parent.
        let fileName: String
        let xml: Data
    }

    private static let schemaVersion: Int64 = 1
    private static let sessionFileKey = "MameCheatLibrary.sessionFilePath"

    private let lock = NSLock()
    private var db: Connection?
    /// Set on the main thread by `prepareSession`, read by the game page it launches.
    private(set) var sessionFile: SessionFile?

    private init() {
        db = Self.open(path: AppConfig.shared.mameCheatDatabasePath)
    }

    // MARK: - Status

    var isImported: Bool {
        info != nil
    }

    var info: Info? {
        lock.lock(); defer { lock.unlock() }
        guard let db else { return nil }
        do {
            let fileCount = try db.scalar("SELECT count(*) FROM cheat_file") as? Int64 ?? 0
            guard fileCount > 0 else { return nil }
            let setCount = try db.scalar("SELECT count(*) FROM game") as? Int64 ?? 0
            var meta: [String: String] = [:]
            for row in try db.prepare("SELECT key, value FROM meta") {
                if let key = row[0] as? String, let value = row[1] as? String { meta[key] = value }
            }
            let importedAt = meta["imported_at"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
            return Info(setCount: Int(setCount), fileCount: Int(fileCount), sourceFileName: meta["source_file"], importedAt: importedAt)
        } catch {
            NSLog("[MameCheat] Failed to read library info: %@", "\(error)")
            return nil
        }
    }

    // MARK: - Import

    /// Rebuilds the library from a cheat.7z (or cheat.zip). Only root-level `<set>.xml`
    /// files of sets the core knows are kept; software-list folders and the Lua plugin's
    /// .json files are ignored. Runs synchronously; call off the main thread.
    func importCollection(at url: URL, progress: (String) -> Void) throws -> Info {
        guard MameCatalogBuilder.shared.waitUntilReady() else { throw ImportError.catalogUnavailable }
        let sets = MameRomSetPersistence.shared.gameSets()
        guard !sets.isEmpty else { throw ImportError.catalogUnavailable }

        progress(Bundle.localizedString(forKey: "mame_cheat_import_reading"))
        let entries: [RAArchiveEntry]
        do {
            entries = try RAArchiveReader.entriesOfArchive(atPath: url.path)
        } catch {
            throw ImportError.extractFailed(error.localizedDescription)
        }
        let available = Set(entries.lazy.map(\.name).filter { !$0.contains("/") && $0.hasSuffix(".xml") }
            .map { String($0.dropLast(4)) })
        let setNames = Set(sets.map(\.name))
        let wanted = available.intersection(setNames)
        guard !wanted.isEmpty else { throw ImportError.noCheatFiles }

        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("MameCheatImport", isDirectory: true)
        try? FileManager.default.removeItem(at: workDir)
        defer { try? FileManager.default.removeItem(at: workDir) }
        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        } catch {
            throw ImportError.writeFailed(error.localizedDescription)
        }

        progress(String(format: Bundle.localizedString(forKey: "mame_cheat_import_extracting"), wanted.count))
        let start = CFAbsoluteTimeGetCurrent()
        var destinations: [String: String] = [:]
        for name in wanted {
            destinations["\(name).xml"] = workDir.appendingPathComponent("\(name).xml").path
        }
        do {
            try RAArchiveReader.extractEntries(destinations, fromArchiveAtPath: url.path)
        } catch {
            throw ImportError.extractFailed(error.localizedDescription)
        }
        NSLog("[MameCheat] Extracted %d cheat files in %.2fs", wanted.count, CFAbsoluteTimeGetCurrent() - start)

        progress(Bundle.localizedString(forKey: "mame_cheat_import_saving"))
        let tempPath = AppConfig.shared.mameCheatDatabasePath + ".importing"
        try? FileManager.default.removeItem(atPath: tempPath)
        do {
            let newDB = try Connection(tempPath)
            try Self.createSchema(newDB)
            try newDB.transaction {
                let insertFile = try newDB.prepare("INSERT INTO cheat_file(name, xml) VALUES (?, ?)")
                for name in wanted {
                    let data = try Data(contentsOf: workDir.appendingPathComponent("\(name).xml"))
                    let compressed = try (data as NSData).compressed(using: .zlib) as Data
                    try insertFile.run(name, compressed.datatypeValue)
                }
                let insertGame = try newDB.prepare("INSERT INTO game(name, file_name, from_parent) VALUES (?, ?, ?)")
                for set in sets {
                    if wanted.contains(set.name) {
                        try insertGame.run(set.name, set.name, 0)
                    } else if let parent = set.cloneOf, wanted.contains(parent) {
                        try insertGame.run(set.name, parent, 1)
                    }
                }
                let insertMeta = try newDB.prepare("INSERT INTO meta(key, value) VALUES (?, ?)")
                try insertMeta.run("source_file", url.lastPathComponent)
                try insertMeta.run("imported_at", String(Date().timeIntervalSince1970))
            }
        } catch {
            try? FileManager.default.removeItem(atPath: tempPath)
            throw ImportError.writeFailed(error.localizedDescription)
        }

        lock.lock()
        db = nil
        let path = AppConfig.shared.mameCheatDatabasePath
        do {
            _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: tempPath))
        } catch {
            db = Self.open(path: path)
            lock.unlock()
            throw ImportError.writeFailed(error.localizedDescription)
        }
        db = Self.open(path: path)
        lock.unlock()

        guard let info else { throw ImportError.noCheatFiles }
        NSLog("[MameCheat] Imported %d files covering %d sets from %@", info.fileCount, info.setCount, url.lastPathComponent)
        return info
    }

    func deleteLibrary() {
        lock.lock(); defer { lock.unlock() }
        db = nil
        try? FileManager.default.removeItem(atPath: AppConfig.shared.mameCheatDatabasePath)
        db = Self.open(path: AppConfig.shared.mameCheatDatabasePath)
    }

    // MARK: - Lookup

    /// The XML for a set: its own file or its parent's. Nil when neither exists.
    func cheatFile(forSet setName: String) -> (fileName: String, xml: Data)? {
        lock.lock(); defer { lock.unlock() }
        guard let db else { return nil }
        do {
            let sql = "SELECT f.name, f.xml FROM game g JOIN cheat_file f ON f.name = g.file_name WHERE g.name = ?"
            for row in try db.prepare(sql, setName.lowercased()) {
                guard let name = row[0] as? String, let blob = row[1] as? Blob else { continue }
                let xml = try (Data.fromDatatypeValue(blob) as NSData).decompressed(using: .zlib) as Data
                return (name, xml)
            }
        } catch {
            NSLog("[MameCheat] Failed to read cheats of %@: %@", setName, "\(error)")
        }
        return nil
    }

    // MARK: - Session file

    /// Writes the cheat file for the game about to launch, or removes the previous one when
    /// the set has none. `runName` is the name MAME runs it under (the staged set name, or
    /// the archive name); `setName` is the recognized set. Main thread.
    func prepareSession(romKey: String, runName: String, setName: String, core: EmuCoreInfoItem) {
        dispatchPrecondition(condition: .onQueue(.main))
        removeSessionFile()
        guard let file = cheatFile(forSet: setName), let directory = Self.cheatDirectory(core: core) else { return }
        let path = (directory as NSString).appendingPathComponent("\(runName).xml")
        do {
            try file.xml.write(to: URL(fileURLWithPath: path), options: .atomic)
            UserDefaults.standard.set(path, forKey: Self.sessionFileKey)
            sessionFile = SessionFile(romKey: romKey, runName: runName, fileName: file.fileName, xml: file.xml)
            NSLog("[MameCheat] %@ uses %@.xml as %@.xml", setName, file.fileName, runName)
        } catch {
            NSLog("[MameCheat] Failed to write %@: %@", path, error.localizedDescription)
        }
    }

    /// Takes the session file prepared for `romKey`; a stale one from another game is dropped.
    func takeSessionFile(romKey: String) -> SessionFile? {
        defer { sessionFile = nil }
        guard let sessionFile, sessionFile.romKey == romKey else { return nil }
        return sessionFile
    }

    /// Deletes the file written for the last session, including one left by a crash.
    func removeSessionFile() {
        sessionFile = nil
        guard let path = UserDefaults.standard.string(forKey: Self.sessionFileKey) else { return }
        try? FileManager.default.removeItem(atPath: path)
        UserDefaults.standard.removeObject(forKey: Self.sessionFileKey)
    }

    /// `-cheatpath` of the MAME core: `<system folder>/mame/cheat`.
    static func cheatDirectory(core: EmuCoreInfoItem) -> String? {
        guard let system = core.systemDirectoryPath() else { return nil }
        let directory = (system as NSString).appendingPathComponent("mame/cheat")
        guard FileManager.default.createDirectoryIfNotExists(atPath: directory) else { return nil }
        return directory
    }

    // MARK: - Database

    private static func open(path: String) -> Connection? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            let db = try Connection(path, readonly: true)
            guard (try db.scalar("PRAGMA user_version") as? Int64) == schemaVersion else {
                NSLog("[MameCheat] Ignoring library with unknown schema at %@", path)
                return nil
            }
            return db
        } catch {
            NSLog("[MameCheat] Failed to open %@: %@", path, "\(error)")
            return nil
        }
    }

    private static func createSchema(_ db: Connection) throws {
        try db.execute("""
            CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
            -- zlib-compressed original XML, named after the set it was written for.
            CREATE TABLE cheat_file (name TEXT PRIMARY KEY, xml BLOB NOT NULL) WITHOUT ROWID;
            -- Every game set of the core that has cheats: its own file, or its parent's.
            CREATE TABLE game (
              name TEXT PRIMARY KEY,
              file_name TEXT NOT NULL REFERENCES cheat_file(name),
              from_parent INTEGER NOT NULL
            ) WITHOUT ROWID;
            PRAGMA user_version = \(schemaVersion);
            """)
    }
}
