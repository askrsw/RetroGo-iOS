//
//  RetroRomFileBrowser.swift
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

enum RetroRomFileBrowserType: Int {
    case icon, list, tree
}

enum RetroRomFileOrganizeType: Int {
    case byFolder, byTag, byCore
}

enum RetroRomFileBrowserMeta: Equatable {
    case iconView(organize: RetroRomFileOrganizeType, folderKey: String?)
    case listView(organize: RetroRomFileOrganizeType, folderKey: String?)
    case treeView

    static func == (lhs: RetroRomFileBrowserMeta, rhs: RetroRomFileBrowserMeta) -> Bool {
        switch (lhs, rhs) {
            case let (.iconView(lOrganize, lFolderKey), .iconView(rOrganize, rFolderKey)):
                return lOrganize == rOrganize && lFolderKey == rFolderKey
            case let (.listView(lOrganize, lFolderKey), .listView(rOrganize, rFolderKey)):
                return lOrganize == rOrganize && lFolderKey == rFolderKey
            case (.treeView, .treeView):
                return true
            default:
                return false
        }
    }
}

enum RetroRomFileSortType: Int {
    case fileNameAsc, fileNameDesc
    case lastPlay
    case addDateDesc, addDateAsc
    case playTime
}

protocol RetroRomFileBrowser: UIView {
    var meta: RetroRomFileBrowserMeta { get }
    var couldShowEmptyTip: Bool { get }

    func reloadData(reload: Bool, sortType: RetroRomFileSortType?)
    func refresh(sortType: RetroRomFileSortType)

    func updateRomInfo()

    func fileItemImported(_ keys: [String])
    func folderItemImported(folderKey: String, itemKeys: [String])
    func itemDeleted(_ item: RetroRomBaseItem, success: Bool)
    func editRomFileName(indexPath: IndexPath)
    func resignKeyboardFocus()
    func languageChanged()
    func fileTagColorChanged(tagId: Int)
}

extension RetroRomFileBrowser {
    func deleteItem(_ item: RetroRomBaseItem) {
        let title = item.itemName
        let message = item.isFile ? Bundle.localizedString(forKey: "homepage_delete_confirm_file") : Bundle.localizedString(forKey: "homepage_delete_confirm_folder")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: Bundle.localizedString(forKey: "delete"), style: .destructive) { [weak self] _ in
            Vibration.medium.vibrate()
            guard let self = self else {
                return
            }

            RetroRomFileManager.shared.deleteItem(item, browser: self)
        }

        let cancelAction = UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel) { _ in
            Vibration.light.vibrate()
        }

        alert.addAction(okAction)
        alert.addAction(cancelAction)
        alert.view.tintColor = .label

        HomePageViewController.instance?.present(alert, animated: true)
    }

    func startGame(_ item: RetroRomFileItem, core: EmuCoreInfoItem? = nil) {
        guard RetroArchX.shared().canRunOnThisDevice(), RetroRomHomePageState.shared.couldShowItemMenu else { return }
        if let core = core, core != .noneCore() {
            RetroArchX.playGame(romItem: item, core: core)
        } else if let core = RetroRomCoreManager.shared.getRunningCore(item) {
            RetroArchX.playGame(romItem: item, core: core)
        } else {
            let holder = HomePageViewController.instance
            let controller = RetroRomCoreSelectViewController(action: .runRomWithItem(item: item))
            let navController = UINavigationController(rootViewController: controller)
            holder?.present(navController, animated: true)
        }
    }

    func configFileItemTag(_ item: RetroRomFileItem) {
        guard let controller = HomePageViewController.instance else {
            return
        }

        let selector = RetroRomTagSelector(fileItem: item)
        let navController = UINavigationController(rootViewController: selector)
        controller.present(navController, animated: true)
    }

    func moveItem(srcItem: RetroRomBaseItem, dstFolderItem: RetroRomFolderItem, completionHandler: @escaping () -> Void) {
        if dstFolderItem.canAddItem(srcItem) {
            if dstFolderItem.addNewItem(srcItem) {
                completionHandler()

                let formatter: String
                if srcItem.isFile {
                    formatter = Bundle.localizedString(forKey: "homepage_move_file_success")
                } else {
                    formatter = Bundle.localizedString(forKey: "homepage_move_folder_success")
                }
                let message = String(format: formatter, srcItem.itemName)
                AppToastManager.shared.toast(message, context: .ui, level: .success)
            } else {
                let formatter: String
                if srcItem.isFile {
                    formatter = Bundle.localizedString(forKey: "homepage_move_file_failed")
                } else {
                    formatter = Bundle.localizedString(forKey: "homepage_move_folder_failed")
                }
                let message = String(format: formatter, srcItem.itemName)
                AppToastManager.shared.toast(message, context: .ui, level: .error)
            }
        } else {
            let title = Bundle.localizedString(forKey: "homepage_move_forbidden_title")
            let format = Bundle.localizedString(forKey: "homepage_move_forbidden_detail")
            let message = String(format: format, dstFolderItem.itemName, srcItem.itemName, srcItem.itemName)
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            let okAction = UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default)
            alert.addAction(okAction)
            HomePageViewController.instance?.present(alert, animated: true)
        }
    }
}

extension RetroRomFileBrowser {
    func getMoveToAction(item: RetroRomBaseItem) -> UIAction {
        UIAction(title: Bundle.localizedString(forKey: "homepage_move_to"), image: UIImage(systemName: "arrow.right.doc.on.clipboard")) { _ in
            Vibration.selection.vibrate()

            let selector = RetroRomLocationSelector(srcItem: item, browser: self)
            let navController = UINavigationController(rootViewController: selector)
            UIViewController.currentActive()?.present(navController, animated: true)
        }
    }

    func getInfoAction(item: RetroRomBaseItem) -> UIAction? {
        nil
    }

    func getDeleteAction(item: RetroRomBaseItem) -> UIAction {
        UIAction(title: Bundle.localizedString(forKey: "homepage_delete"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            Vibration.selection.vibrate()
            self?.deleteItem(item)
        }
    }

    func getRenameAction(indexPath: IndexPath) -> UIAction {
        UIAction(title: Bundle.localizedString(forKey: "homepage_rename"), image: UIImage(systemName: "pencil.line")) { [weak self] _ in
            Vibration.selection.vibrate()
            self?.editRomFileName(indexPath: indexPath)
        }
    }

    func getAssignCoreAction(item: RetroRomBaseItem) -> UIAction {
        UIAction(title: Bundle.localizedString(forKey: "homepage_asign_core"), image: UIImage(systemName: "cpu")) { _ in
            Vibration.selection.vibrate()

            guard let current = UIViewController.currentActive() else {
                return
            }
            let action: RetroRomCoreSelectViewController.Action
            if let item = item as? RetroRomFileItem {
                action = .assignCoreForFile(item: item)
            } else if let item = item as? RetroRomFolderItem {
                action = .assignCoreForFolder(folder: item)
            } else {
                fatalError()
            }
            let controller = RetroRomCoreSelectViewController(action: action)
            let navController = UINavigationController(rootViewController: controller)
            current.present(navController, animated: true)
        }
    }
}
