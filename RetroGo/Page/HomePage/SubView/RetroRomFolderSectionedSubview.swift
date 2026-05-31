//
//  RetroRomFolderSectionedSubview.swift
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
//  Note: file is still named `RetroRomFolderByCoreSubview.swift` to
//  avoid Xcode project file resync. The class itself was renamed to
//  `RetroRomFolderSectionedSubview` because it now serves both byCore
//  and byTag grouping (and any future grouping) via the strategy
//  pattern. Rename the file in Xcode at your leisure.
//

import UIKit
import SnapKit
import ObjcHelper
import RACoordinator

/// Generic sectioned `RetroRomFolderSubview` — one section per
/// grouping bucket (a core for byCore, a tag for byTag). The
/// "what's a section, what files go in which section" decision lives
/// entirely in the injected `RetroRomFolderSectionedDataSource`; this
/// class owns only the UI side (layout, snapshot management, drag-
/// suppression, tap → launch, sticky header, expand/collapse).
///
/// ## Why one class for byCore AND byTag
///
/// The UI behavior is identical: each section has a sticky header
/// (`RetroRomSectionHeaderView`), file cells inside, tap to launch
/// with the picked grouping context (file's section determines which
/// core or which "tag flavor" launches). Only the data layer differs.
///
/// Adopting `UICollectionViewDataSource`-style strategy injection
/// over inheritance keeps the UI body ~600 lines (this file) shared,
/// while each grouping is ~100 lines in its own focused
/// `…SectionedDataSource` file. Adding a new grouping (e.g. by year,
/// by file size bracket) requires only a new data source — no UI
/// changes.
///
/// ## Layout
///
/// Same as before the refactor: one class supports both icon and list
/// layouts internally, dispatching on `viewLayout` captured at init.
/// Width-adaptive icon grid + width-invariant list rows.
///
/// ## Mutation API (exposed to data sources)
///
/// Data sources call `insertWrapper`, `removeFile`, `removeSection`,
/// `refreshHeader`, and `sortAndApply` from their event handlers.
/// These are intentionally `internal` (not `private`) so the
/// separately-filed data sources can drive in-memory state updates
/// without us inventing a mutation-record DSL.
final class RetroRomFolderSectionedSubview: UIView, RetroRomFolderSubview {

    // MARK: - RetroRomFolderSubview

    weak var delegate: RetroRomFolderSubviewDelegate?

    let folderKey: String

    /// Global emptiness — same rule as the sister subviews. Section
    /// view at root with zero games is "library is empty"; in any
    /// other folder we DON'T show the empty CTA (drilling into an
    /// empty subfolder of a populated library shouldn't claim the
    /// library is empty).
    var couldShowEmptyTip: Bool {
        let folderCount = Retro​Rom​Persistence.shared.getFolderCount() ?? 0
        let romCount    = Retro​Rom​Persistence.shared.getRomFileCount() ?? 0
        return folderCount + romCount == 0
    }

    // MARK: - Types

    private typealias DataSourceCV    = UICollectionViewDiffableDataSource<String, RetroRomFileItemWrapper>
    private typealias Snapshot        = NSDiffableDataSourceSnapshot<String, RetroRomFileItemWrapper>
    private typealias SectionSnapshot = NSDiffableDataSourceSectionSnapshot<RetroRomFileItemWrapper>
    private typealias IconCellReg     = UICollectionView.CellRegistration<RetroRomFileIconViewCell, RetroRomFileItemWrapper>
    private typealias ListCellReg     = UICollectionView.CellRegistration<RetroRomFileListViewCell, RetroRomFileItemWrapper>
    private typealias HeaderReg       = UICollectionView.SupplementaryRegistration<RetroRomSectionHeaderView>

    // MARK: - State

    private let sectionedDataSource: RetroRomFolderSectionedDataSource

    private let viewLayout: RetroRomViewLayout

    /// Section order. Mutated by `insertWrapper` / `removeFile` /
    /// `removeSection`. Drives `applySnapshot` order.
    internal private(set) var sectionKeys: [String] = []

