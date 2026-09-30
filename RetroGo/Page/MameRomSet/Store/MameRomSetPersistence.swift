//
//  MameRomSetPersistence.swift
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

import SQLite
import Foundation
import RACoordinator

/// MAME romset database (`mame_romset.db`): the catalog exported from the MAME core
/// plus the index of recognized user archives.
///
/// Everything in it can be rebuilt (catalog from the core, index by rescanning), so it
/// lives outside roms.db and has no migrations: a schema version mismatch or a file
/// that cannot be opened is deleted and created again.
///
/// `db` is nil when even a fresh database cannot be created; callers then skip the
/// romset features and let MAME load games as before.
final class MameRomSetPersistence {
    static let shared = MameRomSetPersistence()

    /// Stored in `PRAGMA user_version`. Bump on any schema change; old files are recreated.
    static let schemaVersion: Int64 = 1

    enum MetaKey: String {
        /// Fingerprint of the MAME binary the catalog was exported from ("uuid:<LC_UUID>").
        case catalogCoreFingerprint = "catalog_core_fingerprint"
        /// `build` attribute of the listxml root, for diagnostics.
        case catalogBuild = "catalog_build"
        /// Core fingerprint the whole Library was last identified against.
        case libraryScanFingerprint = "library_scan_fingerprint"
        /// Set when an import skipped recognition because no catalog was available.
        case libraryScanPending = "library_scan_pending"
    }

    /// SQLite.swift serializes all calls on a connection, so it may be used from any thread.
    let db: Connection?

    private var retroArchReadyObserver: NSObjectProtocol?

    private init() {
        db = Self.openDatabase(at: AppConfig.shared.mameRomSetDatabasePath)
        scheduleCatalogUpdate()
    }

    // MARK: - Catalog Update

    /// Builds the catalog in the background when it is missing or was exported from a
    /// different MAME core binary. Safe to trigger from any thread.
    ///
    /// Waits for RetroArchX to finish starting up: its core list is only valid afterwards
    /// (and cached on first access), and the listxml export must not overlap RetroArch's
    /// own startup on its background thread.
    private func scheduleCatalogUpdate() {
        guard db != nil else { return }
        DispatchQueue.main.async { [self] in
            if RetroArchX.shared().initialized {
                NSLog("[MameCatalog] RetroArchX ready, checking catalog")
                MameCatalogBuilder.shared.updateIfNeeded()
                return
            }
            NSLog("[MameCatalog] Waiting for RetroArchX before checking catalog")
            let waitStart = CFAbsoluteTimeGetCurrent()
            // The ready notification is posted asynchronously on the main queue after
            // `initialized` is set, so it cannot be missed between the check and here.
            retroArchReadyObserver = NotificationCenter.default.addObserver(
                forName: .RetroArchXReady, object: nil, queue: .main
            ) { [self] _ in
                if let retroArchReadyObserver {
                    NotificationCenter.default.removeObserver(retroArchReadyObserver)
                    self.retroArchReadyObserver = nil
                }
                NSLog("[MameCatalog] RetroArchX ready after %.2fs, checking catalog", CFAbsoluteTimeGetCurrent() - waitStart)
                MameCatalogBuilder.shared.updateIfNeeded()
            }
        }
    }

    // MARK: - Meta

    func metaValue(_ key: MetaKey) -> String? {
        guard let db else { return nil }
        do {
            return try db.scalar("SELECT value FROM meta WHERE key = ?", key.rawValue) as? String
        } catch {
            Self.report(error, "read meta \(key.rawValue)")
            return nil
        }
    }

    /// Passing nil removes the key.
    @discardableResult
    func setMetaValue(_ value: String?, for key: MetaKey) -> Bool {
        guard let db else { return false }
        do {
            if let value {
                try db.run("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", key.rawValue, value)
            } else {
                try db.run("DELETE FROM meta WHERE key = ?", key.rawValue)
            }
            return true
        } catch {
            Self.report(error, "write meta \(key.rawValue)")
            return false
        }
    }

    // MARK: - Open & Schema

    private static func openDatabase(at path: String) -> Connection? {
        for attempt in 0..<2 {
            if attempt > 0 {
                // Unreadable, corrupt or from another schema version: start over. The
                // previous connection was released at the end of the last iteration.
                NSLog("[MameRomSet] Recreating database at %@", path)
                removeDatabaseFiles(at: path)
            }
            do {
                let start = CFAbsoluteTimeGetCurrent()
                let db = try connect(path: path)
                if prepareSchema(db: db) {
                    let size = ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.int64Value ?? 0
                    NSLog("[MameRomSet] Opened %@ (%lld bytes, %.3fs)", path, size, CFAbsoluteTimeGetCurrent() - start)
                    return db
                }
            } catch {
                NSLog("[MameRomSet] Failed to open %@: %@", path, "\(error)")
            }
        }
        NSLog("[MameRomSet] Database unavailable, romset features disabled")
        return nil
    }

