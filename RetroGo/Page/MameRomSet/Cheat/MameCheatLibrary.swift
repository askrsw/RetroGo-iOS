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
/// MAME's own cheat engine runs them. The launch records which set is about to run; once
/// the machine runs, `MameCheatSession` hands the set's XML (or its parent's: the engine
/// does not fall back to parent sets on its own) to the core in memory.
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
        /// From the first line of cheat.txt, e.g. "0.279" and "27 July 2025"; nil when
        /// cheat.7z was imported on its own.
        let releaseMameVersion: String?
        let releaseDate: String?
        /// Whether cheat.txt (credits, instructions) was kept.
        let hasNotes: Bool
    }

    /// The set of the game about to run, recorded by the launch check.
    struct Launch {
        let romKey: String
        let setName: String
    }

    private static let schemaVersion: Int64 = 1

    private let lock = NSLock()
    /// One import at a time: they share nothing but the library they replace.
    private let importLock = NSLock()
    private var db: Connection?
    /// Set on the main thread by `prepareLaunch`, taken by the game page it launches.
    private var pendingLaunch: Launch?

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
            let hasNotes = (try db.scalar("SELECT count(*) FROM meta WHERE key = 'notes'") as? Int64 ?? 0) > 0
            return Info(setCount: Int(setCount), fileCount: Int(fileCount), sourceFileName: meta["source_file"],
                        importedAt: importedAt, releaseMameVersion: meta["release_mame"], releaseDate: meta["release_date"],
                        hasNotes: hasNotes)
        } catch {
            NSLog("[MameCheat] Failed to read library info: %@", "\(error)")
            return nil
        }
    }

    // MARK: - Import

    /// What an archive holds, from its entry list.
    enum CollectionLayout {
        /// cheat.7z (or cheat.zip) itself: `<set>.xml` files at the root.
        case cheatArchive
        /// The zip Pugsy publishes: the packed cheat.7z next to cheat.txt, possibly in a folder.
        case release(cheatEntry: String, notesEntry: String?)
    }

    /// Nil when the entries are not a cheat collection.
    static func layout(ofEntries names: [String]) -> CollectionLayout? {
        if let cheat = names.first(where: { ($0 as NSString).lastPathComponent.lowercased() == "cheat.7z" }) {
            let folder = (cheat as NSString).deletingLastPathComponent
            let notes = names.first {
                ($0 as NSString).deletingLastPathComponent == folder && ($0 as NSString).lastPathComponent.lowercased() == "cheat.txt"
            }
            return .release(cheatEntry: cheat, notesEntry: notes)
        }
        // A handful of root XMLs is a game's own cheat file; a collection has thousands.
        let rootXMLs = names.lazy.filter { !$0.contains("/") && $0.lowercased().hasSuffix(".xml") }.prefix(100).count
        return rootXMLs >= 100 ? .cheatArchive : nil
    }

    /// Names that are worth opening to check for a collection during a Library import:
    /// cheat.7z, cheat.zip, or Pugsy's release zip (e.g. "cheat0279.zip").
    static func isCollectionFileName(_ fileName: String) -> Bool {
        let name = fileName.lowercased()
        return name.hasPrefix("cheat") && (name.hasSuffix(".7z") || name.hasSuffix(".zip"))
    }

    /// Rebuilds the library from cheat.7z (or cheat.zip), or from the zip Pugsy publishes,
    /// which holds the packed cheat.7z and cheat.txt (its release line and credits are kept).
    /// Only root-level `<set>.xml` files of sets the core knows are kept; software-list folders
    /// and the Lua plugin's .json files are ignored. Runs synchronously; call off the main thread.
    func importCollection(at url: URL, progress: (String) -> Void) throws -> Info {
        importLock.lock(); defer { importLock.unlock() }
        guard MameCatalogBuilder.shared.waitUntilReady() else { throw ImportError.catalogUnavailable }
        let sets = MameRomSetPersistence.shared.gameSets()
        guard !sets.isEmpty else { throw ImportError.catalogUnavailable }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MameCheatImport-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        } catch {
            throw ImportError.writeFailed(error.localizedDescription)
        }

        progress(Bundle.localizedString(forKey: "mame_cheat_import_reading"))
        var archivePath = url.path
        var entries = try Self.entries(ofArchiveAt: archivePath)
        var notes: String?
        switch Self.layout(ofEntries: entries) {
        case .cheatArchive:
            break
        case .release(let cheatEntry, let notesEntry):
            // Unpack the inner cheat.7z (and cheat.txt) from the release zip first.
            let innerPath = workDir.appendingPathComponent("cheat.7z").path
            var destinations = [cheatEntry: innerPath]
            let notesPath = workDir.appendingPathComponent("cheat.txt").path
            if let notesEntry { destinations[notesEntry] = notesPath }
            do {
                try RAArchiveReader.extractEntries(destinations, fromArchiveAtPath: url.path)
            } catch {
                throw ImportError.extractFailed(error.localizedDescription)
            }
            notes = Self.readText(atPath: notesPath)
            archivePath = innerPath
            entries = try Self.entries(ofArchiveAt: archivePath)
        case nil:
            throw ImportError.noCheatFiles
        }

        let available = Set(entries.lazy.filter { !$0.contains("/") && $0.hasSuffix(".xml") }
            .map { String($0.dropLast(4)) })
        let setNames = Set(sets.map(\.name))
        let wanted = available.intersection(setNames)
        guard !wanted.isEmpty else { throw ImportError.noCheatFiles }
        let xmlDir = workDir.appendingPathComponent("xml", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: xmlDir, withIntermediateDirectories: true)
        } catch {
            throw ImportError.writeFailed(error.localizedDescription)
        }

        progress(String(format: Bundle.localizedString(forKey: "mame_cheat_import_extracting"), wanted.count))
        let start = CFAbsoluteTimeGetCurrent()
        var destinations: [String: String] = [:]
        for name in wanted {
            destinations["\(name).xml"] = xmlDir.appendingPathComponent("\(name).xml").path
        }
        do {
            try RAArchiveReader.extractEntries(destinations, fromArchiveAtPath: archivePath)
        } catch {
            throw ImportError.extractFailed(error.localizedDescription)
        }
        NSLog("[MameCheat] Extracted %d cheat files in %.2fs", wanted.count, CFAbsoluteTimeGetCurrent() - start)

        progress(Bundle.localizedString(forKey: "mame_cheat_import_saving"))
        let tempPath = AppConfig.shared.mameCheatDatabasePath + ".importing-\(UUID().uuidString)"
        do {
            let newDB = try Connection(tempPath)
            try Self.createSchema(newDB)
            try newDB.transaction {
                let insertFile = try newDB.prepare("INSERT INTO cheat_file(name, xml) VALUES (?, ?)")
                for name in wanted {
                    let data = try Data(contentsOf: xmlDir.appendingPathComponent("\(name).xml"))
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
                if let notes {
                    try insertMeta.run("notes", notes)
                    if let release = Self.parseRelease(notes) {
                        try insertMeta.run("release_mame", release.mameVersion)
                        try insertMeta.run("release_date", release.date)
                    }
                }
            }
        } catch {
            for suffix in ["", "-journal", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: tempPath + suffix)
            }
            NSLog("[MameCheat] Writing the cheat library failed: %@", String(describing: error))
            throw ImportError.writeFailed(String(describing: error))
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

    private static func entries(ofArchiveAt path: String) throws -> [String] {
        do {
            return try RAArchiveReader.entriesOfArchive(atPath: path).map(\.name)
        } catch {
            throw ImportError.extractFailed(error.localizedDescription)
        }
    }

    private static func readText(atPath path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    /// "MAME CHEATS Release Date: 27 July 2025 (Base release for MAME 0.279)"
    static func parseRelease(_ notes: String) -> (mameVersion: String, date: String)? {
        guard let line = notes.split(whereSeparator: \.isNewline).first.map(String.init),
              let regex = try? NSRegularExpression(pattern: #"Release Date:\s*(.+?)\s*\(.*MAME\s+([0-9.]+)"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let date = Range(match.range(at: 1), in: line), let version = Range(match.range(at: 2), in: line) else {
            return nil
        }
        return (String(line[version]), String(line[date]))
    }

    /// cheat.txt as imported with the release zip: instructions and contributor credits.
    func notesText() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let db else { return nil }
        return (try? db.scalar("SELECT value FROM meta WHERE key = 'notes'")) as? String
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

    // MARK: - Launch

    /// Records the recognized set of the game about to launch. Main thread.
    func prepareLaunch(romKey: String, setName: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        pendingLaunch = Launch(romKey: romKey, setName: setName)
    }

    /// Takes the launch recorded for `romKey`; a stale one from another game is dropped.
    func takeLaunch(romKey: String) -> Launch? {
        defer { pendingLaunch = nil }
        guard let pendingLaunch, pendingLaunch.romKey == romKey else { return nil }
        return pendingLaunch
    }

    func cancelLaunch() {
        pendingLaunch = nil
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