    /// Per-section items. Source of truth; snapshot is a projection.
    internal private(set) var sectionItems: [String: [RetroRomFileItemWrapper]] = [:]

    /// Per-section header params. Drives header view configuration
    /// and the count-label KVO.
    internal private(set) var sectionParams: [String: RetroRomSectionParam] = [:]

    // MARK: - Views

    private let collectionView: UICollectionView
    private var dataSource: DataSourceCV!
    private var lastIconItemSize: CGSize = .zero
    private weak var blankInteractionHost: UIView?

    // MARK: - Init

    init(folderKey: String, dataSource: RetroRomFolderSectionedDataSource, oldParameters: [String: RetroRomSectionParam]?) {
        self.folderKey           = folderKey
        self.sectionedDataSource = dataSource
        self.viewLayout          = RetroRomFolderPageState.shared.viewLayout
        self.collectionView = UICollectionView(frame: .zero,
                                               collectionViewLayout: UICollectionViewLayout())
        super.init(frame: .zero)
        configCollectionView()
        configDiffableDataSource()
        loadInitialData(oldParameters: oldParameters)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard viewLayout == .icon else { return }
        let newItemSize = computeIconItemSize(forWidth: bounds.width)
        guard newItemSize != lastIconItemSize else { return }
        lastIconItemSize = newItemSize
        collectionView.setCollectionViewLayout(makeIconLayout(forWidth: bounds.width), animated: false)
    }
}

// MARK: - Setup

private extension RetroRomFolderSectionedSubview {

    func configCollectionView() {
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true

        if viewLayout == .list {
            collectionView.collectionViewLayout = makeListLayout()
        }

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

    func configDiffableDataSource() {
        let iconCellReg = IconCellReg { cell, _, wrapped in
            cell.wrappedItem = wrapped
        }
        let listCellReg = ListCellReg { cell, _, wrapped in
            cell.wrappedItem = wrapped
        }

        let layout = self.viewLayout
        dataSource = DataSourceCV(collectionView: collectionView) { cv, indexPath, wrapped in
            switch layout {
            case .icon:
                return cv.dequeueConfiguredReusableCell(using: iconCellReg, for: indexPath, item: wrapped)
            case .list:
                return cv.dequeueConfiguredReusableCell(using: listCellReg, for: indexPath, item: wrapped)
            }
        }

        let headerReg = HeaderReg(elementKind: RetroRomSectionHeaderView.sectionHeaderElementKind) {
            [weak self] header, _, indexPath in
            guard let self = self else { return }
            let sectionKey = self.dataSource.snapshot().sectionIdentifiers[indexPath.section]
            header.param  = self.sectionParams[sectionKey]
            header.holder = self
        }

        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath)
        }
    }

    /// Pull initial state from the data source. Resets all expand
    /// states to collapsed via the params returned by the data source
    /// — every fresh entry into a section view starts collapsed.
    func loadInitialData(oldParameters: [String: RetroRomSectionParam]?) {
        let result = sectionedDataSource.buildSections(oldParameters: oldParameters)
        self.sectionKeys = result.keys
        self.sectionItems = result.items
        self.sectionParams = result.params
        sortSectionItems()
        applySnapshot(animated: false)
    }

    func sortSectionItems() {
        switch RetroRomFolderPageState.shared.sortType {
        case .fileNameAsc:
            sectionItems.keys.forEach { sectionItems[$0]?.sortByFileNameAsc() }
        case .fileNameDesc:
            sectionItems.keys.forEach { sectionItems[$0]?.sortByFileNameDesc() }
        case .lastPlay:
            sectionItems.keys.forEach { sectionItems[$0]?.sortByLastPlayAt() }
        case .addDateDesc:
            sectionItems.keys.forEach { sectionItems[$0]?.sortByCreateDateDesc() }
        case .addDateAsc:
            sectionItems.keys.forEach { sectionItems[$0]?.sortByCreateDateAsc() }
        case .playTime:
            sectionItems.keys.forEach { sectionItems[$0]?.sortByPlayTime() }
        }
    }

    /// Project current in-memory state to snapshot. Empty sections
    /// dropped (no ghost headers); collapsed sections show header only.
    func applySnapshot(animated: Bool, completion: (() -> Void)? = nil) {
        var snap = Snapshot()
        for key in sectionKeys {
            let array = sectionItems[key] ?? []
            guard !array.isEmpty else { continue }
            guard let param = sectionParams[key] else { continue }
            snap.appendSections([key])
            if param.expanded {
                snap.appendItems(array, toSection: key)
            }
        }
        dataSource.apply(snap, animatingDifferences: animated, completion: completion)
    }
}

