//
//  RetroRomFolderFileBrowser.swift
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

protocol RetroRomFolderFileBrowser: RetroRomFileBrowser {
    var folderKey: String { get }
    var items: [RetroRomBaseItem] { get set }
    func getRomFileItem(location: CGPoint, interactionView: UIView?) -> (RetroRomBaseItem?, IndexPath?)
    func showNewFolderItem(_ key: String)
}

extension RetroRomFolderFileBrowser {
    var couldShowEmptyTip: Bool {
        let folderCount = Retro​Rom​Persistence.shared.getFolderCount() ?? 0
        let romCount = Retro​Rom​Persistence.shared.getRomFileCount() ?? 0
        return folderCount + romCount == 0
    }
    
    func sort(type: RetroRomFileSortType) {
        switch type {
            case .fileNameAsc:
                items.sortByFileNameAscFolderFirst()
            case .fileNameDesc:
                items.sortByFileNameDescFolderFirst()
            case .lastPlay:
                items.sortByLastPlayAt()
            case .addDateDesc:
                items.sortByCreateDateDesc()
            case .addDateAsc:
                items.sortByCreateDateAsc()
            case .playTime:
                items.sortByPlayTime()
        }
    }

    func moveItem(srcIndexPath: IndexPath, dstIndexPath: IndexPath) {
        let forward: Bool
        let dstItem = getItem(dstIndexPath)
        let srcItem = getItem(srcIndexPath)
        if srcItem.parentFolderItem == dstItem {
            forward = false
        } else {
            forward = true
        }

        guard let dstFolderItem = dstItem as? RetroRomFolderItem else {
            return
        }

        moveItem(srcItem: srcItem, dstFolderItem: dstFolderItem) {
            HomePageViewController.instance?.enterFolder(dstFolderItem, forward: forward)
        }
    }

    func getFolderFileItemMenuConfiguration(interaction: UIContextMenuInteraction, at location: CGPoint) -> UIContextMenuConfiguration? {
        guard RetroRomHomePageState.shared.couldShowItemMenu else { return nil }

        let (item, indexPath) = getRomFileItem(location: location, interactionView: interaction.view)
        guard let indexPath = indexPath else { return nil }

        if let configuration = getJumpToSuperFolderItemMenuConfiguration(item: item, indexPath: indexPath) {
            return configuration
        }

        guard let item = item else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return nil }
            let actPlayOrEnter = getPlayOrEnterAction(item: item)
            let actAssignCore  = getAssignCoreAction(item: item)
            let actImport      = getImportAction(item: item)
            let actMoveTo      = getMoveToAction(item: item)
            let actRename      = getRenameAction(indexPath: indexPath)
            let actTag         = getTagAction(item: item)
            let actDelete      = getDeleteAction(item: item)
            let actInfo        = getInfoAction(item: item)
            let actions = [actPlayOrEnter, actAssignCore, actImport, actMoveTo, actRename, actTag, actInfo, actDelete].compactMap({ $0 })
            return UIMenu(title: "", children: actions)
        }
    }

    func getBlankMenuConfiguration() -> UIContextMenuConfiguration? {
        let importAction = UIAction(title: Bundle.localizedString(forKey: "homepage_import_for_folder"), image: UIImage(systemName: "plus")) { [weak self] _ in
            guard let self = self else { return }

            Vibration.selection.vibrate()

            let folderKey = folderKey
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                HomePageViewController.instance?.importForFolder(folderKey)
            })
        }

        let newFolderAction = UIAction(title: Bundle.localizedString(forKey: "homepage_new_folder"), image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
            guard let self = self else { return }
            Vibration.selection.vibrate()
            createNewFolder()
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) {  _ in
            let actions = [importAction, newFolderAction]
            return UIMenu(title: "", children: actions)
        }
    }
}

extension RetroRomFolderFileBrowser {
    private func createNewFolder() {
        guard let folder = RetroRomFileManager.shared.folderItem(key: folderKey), let uniqueKey = Retro​Rom​Persistence.shared.getUniqueKey(folder) else {
            return AppToastManager.shared.toast(Bundle.localizedString(forKey: "homepage_new_folder_failed"), context: .ui, level: .error, shouldVibrate: false)
        }

        let showName = Bundle.localizedString(forKey: "homepage_new_folder")
        let newFolder = RetroRomFolderItem(key: uniqueKey, rawName: uniqueKey, showName: showName, parent: folderKey, createAt: Date(), updateAt: Date())
        if let fullPath = newFolder.fullPath {
            do {
                try FileManager.default.createDirectory(atPath: fullPath, withIntermediateDirectories: false)
            } catch {
                return AppToastManager.shared.toast(Bundle.localizedString(forKey: "homepage_new_folder_failed"), context: .ui, level: .error, shouldVibrate: false)
            }

            if !Retro​Rom​Persistence.shared.storeRomFiles([], folders: [newFolder]) {
                try? FileManager.default.removeItem(atPath: fullPath)
                return AppToastManager.shared.toast(Bundle.localizedString(forKey: "homepage_new_folder_failed"), context: .ui, level: .error, shouldVibrate: false)
            } else {
                folder.addSubItemKeys(newFolderKeys: [newFolder.key], newFileKeys: [])
                AppToastManager.shared.toast(Bundle.localizedString(forKey: "homepage_new_folder_success"), context: .ui, level: .success)
                showNewFolderItem(newFolder.key)
            }
        }
    }

