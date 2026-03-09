//
//  RetroRomTreeFileBrowser.swift
//  RetroGo
//
//  Created by haharsw on 2026/2/11.
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

final class RetroRomTreeFileBrowser: UIView, RetroRomFileBrowser {
    private var dragingIndexPath: IndexPath?
    private var dragingOverIndexPath: IndexPath? {
        didSet {
            guard dragingOverIndexPath != oldValue else { return }

            if let oldIndexPath = oldValue, let cell = collectionView.cellForItem(at: oldIndexPath) {
                UIView.animate(withDuration: 0.1) {
                    cell.transform = .identity
                }
            }

            if let newIndexPath = dragingOverIndexPath, let cell = collectionView.cellForItem(at: newIndexPath), dragingOverIndexPath != dragingIndexPath {
                UIView.animate(withDuration: 0.1) {
                    cell.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
                }
            }
        }
    }

    private lazy var collectionView = self.configUI()
    private lazy var dataSource     = self.configDS()

    init() {
        super.init(frame: .zero)

        _ = collectionView
        _ = dataSource

        let snapshot = loadData(sortType: RetroRomHomePageState.shared.homeFileSortType)
        dataSource.apply(snapshot, to: .main, animatingDifferences: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var meta: RetroRomFileBrowserMeta {
        .treeView
    }

    var couldShowEmptyTip: Bool {
        let folderCount = RetroRomFileManager.shared.getFolderCount() ?? 0
        let romCount = RetroRomFileManager.shared.getRomFileCount() ?? 0
        return folderCount + romCount == 0
    }

    func reloadData(reload: Bool, sortType: RetroRomFileSortType?) {
        let snapshot = loadData(sortType: sortType)
        dataSource.apply(snapshot, to: .main, animatingDifferences: true) { [weak self] in
            self?.updateRomInfo()
        }
    }

    func refresh(sortType: RetroRomFileSortType) {
        let snapshot = loadData(sortType: sortType)
        dataSource.apply(snapshot, to: .main, animatingDifferences: true) { [weak self] in
            self?.updateRomInfo()
        }
    }

    func updateRomInfo() {
        // 1. 获取当前快照
        var snapshot = dataSource.snapshot()

        // 2. 获取所有需要更新的 Item 标识符
        // 如果你想更新全部，就直接传 snapshot.itemIdentifiers
        let allItems = snapshot.itemIdentifiers

        // 3. 告知数据源这些 Item 的内容已变更
        snapshot.reconfigureItems(allItems)

        // 4. 应用快照。注意：这里不需要 animatingDifferences，
        // 因为 reconfigure 是原地刷新，系统会自动处理可见 Cell 的更新。
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func fileItemImported(_ keys: [String]) {
        // 业务前提：keys 不能为空
        guard !keys.isEmpty else { return }

        // 业务前提：这些文件在导入前绝对不存在于当前 UI，且所属 Folder 必须已在 UI 中
        var snapshot = dataSource.snapshot(for: .main)
        let subItems = keys.compactMap { RetroRomFileManager.shared.fileItem(key: $0) }

        // 取第一个文件的父文件夹作为容器
        // 假设业务逻辑保证了这批文件属于同一个 Folder
        guard let folderItem = subItems.first?.parentFolderItem else { return }

        if !folderItem.isRoot {
            // 如果这里 folderItem 不在 snapshot 中，或者 subItems 已存在，
            // apply 时底层会直接抛出异常，这符合你的预期（报错即 Bug）
            snapshot.append(subItems, to: folderItem)
            folderItem.expand = true
            snapshot.expand([folderItem])
        } else {
            snapshot.append(subItems, to: nil)
        }

        self.dataSource.apply(snapshot, to: .main, animatingDifferences: true)
    }

    func folderItemImported(folderKey: String, itemKeys: [String]) {
        guard let rootItem = RetroRomFileManager.shared.folderItem(key: folderKey) else { return }

        var snapshot = dataSource.snapshot(for: .main)
        if !snapshot.contains(rootItem) {
            if let parent = rootItem.parentFolderItem, !parent.isRoot, snapshot.contains(parent) {
                snapshot.append([rootItem], to: parent)
            } else {
                snapshot.append([rootItem], to: nil)
            }
        }

        rootItem.expand = true
        snapshot.expand([rootItem])

        func addSubItems(_ parentItem: RetroRomFolderItem) {
            for key in parentItem.subFolderKeys {
                guard let item = RetroRomFileManager.shared.folderItem(key: key) else {
                    continue
                }
                if !snapshot.contains(item) {
                    snapshot.append([item], to: parentItem)
                }
                item.expand = true
                snapshot.expand([item])
                addSubItems(item)
            }

            let fileItems = parentItem.subFileKeys.compactMap { RetroRomFileManager.shared.fileItem(key: $0) }
            let newFiles = fileItems.filter { !snapshot.contains($0) }
            if !newFiles.isEmpty {
                snapshot.append(newFiles, to: parentItem)
            }
        }

        addSubItems(rootItem)
        self.dataSource.apply(snapshot, to: .main, animatingDifferences: true)
    }

    func itemDeleted(_ item: RetroRomBaseItem, success: Bool) {
        guard success else { return }

        // 1. 获取当前 Section 的快照（注意：是 SectionSnapshot）
        var sectionSnapshot = dataSource.snapshot(for: .main)

        // 2. 检查 item 是否还在快照中（防御性编程）
        if sectionSnapshot.contains(item) {
            // 直接删除父项。如果 item 是 Folder，它的子项会一起被干掉
            sectionSnapshot.delete([item])

            // 3. 应用变更，这比全量 loadData 效率高得多
            dataSource.apply(sectionSnapshot, to: .main, animatingDifferences: true)
        }
    }

    func editRomFileName(indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? RetroRomBaseListViewCell {
            cell.editFileName()
        }
    }

    func resignKeyboardFocus() {
        for cell in collectionView.visibleCells {
            if let cell = cell as? RetroRomBaseListViewCell {
                cell.titleEditor?.resignFirstResponder()
            }
        }
    }

    func languageChanged() {
        updateRomInfo()
    }

    func fileTagColorChanged(tagId: Int) {
       updateRomInfo()
    }
}

extension RetroRomTreeFileBrowser {
    enum Section { case main }

    typealias DataSource = UICollectionViewDiffableDataSource<Section, RetroRomBaseItem>
    typealias Snapshot = NSDiffableDataSourceSectionSnapshot<RetroRomBaseItem>
    typealias FileCellRegistration = UICollectionView.CellRegistration<RetroRomFileListViewCell, RetroRomFileItem>
    typealias FolderCellRegistration = UICollectionView.CellRegistration<RetroRomFolderListViewCell, RetroRomFolderItem>

    private func configUI() -> UICollectionView {
        let itemHeight = RetroRomBaseListViewCell.rowHeight
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(itemHeight))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(itemHeight))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 0, leading: 20, bottom: 0, trailing: 20)
        let layout = UICollectionViewCompositionalLayout(section: section)
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.delegate     = self
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        let bgInteraction = UIContextMenuInteraction(delegate: self)
        let bgView = UIView()
        bgView.backgroundColor = .clear
        bgView.addInteraction(bgInteraction)
        bgView.isUserInteractionEnabled = true
        collectionView.backgroundView = bgView

        return collectionView
    }

