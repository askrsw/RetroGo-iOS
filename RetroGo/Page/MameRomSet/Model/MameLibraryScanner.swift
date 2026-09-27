//
//  MameLibraryScanner.swift
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

/// Re-identifies every zip/7z game in the Library against the catalog, so the romset
/// index follows the core:
///
/// - after the catalog was built for a different core (set names and contents may have
///   changed), and
/// - after an import that skipped recognition because no catalog was available.
///
/// Games recognized for the first time get the set's official name and MAME as
/// preferred core, but only where the user has not set either. Games already indexed
/// keep their display name. BIOS archives that ended up in the Library are left alone.
enum MameLibraryScanner {
    private struct Candidate {
        let key: String
        let path: String
        let fileName: String
    }

    /// Runs on the catalog queue right after an update left a catalog matching the core.
    static func scanIfNeeded(coreFingerprint: String) {
        let persistence = MameRomSetPersistence.shared
        let pending = persistence.metaValue(.libraryScanPending) != nil
        guard pending || persistence.metaValue(.libraryScanFingerprint) != coreFingerprint else { return }

        let start = CFAbsoluteTimeGetCurrent()
        // The Library cache lives on the main thread; nothing on the main thread waits for
        // the catalog queue, so this sync hop cannot deadlock.
        let candidates = DispatchQueue.main.sync { collectCandidates() }

        var indexed = 0
        var removed = 0
        var newlyRecognized: [(key: String, match: MameArchiveMatch)] = []
        for candidate in candidates {
            let owner = MameArchiveOwner.game(romgameKey: candidate.key)
            let wasIndexed = persistence.archiveRecord(owner: owner) != nil
            guard let match = MameArchiveIdentifier.identify(archiveAtPath: candidate.path, fileName: candidate.fileName),
                  !match.machine.isSupportSet else {
                if wasIndexed {
                    persistence.deleteArchive(owner: owner)
                    removed += 1
                }
                continue
            }
            if persistence.storeArchive(owner: owner, format: match.formatName, matchedSet: match.machine.name,
                                        matchKind: match.kind.rawValue, entries: match.entries) {
                indexed += 1
                if !wasIndexed {
                    newlyRecognized.append((candidate.key, match))
                }
            }
        }

        if !newlyRecognized.isEmpty {
            DispatchQueue.main.sync { applyMetadata(newlyRecognized) }
        }

        persistence.setMetaValue(coreFingerprint, for: .libraryScanFingerprint)
        persistence.setMetaValue(nil, for: .libraryScanPending)
        NSLog("[MameScan] Scanned %d archives in %.2fs%@: %d indexed (%d new), %d records removed",
              candidates.count, CFAbsoluteTimeGetCurrent() - start, pending ? " (pending import)" : "",
              indexed, newlyRecognized.count, removed)
    }

    /// Marks that an import could not recognize archives; the next catalog update scans.
    static func markPending() {
        MameRomSetPersistence.shared.setMetaValue("1", for: .libraryScanPending)
    }

    private static func collectCandidates() -> [Candidate] {
        RetroRomItemTraversal.allFiles(under: "root").compactMap { item in
            guard item.fileGroupType == .single,
                  RAArchiveReader.formatOfArchive(atPath: item.rawName) != .unknown,
                  let path = item.entryPath else {
                return nil
            }
            return Candidate(key: item.key, path: path, fileName: item.rawName)
        }
    }

    /// Same metadata as an import, without overriding anything the user chose.
    private static func applyMetadata(_ games: [(key: String, match: MameArchiveMatch)]) {
        let mameCore = RetroArchX.shared().allCores.first { $0.coreId == MameImportScreener.mameCoreId }
        for game in games {
            guard let item = RetroRomFileManager.shared.fileItem(key: game.key) else { continue }
            if item.showName == nil, let name = game.match.machine.description {
                _ = item.updateShowName(name)
            }
            if item.inheritedPreferCore == nil, let mameCore {
                _ = item.assignCore(mameCore)
            }
        }
    }
}
