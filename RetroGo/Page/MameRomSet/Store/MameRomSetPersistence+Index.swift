//
//  MameRomSetPersistence+Index.swift
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
import os

/// Who owns an indexed archive. Paths are never stored: Library games are found
/// through roms.db by key, BIOS files by name inside the MAME system folder.
enum MameArchiveOwner {
    /// A game in the Library (`romgame.key` in roms.db).
    case game(romgameKey: String)
    /// A BIOS/device file in the MAME system folder, e.g. "neogeo.zip".
    case bios(fileName: String)

    fileprivate var condition: (sql: String, value: String) {
        switch self {
            case .game(let key): return ("romgame_key = ?", key)
            case .bios(let name): return ("bios_name = ?", name)
        }
    }
}

/// An indexed archive as stored in `archive`.
struct MameArchiveRecord {
    let owner: MameArchiveOwner
    let matchedSet: String
    let matchKind: String
    let format: String
}

extension MameRomSetPersistence {
    /// Records a recognized archive, replacing any earlier record of the same owner.
    @discardableResult
    func storeArchive(owner: MameArchiveOwner, format: String, matchedSet: String, matchKind: String,
                      entries: [RAArchiveEntry]) -> Bool {
        guard let db else { return false }
        do {
            try db.transaction {
                let condition = owner.condition
                // Explicit delete: REPLACE conflict resolution does not reliably run the
                // ON DELETE CASCADE for archive_entry.
                try db.run("DELETE FROM archive WHERE \(condition.sql)", condition.value)

                var romgameKey: String?
                var biosName: String?
                switch owner {
                    case .game(let key): romgameKey = key
                    case .bios(let name): biosName = name
                }
                try db.run("""
                    INSERT INTO archive (romgame_key, bios_name, format, matched_set, match_kind)
                    VALUES (?, ?, ?, ?, ?)
                    """, romgameKey, biosName, format, matchedSet, matchKind)
                let archiveId = db.lastInsertRowid

                let insertEntry = try db.prepare("INSERT INTO archive_entry (archive_id, name, size, crc) VALUES (?, ?, ?, ?)")
                for entry in entries {
                    let crc: Int64? = entry.hasCRC ? Int64(entry.crc32) : nil
                    try insertEntry.run(archiveId, entry.name, Int64(clamping: entry.size), crc)
                }
            }
            return true
        } catch {
            RetroGoLogger.mame.error("Failed to store archive for \(String(describing: owner)): \(String(describing: error))")
            return false
        }
    }

    /// Removes the record of a deleted game or BIOS file; entries go with it (cascade).
    func deleteArchive(owner: MameArchiveOwner) {
        guard let db else { return }
        do {
            let condition = owner.condition
            try db.run("DELETE FROM archive WHERE \(condition.sql)", condition.value)
        } catch {
            RetroGoLogger.mame.error("Failed to delete archive for \(String(describing: owner)): \(String(describing: error))")
        }
    }

    /// CRC/size keys of an indexed archive; nil when the owner has no record.
    func archiveEntryKeys(owner: MameArchiveOwner) -> Set<MameRomKey>? {
        guard let db else { return nil }
        do {
            let condition = owner.condition
            guard let archiveId = try db.scalar("SELECT id FROM archive WHERE \(condition.sql)", condition.value) as? Int64 else {
                return nil
            }
            var keys = Set<MameRomKey>()
            for row in try db.prepare("SELECT crc, size FROM archive_entry WHERE archive_id = ? AND crc IS NOT NULL", archiveId) {
                if let crc = row[0] as? Int64, let size = row[1] as? Int64, let crc32 = UInt32(exactly: crc) {
                    keys.insert(MameRomKey(crc: crc32, size: size))
                }
            }
            return keys
        } catch {
            RetroGoLogger.mame.error("Failed to read archive for \(String(describing: owner)): \(String(describing: error))")
            return nil
        }
    }

    func archiveRecord(owner: MameArchiveOwner) -> MameArchiveRecord? {
        guard let db else { return nil }
        do {
            let condition = owner.condition
            let sql = "SELECT matched_set, match_kind, format FROM archive WHERE \(condition.sql)"
            for row in try db.prepare(sql, condition.value) {
                guard let set = row[0] as? String, let kind = row[1] as? String, let format = row[2] as? String else {
                    return nil
                }
                return MameArchiveRecord(owner: owner, matchedSet: set, matchKind: kind, format: format)
            }
        } catch {
            RetroGoLogger.mame.error("Failed to read archive for \(String(describing: owner)): \(String(describing: error))")
        }
        return nil
    }

    /// Every indexed archive (Library games and BIOS files) holding this file.
    func archivesContaining(_ key: MameRomKey) -> [MameArchiveRecord] {
        guard let db else { return [] }
        do {
            let sql = """
                SELECT DISTINCT a.romgame_key, a.bios_name, a.matched_set, a.match_kind, a.format
                FROM archive_entry e JOIN archive a ON a.id = e.archive_id
                WHERE e.crc = ? AND e.size = ?
                """
            return try db.prepare(sql, Int64(key.crc), key.size).compactMap { row in
                let owner: MameArchiveOwner
                if let key = row[0] as? String {
                    owner = .game(romgameKey: key)
                } else if let name = row[1] as? String {
                    owner = .bios(fileName: name)
                } else {
                    return nil
                }
                guard let set = row[2] as? String, let kind = row[3] as? String, let format = row[4] as? String else {
                    return nil
                }
                return MameArchiveRecord(owner: owner, matchedSet: set, matchKind: kind, format: format)
            }
        } catch {
            RetroGoLogger.mame.error("Failed to locate rom \(key.crc, format: .hex(minDigits: 8)): \(String(describing: error))")
            return []
        }
    }

    /// Library games recognized as this set (e.g. the parent of a clone being launched).
    func libraryArchives(ofSet setName: String) -> [MameArchiveRecord] {
        guard let db else { return [] }
        do {
            let sql = "SELECT romgame_key, match_kind, format FROM archive WHERE matched_set = ? AND romgame_key IS NOT NULL"
            return try db.prepare(sql, setName).compactMap { row in
                guard let key = row[0] as? String, let kind = row[1] as? String, let format = row[2] as? String else {
                    return nil
                }
                return MameArchiveRecord(owner: .game(romgameKey: key), matchedSet: setName, matchKind: kind, format: format)
            }
        } catch {
            RetroGoLogger.mame.error("Failed to find library archives of \(setName, privacy: .public): \(String(describing: error))")
            return []
        }
    }

    /// Name of the entry holding this file inside an indexed archive.
    func entryName(owner: MameArchiveOwner, key: MameRomKey) -> String? {
        guard let db else { return nil }
        do {
            let condition = owner.condition
            let sql = """
                SELECT e.name FROM archive_entry e JOIN archive a ON a.id = e.archive_id
                WHERE a.\(condition.sql) AND e.crc = ? AND e.size = ? LIMIT 1
                """
            return try db.scalar(sql, condition.value, Int64(key.crc), key.size) as? String
        } catch {
            RetroGoLogger.mame.error("Failed to read entry name for \(String(describing: owner)): \(String(describing: error))")
            return nil
        }
    }

    /// Whether any Library game is recognized, i.e. the health report has something to show.
    func hasIndexedGames() -> Bool {
        guard let db else { return false }
        return (try? db.scalar("SELECT EXISTS (SELECT 1 FROM archive WHERE romgame_key IS NOT NULL)") as? Int64) == 1
    }
}