// MARK: - Layout construction

private extension RetroRomFolderSectionedSubview {

    func makeListLayout() -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                              heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .absolute(RetroRomBaseListViewCell.rowHeight))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize,
                                                       repeatingSubitem: item,
                                                       count: 1)
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 0, leading: 0, bottom: 10, trailing: 0)
        section.boundarySupplementaryItems = [makeHeaderItem()]
        return StickyHeaderLayout(section: section)
    }

    func makeIconLayout(forWidth width: CGFloat) -> UICollectionViewLayout {
        let itemSize = computeIconItemSize(forWidth: width)
        let columnCount = computeIconColumnCount(forWidth: width)

        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .absolute(itemSize.width),
            heightDimension: .fractionalHeight(1.0)))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .absolute(itemSize.height)),
            repeatingSubitem: item,
            count: columnCount)
        group.interItemSpacing = .fixed(30)
        group.contentInsets = .init(top: 0, leading: 30, bottom: 0, trailing: 30)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 10
        section.contentInsets = .init(top: 0, leading: 0, bottom: 10, trailing: 0)
        section.boundarySupplementaryItems = [makeHeaderItem()]
        return StickyHeaderLayout(section: section)
    }

    func computeIconItemSize(forWidth width: CGFloat) -> CGSize {
        let columnCount = computeIconColumnCount(forWidth: width)
        let itemWidth: CGFloat
        switch columnCount {
        case ...3:
            itemWidth = (width - 30 - 30 * 2 - 30) / 3
        case 4:
            itemWidth = (min(width, 430) - 30 - 30 * 3 - 30) / 4
        default:
            itemWidth = (width - 30 - 30 * CGFloat(columnCount - 1) - 30) / CGFloat(columnCount)
        }
        let itemHeight = itemWidth / 256 * 240 + RetroRomBaseIconViewCell.titleHeight
        return CGSize(width: max(itemWidth, 1), height: max(itemHeight, 1))
    }

    func computeIconColumnCount(forWidth width: CGFloat) -> Int {
        if width > 500 { return max(1, Int((width - 40) / (150 + 20))) }
        if width > 400 { return 4 }
        return 3
    }

    func makeHeaderItem() -> NSCollectionLayoutBoundarySupplementaryItem {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                          heightDimension: .estimated(54))
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: size,
            elementKind: RetroRomSectionHeaderView.sectionHeaderElementKind,
            alignment: .top)
        header.zIndex = 2
        header.pinToVisibleBounds = true
        return header
    }
}

// MARK: - Mutation primitives (internal — called by data sources)

extension RetroRomFolderSectionedSubview {

    /// Insert a wrapper into a section's in-memory array. Creates the
    /// section if it doesn't exist (using `dataSource.makeParam(for:)`
    /// + `dataSource.insertionIndex(for:in:)` to place the new section
    /// key correctly).
    ///
    /// Idempotent on the (file, sectionKey) pair — if a wrapper for
    /// the same file already exists in that section, skip.
    ///
    /// Does NOT apply the snapshot. Caller batches with `sortAndApply`.
    func insertWrapper(_ wrapper: RetroRomFileItemWrapper,
                       underKey key: String,
                       dataSource ds: RetroRomFolderSectionedDataSource) {
        if let existing = sectionItems[key],
           existing.contains(where: { $0.item == wrapper.item }) {
            return
        }

        // Ensure param exists for the section.
        if sectionParams[key] == nil {
            guard let param = ds.makeParam(forSectionKey: key) else { return }
            sectionParams[key] = param
        }
        let param = sectionParams[key]!

        if sectionItems[key] != nil {
            sectionItems[key]?.append(wrapper)
        } else {
            sectionItems[key] = [wrapper]
            // New section — ask data source where to slot the key.
            let index = ds.insertionIndex(forNewSectionKey: key, in: sectionKeys)
            sectionKeys.insert(key, at: min(index, sectionKeys.count))
        }

        param.itemCount = sectionItems[key]?.count ?? 0
    }