    private func getImportAction(item: RetroRomBaseItem) -> UIAction? {
        guard let folder = item as? RetroRomFolderItem else {
             return nil
        }
        return UIAction(title: Bundle.localizedString(forKey: "homepage_import_for_folder"), image: UIImage(systemName: "plus")) { _ in
            Vibration.selection.vibrate()

            HomePageViewController.instance?.enterFolder(folder, forward: true) {
                HomePageViewController.instance?.importForFolder(folder.key)
            }
        }
    }

    private func getItem(_ indexPath: IndexPath) -> RetroRomBaseItem {
        if folderKey != "root" {
            if indexPath.item != 0 {
                return items[indexPath.item - 1]
            } else {
                return RetroRomFileManager.shared.folderItem(key: folderKey)!.parentFolderItem!
            }
        } else {
            return items[indexPath.item]
        }
    }


    private func getTagAction(item: RetroRomBaseItem) -> UIAction? {
        if let item = item as? RetroRomFileItem {
            return UIAction(title: Bundle.localizedString(forKey: "tags"), image: UIImage(systemName: "tag")) { [weak self] _ in
                Vibration.medium.vibrate()
                self?.configFileItemTag(item)
            }
        } else {
            return nil
        }
    }

    private func getPlayOrEnterAction(item: RetroRomBaseItem) -> UIAction? {
        if let item = item as? RetroRomFileItem {
            return UIAction(title: Bundle.localizedString(forKey: "homepage_play"), image: UIImage(systemName: "play")) { [weak self] _ in
               Vibration.medium.vibrate()
               self?.startGame(item)
            }
        } else if let item = item as? RetroRomFolderItem {
            return UIAction(title: Bundle.localizedString(forKey: "homepage_enter"), image: UIImage(systemName: "arrow.right")) { _ in
                Vibration.medium.vibrate()
                HomePageViewController.instance?.enterFolder(item, forward: true)
            }
        } else {
            return nil
        }
    }

    private func getJumpToSuperFolderItemMenuConfiguration(item: RetroRomBaseItem?, indexPath: IndexPath) -> UIContextMenuConfiguration? {
        if item == nil && indexPath.section == 0 && indexPath.item == 0 {
            if case .iconView(let orgnaize, let folderKey) = meta {
                if orgnaize == .byFolder, let key = folderKey {
                    return jumpToSuperFolder(folderKey: key)
                }
            } else if case .listView(let orgnaize, let folderKey)  = meta {
                if orgnaize == .byFolder, let key = folderKey {
                    return jumpToSuperFolder(folderKey: key)
                }
            }
        }
        return nil
    }

    private func jumpToSuperFolder(folderKey: String) -> UIContextMenuConfiguration? {
        var supers: [(key: String, title: String)] = []
        var folderItem = RetroRomFileManager.shared.folderItem(key: folderKey)
        while true {
            folderItem = folderItem?.parentFolderItem
            if let item = folderItem {
                if item.isRoot {
                    supers.append((key: item.key, title: Bundle.localizedString(forKey: "homepage_root_folder")))
                    break
                } else {
                    supers.append((key: item.key, title: item.itemName))
                }
            } else {
                return nil
            }
        }
        if supers.count > 1 {
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                let actions = supers.map { (key, title) in
                    let iconName = key == "root" ? "house.fill" : "folder.fill"
                    let icon = UIImage(systemName: iconName)
                    let action = UIAction(title: title, image: icon) { _ in
                        Vibration.medium.vibrate()
                        if let item = RetroRomFileManager.shared.folderItem(key: key) {
                            HomePageViewController.instance?.enterFolder(item, forward: false)
                        }
                    }
                    return action
                }
                return UIMenu(title: Bundle.localizedString(forKey: "homepage_jump"), children: actions)
            }
        } else {
            return nil
        }
    }
}
