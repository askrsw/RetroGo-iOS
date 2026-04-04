//
//  RetroRomSectionFileBrowser.swift
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
import ObjcHelper
import RACoordinator

protocol RetroRomSectionFileBrowser: RetroRomFileBrowser {
    var organizeType: RetroRomFileOrganizeType { get }
    var collectionView: UICollectionView { get }
    var items: [String: [RetroRomFileItemWrapper]] { get set }
    var keys: [String] { get set }
    var dataSource: DataSource { get }
    var observers: [NSObjectProtocol] { get set }
}

// MARK: - RetroRomFileBrowser Method

extension RetroRomSectionFileBrowser {
    var couldShowEmptyTip: Bool {
        let romCount = Retro​Rom​Persistence.shared.getRomFileCount() ?? 0
        return romCount == 0 && dataSource.snapshot().numberOfSections == 0
    }

    func reloadData(reload: Bool, sortType: RetroRomFileSortType?) {
        if reload {
            loadData()
        }
        if let sortType = sortType {
            sort(type: sortType)
        }
        applyData(animating: true) { [weak self] in
            self?.updateRomInfo()
        }
    }

    func refresh(sortType: RetroRomFileSortType) {
        sort(type: sortType)
        applyData(animating: true) { [weak self] in
            self?.updateRomInfo()
        }

        NotificationCenter.default.post(name: .romCountChanged, object: nil)
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
        if organizeType == .byTag {
            fileItemImportedByTag(keys)
        } else if organizeType == .byCore {
            fileItemImportedByCore(keys)
        }
    }

    func folderItemImported(folderKey: String, itemKeys: [String]) {
        if organizeType == .byTag {
            fileItemImportedByTag(itemKeys)
        } else if organizeType == .byCore {
            fileItemImportedByCore(itemKeys)
        }
    }

    func itemDeleted(_ item: RetroRomBaseItem, success: Bool) {
        guard success, let item = item as? RetroRomFileItem else {
            return
        }

        if organizeType == .byTag {
            fileItemDeletedByTag(item)
        } else if organizeType == .byCore {
            fileItemDeletedByCore(item)
        }
    }

    func languageChanged() {
        updateRomInfo()

        collectionView.visibleSupplementaryViews(ofKind: RetroRomSectionHeaderView.sectionHeaderElementKind).forEach { view in
            if let header = view as? RetroRomSectionHeaderView {
                let savedType = header.type
                header.type = savedType
            }
        }
    }

    func fileTagColorChanged(tagId: Int) {
        updateRomInfo()

        if let index = keys.firstIndex(of: String(tagId)) {
            let headerView = collectionView.supplementaryView(forElementKind: RetroRomSectionHeaderView.sectionHeaderElementKind, at: IndexPath(item: 0, section: index)) as? RetroRomSectionHeaderView
            headerView?.updateTagColor()
        }
    }
}

extension RetroRomSectionFileBrowser {
    typealias DataSource = UICollectionViewDiffableDataSource<String, RetroRomFileItemWrapper>
    typealias SectionSnapshot = NSDiffableDataSourceSectionSnapshot<RetroRomFileItemWrapper>
    typealias Snapshot = NSDiffableDataSourceSnapshot<String, RetroRomFileItemWrapper>
    typealias IconCellRegistration = UICollectionView.CellRegistration<RetroRomFileIconViewCell, RetroRomFileItemWrapper>
    typealias ListCellRegistration = UICollectionView.CellRegistration<RetroRomFileListViewCell, RetroRomFileItemWrapper>
    typealias HeaderRegistration = UICollectionView.SupplementaryRegistration<RetroRomSectionHeaderView>

