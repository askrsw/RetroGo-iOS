//
//  RetroRomTableFolderFileBrowser.swift
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

final class RetroRomTableFolderFileBrowser: UIView, RetroRomFolderFileBrowser {
    private let tableView: UITableView

    let folderKey: String
    var items: [RetroRomBaseItem]

    private var dragingIndexPath: IndexPath?
    private var dragingOverIndexPath: IndexPath? {
        didSet {
            guard dragingOverIndexPath != oldValue else {
                return
            }

            if let oldIndexPath = oldValue, let cell = tableView.cellForRow(at: oldIndexPath), !(cell is RetroRomFileTableViewCell) {
                UIView.animate(withDuration: 0.1) {
                    cell.transform = .identity
                }
            }

            if let newIndexPath = dragingOverIndexPath, let cell = tableView.cellForRow(at: newIndexPath), !(cell is RetroRomFileTableViewCell) && dragingOverIndexPath != dragingIndexPath {
                UIView.animate(withDuration: 0.1) {
                    cell.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
                }
            }
        }
    }

    init(folderKey: String) {
        self.folderKey = folderKey
        self.items = RetroRomFileManager.shared.folderItem(key: folderKey)?.subItems ?? []
        self.tableView = UITableView(frame: .zero, style: .plain)
        super.init(frame: .zero)

        sort(type: RetroRomHomePageState.shared.homeFileSortType)

        tableView.dataSource   = self
        tableView.delegate     = self
        tableView.dragDelegate = self
        tableView.dropDelegate = self
        tableView.estimatedRowHeight = 60
        tableView.separatorInset = .init(top: 0, left: 20, bottom: 0, right: 20)
        tableView.register(RetroRomFolderTableViewCell.self, forCellReuseIdentifier: "RetroRomFolderTableViewCell")
        tableView.register(RetroRomFileTableViewCell.self, forCellReuseIdentifier: "RetroRomFileTableViewCell")
        tableView.register(RetroRomParentFolderTableViewCell.self, forCellReuseIdentifier: "RetroRomParentFolderTableViewCell")
        addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        let bgInteraction = UIContextMenuInteraction(delegate: self)
        let bgView = UIView()
        bgView.backgroundColor = .clear
        bgView.addInteraction(bgInteraction)
        bgView.isUserInteractionEnabled = true
        tableView.backgroundView = bgView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var meta: RetroRomFileBrowserMeta {
        .listView(organize: .byFolder, folderKey: folderKey)
    }

    func reloadData(reload: Bool, sortType: RetroRomFileSortType?) {
        if reload {
            items = RetroRomFileManager.shared.folderItem(key: folderKey)?.subItems ?? []
        }
        if let sortType = sortType {
            sort(type: sortType)
        }
        tableView.reloadData()
    }

    func refresh(sortType: RetroRomFileSortType) {
        sort(type: sortType)
        tableView.reloadData()

        if items.count > 0 {
            DispatchQueue.main.async { [unowned self] in
                tableView.scrollToRow(at: IndexPath(item: 0, section: 0), at: .top, animated: true)
            }
        }
    }

    func updateRomInfo() {
        for cell in tableView.visibleCells {
            if let cell = cell as? RetroRomBaseTableViewCell {
                cell.updateInfoLabel()
            }
        }
    }

    func getRomFileItem(location: CGPoint, interactionView: UIView?) -> (RetroRomBaseItem?, IndexPath?) {
        let touch = tableView.convert(location, from: interactionView)
        if let indexPath = tableView.indexPathForRow(at: touch) {
            if let cell = tableView.cellForRow(at: indexPath) as? RetroRomBaseTableViewCell {
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
        if let cell = tableView.cellForRow(at: indexPath) as? RetroRomBaseTableViewCell {
            cell.editFileName()
        }
    }

    func resignKeyboardFocus() {
        for cell in tableView.visibleCells {
            if let cell = cell as? RetroRomBaseTableViewCell {
                cell.titleEditor?.resignFirstResponder()
            }
        }
    }

    func languageChanged() {
        for cell in tableView.visibleCells {
            if let cell = cell as? RetroRomBaseTableViewCell {
                cell.updateInfoLabel()
            }
        }
    }

    func fileTagColorChanged(tagId: Int) {
        for cell in tableView.visibleCells {
            guard let cell = cell as? RetroRomBaseTableViewCell, let item = cell.item as? RetroRomFileItem else {
                continue
            }
            if item.tagIdArray.contains(tagId) {
                item.pulseText = !item.pulseText
            }
        }
    }

    func showNewFolderItem(_ key: String) {
        guard let item = RetroRomFileManager.shared.folderItem(key: key) else { return }

        let row = (folderKey != "root" ? 1 : 0) + items.count
        let indexPath = IndexPath(row: row, section: 0)

        items.append(item)

        tableView.performBatchUpdates {
            tableView.insertRows(at: [indexPath], with: .automatic)
        } completion: { [weak self] _ in
            guard let self = self else { return }
            tableView.scrollToRow(at: indexPath, at: .none, animated: true)
            if let cell = self.tableView.cellForRow(at: indexPath) as? RetroRomFolderTableViewCell {
                cell.editFileName()
            }
        }
    }
}

extension RetroRomTableFolderFileBrowser: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        (folderKey != "root" ? 1 : 0) + items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let interaction = UIContextMenuInteraction(delegate: self)

        let row: Int
        if folderKey != "root" {
            if indexPath.row == 0 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "RetroRomParentFolderTableViewCell", for: indexPath) as! RetroRomParentFolderTableViewCell
                cell.addInteraction(interaction)
                return cell
            }
            row = indexPath.row - 1
        } else {
            row = indexPath.row
        }

