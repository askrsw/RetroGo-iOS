//
//  RetroRomFolderTreeSubview.swift
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
import SnapKit
import ObjcHelper
import RACoordinator

/// The tree-layout `RetroRomFolderSubview` implementation — sister of
/// `RetroRomFolderIconSubview` / `RetroRomFolderListSubview`, but
/// fundamentally different in semantics: instead of showing one folder's
/// direct children, it shows the **entire subtree rooted at `folderKey`**
/// as an outline with expand/collapse per folder.
///
/// ## Key differences from icon / list subviews
///
/// - **Tap on folder cell**: toggles expand/collapse in place. Does NOT
///   push a new host VC. The whole point of tree mode is to see multiple
///   levels at once.
/// - **Data starting point**: `folderKey`, not always "root". When the
///   user is inside `FC/Konami/` and switches to tree mode, they see
///   `Konami`'s subtree — not the whole library. Equivalent to legacy
///   only when `folderKey == "root"`.
/// - **Diffable identifier type**: `RetroRomBaseItem` (object reference)
///   rather than `String` key. Required for `NSDiffableDataSourceSectionSnapshot`
///   to track parent/child relationships, and convenient for hanging
///   per-folder state (`folder.expand`) directly on the model.
/// - **Drag & drop is cross-level**: a drop can target any folder in
///   any visible level of the tree. The source folder (if expanded) is
///   collapsed during the drag so the user doesn't drag a phantom subtree.
/// - **Outline disclosure accessory**: `UICollectionViewListCell`'s
///   `.outlineDisclosure()` automatically wires the chevron to the
///   section snapshot's expand/collapse — we don't render or hit-test
///   it ourselves.
///
/// ## Architectural alignment with the protocol
///
/// Follows the same constraints as the other subviews: no modal
/// presentation, no navigation push, no NotificationCenter, no writes
/// to `RetroRomFolderPageState.shared`. Snapshot mutation, expand state,
/// drag preview animation are all internal; everything else bubbles up
/// through `RetroRomFolderSubviewDelegate`.
final class RetroRomFolderTreeSubview: UIView, RetroRomFolderSubview {

    // MARK: - RetroRomFolderSubview

    weak var delegate: RetroRomFolderSubviewDelegate?

    let folderKey: String

    /// Same global-emptiness rule as the sister subviews. We deliberately
    /// don't return true for "tree root has no children" — empty-tip
    /// pretends the whole library is empty (with an Import CTA), which
    /// would be misleading when the user is inside an empty subfolder
    /// of a populated library.
    var couldShowEmptyTip: Bool {
        let folderCount = RetroRomPersistence.shared.getFolderCount() ?? 0
        let romCount    = RetroRomPersistence.shared.getRomFileCount() ?? 0
        return folderCount + romCount == 0
    }

    // MARK: - Types

    private enum Section: Hashable { case main }

    /// Diffable identifier is the actual model object. Item identity
    /// is by object reference (NSObject default), which is fine because
    /// `RetroRomFileManager` caches items — the same key always returns
    /// the same instance for the lifetime of the manager.
    private typealias DataSource     = UICollectionViewDiffableDataSource<Section, RetroRomBaseItem>
    private typealias OutlineSnapshot = NSDiffableDataSourceSectionSnapshot<RetroRomBaseItem>

    // MARK: - Views

    private let collectionView: UICollectionView
    private var dataSource: DataSource!

    /// Transparent host carrying the blank-area `UIContextMenuInteraction`.
    /// Same pattern as icon/list — modern delegate hook is per-cell only,
    /// so empty-region taps need their own interaction.
    private weak var blankInteractionHost: UIView?

    // MARK: - Drag & drop tracking

    private var draggingIndexPath: IndexPath?

