//
//  RetroRomFolderSectionedDataSource.swift
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

/// Strategy contract for `RetroRomFolderSectionedSubview`. Encapsulates
/// the "how do we group files into sections" decision so a single
/// subview class can serve byCore, byTag, and any future grouping
/// without UI duplication.
///
/// Required methods cover the data-build path (initial load, per-file
/// dispatch, scope check). Optional extension methods cover grouping-
/// specific events (core reassignment, tag changes, tag lifecycle) —
/// data sources only implement the events meaningful to their grouping;
/// defaults are no-ops so byCore data source doesn't need stubs for
/// tag events and vice versa.
///
/// Event-handling methods receive a back-reference to the subview so
/// they can call its mutation primitives (`insertWrapper`, `removeFile`,
/// etc.) without us needing to invent a mini-DSL of "section mutation
/// records." The subview's public mutation API is small and focused.
protocol RetroRomFolderSectionedDataSource: AnyObject {

    // MARK: - Required

    /// Scope identity — usually mirrors the subview's `folderKey`.
    /// Stored on the data source so events can scope-filter without
    /// needing the subview as a parameter.
    var folderKey: String { get }

    /// Build initial section state. Called once at subview init and on
    /// `reload()`. Returns ordered section keys + per-key items + per-
    /// key header params, all consistent with each other.
    func buildSections(oldParameters: [String: RetroRomSectionParam]?) -> (keys: [String],
                             items: [String: [RetroRomFileItemWrapper]],
                             params: [String: RetroRomSectionParam])

    /// For an incrementally-imported file, return all (sectionKey,
    /// wrapper) pairs the subview should slot it into. byCore: one per
    /// supported core + the unidentified bucket if no support. byTag:
    /// one per assigned tag + the untagged bucket if no tags.
    func wrappers(for file: RetroRomFileItem) -> [(sectionKey: String, wrapper: RetroRomFileItemWrapper)]

    /// Construct a fresh header param for a section key. Called by the
    /// subview when an incremental insert creates a section that didn't
    /// exist in the snapshot yet — the data source has the type
    /// information (core / tag) needed to build the param.
    func makeParam(forSectionKey key: String) -> RetroRomSectionParam?

    /// Choose insertion position for a brand-new section key. byCore:
    /// before the unidentified-core bucket if present. byTag: before
    /// the untagged bucket if present.
    func insertionIndex(forNewSectionKey key: String, in existingKeys: [String]) -> Int

    /// Whether the data source considers this file in-scope. Used by
    /// event broadcasts (delete, core-assign, tag-change) to skip out-
    /// of-scope updates without scanning sections. Typical impl: walk
    /// `RetroRomItemTraversal.allFiles(under: folderKey)`.
    func isInScope(_ file: RetroRomFileItem) -> Bool

    // MARK: - Optional
    
    /// byCore-only event. Default no-op. byCore data source implements
    /// the legacy `fileCoreAssigned` migration: remove from old prefer-
    /// only section, add to new prefer-only section, handle the
    /// unidentified-bucket boundary.
    func handleFileCoreAssigned(_ file: RetroRomFileItem,
                                newCoreId: String?,
                                oldCoreId: String?,
                                in subview: RetroRomFolderSectionedSubview)

    /// byTag-only event. Default no-op. byTag data source implements
    /// the legacy `fileTagFileChanged` migration: remove from each
    /// removed-tag section, add to each added-tag section, handle the
    /// untagged-bucket boundary.
    func handleFileTagsChanged(_ file: RetroRomFileItem,
                               added: Set<Int>,
                               removed: Set<Int>,
                               in subview: RetroRomFolderSectionedSubview)

    /// byTag-only event. A tag entity was deleted. byTag data source
    /// removes the corresponding section entirely; files that were
    /// only tagged with this tag migrate to the untagged bucket.
    func handleFileTagDeleted(_ tag: RetroRomFileTag,
                              in subview: RetroRomFolderSectionedSubview)

    /// byTag-only event. A tag's title changed. byTag data source
    /// refreshes the corresponding section header (re-binds the same
    /// param to trigger title re-read).
    func handleFileTagTitleChanged(_ tag: RetroRomFileTag,
                                   in subview: RetroRomFolderSectionedSubview)
}

// MARK: - Optional event hooks

extension RetroRomFolderSectionedDataSource {

    /// byCore-only event. Default no-op. byCore data source implements
    /// the legacy `fileCoreAssigned` migration: remove from old prefer-
    /// only section, add to new prefer-only section, handle the
    /// unidentified-bucket boundary.
    func handleFileCoreAssigned(_ file: RetroRomFileItem,
                                newCoreId: String?,
                                oldCoreId: String?,
                                in subview: RetroRomFolderSectionedSubview) {}

    /// byTag-only event. Default no-op. byTag data source implements
    /// the legacy `fileTagFileChanged` migration: remove from each
    /// removed-tag section, add to each added-tag section, handle the
    /// untagged-bucket boundary.
    func handleFileTagsChanged(_ file: RetroRomFileItem,
                               added: Set<Int>,
                               removed: Set<Int>,
                               in subview: RetroRomFolderSectionedSubview) {}

    /// byTag-only event. A tag entity was deleted. byTag data source
    /// removes the corresponding section entirely; files that were
    /// only tagged with this tag migrate to the untagged bucket.
    func handleFileTagDeleted(_ tag: RetroRomFileTag,
                              in subview: RetroRomFolderSectionedSubview) {}

    /// byTag-only event. A tag's title changed. byTag data source
    /// refreshes the corresponding section header (re-binds the same
    /// param to trigger title re-read).
    func handleFileTagTitleChanged(_ tag: RetroRomFileTag,
                                   in subview: RetroRomFolderSectionedSubview) {}
}