    /// Remove every wrapper for `file` from `key`. Drops the section
    /// if it becomes empty. Updates param.itemCount.
    ///
    /// Does NOT apply the snapshot. Caller batches.
    func removeFile(_ file: RetroRomFileItem, fromSectionKey key: String) {
        guard var array = sectionItems[key] else { return }
        let before = array.count
        array.removeAll { $0.item == file }
        guard array.count != before else { return }

        sectionItems[key] = array
        if let param = sectionParams[key] {
            param.itemCount = array.count
        }
        if array.isEmpty {
            sectionKeys.removeAll { $0 == key }
            sectionItems.removeValue(forKey: key)
            sectionParams.removeValue(forKey: key)
        }
    }

    /// Drop a section entirely — header and all items. Used when an
    /// entity backing the section is deleted (tag deleted, etc.).
    func removeSection(_ key: String) {
        sectionKeys.removeAll { $0 == key }
        sectionItems.removeValue(forKey: key)
        sectionParams.removeValue(forKey: key)
    }

    /// Refresh a section header in place — re-binds the same param
    /// to trigger title / icon re-read inside `RetroRomSectionHeaderView`.
    /// Used when a backing entity's display attributes change (tag
    /// title edited, etc.).
    func refreshHeader(forSectionKey key: String) {
        guard let snapshotSection = dataSource.snapshot().sectionIdentifiers.firstIndex(of: key) else { return }
        let indexPath = IndexPath(item: 0, section: snapshotSection)
        guard let header = collectionView.supplementaryView(forElementKind: RetroRomSectionHeaderView.sectionHeaderElementKind, at: indexPath) as? RetroRomSectionHeaderView else { return }
        // Re-assign the same param triggers `param.didSet` in the
        // header → title/icon labels re-read from `param`.
        let savedParam = header.param
        header.param = savedParam
    }

    /// Sort + apply — call from data source event handlers after a
    /// batch of mutations.
    func sortAndApply(animated: Bool) {
        sortSectionItems()
        applySnapshot(animated: animated)
        delegate?.subviewDidChangeContent(self)
    }
}

// MARK: - RetroRomFolderSubview required hooks

extension RetroRomFolderSectionedSubview {

    func reload() {
        loadInitialData(oldParameters: sectionParams)
        delegate?.subviewDidChangeContent(self)
    }

    func languageChanged() {
        var snap = dataSource.snapshot()
        let visible = collectionView.indexPathsForVisibleItems
            .compactMap { dataSource.itemIdentifier(for: $0) }
        if !visible.isEmpty {
            snap.reconfigureItems(visible)
            dataSource.apply(snap, animatingDifferences: false)
        }
        for view in collectionView.visibleSupplementaryViews(ofKind: RetroRomSectionHeaderView.sectionHeaderElementKind) {
            guard let header = view as? RetroRomSectionHeaderView else { continue }
            header.languageChanged()
        }
    }

    func sort() {
        sortSectionItems()
    }

    func applyData(animated: Bool) {
        applySnapshot(animated: animated)
    }
}

// MARK: - RetroRomFolderSubview optional hooks

extension RetroRomFolderSectionedSubview {

    /// Incremental file-import path. Delegates to the data source for
    /// (sectionKey, wrapper) dispatch, then applies a batch update.
    func fileItemImported(_ keys: [String]) {
        guard !keys.isEmpty else { return }

        let files = RetroRomFileManager.shared.retroRomFileItems(in: Set(keys))
        let scoped = files.filter { sectionedDataSource.isInScope($0) }
        guard !scoped.isEmpty else { return }

        for file in scoped {
            for (sectionKey, wrapper) in sectionedDataSource.wrappers(for: file) {
                insertWrapper(wrapper, underKey: sectionKey, dataSource: sectionedDataSource)
            }
        }

        sortAndApply(animated: true)
    }