    /// Hover scale (1.05x) — matches list subview. Tree rows are also
    /// full-width, so a larger factor like icon mode's 1.25 would
    /// visibly stretch past the screen edge. Folder cells and file
    /// cells both get the affordance since cross-level drops are
    /// expected; the source cell itself is skipped (self-drop is no-op).
    private var draggingOverIndexPath: IndexPath? {
        didSet {
            guard draggingOverIndexPath != oldValue else { return }

            if let old = oldValue,
               let cell = collectionView.cellForItem(at: old) {
                UIView.animate(withDuration: 0.1) {
                    cell.transform = .identity
                }
            }

            if let new = draggingOverIndexPath,
               new != draggingIndexPath,
               let cell = collectionView.cellForItem(at: new) {
                UIView.animate(withDuration: 0.1) {
                    cell.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
                }
            }
        }
    }

    // MARK: - Init

    init(folderKey: String) {
        self.folderKey = folderKey

        // Same layout as `RetroRomFolderListSubview`: list config with
        // plain appearance gives full-width cells + automatic separators.
        // The 20pt leading/trailing inset is baked into the cell itself
        // (see `RetroRomBaseListViewCell.configUI`); using the list
        // config here means we get system separators for free, and the
        // outline-disclosure accessory + indentation system both
        // cooperate with `UICollectionViewListCell` natively.
        var listConfig = UICollectionLayoutListConfiguration(appearance: .plain)
        listConfig.backgroundColor = .systemBackground
        listConfig.headerMode = .none
        let layout = UICollectionViewCompositionalLayout.list(using: listConfig)

        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        configCollectionView()
        configDataSource()
        loadInitialData()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // No `layoutSubviews` override: list layout is static (cells are
    // always full-width, height is fixed by the cell's intrinsic content
    // size). Width changes from rotation re-flow existing cells without
    // any reconfiguration.
}

// MARK: - Setup

private extension RetroRomFolderTreeSubview {

    func configCollectionView() {
        collectionView.backgroundColor = .clear
        collectionView.delegate        = self
        collectionView.alwaysBounceVertical = true

        collectionView.dragDelegate = self
        collectionView.dropDelegate = self

        // Blank-area context menu host — same trick as the sister
        // subviews. The transparent backgroundView carries the
        // long-press interaction for empty regions and inter-row gaps.
        let blankHost = UIView()
        blankHost.backgroundColor = .clear
        blankHost.isUserInteractionEnabled = true
        blankHost.addInteraction(UIContextMenuInteraction(delegate: self))
        collectionView.backgroundView = blankHost
        self.blankInteractionHost = blankHost

        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    func configDataSource() {
        // File cells: no outline disclosure (leaves).
        let fileCellReg = UICollectionView.CellRegistration<RetroRomFileListViewCell, RetroRomFileItem> { cell, _, file in
            cell.item = file
            // Clear `accessories` explicitly — `UICollectionViewListCell`
            // reuses cells across registrations, so if a cell was
            // previously a folder cell with the outline-disclosure
            // accessory, we need to drop it on file dequeues.
            cell.accessories = []
        }

        // Folder cells: outline-disclosure chevron on the leading side.
        // The disclosure's automatic style ties directly into the
        // section snapshot's expand/collapse — tapping the chevron
        // triggers `willExpandItem` / `willCollapseItem` on our
        // `sectionSnapshotHandlers` below, and the snapshot animates
        // the children in/out automatically.
        let folderCellReg = UICollectionView.CellRegistration<RetroRomFolderListViewCell, RetroRomFolderItem> { cell, _, folder in
            cell.item = folder
            let options = UICellAccessory.OutlineDisclosureOptions(style: .automatic,
                                                                   tintColor: .mainColor)
            cell.accessories = [.outlineDisclosure(options: options)]
        }

        dataSource = DataSource(collectionView: collectionView) { cv, indexPath, item in
            if let file = item as? RetroRomFileItem {
                return cv.dequeueConfiguredReusableCell(using: fileCellReg, for: indexPath, item: file)
            }
            if let folder = item as? RetroRomFolderItem {
                return cv.dequeueConfiguredReusableCell(using: folderCellReg, for: indexPath, item: folder)
            }
            // Defensive — base item with no concrete subclass shouldn't
            // exist in practice; blank cell beats crash.
            return UICollectionViewCell()
        }

        // Mirror the expand state from the chevron tap back onto the
        // model. This is what lets a tree rebuild (e.g., on sort
        // change) preserve the user's expand/collapse choices — they
        // live on `folder.expand`, not in the snapshot.
        var handlers = DataSource.SectionSnapshotHandlers<RetroRomBaseItem>()
        handlers.willExpandItem = { item in
            (item as? RetroRomFolderItem)?.expand = true
        }
        handlers.willCollapseItem = { item in
            (item as? RetroRomFolderItem)?.expand = false
        }
        dataSource.sectionSnapshotHandlers = handlers
    }

    func loadInitialData() {
        let snap = buildSnapshot()
        dataSource.apply(snap, to: .main, animatingDifferences: false)
    }
}

// MARK: - Snapshot construction

private extension RetroRomFolderTreeSubview {