    func initialize() {
        loadData()
        sort(type: RetroRomHomePageState.shared.homeFileSortType)
        applyData()

        if self.organizeType == .byTag {
            let fileTagChangedObserver = NotificationCenter.default.addObserver(forName: .fileTagFileChanged, object: nil, queue: .main) { [weak self] notif in
                let item = notif.object as? RetroRomFileItem
                let added = notif.userInfo?["added"] as? Set<Int>
                let removed = notif.userInfo?["removed"] as? Set<Int>
                if let item = item, let added = added, let removed = removed {
                    self?.fileTagFileChanged(item, added: added, removed: removed)
                }
            }
            observers.append(fileTagChangedObserver)
            let fileTagDeletedObserver = NotificationCenter.default.addObserver(forName: .fileTagDeleted, object: nil, queue: .main, using: { [weak self] notif in
                if let tag = notif.object as? RetroRomFileTag {
                    self?.fileTagDeleted(tag)
                }
            })
            observers.append(fileTagDeletedObserver)
            let fileTagAddedObserver = NotificationCenter.default.addObserver(forName: .fileTagAdded, object: nil, queue: .main, using: { [weak self] notif in
                if let tag = notif.object as? RetroRomFileTag {
                    self?.fileTagAdded(tag)
                }
            })
            observers.append(fileTagAddedObserver)

            let fileTagTitleChangedObserver = NotificationCenter.default.addObserver(forName: .fileTagTitleChanged, object: nil, queue: .main) { [weak self] notif in
                if let tag = notif.object as? RetroRomFileTag {
                    self?.fileTagTitleChanged(tag)
                }
            }
            observers.append(fileTagTitleChangedObserver)
        } else if self.organizeType == .byCore {
            let coreAssignedObserver = NotificationCenter.default.addObserver(forName: .fileCoreAssigned, object: nil, queue: .main) { [weak self] notif in
                if let item = notif.object as? RetroRomFileItem, let info = notif.userInfo as? [String: String] {
                    self?.fileCoreAssigned(item, new: info["new"], old: info["old"])
                }
            }
            observers.append(coreAssignedObserver)
        }
    }

    func deinitialize() {
        for o in observers {
            NotificationCenter.default.removeObserver(o)
        }
    }

    func getSectionFileItemMenuConfiguration(interaction: UIContextMenuInteraction, at location: CGPoint) -> UIContextMenuConfiguration? {
        guard RetroRomHomePageState.shared.couldShowItemMenu else { return nil }
        guard let indexPath = getIndexPath(location: location, interactionView: interaction.view), let item = dataSource.itemIdentifier(for: indexPath)?.item else {
            return nil
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return nil }
            let actPlay = UIAction(title: Bundle.localizedString(forKey: "homepage_play"), image: UIImage(systemName: "play")) { [weak self] _ in
                Vibration.medium.vibrate()
                self?.startGame(item)
            }
            let actAssignCore = getAssignCoreAction(item: item)
            let actRename = getRenameAction(indexPath: indexPath)
            let actTag = UIAction(title: Bundle.localizedString(forKey: "tags"), image: UIImage(systemName: "tag")) { [weak self] _ in
                Vibration.medium.vibrate()
                self?.configFileItemTag(item)
            }
            let actDelete = getDeleteAction(item: item)
            let actInfo = getInfoAction(item: item)
            let actions = [actPlay, actAssignCore, actRename, actTag, actInfo, actDelete].compactMap({ $0 })
            return UIMenu(title: "", children: actions)
        }
    }

    func toggleSection(key: String, show: Bool) {
        var sectionSnapshot = SectionSnapshot()
        if show {
            sectionSnapshot.append(items[key] ?? [])
        } else {
            sectionSnapshot.append([])
        }
        dataSource.apply(sectionSnapshot, to: key, animatingDifferences: true)
    }
}

extension RetroRomSectionFileBrowser {
    private func loadData() {
        keys   = []
        items  = [:]

        if organizeType == .byTag {
            loadDataByTag()
        } else if organizeType == .byCore {
            loadDataByCore()
        }
    }

    private func sort(type: RetroRomFileSortType) {
        switch type {
            case .fileNameAsc:
                items.forEach({ items[$0.0]?.sortByFileNameAsc() })
            case .fileNameDesc:
                items.forEach({ items[$0.0]?.sortByFileNameDesc() })
            case .lastPlay:
                items.forEach({ items[$0.0]?.sortByLastPlayAt() })
            case .addDateDesc:
                items.forEach({ items[$0.0]?.sortByCreateDateDesc() })
            case .addDateAsc:
                items.forEach({ items[$0.0]?.sortByCreateDateAsc() })
            case .playTime:
                items.forEach({ items[$0.0]?.sortByPlayTime() })
        }
    }