    private func configDS() -> DataSource {
        let fileCellReg = FileCellRegistration { [weak self] (cell, indexPath, item) in
            guard let self = self else { return }
            let interaction = UIContextMenuInteraction(delegate: self)
            cell.item = item
            cell.addInteraction(interaction)
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
        }
        let folderCellReg = FolderCellRegistration { [weak self] (cell, indexPath, item) in
            guard let self = self else { return }
            let interaction = UIContextMenuInteraction(delegate: self)
            cell.item = item
            cell.addInteraction(interaction)

            let disclosureOptions = UICellAccessory.OutlineDisclosureOptions(style: .automatic)
            cell.accessories = [.outlineDisclosure(options: disclosureOptions)]
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
        }

        let ds = DataSource(collectionView: self.collectionView) { collectionView, indexPath, item in
            if let item = item as? RetroRomFileItem {
                return collectionView.dequeueConfiguredReusableCell(using: fileCellReg, for: indexPath, item: item)
            } else if let item = item as? RetroRomFolderItem {
                return collectionView.dequeueConfiguredReusableCell(using: folderCellReg, for: indexPath, item: item)
            } else {
                return nil
            }
        }
        var handler = DataSource.SectionSnapshotHandlers<RetroRomBaseItem>()
        handler.willCollapseItem = { item in
            (item as? RetroRomFolderItem)?.expand = false
        }
        handler.willExpandItem = { item in
            (item as? RetroRomFolderItem)?.expand = true
        }
        ds.sectionSnapshotHandlers = handler
        return ds
    }