    /// Walk the folder hierarchy starting from this subview's
    /// `folderKey` and produce a section snapshot. Sort is applied at
    /// every level. Each folder's persisted `expand` state is honored —
    /// rebuilding the snapshot doesn't reset the user's open/closed
    /// choices.
    ///
    /// Note the divergence from legacy `RetroRomTreeFileBrowser` which
    /// always started from `"root"`. We start from `folderKey` so that
    /// switching to tree mode while inside a subfolder shows that
    /// subfolder's subtree only — not the whole library above it.
    /// `folderKey == "root"` falls back to legacy behavior naturally.
    private func buildSnapshot() -> OutlineSnapshot {
        var snap = OutlineSnapshot()

        func addChildren(of parentKey: String, parentItem: RetroRomFolderItem?) {
            guard let parent = RetroRomFileManager.shared.folderItem(key: parentKey) else { return }
            var children = parent.subItems
            sortItems(&children)
            snap.append(children, to: parentItem)
            for child in children {
                if let subFolder = child as? RetroRomFolderItem {
                    addChildren(of: subFolder.key, parentItem: subFolder)
                }
            }
            // The container itself is "expanded" — applied AFTER we've
            // appended its children, so the expand call has something
            // to reveal.
            if parent.expand {
                snap.expand([parent])
            }
        }

        addChildren(of: folderKey, parentItem: nil)
        return snap
    }

    /// Apply the global sort criterion to an item array, folders-first.
    /// Shared by both `buildSnapshot` (initial / rebuild) and the
    /// incremental update paths (so newly-inserted items land in
    /// sort-correct order).
    func sortItems(_ items: inout [RetroRomBaseItem]) {
        switch RetroRomFolderPageState.shared.sortType {
        case .fileNameAsc:  items.sortByFileNameAscFolderFirst()
        case .fileNameDesc: items.sortByFileNameDescFolderFirst()
        case .lastPlay:     items.sortByLastPlayAtFolderFirst()
        case .addDateDesc:  items.sortByCreateDateDescFolderFirst()
        case .addDateAsc:   items.sortByCreateDateAscFolderFirst()
        case .playTime:     items.sortByPlayTimeFolderFirst()
        }
    }
}

// MARK: - RetroRomFolderSubview required hooks

extension RetroRomFolderTreeSubview {

    func reload() {
        let snap = buildSnapshot()
        dataSource.apply(snap, to: .main, animatingDifferences: false)
        delegate?.subviewDidChangeContent(self)
    }

    func languageChanged() {
        // Reconfigure visible items so cells re-read localized strings
        // from their bound model. Cell identity stays the same so no
        // structural change is needed.
        var snap = dataSource.snapshot()
        let visible = collectionView.indexPathsForVisibleItems
            .compactMap { dataSource.itemIdentifier(for: $0) }
        guard !visible.isEmpty else { return }
        snap.reconfigureItems(visible)
        dataSource.apply(snap, animatingDifferences: false)
    }