    func folderItemImported(folderKey importedFolderKey: String, itemKeys: [String]) {
        fileItemImported(itemKeys)
    }

    /// Remove the deleted file from every section it lives in.
    func itemDeleted(_ item: RetroRomBaseItem) {
        guard sectionItems.values.contains(where: { $0.contains(where: { $0.item == item }) }),
              let file = item as? RetroRomFileItem else { return }

        let affectedKeys = sectionItems.compactMap { (key, array) in
            array.contains(where: { $0.item == file }) ? key : nil
        }
        for key in affectedKeys {
            removeFile(file, fromSectionKey: key)
        }
        guard !affectedKeys.isEmpty else { return }

        applySnapshot(animated: true)
        delegate?.subviewDidChangeContent(self)
    }

    func fileTagColorChanged(tagId: Int) {
        // pulseText KVO trick — cells redraw tag chips without snapshot apply.
        for cell in collectionView.visibleCells {
            if let cell = cell as? RetroRomBaseListViewCell,
               let file = cell.item as? RetroRomFileItem,
               file.tagIdArray.contains(tagId) {
                file.pulseText.toggle()
                continue
            }
            if let cell = cell as? RetroRomBaseIconViewCell,
               let file = cell.item as? RetroRomFileItem,
               file.tagIdArray.contains(tagId) {
                file.pulseText.toggle()
            }
        }
    }

    /// Section views don't show folder cells — new folder is a no-op.
    func appendNewFolder(_ folder: RetroRomFolderItem) {
        // Intentionally empty.
    }

    func itemMovedIn(_ item: RetroRomBaseItem) {
        guard let file = item as? RetroRomFileItem else { return }
        fileItemImported([file.key])
    }

    // Forward grouping-specific events to the data source.

    func fileCoreAssigned(_ file: RetroRomFileItem, newCoreId: String?, oldCoreId: String?) {
        sectionedDataSource.handleFileCoreAssigned(file,
                                                   newCoreId: newCoreId,
                                                   oldCoreId: oldCoreId,
                                                   in: self)
    }

    func fileTagsChanged(_ file: RetroRomFileItem, added: Set<Int>, removed: Set<Int>) {
        sectionedDataSource.handleFileTagsChanged(file, added: added, removed: removed, in: self)
    }

    func fileTagDeleted(_ tag: RetroRomFileTag) {
        sectionedDataSource.handleFileTagDeleted(tag, in: self)
    }

    func fileTagTitleChanged(_ tag: RetroRomFileTag) {
        sectionedDataSource.handleFileTagTitleChanged(tag, in: self)
    }
}

// MARK: - RetroRomSectionHeaderHolder

extension RetroRomFolderSectionedSubview: RetroRomSectionHeaderHolder {

    func toggleSection(key: String, show: Bool) {
        var sectionSnapshot = SectionSnapshot()
        if show, let items = sectionItems[key] {
            sectionSnapshot.append(items)
        }
        dataSource.apply(sectionSnapshot, to: key, animatingDifferences: true)
    }
}

// MARK: - UICollectionViewDelegate

extension RetroRomFolderSectionedSubview: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let wrapped = dataSource.itemIdentifier(for: indexPath) else { return }
        Vibration.selection.vibrate()
        delegate?.subview(self, didTapFile: wrapped.item, withPreferredCore: wrapped.core)
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first,
              let wrapped = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) {
            [weak self] _ in
            guard let self = self else { return nil }
            return self.delegate?.subview(self, contextMenuForItem: wrapped.item)
        }
    }
}

// MARK: - UIContextMenuInteractionDelegate (blank area)

extension RetroRomFolderSectionedSubview: UIContextMenuInteractionDelegate {

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return nil }
            return self.delegate?.subviewContextMenuForBlankArea(self)
        }
    }

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