    private func applyData(animating: Bool = false, completion: (() -> Void)? = nil) {
        if organizeType == .byTag {
            applyDataByTag(animating: animating, completion: completion)
        } else if organizeType == .byCore {
            applyDataByCore(animating: animating, completion: completion)
        }
    }

    private func getIndexPath(location: CGPoint, interactionView: UIView?) -> IndexPath? {
        let touch = collectionView.convert(location, from: interactionView)
        return collectionView.indexPathForItem(at: touch)
    }
}

extension RetroRomSectionFileBrowser {
    private func loadDataByTag() {
        let untagKey = RetroRomFileItemWrapper.uncategorizedKey
        let tags = RetroRomFileManager.shared.getAllFileTags()
        let rawDict = RetroRomFileManager.shared.getRomFileArrayByTag()
        for tag in tags {
            let key = String(tag.id)
            keys.append(key)

            let array = rawDict[tag.id] ?? []
            items[key] = array.map({ RetroRomFileItemWrapper(item: $0, tag: tag) })
            tag.itemCount = array.count
        }
        let untagItems = RetroRomFileManager.shared.getUntagFileItems()
        items[untagKey] = untagItems.map({ RetroRomFileItemWrapper(item: $0, tag: .untaged) })
        keys.append(untagKey)
        RetroRomFileTag.untaged.itemCount = untagItems.count
    }

    private func applyDataByTag(animating: Bool = false, completion: (() -> Void)? = nil) {
        var snapshot = Snapshot()
        for key in keys {
            let array = items[key] ?? []
            guard !array.isEmpty, let id = Int(key), let tag = RetroRomFileManager.shared.fileTag(id: id), tag.isHidden == false else {
                continue
            }
            snapshot.appendSections([key])
            if tag.expanded {
                snapshot.appendItems(array, toSection: key)
            }
        }
        dataSource.apply(snapshot, animatingDifferences: animating, completion: completion)
    }

    private func fileItemImportedByTag(_ keys: [String]) {
        let untagKey = RetroRomFileItemWrapper.uncategorizedKey
        let files = RetroRomFileManager.shared.retroRomFileItems(in: Set(keys))
        let first = items[untagKey]?.first
        var untagArray = items[untagKey] ?? []
        let wrappedFiles = files
            .filter({ item1 in
                !untagArray.contains(where: { item2 in
                    item2.item.key == item1.key
                })
            })
            .map({ RetroRomFileItemWrapper(item: $0, tag: .untaged) })
        if wrappedFiles.isEmpty {
            return
        }
        if !untagArray.isEmpty {
            untagArray.insert(contentsOf: wrappedFiles, at: 0)
        } else {
            untagArray.append(contentsOf: wrappedFiles)
        }
        items[untagKey] = untagArray
        RetroRomFileTag.untaged.itemCount = items[untagKey]?.count ?? 0
        if RetroRomFileTag.untaged.isHidden == false {
            addSection(untagKey)
            if RetroRomFileTag.untaged.expanded {
                var snapshot = dataSource.snapshot(for: untagKey)
                if let first = first {
                    snapshot.insert(wrappedFiles, before: first)
                } else {
                    snapshot.append(wrappedFiles)
                }
                dataSource.apply(snapshot, to: untagKey, animatingDifferences: true)
            }
        }
    }

