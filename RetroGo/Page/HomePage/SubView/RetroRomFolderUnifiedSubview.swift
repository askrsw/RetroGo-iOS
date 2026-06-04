//
//  RetroRomFolderUnifiedSubview.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/27.
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

/// Unified `RetroRomFolderSubview` that can render as either an icon grid
/// (iOS Files-like) or a list, selected at init via `Style`. Merges the
/// previously separate `RetroRomFolderIconSubview` and
/// `RetroRomFolderListSubview` — see those files for per-mode design notes.
///
/// Differences encapsulated by `Style`:
/// - layout: width-adaptive flow grid vs compositional list (`.plain`)
/// - cells: `RetroRom{File,Folder}IconViewCell` vs `...ListViewCell`
/// - drag hover scale: 1.25 (icon) vs 1.05 (list, already full-width)
/// - `layoutSubviews` width-adaptive recompute: icon only
final class RetroRomFolderUnifiedSubview: UIView, RetroRomFolderSubview {

    // MARK: - Style

    enum Style {
        case icon
        case list
    }

    let style: Style

    // MARK: - RetroRomFolderSubview

    weak var delegate: RetroRomFolderSubviewDelegate?

    let folderKey: String

    var couldShowEmptyTip: Bool {
        let folderCount = RetroRomPersistence.shared.getFolderCount() ?? 0
        let romCount    = RetroRomPersistence.shared.getRomFileCount() ?? 0
        return folderCount + romCount == 0
    }

    // MARK: - State

    private var items: [RetroRomBaseItem] = []
    private var itemsByKey: [String: RetroRomBaseItem] = [:]

    private enum Section: Hashable { case main }
    private typealias DataSource = UICollectionViewDiffableDataSource<Section, String>
    private typealias Snapshot   = NSDiffableDataSourceSnapshot<Section, String>

    // MARK: - Views

    private let collectionView: UICollectionView
    private var dataSource: DataSource!

    /// Icon mode only: cached itemSize from the last layout pass, used to
    /// skip redundant `setCollectionViewLayout` swaps when bounds change
    /// without crossing a column-count threshold.
    private var lastItemSize: CGSize = .zero

    private weak var blankInteractionHost: UIView?

    // MARK: - Drag & drop tracking

    private var draggingIndexPath: IndexPath?

    private var draggingOverIndexPath: IndexPath? {
        didSet {
            guard draggingOverIndexPath != oldValue else { return }

            let scale = style.dragHoverScale

            if let old = oldValue,
               let cell = collectionView.cellForItem(at: old),
               !isFileCell(cell) {
                UIView.animate(withDuration: 0.1) {
                    cell.transform = .identity
                }
            }

            if let new = draggingOverIndexPath,
               new != draggingIndexPath,
               let cell = collectionView.cellForItem(at: new),
               !isFileCell(cell) {
                UIView.animate(withDuration: 0.1) {
                    cell.transform = CGAffineTransform(scaleX: scale, y: scale)
                }
            }
        }
    }

    // MARK: - Init

    init(folderKey: String, style: Style) {
        self.folderKey = folderKey
        self.style = style

        switch style {
        case .icon:
            self.collectionView = UICollectionView(
                frame: .zero,
                collectionViewLayout: UICollectionViewFlowLayout()
            )
        case .list:
            var listConfig = UICollectionLayoutListConfiguration(appearance: .plain)
            listConfig.backgroundColor = .systemBackground
            listConfig.headerMode = .none
            let layout = UICollectionViewCompositionalLayout.list(using: listConfig)
            self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        }

        super.init(frame: .zero)
        configCollectionView()
        configDataSource()
        loadInitialItems()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // List layout is static; only the icon grid needs width-adaptive
        // recompute.
        guard style == .icon else { return }
        let layout = makeFlowLayout(forWidth: bounds.width)
        guard layout.itemSize != lastItemSize else { return }
        lastItemSize = layout.itemSize
        collectionView.setCollectionViewLayout(layout, animated: false)
    }
}

// MARK: - Style helpers

private extension RetroRomFolderUnifiedSubview.Style {

    var dragHoverScale: CGFloat {
        switch self {
        case .icon: return 1.25
        case .list: return 1.05
        }
    }

    var fileCellID: String {
        switch self {
        case .icon: return "RetroRomFileIconViewCell"
        case .list: return "RetroRomFileListViewCell"
        }
    }

    var folderCellID: String {
        switch self {
        case .icon: return "RetroRomFolderIconViewCell"
        case .list: return "RetroRomFolderListViewCell"
        }
    }

    var fileCellClass: AnyClass {
        switch self {
        case .icon: return RetroRomFileIconViewCell.self
        case .list: return RetroRomFileListViewCell.self
        }
    }

    var folderCellClass: AnyClass {
        switch self {
        case .icon: return RetroRomFolderIconViewCell.self
        case .list: return RetroRomFolderListViewCell.self
        }
    }
}