    private func loadData(sortType: RetroRomFileSortType?) -> Snapshot {
        var snapshot = Snapshot()

        func addItems(folderKey: String, to parentItem: RetroRomFolderItem?) {
            guard let item = RetroRomFileManager.shared.folderItem(key: folderKey) else { return }
            var subItems = item.subItems
            if let sortType = sortType {
                switch sortType {
                    case .fileNameAsc:
                        subItems.sortByFileNameAscFolderFirst()
                    case .fileNameDesc:
                        subItems.sortByFileNameDescFolderFirst()
                    case .lastPlay:
                        subItems.sortByLastPlayAtFolderFirst()
                    case .addDateDesc:
                        subItems.sortByCreateDateDescFolderFirst()
                    case .addDateAsc:
                        subItems.sortByCreateDateAscFolderFirst()
                    case .playTime:
                        subItems.sortByPlayTimeFolderFirst()
                }
            }
            snapshot.append(subItems, to: parentItem)
            for item in subItems {
                if let item = item as? RetroRomFolderItem {
                    addItems(folderKey: item.key, to: item)
                }
            }

            if item.expand {
                snapshot.expand([item])
            }
        }

        addItems(folderKey: "root", to: nil)
        return snapshot
    }
}

extension RetroRomTreeFileBrowser: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        Vibration.selection.vibrate()

        let item = dataSource.itemIdentifier(for: indexPath)
        if let item = item as? RetroRomFolderItem {
            item.expand.toggle()
            var snapshot = dataSource.snapshot(for: .main)
            if item.expand {
                snapshot.expand([item])
            } else {
                snapshot.collapse([item])
            }
            dataSource.apply(snapshot, to: .main, animatingDifferences: true)
        } else if let item = item as? RetroRomFileItem {
            startGame(item)
        }
    }
}