    /// Tree's sort is structurally the same as a full rebuild — every
    /// level needs reordering. We rebuild the snapshot but the per-
    /// folder `expand` state is preserved on the model, so the user's
    /// open subtrees stay open after the reorder.
    func sort() {
        let snap = buildSnapshot()
        dataSource.apply(snap, to: .main, animatingDifferences: false)
    }

    /// For tree, sort and applyData collapse into the same "rebuild
    /// from current model state." The icon/list distinction (sort
    /// touches data, applyData touches UI) doesn't map onto the tree's
    /// hierarchical data model — one snapshot apply does both.
    func applyData(animated: Bool) {
        let snap = buildSnapshot()
        dataSource.apply(snap, to: .main, animatingDifferences: animated)
    }
}

// MARK: - RetroRomFolderSubview optional hooks

extension RetroRomFolderTreeSubview {

    /// Incremental insert for newly-imported file items. Legacy's
    /// algorithm: locate the parent folder in the current snapshot,
    /// append the files under it, expand if needed. We follow the same
    /// shape but additionally guard that the parent folder is actually
    /// in OUR subtree — files imported into folders outside our scope
    /// (e.g. a sibling subtree) are silently ignored.
    func fileItemImported(_ keys: [String]) {
        guard !keys.isEmpty else { return }

        let files = keys.compactMap { RetroRomFileManager.shared.fileItem(key: $0) }
        guard let firstFile = files.first,
              let parentFolder = firstFile.parentFolderItem else { return }

        var snap = dataSource.snapshot(for: .main)

        // Determine where to attach: nil parent (top of our subtree) or
        // an existing folder inside the snapshot.
        if parentFolder.key == folderKey {
            // Imported into the tree's root — top-level append.
            // Skip files already present (re-import / duplicate signal).
            let newFiles = files.filter { !snap.contains($0) }
            guard !newFiles.isEmpty else { return }
            snap.append(newFiles, to: nil)
        } else if snap.contains(parentFolder) {
            let newFiles = files.filter { !snap.contains($0) }
            guard !newFiles.isEmpty else { return }
            snap.append(newFiles, to: parentFolder)
            parentFolder.expand = true
            snap.expand([parentFolder])
        } else {
            // Parent isn't in our subtree — ignore.
            return
        }

        dataSource.apply(snap, to: .main, animatingDifferences: true)
        delegate?.subviewDidChangeContent(self)
    }

    /// Incremental insert for a newly-imported folder (and its
    /// recursively-imported contents). Walks the new folder's subtree
    /// and inserts every descendant folder + file into the snapshot.
    /// Adapted from legacy `folderItemImported` with the same scope
    /// guard as `fileItemImported`: ignore imports outside our subtree.
    func folderItemImported(folderKey importedFolderKey: String, itemKeys: [String]) {
        guard let importedFolder = RetroRomFileManager.shared.folderItem(key: importedFolderKey) else { return }

        var snap = dataSource.snapshot(for: .main)

        // Attach point for the imported folder.
        if importedFolder.parent == folderKey {
            // Direct child of the tree's root.
            if !snap.contains(importedFolder) {
                snap.append([importedFolder], to: nil)
            }
        } else if let parent = importedFolder.parentFolderItem,
                  snap.contains(parent) {
            // Nested under an existing folder in our subtree.
            if !snap.contains(importedFolder) {
                snap.append([importedFolder], to: parent)
            }
        } else {
            // Out of scope.
            return
        }

        importedFolder.expand = true
        snap.expand([importedFolder])

        // Recursively add the imported folder's subtree.
        func addSubItems(_ parent: RetroRomFolderItem) {
            for childKey in parent.subFolderKeys {
                guard let childFolder = RetroRomFileManager.shared.folderItem(key: childKey) else { continue }
                if !snap.contains(childFolder) {
                    snap.append([childFolder], to: parent)
                }
                childFolder.expand = true
                snap.expand([childFolder])
                addSubItems(childFolder)
            }
            let files = parent.subFileKeys.compactMap { RetroRomFileManager.shared.fileItem(key: $0) }
            let newFiles = files.filter { !snap.contains($0) }
            if !newFiles.isEmpty {
                snap.append(newFiles, to: parent)
            }
        }
        addSubItems(importedFolder)

        dataSource.apply(snap, to: .main, animatingDifferences: true)
        delegate?.subviewDidChangeContent(self)
    }

