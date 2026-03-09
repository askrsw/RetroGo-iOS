//
//  RetroRomIconFolderFileBrowser.swift
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

final class RetroRomIconFolderFileBrowser: UIView, RetroRomFolderFileBrowser {
    private let collectionView: UICollectionView

    let folderKey: String
    var items: [RetroRomBaseItem]

    private var dragingIndexPath: IndexPath?
    private var dragingOverIndexPath: IndexPath? {
        didSet {
            guard dragingOverIndexPath != oldValue else { return }

            if let oldIndexPath = oldValue, let cell = collectionView.cellForItem(at: oldIndexPath), !(cell is RetroRomFileIconViewCell) {
                UIView.animate(withDuration: 0.1) {
                    cell.transform = .identity
                }
            }

            if let newIndexPath = dragingOverIndexPath, let cell = collectionView.cellForItem(at: newIndexPath), !(cell is RetroRomFileIconViewCell) && dragingOverIndexPath != dragingIndexPath {
                UIView.animate(withDuration: 0.1) {
                    cell.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
                }
            }
        }
    }

    init(folderKey: String) {
        self.folderKey = folderKey
        self.items = RetroRomFileManager.shared.folderItem(key: folderKey)?.subItems ?? []
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        super.init(frame: .zero)

        sort(type: RetroRomHomePageState.shared.homeFileSortType)

        collectionView.dataSource   = self
        collectionView.delegate     = self
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.register(RetroRomFileIconViewCell.self, forCellWithReuseIdentifier: "RetroRomFileIconViewCell")
        collectionView.register(RetroRomFolderIconViewCell.self, forCellWithReuseIdentifier: "RetroRomFolderIconViewCell")
        collectionView.register(RetroRomParentFolderIconViewCell.self, forCellWithReuseIdentifier: "RetroRomParentFolderIconViewCell")
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let layout = rekonCollectionViewLayout(width)
        collectionView.collectionViewLayout = layout
    }

    var meta: RetroRomFileBrowserMeta {
        .iconView(organize: .byFolder, folderKey: folderKey)
    }

    func reloadData(reload: Bool, sortType: RetroRomFileSortType?) {
        if reload {
            items = RetroRomFileManager.shared.folderItem(key: folderKey)?.subItems ?? []
        }
        if let sortType = sortType {
            sort(type: sortType)
        }
        collectionView.reloadData()
    }

    func refresh(sortType: RetroRomFileSortType) {
        sort(type: sortType)
        collectionView.reloadData()

        if items.count > 0 {
            DispatchQueue.main.async { [unowned self] in
                collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: true)
            }
        }
    }

    func updateRomInfo() {
        for cell in collectionView.visibleCells {
            if let cell = cell as? RetroRomBaseIconViewCell {
                cell.updateInfoLabel()
            }
        }
    }

    func getRomFileItem(location: CGPoint, interactionView: UIView?) -> (RetroRomBaseItem?, IndexPath?) {
        let touch = collectionView.convert(location, from: interactionView)
        if let indexPath = collectionView.indexPathForItem(at: touch) {
            if let cell = collectionView.cellForItem(at: indexPath) as? RetroRomBaseIconViewCell {
                return (cell.item, indexPath)
            } else {
                return (nil, indexPath)
            }
        }
        return (nil, nil)
    }

    func fileItemImported(_ keys: [String]) {
        reloadData(reload: true, sortType: RetroRomHomePageState.shared.homeFileSortType)
    }

    func folderItemImported(folderKey: String, itemKeys: [String]) {
        reloadData(reload: true, sortType: RetroRomHomePageState.shared.homeFileSortType)
    }

    func itemDeleted(_ item: RetroRomBaseItem, success: Bool) {
        if success {
            items.removeAll(where: { $0.key == item.key })
            reloadData(reload: false, sortType: nil)
        }
    }

    func editRomFileName(indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? RetroRomBaseIconViewCell {
            cell.editFileName()
        }
    }

    func resignKeyboardFocus() {
        for cell in collectionView.visibleCells {
            if let cell = cell as? RetroRomBaseIconViewCell {
                cell.titleEditor?.resignFirstResponder()
            }
        }
    }

    func languageChanged() {
        for cell in collectionView.visibleCells {
            if let cell = cell as? RetroRomBaseIconViewCell {
                cell.updateInfoLabel()
            }
        }
    }

    func fileTagColorChanged(tagId: Int) {
        for cell in collectionView.visibleCells {
            guard let cell = cell as? RetroRomBaseIconViewCell, let item = cell.item as? RetroRomFileItem else {
                continue
            }

            if item.tagIdArray.contains(tagId) {
                item.pulseText = !item.pulseText
            }
        }
    }

    func showNewFolderItem(_ key: String) {
        guard let item = RetroRomFileManager.shared.folderItem(key: key) else { return }

        let index = (folderKey != "root" ? 1 : 0) + items.count
        let indexPath = IndexPath(item: index, section: 0)

        items.append(item)

        collectionView.performBatchUpdates {
            collectionView.insertItems(at: [indexPath])
        } completion: { [weak self] _ in
            guard let self = self else { return }
            collectionView.scrollToItem(at: indexPath, at: .top, animated: true)
            if let cell = self.collectionView.cellForItem(at: indexPath) as? RetroRomFolderIconViewCell {
                cell.editFileName()
            }
        }
    }
}

