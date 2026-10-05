//
//  MameArchiveIdentifier.swift
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
import os

/// A zip/7z recognized as a MAME set.
struct MameArchiveMatch {
    enum Kind: String {
        /// File name equals the set name and the content confirms it.
        case name
        /// Recognized from the files inside (the user renamed the archive).
        case content
    }

    let machine: MameMachineRecord
    let kind: Kind
    let format: RAArchiveFormat
    let entries: [RAArchiveEntry]
    /// CRC/size keys of the entries that carry a CRC.
    let entryKeys: Set<MameRomKey>

    var formatName: String {
        format == .sevenZip ? "7z" : "zip"
    }
}

/// Recognizes MAME sets from the archive's directory alone (no decompression), using
/// the catalog in mame_romset.db. Call off the main thread with the catalog ready.
enum MameArchiveIdentifier {
    /// Content recognition requires at least this share of the set's own files.
    static let minimumContentCoverage = 0.5

    static func identify(archiveAtPath path: String, fileName: String) -> MameArchiveMatch? {
        let format = RAArchiveReader.formatOfArchive(atPath: path)
        guard format != .unknown else { return nil }

        let entries: [RAArchiveEntry]
        do {
            entries = try RAArchiveReader.entriesOfArchive(atPath: path)
        } catch {
            RetroGoLogger.mame.error("Cannot list archive \(fileName): \(error.localizedDescription)")
            return nil
        }
        guard !entries.isEmpty else { return nil }

        let keys = Set(entries.filter(\.hasCRC).map { MameRomKey(crc: $0.crc32, size: Int64(clamping: $0.size)) })
        let persistence = MameRomSetPersistence.shared

        let baseName = (fileName as NSString).deletingPathExtension
        if let machine = persistence.machine(named: baseName), matchesByName(machine, entries: entries, keys: keys) {
            return MameArchiveMatch(machine: machine, kind: .name, format: format, entries: entries, entryKeys: keys)
        }
        if let machine = bestContentMatch(keys: keys) {
            return MameArchiveMatch(machine: machine, kind: .content, format: format, entries: entries, entryKeys: keys)
        }
        return nil
    }

    /// A same-named archive must also contain at least one file that belongs to this set
    /// itself, so an unrelated zip that happens to share a set name is not claimed.
    private static func matchesByName(_ machine: MameMachineRecord, entries: [RAArchiveEntry], keys: Set<MameRomKey>) -> Bool {
        let persistence = MameRomSetPersistence.shared
        var ownKeys = persistence.romKeys(of: machine.name, filter: .ownFiles)
        if ownKeys.isEmpty {
            // Clones whose every file is merged from the parent.
            ownKeys = persistence.romKeys(of: machine.name, filter: .required)
        }
        if !ownKeys.isDisjoint(with: keys) {
            return true
        }

        // 7z archives may omit CRCs; fall back to file name + size for those entries.
        let entriesWithoutCRC = entries.filter { !$0.hasCRC }
        guard !entriesWithoutCRC.isEmpty else { return false }
        let namesAndSizes = persistence.romNamesAndSizes(of: machine.name)
        return entriesWithoutCRC.contains { entry in
            let name = (entry.name as NSString).lastPathComponent.lowercased()
            return namesAndSizes.contains("\(name)#\(entry.size)")
        }
    }

    /// Picks the set an archive holds, family by family (a parent and its clones):
    ///
    /// - When every one of the parent's own files is present, the archive is the parent
    ///   set: a split or non-merged parent zip, or a merged zip that also carries clones.
    ///   A non-merged clone zip always lacks at least one parent file, the one the clone
    ///   replaces, so it cannot be mistaken for the parent.
    /// - Otherwise the best clone is the one whose full file list (merged parent/BIOS files
    ///   included) explains the most entries, among clones with at least
    ///   `minimumContentCoverage` of their own files present.
    ///
    /// Across families the set explaining the most entries wins, so a small unrelated set
    /// that happens to share one common chip cannot win on coverage alone.
    private static func bestContentMatch(keys: Set<MameRomKey>) -> MameMachineRecord? {
        let persistence = MameRomSetPersistence.shared
        var ownHits: [String: Int] = [:]
        for key in keys {
            // A set may list the same file under two names; count it once per key.
            let machines = Set(persistence.machinesContaining(key).filter { !$0.merged }.map(\.machine))
            for machine in machines {
                ownHits[machine, default: 0] += 1
            }
        }

        var records: [String: MameMachineRecord] = [:]
        func record(_ name: String) -> MameMachineRecord? {
            if let cached = records[name] {
                return cached
            }
            let fetched = persistence.machine(named: name)
            records[name] = fetched
            return fetched
        }

        var families: [String: [String]] = [:]
        for name in ownHits.keys {
            guard let machine = record(name) else { continue }
            families[machine.cloneOf ?? machine.name, default: []].append(name)
        }

        var best: (name: String, explained: Int, coverage: Double)?
        func consider(_ name: String, coverage: Double) {
            let explained = keys.intersection(persistence.romKeys(of: name, filter: .all)).count
            if let current = best,
               explained < current.explained || (explained == current.explained && coverage <= current.coverage) {
                return
            }
            best = (name, explained, coverage)
        }

        for (parent, members) in families.sorted(by: { $0.key < $1.key }) {
            let parentOwn = persistence.romKeys(of: parent, filter: .ownFiles).count
            if parentOwn > 0, ownHits[parent] == parentOwn {
                consider(parent, coverage: 1)
                continue
            }
            for name in members.sorted() {
                let ownCount = persistence.romKeys(of: name, filter: .ownFiles).count
                guard ownCount > 0, let hits = ownHits[name] else { continue }
                let coverage = Double(hits) / Double(ownCount)
                if coverage >= minimumContentCoverage {
                    consider(name, coverage: coverage)
                }
            }
        }
        return best.flatMap { record($0.name) }
    }
}