    private func fileItemDeletedByTag(_ item: RetroRomFileItem) {
        if item.tagIdArray.count > 0 {
            for id in item.tagIdArray {
                let key = String(id)
                if let tag = RetroRomFileManager.shared.fileTag(id: id), let wrappedItem = items[key]?.first(where: { $0.item == item }) {
                    items[key]?.removeAll(where: { $0.item == item })
                    if tag.expanded && isSectionAdded(key) {
                        var snapshot = dataSource.snapshot(for: key)
                        snapshot.delete([wrappedItem])
                        dataSource.apply(snapshot, to: key, animatingDifferences: true)
                    }
                    tag.itemCount = items[key]?.count ?? 0
                }
            }
        } else {
            let untagKey = RetroRomFileItemWrapper.uncategorizedKey
            if let wrappedItem = items[untagKey]?.first(where: { $0.item == item }) {
                items[untagKey]?.removeAll(where: { $0.item.key == item.key })
                if RetroRomFileTag.untaged.expanded && isSectionAdded(untagKey) {
                    var snapshot = dataSource.snapshot(for: untagKey)
                    snapshot.delete([wrappedItem])
                    dataSource.apply(snapshot, to: untagKey, animatingDifferences: true)
                }
                RetroRomFileTag.untaged.itemCount = items[untagKey]?.count ?? 0
            }
        }
    }

    private func fileTagFileChanged(_ item: RetroRomFileItem, added: Set<Int>, removed: Set<Int>) {
        // 1. 处理移除标签逻辑
        for id in removed {
            let key = String(id)
            // 同步内存数据
            items[key]?.removeAll(where: { $0.item == item })

            if isSectionAdded(key) {
                // 增量更新 UI
                var sectionSnapshot = dataSource.snapshot(for: key)
                // 找到该 Section 下对应的那个 Wrapper (基于 Hashable 匹配)
                if let wrapperToDelete = sectionSnapshot.items.first(where: { $0.item == item }) {
                    sectionSnapshot.delete([wrapperToDelete])
                    dataSource.apply(sectionSnapshot, to: key, animatingDifferences: true)
                }
            }
            let tag = RetroRomFileManager.shared.fileTag(id: id)
            tag?.itemCount = items[key]?.count ?? 0
        }

        // 2. 处理新增标签逻辑
        for id in added {
            let key = String(id)
            guard let tag = RetroRomFileManager.shared.fileTag(id: id) else { continue }
            let wrapped = RetroRomFileItemWrapper(item: item, tag: tag)
            items[key]?.insert(wrapped, at: 0)
            tag.itemCount = items[key]?.count ?? 0
            if !tag.isHidden {
                addSection(key)
                if tag.expanded {
                    var sectionSnapshot = dataSource.snapshot(for: key)
                    if !sectionSnapshot.contains(wrapped) {
                        if let firstItem = sectionSnapshot.items.first {
                            sectionSnapshot.insert([wrapped], before: firstItem)
                        } else {
                            sectionSnapshot.append([wrapped])
                        }
                        dataSource.apply(sectionSnapshot, to: key, animatingDifferences: true)
                    }
                }
            }
        }

        // 3. 处理 "未分类" (Untagged) 的增量迁移
        let untagKey = RetroRomFileItemWrapper.uncategorizedKey
        let isCurrentlyInUntagged = (items[untagKey] ?? []).contains(where: { $0.item.key == item.key })

        // 情况 A: 变成了无标签状态 -> 移入 "未分类"
        if item.tagIdArray.isEmpty && !isCurrentlyInUntagged {
            let wrapped = RetroRomFileItemWrapper(item: item, tag: .untaged)
            items[untagKey]?.insert(wrapped, at: 0)
            RetroRomFileTag.untaged.itemCount =  items[untagKey]?.count ?? 0
            if !RetroRomFileTag.untaged.isHidden {
                addSection(untagKey)
                if RetroRomFileTag.untaged.expanded {
                    var sectionSnapshot = dataSource.snapshot(for: untagKey)
                    if let first = sectionSnapshot.items.first {
                        sectionSnapshot.insert([wrapped], before: first)
                    } else {
                        sectionSnapshot.append([wrapped])
                    }
                    dataSource.apply(sectionSnapshot, to: untagKey, animatingDifferences: true)
                }
            }
        }
        // 情况 B: 从无标签变成了有标签 -> 从 "未分类" 移出
        else if !item.tagIdArray.isEmpty && isCurrentlyInUntagged {
            items[untagKey]?.removeAll(where: { $0.item.key == item.key })
            RetroRomFileTag.untaged.itemCount =  items[untagKey]?.count ?? 0
            if isSectionAdded(untagKey) {
                if RetroRomFileTag.untaged.expanded {
                    var sectionSnapshot = dataSource.snapshot(for: untagKey)
                    if let wrapperToRemove = sectionSnapshot.items.first(where: { $0.item.key == item.key }) {
                        sectionSnapshot.delete([wrapperToRemove])
                        dataSource.apply(sectionSnapshot, to: untagKey, animatingDifferences: true)
                    }
                }
            }
        }
    }

