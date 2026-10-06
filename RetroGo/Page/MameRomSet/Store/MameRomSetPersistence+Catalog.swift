//
//  MameRomSetPersistence+Catalog.swift
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
import SQLite3
import Foundation
import os

enum MameRomSetPersistenceError: LocalizedError {
    case databaseUnavailable
    case sqlite(String)

    var errorDescription: String? {
        switch self {
            case .databaseUnavailable:
                return "MAME romset database is unavailable"
            case .sqlite(let message):
                return "SQLite error: \(message)"
        }
    }
}

struct MameCatalogSummary {
    var machineCount = 0
    var romCount = 0
    var diskCount = 0
    /// device_ref rows actually stored (see MameCatalogWriter).
    var deviceRefCount = 0
}

/// A prepared INSERT driven through the raw sqlite3 API. SQLite.swift's `Statement.run`
/// boxes every value into an array of existentials; for the ~190k catalog rows that
/// overhead cost 3.5 s on an iPhone 15 Pro Max, and binding directly is ~40% faster.
/// Values are bound in parameter order, then `execute()` runs and resets the statement.
private final class BulkInsertStatement {
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let db: OpaquePointer
    private var statement: OpaquePointer?
    private var index: Int32 = 0

    init(_ connection: Connection, _ sql: String) throws {
        db = connection.handle
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MameRomSetPersistenceError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func bind(_ value: String?) {
        index += 1
        if let value {
            sqlite3_bind_text(statement, index, value, -1, Self.transient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func bind(_ value: Int64?) {
        index += 1
        if let value {
            sqlite3_bind_int64(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func bind(_ value: Bool) {
        bind(Int64(value ? 1 : 0))
    }

    func execute() throws {
        assert(index == sqlite3_bind_parameter_count(statement), "bound \(index) values")
        let result = sqlite3_step(statement)
        sqlite3_reset(statement)
        index = 0
        guard result == SQLITE_DONE else {
            throw MameRomSetPersistenceError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }
}

/// Inserts machines into the catalog tables with reused prepared statements.
/// Only valid inside `MameRomSetPersistence.replaceCatalog`.
final class MameCatalogWriter {
    private let insertMachine: BulkInsertStatement
    private let insertRom: BulkInsertStatement
    private let insertDisk: BulkInsertStatement
    private let insertDevice: BulkInsertStatement

    /// device_ref rows are held back until every machine is known; see `flushDeviceRefs`.
    private var deviceRefs: [(machine: String, devices: [String])] = []
    private var machinesWithMedia = Set<String>()
    private(set) var summary = MameCatalogSummary()

    fileprivate init(db: Connection) throws {
        insertMachine = try BulkInsertStatement(db, """
            INSERT INTO machine (name, description, year, manufacturer, cloneof, romof,
                                 is_bios, is_device, runnable, driver_status, default_bios)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        insertRom = try BulkInsertStatement(db, """
            INSERT INTO machine_rom (machine, name, size, crc, sha1, merge, bios, status, optional)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        insertDisk = try BulkInsertStatement(db, """
            INSERT INTO machine_disk (machine, name, sha1, merge, status, optional)
            VALUES (?, ?, ?, ?, ?, ?)
            """)
        insertDevice = try BulkInsertStatement(db, "INSERT INTO machine_device (machine, device) VALUES (?, ?)")
    }

    func insert(_ machine: MameCatalogMachine) throws {
        insertMachine.bind(machine.name)
        insertMachine.bind(machine.description)
        insertMachine.bind(machine.year)
        insertMachine.bind(machine.manufacturer)
        insertMachine.bind(machine.cloneOf)
        insertMachine.bind(machine.romOf)
        insertMachine.bind(machine.isBios)
        insertMachine.bind(machine.isDevice)
        insertMachine.bind(machine.runnable)
        insertMachine.bind(machine.driverStatus)
        insertMachine.bind(machine.defaultBios)
        try insertMachine.execute()

        for rom in machine.roms {
            insertRom.bind(machine.name)
            insertRom.bind(rom.name)
            insertRom.bind(rom.size)
            insertRom.bind(rom.crc.map { Int64($0) })
            insertRom.bind(rom.sha1)
            insertRom.bind(rom.merge)
            insertRom.bind(rom.bios)
            insertRom.bind(rom.status)
            insertRom.bind(rom.optional)
            try insertRom.execute()
        }
        for disk in machine.disks {
            insertDisk.bind(machine.name)
            insertDisk.bind(disk.name)
            insertDisk.bind(disk.sha1)
            insertDisk.bind(disk.merge)
            insertDisk.bind(disk.status)
            insertDisk.bind(disk.optional)
            try insertDisk.execute()
        }

        summary.machineCount += 1
        summary.romCount += machine.roms.count
        summary.diskCount += machine.disks.count
        if !machine.roms.isEmpty || !machine.disks.isEmpty {
            machinesWithMedia.insert(machine.name)
        }
        if !machine.devices.isEmpty {
            deviceRefs.append((machine.name, machine.devices))
        }
    }

    /// Most device_refs point at devices without any ROM or CHD (CPUs, sound chips,
    /// screens...), which never matter for an audit. Keep only references to devices
    /// that need files themselves or through their own device_refs, which cuts ~150k
    /// rows down to a few thousand.
    fileprivate func flushDeviceRefs() throws {
        var relevant = machinesWithMedia
        var devicesOf: [String: [String]] = [:]
        for ref in deviceRefs {
            devicesOf[ref.machine] = ref.devices
        }
        // Fixed point: a device is relevant when it references a relevant device.
        var changed = true
        while changed {
            changed = false
            for (machine, devices) in devicesOf where !relevant.contains(machine) {
                if devices.contains(where: relevant.contains) {
                    relevant.insert(machine)
                    changed = true
                }
            }
        }

        for ref in deviceRefs {
            for device in ref.devices where relevant.contains(device) {
                insertDevice.bind(ref.machine)
                insertDevice.bind(device)
                try insertDevice.execute()
                summary.deviceRefCount += 1
            }
        }
        deviceRefs.removeAll()
    }
}

extension MameRomSetPersistence {
    /// Replaces the whole catalog in one transaction. `fill` streams machines into the
    /// writer and returns the listxml build string; if anything throws, the previous
    /// catalog and its meta stay untouched.
    ///
    /// The user index (archive tables) is left alone; callers re-identify archives
    /// after a rebuild because set names may have changed.
    @discardableResult
    func replaceCatalog(coreFingerprint: String, fill: (MameCatalogWriter) throws -> String?) throws -> MameCatalogSummary {
        guard let db else {
            throw MameRomSetPersistenceError.databaseUnavailable
        }

        var summary = MameCatalogSummary()
        var build: String?
        var stageStart = CFAbsoluteTimeGetCurrent()
        var commitStart = stageStart
        try db.transaction {
            // All catalog_* meta keys, including ones written by earlier versions.
            try db.execute("""
                DELETE FROM machine;
                DELETE FROM machine_rom;
                DELETE FROM machine_disk;
                DELETE FROM machine_device;
                DELETE FROM meta WHERE key LIKE 'catalog\\_%' ESCAPE '\\';
                """)

            RetroGoLogger.mame.debug("Cleared old catalog: \(CFAbsoluteTimeGetCurrent() - stageStart, format: .fixed(precision: 2))s")

            let writer = try MameCatalogWriter(db: db)
            build = try fill(writer)

            stageStart = CFAbsoluteTimeGetCurrent()
            try writer.flushDeviceRefs()
            summary = writer.summary
            RetroGoLogger.mame.debug("Catalog device refs written: \(CFAbsoluteTimeGetCurrent() - stageStart, format: .fixed(precision: 2))s")

            try db.run("INSERT INTO meta (key, value) VALUES (?, ?)", MetaKey.catalogCoreFingerprint.rawValue, coreFingerprint)
            if let build {
                try db.run("INSERT INTO meta (key, value) VALUES (?, ?)", MetaKey.catalogBuild.rawValue, build)
            }
            commitStart = CFAbsoluteTimeGetCurrent()
        }
        RetroGoLogger.mame.info("Catalog committed: \(CFAbsoluteTimeGetCurrent() - commitStart, format: .fixed(precision: 2))s (listxml build \(build ?? "unknown", privacy: .public))")

        // The rebuild leaves a WAL as large as the database itself; fold it back and
        // truncate it. Failure (e.g. a concurrent reader) only costs disk space.
        stageStart = CFAbsoluteTimeGetCurrent()
        do {
            try db.execute("PRAGMA wal_checkpoint(TRUNCATE);")
            RetroGoLogger.mame.debug("Catalog WAL checkpoint: \(CFAbsoluteTimeGetCurrent() - stageStart, format: .fixed(precision: 2))s")
        } catch {
            RetroGoLogger.mame.error("Catalog WAL checkpoint failed: \(String(describing: error))")
        }
        return summary
    }

    /// True when a catalog exported from the core with this fingerprint is stored.
    func hasCatalog(coreFingerprint: String) -> Bool {
        guard let db, metaValue(.catalogCoreFingerprint) == coreFingerprint else { return false }
        do {
            return try db.scalar("SELECT EXISTS (SELECT 1 FROM machine)") as? Int64 == 1
        } catch {
            RetroGoLogger.mame.error("Failed to check catalog: \(String(describing: error))")
            return false
        }
    }
}