extension RetroRomTreeFileBrowser: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard RetroRomHomePageState.shared.couldShowItemMenu else { return nil }

        if interaction.view == collectionView.backgroundView {
            return getBlankMenuConfiguration()
        } else {
            return getItemMenuConfiguration(interaction: interaction, at: location)
        }
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {

        guard let bgView = interaction.view, bgView == collectionView.backgroundView else { return nil }
        let location = interaction.location(in: bgView)

        // 1. 创建一个临时的、不 addSubview 的视图
        let tempView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        tempView.backgroundColor = .clear // 设为透明

        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear

        // 2. 指定 target，将这个视图“定位”到手指点击的位置
        // 系统会处理这个 tempView 的显示，而不需要你手动管理它的生命周期
        let target = UIPreviewTarget(container: bgView, center: location)

        return UITargetedPreview(view: tempView, parameters: parameters, target: target)
    }

    func getBlankMenuConfiguration() -> UIContextMenuConfiguration? {
        let importAction = UIAction(title: Bundle.localizedString(forKey: "homepage_import_for_folder"), image: UIImage(systemName: "plus")) { _ in
            Vibration.selection.vibrate()
            let folderKey = "root"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                HomePageViewController.instance?.importForFolder(folderKey)
            })
        }

        let newFolderAction = UIAction(title: Bundle.localizedString(forKey: "homepage_new_folder"), image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
            guard let self = self else { return }
            Vibration.selection.vibrate()
            if let root = RetroRomFileManager.shared.folderItem(key: "root") {
                performCreateNewFolder(under: root)
            }
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) {  _ in
            let actions = [importAction, newFolderAction]
            return UIMenu(title: "", children: actions)
        }
    }

    private func getItemMenuConfiguration(interaction: UIContextMenuInteraction, at location: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = getIndexPath(location: location, interactionView: interaction.view), let item = dataSource.itemIdentifier(for: indexPath) else {
            return nil
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return nil }
            let actPlay: UIAction?
            let actTag: UIAction?
            if let item = item as? RetroRomFileItem {
                actPlay = UIAction(title: Bundle.localizedString(forKey: "homepage_play"), image: UIImage(systemName: "play")) { [weak self] _ in
                    Vibration.medium.vibrate()
                    self?.startGame(item)
                }
                actTag = UIAction(title: Bundle.localizedString(forKey: "tags"), image: UIImage(systemName: "tag")) { [weak self] _ in
                    Vibration.medium.vibrate()
                    self?.configFileItemTag(item)
                }
            } else {
                actPlay = nil
                actTag = nil
            }
            let actAssignCore = getAssignCoreAction(item: item)
            let actImport = getImportAction(item: item)
            let actNewFolder = getNewFolderAction(item: item)
            let actRename = getRenameAction(indexPath: indexPath)
            let actDelete = getDeleteAction(item: item)
            let actInfo = getInfoAction(item: item)
            let actions = [actPlay, actAssignCore, actImport, actNewFolder, actRename, actTag, actInfo, actDelete].compactMap({ $0 })
            return UIMenu(title: "", children: actions)
        }
    }

    private func getNewFolderAction(item: RetroRomBaseItem) -> UIAction? {
        guard let folder = item as? RetroRomFolderItem else {
            return nil
        }

        let title = Bundle.localizedString(forKey: "homepage_new_folder")
        let image = UIImage(systemName: "folder.badge.plus")
        return UIAction(title: title, image: image) { [weak self] _ in
            guard let self = self else { return }
            Vibration.selection.vibrate()
            if !folder.expand {
                folder.expand = true
                var snapshot = dataSource.snapshot(for: .main)
                snapshot.expand([folder])
                dataSource.apply(snapshot, to: .main, animatingDifferences: true)
            }
            performCreateNewFolder(under: folder)
        }
    }

    func performCreateNewFolder(under folder: RetroRomFolderItem) {
        guard let uniqueKey = RetroRomFileManager.shared.getUniqueKey(folder) else {
            return AppToastManager.shared.toast(Bundle.localizedString(forKey: "homepage_new_folder_failed"), context: .ui, level: .error, shouldVibrate: false)
        }

        let showName = Bundle.localizedString(forKey: "homepage_new_folder")
        let newFolder = RetroRomFolderItem(key: uniqueKey, rawName: uniqueKey, showName: showName, parent: folder.key, createAt: Date(), updateAt: Date())
        if let fullPath = newFolder.fullPath {
            do {
                try FileManager.default.createDirectory(atPath: fullPath, withIntermediateDirectories: false)
            } catch {
                return AppToastManager.shared.toast(Bundle.localizedString(forKey: "homepage_new_folder_failed"), context: .ui, level: .error, shouldVibrate: false)
            }

            if !RetroRomFileManager.shared.storeRomFiles([], folders: [newFolder]) {
                try? FileManager.default.removeItem(atPath: fullPath)
                return AppToastManager.shared.toast(Bundle.localizedString(forKey: "homepage_new_folder_failed"), context: .ui, level: .error, shouldVibrate: false)
            } else {
                folder.addSubItemKeys(newFolderKeys: [newFolder.key], newFileKeys: [])

                AppToastManager.shared.toast(Bundle.localizedString(forKey: "homepage_new_folder_success"), context: .ui, level: .success)

                animateAndEditNewFolder(newFolder.key, under: folder)
            }
        }
    }

    func animateAndEditNewFolder(_ key: String, under folder: RetroRomFolderItem) {
        guard let item = RetroRomFileManager.shared.folderItem(key: key) else {
            return
        }

        var snapshot = dataSource.snapshot(for: .main)
        snapshot.append([item], to: folder.isRoot ? nil : folder)

        // 关键点：在 apply 的 completion 闭包中处理 UI
        dataSource.apply(snapshot, to: .main, animatingDifferences: true) { [weak self] in
            guard let self = self else { return }
            
            // 1. 获取对应的 IndexPath
            guard let indexPath = self.dataSource.indexPath(for: item) else { return }
            
            // 2. 确保 Cell 可见（滚动到该位置）
            self.collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
            
            // 3. 获取 Cell。注意：如果滚动跨度大，Cell 可能需要微小的延迟才能 get 到
            // 或者直接调用 layoutIfNeeded 强制同步布局
            self.collectionView.layoutIfNeeded()
            
            if let cell = self.collectionView.cellForItem(at: indexPath) as? RetroRomFolderListViewCell {
                cell.editFileName()
            } else {
                // 这是一个保底逻辑：即便同步拿不到，下一帧渲染一定会出现
                DispatchQueue.main.async {
                    if let cell = self.collectionView.cellForItem(at: indexPath) as? RetroRomFolderListViewCell {
                        cell.editFileName()
                    }
                }
            }
        }
    }

    private func getImportAction(item: RetroRomBaseItem) -> UIAction? {
        guard let folder = item as? RetroRomFolderItem else {
            return nil
        }
        return  UIAction(title: Bundle.localizedString(forKey: "homepage_import_for_folder"), image: UIImage(systemName: "plus")) { [weak self] _ in
            Vibration.selection.vibrate()
            guard let self = self else { return }
            if !folder.expand {
                folder.expand = true
                var snapshot = dataSource.snapshot(for: .main)
                snapshot.expand([folder])
                dataSource.apply(snapshot, to: .main, animatingDifferences: true)
            }

            let folderKey = folder.key
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                HomePageViewController.instance?.importForFolder(folderKey)
            })
        }
    }

    private func getIndexPath(location: CGPoint, interactionView: UIView?) -> IndexPath? {
        let touch = collectionView.convert(location, from: interactionView)
        return collectionView.indexPathForItem(at: touch)
    }
}