private extension RetroRomFolderUnifiedSubview {

    func isFileCell(_ cell: UICollectionViewCell) -> Bool {
        switch style {
        case .icon: return cell is RetroRomFileIconViewCell
        case .list: return cell is RetroRomFileListViewCell
        }
    }
}

// MARK: - Setup

private extension RetroRomFolderUnifiedSubview {

    func configCollectionView() {
        collectionView.backgroundColor = .clear
        collectionView.delegate        = self
        collectionView.alwaysBounceVertical = true

        collectionView.dragDelegate = self
        collectionView.dropDelegate = self

        collectionView.register(style.fileCellClass,
                                forCellWithReuseIdentifier: style.fileCellID)
        collectionView.register(style.folderCellClass,
                                forCellWithReuseIdentifier: style.folderCellID)

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
        dataSource = DataSource(collectionView: collectionView) {
            [weak self] cv, indexPath, key in
            guard let self = self,
                  let item = self.itemsByKey[key] else {
                return UICollectionViewCell()
            }

            switch item.retroRomType {
            case .file:
                let cell = cv.dequeueReusableCell(
                    withReuseIdentifier: self.style.fileCellID,
                    for: indexPath
                )
                self.assignItem(item, to: cell)
                return cell

            case .folder:
                let cell = cv.dequeueReusableCell(
                    withReuseIdentifier: self.style.folderCellID,
                    for: indexPath
                )
                self.assignItem(item, to: cell)
                return cell

            case .none:
                return UICollectionViewCell()
            }
        }
    }

    /// Routes the `item` assignment through whichever cell base type
    /// matches the current style. Keeps the data-source closure free of
    /// style-specific casts.
    func assignItem(_ item: RetroRomBaseItem, to cell: UICollectionViewCell) {
        switch style {
        case .icon:
            (cell as? RetroRomBaseIconViewCell)?.item = item
        case .list:
            (cell as? RetroRomBaseListViewCell)?.item = item
        }
    }

    func loadInitialItems() {
        items = RetroRomFileManager.shared.folderItem(key: folderKey)?.subItems ?? []
        sort()
        rebuildItemsByKey()
        applySnapshot(animated: false)
    }
}

// MARK: - Data refresh

private extension RetroRomFolderUnifiedSubview {

    func fullReload(animated: Bool) {
        items = RetroRomFileManager.shared.folderItem(key: folderKey)?.subItems ?? []
        sort()
        rebuildItemsByKey()
        applySnapshot(animated: animated)
        delegate?.subviewDidChangeContent(self)
    }

    func rebuildItemsByKey() {
        itemsByKey.removeAll(keepingCapacity: true)
        for item in items {
            itemsByKey[item.key] = item
        }
    }

    func applySnapshot(animated: Bool) {
        var snap = Snapshot()
        snap.appendSections([.main])
        snap.appendItems(items.map { $0.key }, toSection: .main)
        dataSource.apply(snap, animatingDifferences: animated)
    }

    func appendImportedItems(_ newItems: [RetroRomBaseItem]) {
        let toAppend = newItems.filter { itemsByKey[$0.key] == nil }
        guard !toAppend.isEmpty else { return }

        items.append(contentsOf: toAppend)
        for item in toAppend {
            itemsByKey[item.key] = item
        }

        var snap = dataSource.snapshot()
        snap.appendItems(toAppend.map { $0.key }, toSection: .main)
        dataSource.apply(snap, animatingDifferences: true) { [weak self] in
            self?.scrollToLastItem(animated: true)
        }

        delegate?.subviewDidChangeContent(self)
    }

    func scrollToLastItem(animated: Bool) {
        guard !items.isEmpty else { return }
        let indexPath = IndexPath(item: items.count - 1, section: 0)
        collectionView.scrollToItem(at: indexPath, at: .bottom, animated: animated)
    }
}

// MARK: - RetroRomFolderSubview required hooks

extension RetroRomFolderUnifiedSubview {

    func reload() {
        fullReload(animated: false)
    }

    func languageChanged() {
        for cell in collectionView.visibleCells {
            switch style {
            case .icon:
                (cell as? RetroRomBaseIconViewCell)?.updateInfoLabel()
            case .list:
                (cell as? RetroRomBaseListViewCell)?.updateInfoLabel()
            }
        }
    }

    func sort() {
        switch RetroRomFolderPageState.shared.sortType {
        case .fileNameAsc:  items.sortByFileNameAscFolderFirst()
        case .fileNameDesc: items.sortByFileNameDescFolderFirst()
        case .lastPlay:     items.sortByLastPlayAtFolderFirst()
        case .addDateDesc:  items.sortByCreateDateDescFolderFirst()
        case .addDateAsc:   items.sortByCreateDateAscFolderFirst()
        case .playTime:     items.sortByPlayTimeFolderFirst()
        }
    }

