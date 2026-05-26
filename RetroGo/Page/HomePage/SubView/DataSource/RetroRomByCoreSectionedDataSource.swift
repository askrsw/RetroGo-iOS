//
//  RetroRomByCoreSectionedDataSource.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/26.
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

import UIKit
import RACoordinator

/// Groups files by emulator core. Section identifier is `core.coreId`;
/// `EmuCoreInfoItem.noneCore().coreId == "0"` is the "no recognized
/// core" bucket which always appears last.
///
/// One file with multiple supported cores appears in MULTIPLE sections
/// (each wrapper has a unique `index` for diffable identity). This is
/// intentional — the user can pick which core's section they want to
/// launch from.
final class RetroRomByCoreSectionedDataSource: RetroRomFolderSectionedDataSource {

    let folderKey: String

    init(folderKey: String) {
        self.folderKey = folderKey
    }

    func buildSections(oldParameters: [String: RetroRomSectionParam]?) -> (keys: [String],
                             items: [String: [RetroRomFileItemWrapper]],
                             params: [String: RetroRomSectionParam]) {
        var keys: [String] = []
        var items: [String: [RetroRomFileItemWrapper]] = [:]

        var params: [String: RetroRomSectionParam]
        if let old = oldParameters?.first?.value, case .byCore(_) = old.type {
            params = oldParameters!
        } else {
            params = [:]
        }

        let present = Set(RetroRomItemTraversal.distinctCores(under: folderKey).map { $0.coreId })
        guard !present.isEmpty else { return (keys, items, params) }

        let allCores = RetroRomCoreManager.shared.allCores
        let noneKey  = EmuCoreInfoItem.noneCore().coreId

        // Preserve `allCores` order for predictable / stable section
        // sequence across reloads.
        for core in allCores where present.contains(core.coreId) {
            let files = RetroRomItemTraversal.files(under: folderKey, matching: core)
            guard !files.isEmpty else { continue }
            keys.append(core.coreId)
            items[core.coreId] = files.map { RetroRomFileItemWrapper(item: $0, core: core) }

            if params[core.coreId] != nil {
                params[core.coreId]?.itemCount = files.count
            } else {
                let param = RetroRomSectionParam(type: .byCore(core))
                param.itemCount = files.count
                params[core.coreId] = param
            }
        }

        // "No recognized core" bucket — always last.
        if present.contains(noneKey) {
            let noneFiles = RetroRomItemTraversal.files(under: folderKey, matching: .noneCore())
            if !noneFiles.isEmpty {
                keys.append(noneKey)
                items[noneKey] = noneFiles.map { RetroRomFileItemWrapper(item: $0, core: .noneCore()) }
                if params[noneKey] != nil {
                    params[noneKey]?.itemCount = noneFiles.count
                } else {
                    let param = RetroRomSectionParam(type: .byCore(EmuCoreInfoItem.noneCore()))
                    param.itemCount = noneFiles.count
                    params[noneKey] = param
                }
            }
        }

        return (keys, items, params)
    }

    func wrappers(for file: RetroRomFileItem) -> [(sectionKey: String, wrapper: RetroRomFileItemWrapper)] {
        let supported = file.getSupportedCores()
        if supported.isEmpty {
            let none = EmuCoreInfoItem.noneCore()
            return [(none.coreId, RetroRomFileItemWrapper(item: file, core: none))]
        }
        return supported.map { core in
            (core.coreId, RetroRomFileItemWrapper(item: file, core: core))
        }
    }

    func makeParam(forSectionKey key: String) -> RetroRomSectionParam? {
        guard let core = RetroRomCoreManager.shared.core(key) else { return nil }
        return RetroRomSectionParam(type: .byCore(core))
    }

    func insertionIndex(forNewSectionKey key: String, in existingKeys: [String]) -> Int {
        let noneKey = EmuCoreInfoItem.noneCore().coreId
        if key == noneKey { return existingKeys.count }
        if let noneIndex = existingKeys.firstIndex(of: noneKey) { return noneIndex }
        return existingKeys.count
    }

    func isInScope(_ file: RetroRomFileItem) -> Bool {
        RetroRomItemTraversal.allFiles(under: folderKey).contains { $0.key == file.key }
    }

    // MARK: - byCore-specific event

    /// Ported from legacy `RetroRomSectionFileBrowser.fileCoreAssigned`.
    /// Three pieces:
    ///   1. Remove from old prefer-only section (if oldCoreId given).
    ///   2. Add to new prefer-only section (if newCoreId given).
    ///   3. Unidentified-bucket migration based on the file's live
    ///      `getRunningCore` result.
    func handleFileCoreAssigned(_ file: RetroRomFileItem,
                                newCoreId: String?,
                                oldCoreId: String?,
                                in subview: RetroRomFolderSectionedSubview) {
        guard isInScope(file) else { return }

        if let oldKey = oldCoreId {
            subview.removeFile(file, fromSectionKey: oldKey)
        }

        if let newKey = newCoreId, let newCore = RetroRomCoreManager.shared.core(newKey) {
            let wrapped = RetroRomFileItemWrapper(item: file, core: newCore)
            subview.insertWrapper(wrapped, underKey: newKey, dataSource: self)
        }

        // Unidentified bucket migration. Live truth: getRunningCore.
        let noneKey = EmuCoreInfoItem.noneCore().coreId
        let isInNoneBucket = subview.sectionItems[noneKey]?.contains(where: { $0.item == file }) ?? false
        let hasRunningCore = RetroRomCoreManager.shared.getRunningCore(file) != nil

        if hasRunningCore, isInNoneBucket {
            subview.removeFile(file, fromSectionKey: noneKey)
        } else if !hasRunningCore, !isInNoneBucket {
            let none = EmuCoreInfoItem.noneCore()
            let wrapped = RetroRomFileItemWrapper(item: file, core: none)
            subview.insertWrapper(wrapped, underKey: noneKey, dataSource: self)
        }

        subview.sortAndApply(animated: true)
    }
}