    /// Smart "item removed from its old location" handler — covers
    /// **both** the literal-delete and the post-move cases with the same
    /// callback signature.
    ///
    /// The host calls this after either `RetroRomFileManager.deleteItem`
    /// (real delete) or `moveItem` (move to another folder). The two
    /// look the same from the host's POV — "item is gone from its old
    /// spot" — so this method has to disambiguate:
    ///
    /// 1. Remove the item from its current snapshot position.
    /// 2. If the item still exists in the manager AND its (now updated)
    ///    parent is visible in this tree, re-insert it under that parent.
    ///    This handles the move case in-place.
    ///
    /// For icon/list subviews this method just removes the cell; for
    /// tree we get the cross-level reattachment for free without
    /// needing a new protocol method.
    func itemDeleted(_ item: RetroRomBaseItem) {
        // Scope check: every host in the nav stack receives this
        // callback (delete is broadcast), and trees in unrelated
        // subtrees should bail out without touching their snapshot.
        //
        // We deliberately check `snapshot.contains(item)` rather than
        // `dataSource.indexPath(for: item) != nil`. The latter only
        // returns non-nil for items currently **rendered** — an item
        // sitting inside a *collapsed* parent folder is in the
        // snapshot but not rendered, so `indexPath(for:)` is nil for
        // it. A guard on `indexPath` would falsely treat that case as
        // "out of scope" and leave stale data in the snapshot; the
        // user would see a ghost cell next time they expand that
        // parent. `contains` is visibility-independent and is the
        // correct scope predicate.
        var snap = dataSource.snapshot(for: .main)
        guard snap.contains(item) else { return }

        snap.delete([item])

        // Was this a move (item still in manager) rather than a real
        // delete (item gone)?
        let stillExists = RetroRomFileManager.shared.retroItem(key: item.key) != nil
        if stillExists {
            // Look up the new parent — `item.parent` was mutated by
            // `RetroRomFileManager.moveItem` before this callback fires.
            //
            // Idempotency guard: when this tree is BOTH source and
            // destination of the drop (drop landed within the tree's
            // own scope), the `state.itemMoved` Combine broadcast
            // also fires `itemMovedIn` on this same subview. We don't
            // want to add the item twice — `!snap.contains(item)`
            // catches both orderings (this callback first vs the
            // broadcast first).
            if item.parent == folderKey {
                if !snap.contains(item) {
                    snap.append([item], to: nil)
                }
            } else if let newParent = RetroRomFileManager.shared.folderItem(key: item.parent),
                      snap.contains(newParent) {
                if !snap.contains(item) {
                    snap.append([item], to: newParent)
                }
                newParent.expand = true
                snap.expand([newParent])
            }
            // Else: new parent isn't in our subtree (cross-subtree move),
            // and we just let the item disappear from this view.
        }

        dataSource.apply(snap, to: .main, animatingDifferences: true)
        delegate?.subviewDidChangeContent(self)
    }