extension RetroRomTreeFileBrowser: UICollectionViewDragDelegate {
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        dragingIndexPath = indexPath

        guard let item = dataSource.itemIdentifier(for: indexPath) else { return [] }

        let itemProvider = NSItemProvider(object: item.key as NSString)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = item
        return [dragItem]
    }

    func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: any UIDragSession) {
        dragingOverIndexPath = nil
        dragingIndexPath = nil
    }
}

extension RetroRomTreeFileBrowser: UICollectionViewDropDelegate {
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: any UICollectionViewDropCoordinator) {
        guard let dstIndexPath = coordinator.destinationIndexPath,
              let dstItem = dataSource.itemIdentifier(for: dstIndexPath),
              let srcItem = coordinator.session.localDragSession?.items.first?.localObject as? RetroRomBaseItem
        else { return }

        let dstFolderItem: RetroRomFolderItem
        if let item = dstItem as? RetroRomFolderItem {
            dstFolderItem = item
        } else if let item = dstItem.parentFolderItem {
            dstFolderItem = item
        } else {
            return
        }

        if srcItem.parentFolderItem == dstFolderItem {
            return
        }

        dstFolderItem.expand = true

        moveItem(srcItem: srcItem, dstFolderItem: dstFolderItem) { [weak self] in
            guard let self = self else { return }

            // 1. 获取当前该 Section 的 SectionSnapshot
            var sectionSnapshot = self.dataSource.snapshot(for: .main)

            // 2. 从当前快照中移除被拖拽的项目
            // 注意：即使在不同的层级，deleteItems 也会找到并移除它
            sectionSnapshot.delete([srcItem])

            // 3. 将它插入到新的目标文件夹下
            // 如果 dstFolderItem 是父节点，使用 append 将 srcItem 变成它的子项
            if dstFolderItem.isRoot {
                sectionSnapshot.append([srcItem], to: nil)
            } else {
                sectionSnapshot.append([srcItem], to: dstFolderItem)
            }

            // 4. 确保目标文件夹是展开状态（如果你需要的话）
            if !dstFolderItem.isRoot {
                sectionSnapshot.expand([dstFolderItem])
            }

            // 5. 应用增量更新
            self.dataSource.apply(sectionSnapshot, to: .main, animatingDifferences: true) {
                // 滚动到新位置
                if let indexPath = self.dataSource.indexPath(for: srcItem) {
                    self.collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
                }
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard session.localDragSession != nil, session.items.count == 1 else {
            return .init(operation: .cancel)
        }

        if let indexPath = dragingIndexPath, let item = dataSource.itemIdentifier(for: indexPath) as? RetroRomFolderItem, item.expand {
            var snapshot = dataSource.snapshot(for: .main)
            item.expand = false
            snapshot.collapse([item])
            dataSource.apply(snapshot, to: .main, animatingDifferences: true)
        }

        if let indexPath = destinationIndexPath {
            dragingOverIndexPath = indexPath
        }

        return .init(operation: .move, intent: .insertIntoDestinationIndexPath)
    }
}