    private static func connect(path: String) throws -> Connection {
        let db = try Connection(path, readonly: false)
        try db.execute("PRAGMA journal_mode = WAL;")
        try db.execute("PRAGMA foreign_keys = ON;")
        db.busyTimeout = 5.0
        excludeFromBackup(path: path)
        return db
    }

    /// Returns false when the file holds another schema version and must be recreated.
    private static func prepareSchema(db: Connection) -> Bool {
        do {
            guard let version = try db.scalar("PRAGMA user_version") as? Int64 else {
                return false
            }
            switch version {
                case schemaVersion:
                    return true
                case 0:
                    NSLog("[MameRomSet] Creating schema v%lld", schemaVersion)
                    try db.transaction {
                        try db.execute(schemaSQL)
                        try db.execute("PRAGMA user_version = \(schemaVersion);")
                    }
                    return true
                default:
                    NSLog("[MameRomSet] Schema version %lld, expected %lld", version, schemaVersion)
                    return false
            }
        } catch {
            // Expected for a corrupt file; the caller recreates it, so no assertion here.
            NSLog("[MameRomSet] Failed to prepare schema: %@", "\(error)")
            return false
        }
    }

    private static func removeDatabaseFiles(at path: String) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }

    /// The data is regenerated on demand, so keep it out of device backups.
    private static func excludeFromBackup(path: String) {
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private static func report(_ error: Error, _ context: String) {
        NSLog("[MameRomSet] Failed to %@: %@", context, "\(error)")
        assertionFailure("\(context): \(error)")
    }

    // Catalog tables mirror the core's -listxml; index tables describe the user's archives.
    // CRCs are stored as INTEGER (unsigned 32-bit values fit in SQLite's 64-bit integer).
    private static let schemaSQL = """
        CREATE TABLE IF NOT EXISTS meta (
            key   TEXT PRIMARY KEY,
            value TEXT
        );

        CREATE TABLE IF NOT EXISTS machine (
            name          TEXT PRIMARY KEY,
            description   TEXT,
            year          TEXT,
            manufacturer  TEXT,
            cloneof       TEXT,
            romof         TEXT,
            is_bios       INTEGER NOT NULL,
            is_device     INTEGER NOT NULL,
            runnable      INTEGER NOT NULL,
            driver_status TEXT,
            default_bios  TEXT
        );

        CREATE TABLE IF NOT EXISTS machine_rom (
            machine  TEXT NOT NULL,
            name     TEXT NOT NULL,
            size     INTEGER NOT NULL,
            crc      INTEGER,
            sha1     TEXT,
            merge    TEXT,
            bios     TEXT,
            status   TEXT NOT NULL,
            optional INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS machine_rom_crc ON machine_rom(crc, size);
        CREATE INDEX IF NOT EXISTS machine_rom_machine ON machine_rom(machine);

        CREATE TABLE IF NOT EXISTS machine_disk (
            machine  TEXT NOT NULL,
            name     TEXT NOT NULL,
            sha1     TEXT,
            merge    TEXT,
            status   TEXT NOT NULL,
            optional INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS machine_disk_machine ON machine_disk(machine);

        CREATE TABLE IF NOT EXISTS machine_device (
            machine TEXT NOT NULL,
            device  TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS machine_device_machine ON machine_device(machine);

        CREATE TABLE IF NOT EXISTS archive (
            id          INTEGER PRIMARY KEY,
            romgame_key TEXT UNIQUE,
            bios_name   TEXT UNIQUE,
            format      TEXT NOT NULL,
            matched_set TEXT NOT NULL,
            match_kind  TEXT NOT NULL,
            CHECK ((romgame_key IS NULL) <> (bios_name IS NULL))
        );

        CREATE TABLE IF NOT EXISTS archive_entry (
            archive_id INTEGER NOT NULL REFERENCES archive(id) ON DELETE CASCADE,
            name       TEXT NOT NULL,
            size       INTEGER NOT NULL,
            crc        INTEGER
        );
        CREATE INDEX IF NOT EXISTS archive_entry_crc ON archive_entry(crc, size);
        CREATE INDEX IF NOT EXISTS archive_entry_archive ON archive_entry(archive_id);
        """
}