    /// Move-into-destination event from `RetroRomFolderPageState.itemMoved`.
    /// Host has filtered by `destinationFolderKey == folderKey`, so the
    /// item's new parent is this tree's root — we add it at the top
    /// level. Idempotent: if a same-host drop already inserted via
    /// `itemDeleted`'s smart logic, we skip silently.
    func itemMovedIn(_ item: RetroRomBaseItem) {
        var snap = dataSource.snapshot(for: .main)
        guard !snap.contains(item) else { return }
        snap.append([item], to: nil)
        dataSource.apply(snap, to: .main, animatingDifferences: true)
        delegate?.subviewDidChangeContent(self)
    }

    func fileTagColorChanged(tagId: Int) {
        // `pulseText` KVO trick — cells observe it and redraw their tag
        // chips. No snapshot structure change.
        for cell in collectionView.visibleCells {
            guard let cell = cell as? RetroRomBaseListViewCell,
                  let file = cell.item as? RetroRomFileItem,
                  file.tagIdArray.contains(tagId) else { continue }
            file.pulseText.toggle()
        }
    }

    /// A folder was just created by the host (via
    /// `RetroRomFileManager.createNewFolder`) and the host wants the
    /// subview to reveal it. For tree, we insert it under its parent
    /// (which is `folder.parent`, possibly nested deep inside our
    /// subtree) and expand the parent. The host follows up with
    /// `presentRenameAlert(for:)` so the user can name it immediately.
    func appendNewFolder(_ folder: RetroRomFolderItem) {
        var snap = dataSource.snapshot(for: .main)
        guard !snap.contains(folder) else { return }

        if folder.parent == folderKey {
            snap.append([folder], to: nil)
        } else if let parent = RetroRomFileManager.shared.folderItem(key: folder.parent),
                  snap.contains(parent) {
            snap.append([folder], to: parent)
            parent.expand = true
            snap.expand([parent])
        } else {
            // Parent not in our subtree — shouldn't happen via the
            // current "New Folder" UX flow (host only creates folders
            // inside the current subtree), but defensive return keeps
            // the snapshot consistent.
            return
        }

        dataSource.apply(snap, to: .main, animatingDifferences: true) { [weak self] in
            // Scroll the new folder into view so the rename alert
            // (presented by host immediately after this call) lines up
            // with a visible cell.
            guard let self = self,
                  let indexPath = self.dataSource.indexPath(for: folder) else { return }
            self.collectionView.scrollToItem(at: indexPath, at: [], animated: false)
        }

        delegate?.subviewDidChangeContent(self)
    }
}

// MARK: - UICollectionViewDelegate

extension RetroRomFolderTreeSubview: UICollectionViewDelegate {

    /// Tap behavior diverges from icon/list:
    ///
    /// - **Folder cell**: toggle expand/collapse in place. We deliberately
    ///   do NOT call `delegate?.subview(self, didTapFolder:)` — the
    ///   whole point of tree mode is to expand multiple levels at
    ///   once. Pushing a new host VC would defeat that.
    /// - **File cell**: launch via delegate, same as icon/list.
    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        Vibration.selection.vibrate()

        if let folder = item as? RetroRomFolderItem {
            folder.expand.toggle()
            var snap = dataSource.snapshot(for: .main)
            if folder.expand {
                snap.expand([folder])
            } else {
                snap.collapse([folder])
            }
            dataSource.apply(snap, to: .main, animatingDifferences: true)
        } else if let file = item as? RetroRomFileItem {
            delegate?.subview(self, didTapFile: file)
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first,
              let item = dataSource.itemIdentifier(for: indexPath) else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) {
            [weak self] _ in
            guard let self = self else { return nil }
            return self.delegate?.subview(self, contextMenuForItem: item)
        }
    }
}

// MARK: - UICollectionViewDragDelegate

extension RetroRomFolderTreeSubview: UICollectionViewDragDelegate {

    func collectionView(_ collectionView: UICollectionView,
                        itemsForBeginning session: UIDragSession,
                        at indexPath: IndexPath) -> [UIDragItem] {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return [] }
        draggingIndexPath = indexPath

