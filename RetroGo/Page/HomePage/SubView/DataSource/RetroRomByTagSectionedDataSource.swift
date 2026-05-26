//
//  RetroRomByTagSectionedDataSource.swift
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

/// Groups files by tag. Section identifier is `String(tag.id)`;
/// `String(RetroRomFileTag.untaged.id) == "0"` is the untagged bucket
/// which always appears last.
///
/// One file with multiple assigned tags appears in MULTIPLE sections
/// — same model as byCore. A file with no tags appears once in the
/// untagged bucket.
final class RetroRomByTagSectionedDataSource: RetroRomFolderSectionedDataSource {

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
        if let old = oldParameters?.first?.value, case .byTag(_) = old.type {
            params = oldParameters!
        } else {
            params = [:]
        }

        // `distinctTags(under:)` returns tags ordered + .untaged if any
        // file has empty tagIdArray.
        let tags = RetroRomItemTraversal.distinctTags(under: folderKey)
        guard !tags.isEmpty else { return (keys, items, params) }

        let untagged = RetroRomFileTag.untaged
        let untaggedKey = String(untagged.id)

        // Walk in order; defer the untagged bucket to the end so it
        // appears last in the section list regardless of where
        // `distinctTags` placed it.
        for tag in tags where tag.id != untagged.id {
            let files = RetroRomItemTraversal.files(under: folderKey, matching: tag)
            guard !files.isEmpty else { continue }
            let key = String(tag.id)
            keys.append(key)
            items[key] = files.map { RetroRomFileItemWrapper(item: $0, tag: tag) }

            if params[key] != nil {
                params[key]?.itemCount = files.count
            } else {
                let param = RetroRomSectionParam(type: .byTag(tag))
                param.itemCount = files.count
                params[key] = param
            }
        }

        // Untagged bucket — last.
        let untaggedFiles = RetroRomItemTraversal.files(under: folderKey, matching: untagged)
        if !untaggedFiles.isEmpty {
            keys.append(untaggedKey)
            items[untaggedKey] = untaggedFiles.map { RetroRomFileItemWrapper(item: $0, tag: untagged) }
            if params[untaggedKey] != nil {
                params[untaggedKey]?.itemCount = untaggedFiles.count
            } else {
                let param = RetroRomSectionParam(type: .byTag(untagged))
                param.itemCount = untaggedFiles.count
                params[untaggedKey] = param
            }
        }

        return (keys, items, params)
    }

    func wrappers(for file: RetroRomFileItem) -> [(sectionKey: String, wrapper: RetroRomFileItemWrapper)] {
        if file.tagIdArray.isEmpty {
            let untagged = RetroRomFileTag.untaged
            return [(String(untagged.id), RetroRomFileItemWrapper(item: file, tag: untagged))]
        }
        // Resolve tag instances from ids; skip any tag that doesn't
        // exist in the manager cache (shouldn't happen, defensive).
        let tags = RetroRomFileManager.shared.fileTags(in: file.tagIdArray)
        return tags.map { tag in
            (String(tag.id), RetroRomFileItemWrapper(item: file, tag: tag))
        }
    }

    func makeParam(forSectionKey key: String) -> RetroRomSectionParam? {
        if key == String(RetroRomFileTag.untaged.id) {
            return RetroRomSectionParam(type: .byTag(.untaged))
        }
        guard let id = Int(key),
              let tag = RetroRomFileManager.shared.fileTag(id: id) else { return nil }
        return RetroRomSectionParam(type: .byTag(tag))
    }

    func insertionIndex(forNewSectionKey key: String, in existingKeys: [String]) -> Int {
        let untaggedKey = String(RetroRomFileTag.untaged.id)
        if key == untaggedKey { return existingKeys.count }
        if let idx = existingKeys.firstIndex(of: untaggedKey) { return idx }
        return existingKeys.count
    }

    func isInScope(_ file: RetroRomFileItem) -> Bool {
        RetroRomItemTraversal.allFiles(under: folderKey).contains { $0.key == file.key }
    }

    // MARK: - byTag-specific events

    /// Ported from legacy `RetroRomSectionFileBrowser.fileTagFileChanged`.
    /// Three pieces:
    ///   1. For each removed tag id, remove the file from that section.
    ///   2. For each added tag id, insert a fresh wrapper under that
    ///      section.
    ///   3. Untagged bucket migration: file went from tagged → untagged
    ///      or vice versa.
    func handleFileTagsChanged(_ file: RetroRomFileItem,
                               added: Set<Int>,
                               removed: Set<Int>,
                               in subview: RetroRomFolderSectionedSubview) {
        guard isInScope(file) else { return }

        // 1. Remove from sections of removed tags.
        for id in removed {
            subview.removeFile(file, fromSectionKey: String(id))
        }

        // 2. Add to sections of added tags.
        for id in added {
            guard let tag = RetroRomFileManager.shared.fileTag(id: id) else { continue }
            let wrapped = RetroRomFileItemWrapper(item: file, tag: tag)
            subview.insertWrapper(wrapped, underKey: String(id), dataSource: self)
        }

        // 3. Untagged bucket migration. Compare the file's current
        //    `tagIdArray` against its presence in the untagged bucket.
        let untagged = RetroRomFileTag.untaged
        let untaggedKey = String(untagged.id)
        let isInUntagged = subview.sectionItems[untaggedKey]?.contains(where: { $0.item == file }) ?? false

        if file.tagIdArray.isEmpty, !isInUntagged {
            // Moved INTO untagged bucket.
            let wrapped = RetroRomFileItemWrapper(item: file, tag: untagged)
            subview.insertWrapper(wrapped, underKey: untaggedKey, dataSource: self)
        } else if !file.tagIdArray.isEmpty, isInUntagged {
            // Moved OUT of untagged bucket.
            subview.removeFile(file, fromSectionKey: untaggedKey)
        }

        subview.sortAndApply(animated: true)
    }

    /// Ported from legacy `RetroRomSectionFileBrowser.fileTagDeleted`.
    /// The deleted tag's section is dropped entirely; files that were
    /// only carrying this tag migrate to the untagged bucket.
    func handleFileTagDeleted(_ tag: RetroRomFileTag,
                              in subview: RetroRomFolderSectionedSubview) {
        let key = String(tag.id)
        guard let wrappers = subview.sectionItems[key] else { return }

        // Find files in this section that, post-deletion, have no
        // remaining tags → they need to migrate to untagged.
        //
        // Note: `tag.id` has already been removed from each file's
        // `tagIdArray` by the time this fires (the manager mutates the
        // file before posting), so a file with empty `tagIdArray` here
        // is one that lost its last tag with this deletion.
        let migratingFiles = wrappers
            .map { $0.item }
            .filter { $0.tagIdArray.isEmpty }

        subview.removeSection(key)

        if !migratingFiles.isEmpty {
            let untagged = RetroRomFileTag.untaged
            let untaggedKey = String(untagged.id)
            for file in migratingFiles {
                let wrapped = RetroRomFileItemWrapper(item: file, tag: untagged)
                subview.insertWrapper(wrapped, underKey: untaggedKey, dataSource: self)
            }
        }

        subview.sortAndApply(animated: true)
    }

    /// Ported from legacy `RetroRomSectionFileBrowser.fileTagTitleChanged`.
    /// Re-bind the header's param to trigger title re-read in the
    /// header view.
    func handleFileTagTitleChanged(_ tag: RetroRomFileTag,
                                   in subview: RetroRomFolderSectionedSubview) {
        let key = String(tag.id)
        subview.refreshHeader(forSectionKey: key)
    }
}
