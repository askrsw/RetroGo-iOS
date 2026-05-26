//
//  RetroRomItemTraversal.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/24.
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

import RACoordinator

/// Subtree query helpers. Encapsulates "give me all the file items rooted at
/// folderKey X" and its derivatives (group by core / tag, count distinct
/// groups, etc.).
///
/// Implementation strategy: **lazy recursive descent via `subItems`**, which
/// itself is backed by `RetroRomFileManager`'s in-memory caches. The cost
/// of the first descent on a cold cache is one DB roundtrip per folder; once
/// warm, repeated descents are pure memory access.
///
/// We deliberately do NOT add a single recursive-CTE query to the persistence
/// layer for this. The lazy-descent approach is simple, leans on caches that
/// already exist, and avoids broadening the SQL surface. If a future profiler
/// shows root-scope descents are a hotspot, this is the place to optimize —
/// the call sites are agnostic to the strategy.
enum RetroRomItemTraversal {

    // MARK: - Subtree files

    /// All file items in the subtree rooted at `folderKey`.
    /// Returns empty if the folder doesn't exist or has no descendants.
    static func allFiles(under folderKey: String) -> [RetroRomFileItem] {
        guard let folder = RetroRomFileManager.shared.folderItem(key: folderKey) else {
            return []
        }
        return allFiles(under: folder)
    }

    static func allFiles(under folder: RetroRomFolderItem) -> [RetroRomFileItem] {
        var result: [RetroRomFileItem] = []
        collectFiles(in: folder, into: &result)
        return result
    }

    /// Inout accumulator + iterative-ish recursion (no closures, no allocs
    /// per level beyond the result array growth). Keeps the call site cheap
    /// for deep trees.
    private static func collectFiles(in folder: RetroRomFolderItem,
                                     into result: inout [RetroRomFileItem]) {
        for sub in folder.subItems {
            if let file = sub as? RetroRomFileItem {
                result.append(file)
            } else if let subFolder = sub as? RetroRomFolderItem {
                collectFiles(in: subFolder, into: &result)
            }
        }
    }

    // MARK: - Distinct cores in subtree

    /// One `EmuCoreInfoItem` per distinct core represented by files in the
    /// subtree. Files matching multiple cores contribute to each. If any
    /// file lacks an identifiable core, `EmuCoreInfoItem.noneCore()` is
    /// included in the result.
    ///
    /// Used by:
    /// - The factory's single-group-skip check (count == 1)
    /// - The `GameGroupListViewController` row data source
    static func distinctCores(under folderKey: String) -> [EmuCoreInfoItem] {
        let files = allFiles(under: folderKey)
        var seen = Set<String>()
        var result: [EmuCoreInfoItem] = []
        for file in files {
            let cores = file.getSupportedCores()
            if cores.isEmpty {
                let none = EmuCoreInfoItem.noneCore()
                if seen.insert(none.coreId).inserted {
                    result.append(none)
                }
            } else {
                for core in cores where seen.insert(core.coreId).inserted {
                    result.append(core)
                }
            }
        }
        return result
    }

    /// Files in subtree that match a specific core. Uses `getSupportedCores()`
    /// which combines extension matches with the user-assigned `preferCore`,
    /// keeping this method symmetric with `distinctCores` above.
    ///
    /// Equivalence with the legacy `RetroRomFileManager.getRomFileArrayByCore`:
    /// - "Unidentified" bucket — `noneCore()` — receives a file iff
    ///   `getSupportedCores()` returns empty (no extension match AND no prefer).
    /// - Any concrete core receives a file iff that core appears in
    ///   `getSupportedCores()` (which includes prefer-but-not-extension cases).
    static func files(under folderKey: String, matching core: EmuCoreInfoItem) -> [RetroRomFileItem] {
        let files = allFiles(under: folderKey)
        let isNoneCore = (core == EmuCoreInfoItem.noneCore())
        return files.filter { file in
            let supported = file.getSupportedCores()
            if isNoneCore {
                return supported.isEmpty
            }
            return supported.contains(where: { $0.coreId == core.coreId })
        }
    }

    // MARK: - Distinct tags in subtree

    /// One `RetroRomFileTag` per distinct tag represented by files in the
    /// subtree. Includes `RetroRomFileTag.untaged` if any file has an
    /// empty `tagIdArray`.
    static func distinctTags(under folderKey: String) -> [RetroRomFileTag] {
        let files = allFiles(under: folderKey)
        var seenIds = Set<Int>()
        var tagIds: [Int] = []
        for file in files {
            if file.tagIdArray.isEmpty {
                if seenIds.insert(RetroRomFileTag.untaged.id).inserted {
                    tagIds.append(RetroRomFileTag.untaged.id)
                }
            } else {
                for id in file.tagIdArray where seenIds.insert(id).inserted {
                    tagIds.append(id)
                }
            }
        }
        // Single batched fetch — leans on the file manager's tag cache.
        return RetroRomFileManager.shared.fileTags(in: tagIds, order: true)
    }

    /// Files in subtree carrying a specific tag id. Tag id `0` selects
    /// untagged files (those with an empty `tagIdArray`).
    static func files(under folderKey: String, matching tag: RetroRomFileTag) -> [RetroRomFileItem] {
        let files = allFiles(under: folderKey)
        if tag.id == 0 {
            return files.filter { $0.tagIdArray.isEmpty }
        }
        return files.filter { $0.tagIdArray.contains(tag.id) }
    }
}
