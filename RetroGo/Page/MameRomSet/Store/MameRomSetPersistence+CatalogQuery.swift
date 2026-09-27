//
//  MameRomSetPersistence+CatalogQuery.swift
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

/// Identity of a ROM file as MAME matches it inside an archive.
struct MameRomKey: Hashable {
    let crc: UInt32
    let size: Int64
}

/// The catalog fields needed to identify and audit an archive.
struct MameMachineRecord {
    let name: String
    let description: String?
    let cloneOf: String?
    let romOf: String?
    let isBios: Bool
    let isDevice: Bool
    let runnable: Bool
    let driverStatus: String?
    let defaultBios: String?

    /// BIOS and device sets live in the MAME BIOS folder instead of the Library.
    var isSupportSet: Bool {
        isBios || isDevice
    }
}

extension MameRomSetPersistence {
    enum RomFilter {
        /// Every file the set lists, including those merged from its parent/BIOS.
        case all
        /// Files stored in the set's own zip (`merge` is empty), i.e. what tells this set
        /// apart from its parent/BIOS.
        case ownFiles
        /// Files MAME refuses to run without: excludes nodump and optional entries.
        case required
    }

    /// Set names are lowercase in MAME; the lookup is case-insensitive for user file names.
    func machine(named name: String) -> MameMachineRecord? {
        guard let db else { return nil }
        do {
            let sql = """
                SELECT name, description, cloneof, romof, is_bios, is_device, runnable, driver_status, default_bios
                FROM machine WHERE name = ?
                """
            for row in try db.prepare(sql, name.lowercased()) {
                return Self.machineRecord(row)
            }
        } catch {
            NSLog("[MameRomSet] Failed to read machine %@: %@", name, "\(error)")
        }
        return nil
    }

    /// Every runnable game set (no BIOS/device sets) with its parent, if it is a clone.
    func gameSets() -> [(name: String, cloneOf: String?)] {
        guard let db else { return [] }
        do {
            let sql = "SELECT name, cloneof FROM machine WHERE is_bios = 0 AND is_device = 0 AND runnable = 1"
            return try db.prepare(sql).compactMap { row in
                guard let name = row[0] as? String else { return nil }
                return (name, row[1] as? String)
            }
        } catch {
            NSLog("[MameRomSet] Failed to list game sets: %@", "\(error)")
            return []
        }
    }

    /// Sets that list a file with this CRC and size, and whether the file is merged
    /// (stored in the parent/BIOS zip) for that set.
    func machinesContaining(_ key: MameRomKey) -> [(machine: String, merged: Bool)] {
        guard let db else { return [] }
        do {
            let sql = "SELECT machine, merge IS NOT NULL FROM machine_rom WHERE crc = ? AND size = ?"
            return try db.prepare(sql, Int64(key.crc), key.size).compactMap { row in
                guard let machine = row[0] as? String else { return nil }
                return (machine, (row[1] as? Int64) == 1)
            }
        } catch {
            NSLog("[MameRomSet] Failed to look up rom %08x: %@", key.crc, "\(error)")
            return []
        }
    }

    /// Distinct CRC/size keys of a set's dumped files (nodump entries have no CRC).
    func romKeys(of machine: String, filter: RomFilter) -> Set<MameRomKey> {
        guard let db else { return [] }
        let condition: String
        switch filter {
            case .all: condition = "1"
            case .ownFiles: condition = "merge IS NULL"
            case .required: condition = "status != 'nodump' AND optional = 0"
        }
        do {
            let sql = "SELECT DISTINCT crc, size FROM machine_rom WHERE machine = ? AND crc IS NOT NULL AND \(condition)"
            var keys = Set<MameRomKey>()
            for row in try db.prepare(sql, machine) {
                if let crc = row[0] as? Int64, let size = row[1] as? Int64, let crc32 = UInt32(exactly: crc) {
                    keys.insert(MameRomKey(crc: crc32, size: size))
                }
            }
            return keys
        } catch {
            NSLog("[MameRomSet] Failed to read roms of %@: %@", machine, "\(error)")
            return []
        }
    }

    /// Lowercased file names with sizes, for archives (7z) that did not record CRCs.
    func romNamesAndSizes(of machine: String) -> Set<String> {
        guard let db else { return [] }
        do {
            let sql = "SELECT name, size FROM machine_rom WHERE machine = ?"
            var result = Set<String>()
            for row in try db.prepare(sql, machine) {
                if let name = row[0] as? String, let size = row[1] as? Int64 {
                    result.insert("\(name.lowercased())#\(size)")
                }
            }
            return result
        } catch {
            NSLog("[MameRomSet] Failed to read rom names of %@: %@", machine, "\(error)")
            return []
        }
    }