    func applyData(animated: Bool) {
        applySnapshot(animated: animated)
    }
}

// MARK: - RetroRomFolderSubview optional hooks

extension RetroRomFolderUnifiedSubview {

    func fileItemImported(_ keys: [String]) {
        let newItems: [RetroRomBaseItem] = keys.compactMap { key in
            guard let file = RetroRomFileManager.shared.fileItem(key: key),
                  file.parent == folderKey else { return nil }
            return file
        }
        appendImportedItems(newItems)
    }

    func folderItemImported(folderKey importedFolderKey: String, itemKeys: [String]) {
        guard let folder = RetroRomFileManager.shared.folderItem(key: importedFolderKey),
              folder.parent == self.folderKey else { return }
        appendImportedItems([folder])
    }

    func itemDeleted(_ item: RetroRomBaseItem) {
        guard itemsByKey[item.key] != nil else { return }
        items.removeAll { $0.key == item.key }
        itemsByKey.removeValue(forKey: item.key)
        applySnapshot(animated: true)
        delegate?.subviewDidChangeContent(self)
    }

    func fileTagColorChanged(tagId: Int) {
        for cell in collectionView.visibleCells {
            let file: RetroRomFileItem?
            switch style {
            case .icon:
                file = (cell as? RetroRomBaseIconViewCell)?.item as? RetroRomFileItem
            case .list:
                file = (cell as? RetroRomBaseListViewCell)?.item as? RetroRomFileItem
            }
            guard let file = file,
                  file.tagIdArray.contains(tagId) else { continue }
            file.pulseText.toggle()
        }
    }

    func appendNewFolder(_ folder: RetroRomFolderItem) {
        appendImportedItems([folder])
    }

    func itemMovedIn(_ item: RetroRomBaseItem) {
        appendImportedItems([item])
    }
}

// MARK: - UICollectionViewDelegate

extension RetroRomFolderUnifiedSubview: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        guard indexPath.item < items.count else { return }
        let item = items[indexPath.item]

        Vibration.selection.vibrate()

        if let folder = item as? RetroRomFolderItem {
            delegate?.subview(self, didTapFolder: folder)
        } else if let file = item as? RetroRomFileItem {
            delegate?.subview(self, didTapFile: file)
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first,
              indexPath.item < items.count else { return nil }
        let item = items[indexPath.item]

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) {
            [weak self] _ in
            guard let self = self else { return nil }
            return self.delegate?.subview(self, contextMenuForItem: item)
        }
    }
}

// MARK: - Adaptive flow layout (icon mode)

private extension RetroRomFolderUnifiedSubview {

    func makeFlowLayout(forWidth width: CGFloat) -> UICollectionViewFlowLayout {
        let itemWidth: CGFloat
        if width > 500 {
            itemWidth = 150
        } else if width > 400 {
            itemWidth = (min(width, 430) - 30 - 30 * 3 - 30) / 4
        } else {
            itemWidth = (width - 30 - 30 * 2 - 30) / 3
        }
        let itemHeight = itemWidth / 256 * 240 + RetroRomBaseIconViewCell.titleHeight

        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing      = 30
        layout.minimumInteritemSpacing = 30
        layout.sectionInset            = UIEdgeInsets(top: 10, left: 30, bottom: 10, right: 30)
        layout.itemSize                = CGSize(width: max(itemWidth, 1), height: max(itemHeight, 1))
        layout.scrollDirection         = .vertical
        return layout
    }
}

// MARK: - IndexPath → item resolution

private extension RetroRomFolderUnifiedSubview {

    func resolveItem(at indexPath: IndexPath) -> RetroRomBaseItem? {
        guard let key = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return itemsByKey[key]
    }
}

// MARK: - UICollectionViewDragDelegate

extension RetroRomFolderUnifiedSubview: UICollectionViewDragDelegate {

    func collectionView(_ collectionView: UICollectionView,
                        itemsForBeginning session: UIDragSession,
                        at indexPath: IndexPath) -> [UIDragItem] {
        guard let item = resolveItem(at: indexPath) else { return [] }
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

extension RetroRomFolderUnifiedSubview: UICollectionViewDropDelegate {

    func collectionView(_ collectionView: UICollectionView,
                        dropSessionDidUpdate session: UIDropSession,
                        withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard session.localDragSession != nil,
              session.items.count == 1 else {
            return UICollectionViewDropProposal(operation: .cancel)
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
              let srcItem = resolveItem(at: srcIndexPath),
              let dstFolder = resolveItem(at: dstIndexPath) as? RetroRomFolderItem else {
            return
        }

        delegate?.subview(self, didDropItem: srcItem, intoFolder: dstFolder)
    }
}

// MARK: - UIContextMenuInteractionDelegate (blank area)

extension RetroRomFolderUnifiedSubview: UIContextMenuInteractionDelegate {

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