        let item = items[row]
        let cell: RetroRomBaseTableViewCell
        switch item.retroRomType {
            case .file:
                cell = tableView.dequeueReusableCell(withIdentifier: "RetroRomFileTableViewCell") as! RetroRomFileTableViewCell
            case .folder:
                cell = tableView.dequeueReusableCell(withIdentifier: "RetroRomFolderTableViewCell") as! RetroRomFolderTableViewCell
            default:
                fatalError()
        }
        cell.item = item
        cell.addInteraction(interaction)
        return cell
    }
}

extension RetroRomTableFolderFileBrowser: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if folderKey != "root" && indexPath.row == 0 {
            return RetroRomParentFolderTableViewCell.rowHeight
        } else {
            return RetroRomBaseTableViewCell.rowHeight
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        Vibration.selection.vibrate()

        let row: Int
        if folderKey != "root" {
            if indexPath.row == 0 {
                let item = RetroRomFileManager.shared.folderItem(key: folderKey)
                if let parent = item?.parentFolderItem {
                    HomePageViewController.instance?.enterFolder(parent, forward: false)
                }
                return
            }
            row = indexPath.row - 1
        } else {
            row = indexPath.row
        }

        let item = items[row]
        if let item = item as? RetroRomFileItem {
            startGame(item)
        } else if let item = item as? RetroRomFolderItem {
            HomePageViewController.instance?.enterFolder(item, forward: true)
        }
    }
}

extension RetroRomTableFolderFileBrowser: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        if interaction.view == tableView.backgroundView {
            return getBlankMenuConfiguration()
        } else {
            return getFolderFileItemMenuConfiguration(interaction: interaction, at: location)
        }
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {

        guard let bgView = interaction.view, bgView == tableView.backgroundView else { return nil }
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

extension RetroRomTableFolderFileBrowser: UITableViewDragDelegate {
    func tableView(_ tableView: UITableView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
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

    func tableView(_ tableView: UITableView, dragSessionDidEnd session: any UIDragSession) {
        dragingOverIndexPath = nil
        dragingIndexPath = nil
    }
}

extension RetroRomTableFolderFileBrowser: UITableViewDropDelegate {
    func tableView(_ tableView: UITableView, performDropWith coordinator: any UITableViewDropCoordinator) {
        guard let indexPath = coordinator.destinationIndexPath, let dragingIndexPath = dragingIndexPath else {
            return
        }
        moveItem(srcIndexPath: dragingIndexPath, dstIndexPath: indexPath)
    }

    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        guard session.localDragSession != nil, session.items.count == 1 else {
            return .init(operation: .cancel)
        }

        if let indexPath = destinationIndexPath {
            dragingOverIndexPath = indexPath
        }

        return .init(operation: .move, intent: .insertIntoDestinationIndexPath)
    }
}