    /// A file MAME must find to start a set.
    struct RequiredRom {
        let name: String
        let key: MameRomKey
        /// Name in the parent/BIOS set when the file is merged from there.
        let merge: String?
    }

    /// Files a set needs to start: its full ROM list (listxml already includes files
    /// merged from the parent and BIOS), restricted to the given BIOS option, without
    /// nodump and optional entries. Duplicate files are listed once.
    func requiredRoms(of machine: String, biosOption: String?) -> [RequiredRom] {
        guard let db else { return [] }
        do {
            let sql = """
                SELECT name, crc, size, merge FROM machine_rom
                WHERE machine = ? AND crc IS NOT NULL AND status != 'nodump' AND optional = 0
                  AND (bios IS NULL OR bios = ?)
                """
            var seen = Set<MameRomKey>()
            var result: [RequiredRom] = []
            for row in try db.prepare(sql, machine, biosOption) {
                guard let name = row[0] as? String, let crc = row[1] as? Int64, let size = row[2] as? Int64,
                      let crc32 = UInt32(exactly: crc) else { continue }
                let key = MameRomKey(crc: crc32, size: size)
                if seen.insert(key).inserted {
                    result.append(RequiredRom(name: name, key: key, merge: row[3] as? String))
                }
            }
            return result
        } catch {
            NSLog("[MameRomSet] Failed to read required roms of %@: %@", machine, "\(error)")
            return []
        }
    }

    /// Every dumped file stored in the set's own zip (merge empty), for all BIOS options,
    /// with whether MAME can do without it. This is what a rebuilt split zip must hold.
    func ownRoms(of machine: String) -> [(rom: RequiredRom, optional: Bool)] {
        guard let db else { return [] }
        do {
            let sql = """
                SELECT name, crc, size, optional FROM machine_rom
                WHERE machine = ? AND merge IS NULL AND crc IS NOT NULL AND status != 'nodump'
                """
            var seen = Set<MameRomKey>()
            var result: [(rom: RequiredRom, optional: Bool)] = []
            for row in try db.prepare(sql, machine) {
                guard let name = row[0] as? String, let crc = row[1] as? Int64, let size = row[2] as? Int64,
                      let crc32 = UInt32(exactly: crc) else { continue }
                let key = MameRomKey(crc: crc32, size: size)
                if seen.insert(key).inserted {
                    result.append((RequiredRom(name: name, key: key, merge: nil), (row[3] as? Int64) == 1))
                }
            }
            return result
        } catch {
            NSLog("[MameRomSet] Failed to read own roms of %@: %@", machine, "\(error)")
            return []
        }
    }

    /// Devices a set pulls in, expanded recursively (only devices that need files are
    /// stored in the catalog).
    func devices(of machine: String) -> [String] {
        guard let db else { return [] }
        do {
            let sql = """
                WITH RECURSIVE dev(name) AS (
                    SELECT device FROM machine_device WHERE machine = ?
                    UNION
                    SELECT d.device FROM machine_device d JOIN dev ON d.machine = dev.name
                )
                SELECT name FROM dev ORDER BY name
                """
            return try db.prepare(sql, machine).compactMap { $0[0] as? String }
        } catch {
            NSLog("[MameRomSet] Failed to read devices of %@: %@", machine, "\(error)")
            return []
        }
    }

    /// CHD images a set needs (optional and nodump disks excluded).
    func requiredDisks(of machine: String) -> [String] {
        guard let db else { return [] }
        do {
            let sql = "SELECT name FROM machine_disk WHERE machine = ? AND optional = 0 AND status != 'nodump' ORDER BY name"
            return try db.prepare(sql, machine).compactMap { $0[0] as? String }
        } catch {
            NSLog("[MameRomSet] Failed to read disks of %@: %@", machine, "\(error)")
            return []
        }
    }

    private static func machineRecord(_ row: Statement.Element) -> MameMachineRecord? {
        guard let name = row[0] as? String else { return nil }
        return MameMachineRecord(
            name: name,
            description: row[1] as? String,
            cloneOf: row[2] as? String,
            romOf: row[3] as? String,
            isBios: (row[4] as? Int64) == 1,
            isDevice: (row[5] as? Int64) == 1,
            runnable: (row[6] as? Int64) != 0,
            driverStatus: row[7] as? String,
            defaultBios: row[8] as? String
        )
    }
}
