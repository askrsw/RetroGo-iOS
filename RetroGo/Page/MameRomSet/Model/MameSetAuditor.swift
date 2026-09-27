//
//  MameSetAuditor.swift
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

/// Whether a recognized game has every file MAME will look for.
struct MameSetAudit {
    enum Verdict {
        /// Every required file is available to the session, possibly through links and
        /// extracted files.
        case complete
        /// At least one file exists nowhere.
        case incomplete
    }

    /// Which part of the set a file belongs to, for grouping the report.
    enum Source: Hashable {
        case game
        case parent(String)
        case bios(String)
        case device(String)
    }

    /// A required file that exists in no indexed archive.
    struct Problem {
        let source: Source
        let fileName: String
    }

    /// A Library archive to link into the session under the name MAME looks for.
    struct SessionLink {
        /// e.g. "kof2001.zip"
        let stagedName: String
        let romgameKey: String
    }

    /// A single file to take out of another indexed archive before launch.
    struct Extraction {
        /// Where MAME looks for it as a loose file, e.g. "sfa3u/sfa3u.03c".
        let stagedPath: String
        let source: MameArchiveOwner
        let entryName: String
    }

    let machine: MameMachineRecord
    let problems: [Problem]
    /// Name for the game archive in the session when the user file is not named after its
    /// set (recognized by content); nil when the name already fits.
    let gameStagedName: String?
    /// Parent sets found elsewhere in the Library; their files count as present.
    let links: [SessionLink]
    /// Files still missing after the links but present in some other indexed archive.
    let extractions: [Extraction]
    /// CHD images the set needs. Sessions only contain zip/7z files, so these are
    /// always reported.
    let requiredDisks: [String]

    var verdict: Verdict {
        problems.isEmpty ? .complete : .incomplete
    }

    /// The driver itself is known not to work in this core.
    var mayNotRun: Bool {
        !machine.runnable || machine.driverStatus == "preliminary"
    }

    var needsAttention: Bool {
        !problems.isEmpty || !requiredDisks.isEmpty || mayNotRun
    }
}

/// Checks a Library game against the catalog before MAME loads it. Only reads the
/// romset database and archive directories; takes milliseconds.
///
/// The session is assembled so MAME finds every file it can: the game archive under its
/// set name, BIOS-folder archives named after the parent/BIOS/devices, parent sets
/// elsewhere in the Library linked under their set names, and any remaining file that
/// exists in another indexed archive extracted into the set's loose-file folder. Only
/// files found nowhere are reported.
enum MameSetAuditor {
    /// Nil when the game was never recognized or its set is no longer in the catalog.
    static func audit(romgameKey: String, archiveFileName: String, biosFolder: MameBiosFolder) -> MameSetAudit? {
        let persistence = MameRomSetPersistence.shared
        guard let record = persistence.archiveRecord(owner: .game(romgameKey: romgameKey)),
              let machine = persistence.machine(named: record.matchedSet) else {
            return nil
        }

        // romof chain: the set itself, then its parent and/or BIOS.
        var chain = [machine]
        var next = machine.romOf
        while let name = next, chain.count < 8, !chain.contains(where: { $0.name == name }),
              let ancestor = persistence.machine(named: name) {
            chain.append(ancestor)
            next = ancestor.romOf
        }
        let biosName = chain.first(where: \.isBios)?.name
        let biosOption = chain.lazy.compactMap(\.defaultBios).first
        let biosKeys = biosName.map { persistence.romKeys(of: $0, filter: .all) } ?? []
        let devices = persistence.devices(of: machine.name)

        // What MAME can open in the session. A renamed archive is staged under its set name.
        var visible = persistence.archiveEntryKeys(owner: .game(romgameKey: romgameKey)) ?? []
        let archiveBaseName = (archiveFileName as NSString).deletingPathExtension.lowercased()
        let gameStagedName = archiveBaseName == machine.name ? nil : "\(machine.name).\(record.format)"
        for name in chain.dropFirst().map(\.name) + devices {
            visible.formUnion(biosFolder.entryKeys(ofSet: name))
        }

        // Parent sets in the Library (not in the BIOS folder): link the copy holding the
        // most of what the game still lacks.
        var links: [MameSetAudit.SessionLink] = []
        let required = persistence.requiredRoms(of: machine.name, biosOption: biosOption)
        for ancestor in chain.dropFirst() where !ancestor.isBios && biosFolder.installedFileNames(ofSet: ancestor.name).isEmpty {
            let needed = Set(required.map(\.key)).subtracting(visible)
            guard !needed.isEmpty else { break }
            let candidates = persistence.libraryArchives(ofSet: ancestor.name).compactMap { record -> (MameArchiveRecord, Set<MameRomKey>)? in
                guard case .game(let key) = record.owner,
                      let keys = persistence.archiveEntryKeys(owner: .game(romgameKey: key)) else { return nil }
                return (record, keys)
            }
            guard let best = candidates.max(by: { $0.1.intersection(needed).count < $1.1.intersection(needed).count }),
                  !best.1.isDisjoint(with: needed), case .game(let key) = best.0.owner else { continue }
            visible.formUnion(best.1)
            links.append(MameSetAudit.SessionLink(stagedName: "\(ancestor.name).\(best.0.format)", romgameKey: key))
        }

        var problems: [MameSetAudit.Problem] = []
        var extractions: [MameSetAudit.Extraction] = []
        func report(_ rom: MameRomSetPersistence.RequiredRom, source: MameSetAudit.Source, folder: String) {
            guard !visible.contains(rom.key) else { return }
            // MAME looks for loose files in a folder named after the set (or device), under
            // the name the set lists.
            for record in persistence.archivesContaining(rom.key) {
                if let entryName = persistence.entryName(owner: record.owner, key: rom.key) {
                    extractions.append(MameSetAudit.Extraction(stagedPath: "\(folder)/\(rom.name)",
                                                               source: record.owner, entryName: entryName))
                    visible.insert(rom.key)
                    return
                }
            }
            problems.append(MameSetAudit.Problem(source: source, fileName: rom.name))
        }

        for rom in required {
            let source: MameSetAudit.Source
            if let biosName, biosKeys.contains(rom.key) {
                source = .bios(biosName)
            } else if rom.merge != nil, let parent = machine.cloneOf {
                source = .parent(parent)
            } else {
                source = .game
            }
            report(rom, source: source, folder: machine.name)
        }
        for device in devices {
            for rom in persistence.requiredRoms(of: device, biosOption: nil) {
                report(rom, source: .device(device), folder: device)
            }
        }

        return MameSetAudit(machine: machine, problems: problems, gameStagedName: gameStagedName, links: links,
                            extractions: extractions, requiredDisks: persistence.requiredDisks(of: machine.name))
    }
}
