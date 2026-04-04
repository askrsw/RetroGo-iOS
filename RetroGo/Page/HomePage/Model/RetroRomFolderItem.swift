//
//  RetroRomFolderItem.swift
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

final class RetroRomFolderItem: RetroRomBaseItem {
    private(set) var subFolderKeys: Set<String>
    private(set) var subFileKeys: Set<String>

    var expand: Bool = false

    init(key: String, rawName: String, showName: String? = nil, parent: String, createAt: Date, updateAt: Date, preferCore: String? = nil, preferIcon: String? = nil, subFolderKeys: Set<String> = [], subFileKeys: Set<String> = []) {
        self.subFolderKeys = subFolderKeys
        self.subFileKeys   = subFileKeys
        super.init(key: key, rawName: rawName, showName: showName, parent: parent, createAt: createAt, updateAt: updateAt, preferCore: preferCore, preferIcon: preferIcon)
    }

    var isRoot: Bool {
        key == "root"
    }

    static func isRootFolder(key: String) -> Bool {
        key == "root"
    }

    var subItems: [RetroRomBaseItem] {
        let subFiles = RetroRomFileManager.shared.retroRomFileItems(in: subFileKeys)
        let subFolders = RetroRomFileManager.shared.retroRomFolderItems(in: subFolderKeys)
        return subFiles + subFolders
    }

    func canAddItem(_ item: RetroRomBaseItem) -> Bool {
        guard let fullPath = fullPath else {
            return false
        }

        let fileManager = FileManager.default
        let newItemPath = fullPath + item.rawName

        if fileManager.fileExists(atPath: newItemPath) {
            return false
        } else {
            return true
        }
    }

    func addNewItem(_ item: RetroRomBaseItem) -> Bool {
        guard let path = fullPath, let srcPath = item.fullPath else {
            return false
        }

        let dstPath = path + item.rawName
        do {
            try FileManager.default.moveItem(atPath: srcPath, toPath: dstPath)
        } catch {
            print("Move \(item.rawName) from \(srcPath) to \(dstPath) error: \(error)")
            return false
        }

        if item.moveToFolder(key) {
            if item.isFile {
                subFileKeys.insert(item.key)
            } else if item.isFolder {
                subFolderKeys.insert(item.key)
            }
            return true
        } else {
            do {
                try FileManager.default.moveItem(atPath: dstPath, toPath: srcPath)
            } catch {
                print("Move \(item.rawName) from \(dstPath) to \(srcPath) error: \(error)")
            }
            return false
        }
    }

    override func delete(path: String, indicatorView: RetroRomActivityView) -> Bool {
        let filePath = (path.count > 0 ? path + "/" : "") + itemName
        for item in subItems {
            if !item.delete(path: filePath, indicatorView: indicatorView) {
                return false
            }
        }

        let title = Bundle.localizedString(forKey: "homepage_delete_deleting")
        let message = Bundle.localizedString(forKey: "homepage_delete_folder") + filePath
        indicatorView.activeMessage(message, title: title)

        if RetroRomFileManager.shared.deleteFolderItem(key) {
            parentFolderItem?.removeSubFolderItemKey(key)
            if let path = self.fullPath {
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    print("Failed to delete rom folder: \(rawName) for item: \(itemName)")
                }
            }
            return true
        } else {
            let message = String(format: Bundle.localizedString(forKey: "homepage_delete_item_failed"), filePath)
            indicatorView.errorMessage(message, title: Bundle.localizedString(forKey: "error"), canDismiss: true)
            return false
        }
    }

    func addSubItemKeys(newFolderKeys: [String], newFileKeys: [String]) {
        newFolderKeys.forEach({ subFolderKeys.insert($0) })
        newFileKeys.forEach({ subFileKeys.insert($0) })
    }

    func removeSubFileItemKey(_ key: String) {
        subFileKeys.remove(key)
    }

    func removeSubFolderItemKey(_ key: String) {
        subFolderKeys.remove(key)
    }

    func updateSubItemKeys() {
        if let subs = Retro​Rom​Persistence.shared.getFolderSubItemKeys(key) {
            subFolderKeys = subs.folderKeys
            subFileKeys   = subs.fileKeys
        }
    }
}