        let provider = NSItemProvider(object: item.key as NSString)
        let dragItem = UIDragItem(itemProvider: provider)
        dragItem.localObject = item
        return [dragItem]
    }

    func collectionView(_ collectionView: UICollectionView,
                        dragSessionDidEnd session: UIDragSession) {
        draggingOverIndexPath = nil
        draggingIndexPath = nil
    }
}

// MARK: - UICollectionViewDropDelegate

extension RetroRomFolderTreeSubview: UICollectionViewDropDelegate {

    func collectionView(_ collectionView: UICollectionView,
                        dropSessionDidUpdate session: UIDropSession,
                        withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard session.localDragSession != nil,
              session.items.count == 1 else {
            return UICollectionViewDropProposal(operation: .cancel)
        }

        // Collapse the source folder if it's currently expanded —
        // otherwise dragging a folder visibly "carries" its expanded
        // children with it through the tree, which reads as chaos.
        // Lifted from legacy `RetroRomTreeFileBrowser`'s same trick.
        if let srcIndexPath = draggingIndexPath,
           let srcFolder = dataSource.itemIdentifier(for: srcIndexPath) as? RetroRomFolderItem,
           srcFolder.expand {
            srcFolder.expand = false
            var snap = dataSource.snapshot(for: .main)
            snap.collapse([srcFolder])
            dataSource.apply(snap, to: .main, animatingDifferences: true)
        }

        draggingOverIndexPath = destinationIndexPath

        return UICollectionViewDropProposal(operation: .move,
                                            intent: .insertIntoDestinationIndexPath)
    }

    func collectionView(_ collectionView: UICollectionView,
                        dropSessionDidExit session: UIDropSession) {
        draggingOverIndexPath = nil
    }

    func collectionView(_ collectionView: UICollectionView,
                        performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let dstIndexPath = coordinator.destinationIndexPath,
              let srcIndexPath = draggingIndexPath,
              dstIndexPath != srcIndexPath,
              let srcItem = dataSource.itemIdentifier(for: srcIndexPath),
              let dstItem = dataSource.itemIdentifier(for: dstIndexPath) else {
            return
        }

        // Resolve the drop destination to a folder: dropping directly
        // onto a folder cell uses that folder; dropping onto a file
        // cell uses the file's parent folder (matches legacy semantics
        // — "drop in the vicinity of THESE rows" intent).
        let dstFolder: RetroRomFolderItem
        if let folder = dstItem as? RetroRomFolderItem {
            dstFolder = folder
        } else if let parent = dstItem.parentFolderItem {
            dstFolder = parent
        } else {
            return
        }

        // Reject moving to the source's current parent — would be a
        // no-op move and the file manager's alert flow would just
        // pop up the "same folder" error.
        if srcItem.parentFolderItem == dstFolder { return }

        // Host owns the move (calls `RetroRomFileManager.moveItem`).
        // On success the host calls back via `itemDeleted`, and our
        // smart `itemDeleted` handles both the old-position removal
        // AND the new-position insertion automatically.
        delegate?.subview(self, didDropItem: srcItem, intoFolder: dstFolder)
    }
}

// MARK: - UIContextMenuInteractionDelegate (blank area)

extension RetroRomFolderTreeSubview: UIContextMenuInteractionDelegate {

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return nil }
            return self.delegate?.subviewContextMenuForBlankArea(self)
        }
    }

    /// Suppress the default huge backgroundView screenshot preview —
    /// 1×1 transparent at the touch point. Same pattern as icon/list
    /// subviews; see those for the full rationale.
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let host = interaction.view else { return nil }

        let tempView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        tempView.backgroundColor = .clear

        let params = UIPreviewParameters()
        params.backgroundColor = .clear

        let target = UIPreviewTarget(container: host,
                                     center: interaction.location(in: host))
        return UITargetedPreview(view: tempView, parameters: params, target: target)
    }
}