extension RetroRomIconFolderFileBrowser {
    private func rekonCollectionViewLayout(_ width: CGFloat) -> UICollectionViewFlowLayout {
        let w: CGFloat
        if width > 500 {
            w = 150
        } else if width > 400 {
            w = (min(width, 430) - 30 - 30.0 * 3 - 30) / 4.0
        } else {
            w = (width - 30.0 - 30.0 * 2 - 30) / 3.0
        }
        let h = w / 256 * 240 + RetroRomBaseIconViewCell.titleHeight
        let size = CGSize(width: w, height: h)
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 30
        layout.minimumInteritemSpacing = 30
        layout.sectionInset = UIEdgeInsets(top: 10, left: 30, bottom: 10, right: 30)
        layout.itemSize = size
        layout.scrollDirection = .vertical
        return layout
    }
}

extension RetroRomIconFolderFileBrowser: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        (folderKey != "root" ? 1 : 0) + items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let interaction = UIContextMenuInteraction(delegate: self)

        let item: RetroRomBaseItem
        if folderKey != "root" {
            if indexPath.item == 0 {
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "RetroRomParentFolderIconViewCell", for: indexPath)
                cell.addInteraction(interaction)
                return cell
            }
            item = items[indexPath.item - 1]
        } else {
            item = items[indexPath.item]
        }

        let cell: RetroRomBaseIconViewCell
        switch item.retroRomType {
            case .file:
                cell = collectionView.dequeueReusableCell(withReuseIdentifier: "RetroRomFileIconViewCell", for: indexPath) as! RetroRomFileIconViewCell
            case .folder:
                cell = collectionView.dequeueReusableCell(withReuseIdentifier: "RetroRomFolderIconViewCell", for: indexPath) as! RetroRomFolderIconViewCell
            default:
                fatalError()
        }
        cell.item = item
        cell.addInteraction(interaction)
        return cell
    }
}

extension RetroRomIconFolderFileBrowser: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        Vibration.selection.vibrate()

        let row: Int
        if folderKey != "root" {
            if indexPath.item == 0 {
                if let item = RetroRomFileManager.shared.folderItem(key: folderKey)?.parentFolderItem {
                    HomePageViewController.instance?.enterFolder(item, forward: false)
                }
                return
            }
            row = indexPath.item - 1
        } else {
            row = indexPath.item
        }

        let item = items[row]
        if let item = item as? RetroRomFileItem {
            startGame(item)
        } else if let item = item as? RetroRomFolderItem {
            HomePageViewController.instance?.enterFolder(item, forward: true)
        }
    }
}

extension RetroRomIconFolderFileBrowser: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        if interaction.view == collectionView.backgroundView {
            return getBlankMenuConfiguration()
        } else {
            return getFolderFileItemMenuConfiguration(interaction: interaction, at: location)
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
}

extension RetroRomIconFolderFileBrowser: UICollectionViewDragDelegate {
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        if folderKey != "root" && indexPath.item == 0 {
            return []
        }

        dragingIndexPath = indexPath

        let item: RetroRomBaseItem
        if folderKey != "root" {
            item = items[indexPath.item - 1]
        } else {
            item = items[indexPath.item]
        }

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

extension RetroRomIconFolderFileBrowser: UICollectionViewDropDelegate {
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: any UICollectionViewDropCoordinator) {
        guard let dstIndexPath = coordinator.destinationIndexPath, let srcIndexPath = dragingIndexPath else { return }
        moveItem(srcIndexPath: srcIndexPath, dstIndexPath: dstIndexPath)
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard session.localDragSession != nil, session.items.count == 1 else {
            return .init(operation: .cancel)
        }

        if let indexPath = destinationIndexPath {
            dragingOverIndexPath = indexPath
        }

        return .init(operation: .move, intent: .insertIntoDestinationIndexPath)
    }
}