    private func fileTagDeleted(_ tag: RetroRomFileTag) {
        let key = String(tag.id)
        let untagKey = RetroRomFileItemWrapper.uncategorizedKey

        // 1. 获取当前全局快照 (假设你使用的是全量 Snapshot 管理多个 Section)
        var snapshot = dataSource.snapshot()

        // 2. 找到该 Tag 下的所有 Item
        // 注意：直接从 snapshot 中获取 itemIdentifiers，比从内存 items 字典找更安全
        let itemsInDeletedSection = snapshot.itemIdentifiers(inSection: key)

        // 3. 处理“变为无标签”的 Item 迁移逻辑
        var itemsToMoveToUntagged: [RetroRomFileItemWrapper] = []

        for item in itemsInDeletedSection {
            // 更新业务模型：假设这里的 item 已经是你更新过 tagIdArray 后的对象
            // 或者你需要在这里手动处理模型逻辑
            if item.item.tagIdArray.isEmpty {
                itemsToMoveToUntagged.append(RetroRomFileItemWrapper(item: item.item, tag: .untaged))
            }
        }

        // 4. 执行增量操作
        // a. 删除整个旧 Section（这会自动删除里面所有的 Item）
        if isSectionAdded(key) {
            snapshot.deleteSections([key])
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        // b. 将符合条件的项移动/插入到 "0" Section
        if !itemsToMoveToUntagged.isEmpty && !RetroRomFileTag.untaged.isHidden {
            addSection(untagKey)

            snapshot = dataSource.snapshot()

            // 增量插入到 "0" Section 的最前面
            if let firstItemInUntagged = snapshot.itemIdentifiers(inSection: untagKey).first {
                snapshot.insertItems(itemsToMoveToUntagged, beforeItem: firstItemInUntagged)
            } else {
                snapshot.appendItems(itemsToMoveToUntagged, toSection: untagKey)
            }
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        // 5. 应用更新
        // 同步内存数据结构（保持你原有的 items 字典同步）
        self.items.removeValue(forKey: key)
        self.keys.removeAll(where: { $0 == key })
        if !itemsToMoveToUntagged.isEmpty {
            var untagArray = self.items[untagKey] ?? []
            if untagArray.isEmpty {
                untagArray.append(contentsOf: itemsToMoveToUntagged)
            } else {
                untagArray.insert(contentsOf: itemsToMoveToUntagged, at: 0)
            }
            self.items[untagKey] = untagArray
            RetroRomFileTag.untaged.itemCount = self.items[untagKey]?.count ?? 0
        }
    }

    private func fileTagAdded(_ tag: RetroRomFileTag) {
        let key = String(tag.id)

        // 1. 更新底层数据模型
        // 逻辑：插入到倒数第二个位置
        if keys.count > 0 {
            keys.insert(key, at: keys.count - 1)
        } else {
            keys.append(key)
        }
        items[key] = []
    }

    private func fileTagTitleChanged(_ tag: RetroRomFileTag) {
        let key = String(tag.id)
        if let index = dataSource.snapshot().sectionIdentifiers.firstIndex(of: key) {
            let headerView = collectionView.supplementaryView(forElementKind: RetroRomSectionHeaderView.sectionHeaderElementKind, at: IndexPath(item: 0, section: index)) as? RetroRomSectionHeaderView
            headerView?.updateTitle(tag.showTitle)
        }
    }
}

extension RetroRomSectionFileBrowser {
    private func loadDataByCore() {
        let noneKey = RetroRomFileItemWrapper.uncategorizedKey
        let cores = RetroRomCoreManager.shared.allCores
        let rawDict = RetroRomFileManager.shared.getRomFileArrayByCore()
        for core in cores {
            let key = core.coreId
            keys.append(key)
            let array = rawDict[key] ?? []
            items[key] = array.map({ RetroRomFileItemWrapper(item: $0, core: core) })
            core.itemCount = array.count
        }
        let noneItems = rawDict[noneKey] ?? []
        items[noneKey] = noneItems.map({ RetroRomFileItemWrapper(item: $0, core: EmuCoreInfoItem.noneCore()) })
        keys.append(noneKey)
        EmuCoreInfoItem.noneCore().itemCount = noneItems.count
    }

    private func applyDataByCore(animating: Bool = false, completion: (() -> Void)? = nil) {
        var snapshot = Snapshot()
        for key in keys {
            let array = items[key] ?? []
            guard !array.isEmpty, let core = RetroRomCoreManager.shared.core(key), core.isHidden == false else {
                continue
            }
            snapshot.appendSections([key])
            if core.expanded {
                snapshot.appendItems(array, toSection: key)
            }
        }
        dataSource.apply(snapshot, animatingDifferences: animating, completion: completion)
    }

    private func fileItemImportedByCore(_ itemKeys: [String]) {
        let noneKey = RetroRomFileItemWrapper.uncategorizedKey
        let files = RetroRomFileManager.shared.retroRomFileItems(in: Set(itemKeys))
        var rawDict: [String: [RetroRomFileItem]] = [:]
        for file in files {
            let cores = file.getSupportedCores()
            if cores.count > 0 {
                for core in cores {
                    let key = core.coreId
                    if rawDict[key] == nil {
                        rawDict[key] = []
                    }
                    rawDict[key]?.append(file)
                }
            } else {
                if rawDict[noneKey] == nil {
                    rawDict[noneKey] = []
                }
                rawDict[noneKey]?.append(file)
            }
        }

        for (k, v) in rawDict {
            guard let core = RetroRomCoreManager.shared.core(k), core.isHidden == false else {
                continue
            }
            let wrapped = v.map({ RetroRomFileItemWrapper(item: $0, core: core) })
            addSection(k)
            if core.expanded {
                var section = dataSource.snapshot(for: k)
                if let first = items[k]?.first {
                    section.insert(wrapped, before: first)
                } else {
                    section.append(wrapped)
                }
                dataSource.apply(section, to: k, animatingDifferences: true)
            }

            if items[k] != nil {
                items[k]?.insert(contentsOf: wrapped, at: 0)
            } else {
                items[k] = wrapped
            }
            core.itemCount = items[k]?.count ?? 0
        }
    }

    private func fileItemDeletedByCore(_ item: RetroRomFileItem) {
        let cores = item.getSupportedCores()
        if cores.count > 0 {
            for core in cores {
                let key = core.coreId
                if let wrappedItem = items[key]?.first(where: { $0.item == item }) {
                    items[key]?.removeAll(where: { $0.item == item })
                    if core.expanded && isSectionAdded(key) {
                        var snapshot = dataSource.snapshot(for: key)
                        snapshot.delete([wrappedItem])
                        dataSource.apply(snapshot, to: key, animatingDifferences: true)
                    }
                    core.itemCount = items[key]?.count ?? 0
                }
            }
        } else {
            let noneKey = RetroRomFileItemWrapper.uncategorizedKey
            if let wrappedItem = items[noneKey]?.first(where: { $0.item == item }) {
                items[noneKey]?.removeAll(where: { $0.item.key == item.key })
                let core = EmuCoreInfoItem.noneCore()
                if core.expanded && isSectionAdded(noneKey) {
                    var snapshot = dataSource.snapshot(for: noneKey)
                    snapshot.delete([wrappedItem])
                    dataSource.apply(snapshot, to: noneKey, animatingDifferences: true)
                }
                core.itemCount = items[noneKey]?.count ?? 0
            }
        }
    }

    private func fileCoreAssigned(_ item: RetroRomFileItem, new: String?, old: String?) {
        if let old = old {
            items[old]?.removeAll(where: { $0.item == item })
            if isSectionAdded(old) {
                var sectionSnapshot = dataSource.snapshot(for: old)
                if let wrapperToDelete = sectionSnapshot.items.first(where: { $0.item == item }) {
                    sectionSnapshot.delete([wrapperToDelete])
                    dataSource.apply(sectionSnapshot, to: old, animatingDifferences: true)
                }
            }
            let core = RetroRomCoreManager.shared.core(old)
            core?.itemCount = items[old]?.count ?? 0
        }

        if let new = new, let core = RetroRomCoreManager.shared.core(new) {
            let wrapped = RetroRomFileItemWrapper(item: item, core: core)
            items[new]?.insert(wrapped, at: 0)
            core.itemCount = items[new]?.count ?? 0
            if !core.isHidden {
                addSection(core.coreId)
                if core.expanded {
                    var sectionSnapshot = dataSource.snapshot(for: new)
                    if !sectionSnapshot.contains(wrapped) {
                        if let firstItem = sectionSnapshot.items.first {
                            sectionSnapshot.insert([wrapped], before: firstItem)
                        } else {
                            sectionSnapshot.append([wrapped])
                        }
                        dataSource.apply(sectionSnapshot, to: new, animatingDifferences: true)
                    }
                }
            }
        }

        let noneCore = EmuCoreInfoItem.noneCore()
        let isCurrentlyInNoneCore = (items[noneCore.coreId] ?? []).contains(where: { $0.item.key == item.key })

        let runningCore = RetroRomCoreManager.shared.getRunningCore(item)
        if runningCore != nil && isCurrentlyInNoneCore {
            items[noneCore.coreId]?.removeAll(where: { $0.item == item })
            noneCore.itemCount = items[noneCore.coreId]?.count ?? 0
            if isSectionAdded(noneCore.coreId) {
                if noneCore.expanded {
                    var sectionSnapshot = dataSource.snapshot(for: noneCore.coreId)
                    if let wrapperToRemove = sectionSnapshot.items.first(where: { $0.item.key == item.key }) {
                        sectionSnapshot.delete([wrapperToRemove])
                        dataSource.apply(sectionSnapshot, to: noneCore.coreId, animatingDifferences: true)
                    }
                }
            }
        } else if runningCore == nil && !isCurrentlyInNoneCore {
            let wrapped = RetroRomFileItemWrapper(item: item, core: noneCore)
            items[noneCore.coreId]?.insert(wrapped, at: 0)
            noneCore.itemCount = items[noneCore.coreId]?.count ?? 0
            if !noneCore.isHidden {
                addSection(noneCore.coreId)
                if noneCore.expanded {
                    var sectionSnapshot = dataSource.snapshot(for: noneCore.coreId)
                    if let first = sectionSnapshot.items.first {
                        sectionSnapshot.insert([wrapped], before: first)
                    } else {
                        sectionSnapshot.append([wrapped])
                    }
                    dataSource.apply(sectionSnapshot, to: noneCore.coreId, animatingDifferences: true)
                }
            }
        }
    }
}

// MARK: - Utils

extension RetroRomSectionFileBrowser {
    private func addSection(_ k: String) {
        var snapshot = dataSource.snapshot()
        if !snapshot.sectionIdentifiers.contains(k) {
            let zeroKey = RetroRomFileItemWrapper.uncategorizedKey
            if snapshot.sectionIdentifiers.contains(zeroKey) {
                snapshot.insertSections([k], beforeSection: zeroKey)
            } else {
                snapshot.appendSections([k])
            }
            dataSource.apply(snapshot, animatingDifferences: false)
        }
    }

    private func isSectionAdded(_ k: String) -> Bool {
        let snapshot = dataSource.snapshot()
        return snapshot.sectionIdentifiers.contains(k)
    }
}
