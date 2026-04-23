//
//  RetroRomFileManager.swift
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

import Foundation
import ObjcHelper
import RACoordinator

final class RetroRomFileManager {
    static let shared = RetroRomFileManager()

    private var folderItemCache = Dictionary<String, RetroRomFolderItem>()
    private var fileItemCache   = Dictionary<String, RetroRomFileItem>()
    private var fileTagCache    = Dictionary<Int, RetroRomFileTag>()

    func folderItem(key: String) -> RetroRomFolderItem? {
        if let item = folderItemCache[key] {
            return item
        } else {
            if let item = Retro​Rom​Persistence.shared.getFolderItem(key: key) {
                folderItemCache[key] = item
                return item
            } else {
                return nil
            }
        }
    }

    func folderItem(parent: String, rawName: String) -> RetroRomFolderItem? {
        if let item = Retro​Rom​Persistence.shared.getFolderItem(parent: parent, rawName: rawName) {
            if let stored = folderItemCache[item.key] {
                return stored
            } else {
                folderItemCache[item.key] = item
                return item
            }
        } else {
            return nil
        }
    }

    func fileItem(key: String) -> RetroRomFileItem? {
        if let item = fileItemCache[key] {
            return item
        } else {
            if let item = Retro​Rom​Persistence.shared.getFileItem(key: key) {
                fileItemCache[key] = item
                return item
            } else {
                return nil
            }
        }
    }

    func fileTag(id: Int) -> RetroRomFileTag? {
        if id == 0 {
            return .untaged
        }

        if let tag = fileTagCache[id] {
            return tag
        } else {
            if let tag = Retro​Rom​Persistence.shared.getFileTag(id: id) {
                fileTagCache[id] = tag
                return tag
            } else {
                return nil
            }
        }
    }

    func fileTags(in idArray: [Int], order: Bool = false) -> [RetroRomFileTag] {
        var lacked: [Int] = []
        var result: [RetroRomFileTag] = []
        for id in idArray {
            if let tag = fileTagCache[id] {
                result.append(tag)
            } else {
                lacked.append(id)
            }
        }
        if !lacked.isEmpty {
            let fetched = Retro​Rom​Persistence.shared.getFileTags(in: lacked) ?? []
            for tag in fetched {
                fileTagCache[tag.id] = tag
            }
            result.append(contentsOf: fetched)
        }

        if order {
            let tagDict = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
            result = idArray.compactMap { tagDict[$0] }
        }

        return result
    }

    func retroItem(key: String) -> RetroRomBaseItem? {
        fileItem(key: key) ?? folderItem(key: key)
    }

    func retroItems(parent: String) -> [RetroRomBaseItem]? {
        let files = Retro​Rom​Persistence.shared.getFileItems(parent: parent)
        let folders = Retro​Rom​Persistence.shared.getFolderItems(parent: parent)
        guard let files = files, let folders = folders else {
            return nil
        }
        return files + folders
    }

    func retroRomFileItems(in keys: Set<String>) -> [RetroRomFileItem] {
        var lacked: [String] = []
        var result: [RetroRomFileItem] = []
        for key in keys {
            if let item = fileItemCache[key] {
                result.append(item)
            } else {
                lacked.append(key)
            }
        }

        if !lacked.isEmpty {
            let fetched = Retro​Rom​Persistence.shared.getFileItems(in: lacked) ?? []
            for item in fetched {
                fileItemCache[item.key] = item
            }
            result.append(contentsOf: fetched)
        }

        return result
    }

    func retroRomFolderItems(in keys: Set<String>) -> [RetroRomFolderItem] {
        var lacked: [String] = []
        var result: [RetroRomFolderItem] = []
        for key in keys {
            if let item = folderItemCache[key] {
                result.append(item)
            } else {
                lacked.append(key)
            }
        }

        if !lacked.isEmpty {
            let fetched = Retro​Rom​Persistence.shared.getFolderItems(in: lacked) ?? []
            for item in fetched {
                folderItemCache[item.key] = item
            }
            result.append(contentsOf: fetched)
        }

        return result
    }

    func importGame(urls: [URL], rootParent: String) {
        if urls.count == 1 {
            let url = urls[0]
            if url.startAccessingSecurityScopedResource() {
                if FileManager.default.pathIsDirectory(url.path(percentEncoded: false)){
                    url.stopAccessingSecurityScopedResource()
                    let importor = RetroRomFolderImportor(rootUrl: url, rootParent: rootParent)
                    importor?.start()
                } else {
                    url.stopAccessingSecurityScopedResource()
                    let importor = RetroRomFileImportor(urls: urls, rootParent: rootParent)
                    importor?.start()
                }
            } else {
                return
            }
        } else {
            let importor = RetroRomFileImportor(urls: urls, rootParent: rootParent)
            importor?.start()
        }
    }

    func deleteItem(_ item: RetroRomBaseItem, browser: RetroRomFileBrowser) {
        let indicatorView = RetroRomActivityView(mainTitle: Bundle.localizedString(forKey: "homepage_delete_deleting"))
        indicatorView.install()

        DispatchQueue.global().async {
            if item.delete(path: "", indicatorView: indicatorView) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .romCountChanged, object: nil)
                    let message = String(format: Bundle.localizedString(forKey: "homepage_delete_item_success"), item.itemName)
                    indicatorView.successMessage(message, title: Bundle.localizedString(forKey: "info"), canDismiss: true)
                    browser.itemDeleted(item, success: true)
                }
            } else {
                DispatchQueue.main.async {
                    browser.itemDeleted(item, success: false)
                }
            }
        }
    }

    @discardableResult
    func deleteGameStateItem(_ item: RetroRomGameStateItem) -> Bool {
        let ret1 = Retro​Rom​Persistence.shared.deleteGameState(coreId: item.coreId, sha256: item.sha256, fileName: item.rawName)
        let ret2 = {
            do {
                try FileManager.default.removeItem(atPath: item.statePath)
                return true
            } catch {
            #if DEBUG
                fatalError(error.localizedDescription)
            #else
                return false
            #endif
            }
        }()
        try? FileManager.default.removeItem(atPath: item.pngPath)
        return ret1 && ret2
    }

    func saveState(rawName: String, showName: String?, sha256: String?, romKey: String?, autoSave: Bool) -> Bool {
        guard let currentCoreItem = RetroArchX.shared().currentCoreItem else {
            return false
        }

        let stateFolder = AppConfig.shared.statesFolder + currentCoreItem.coreId
        if !FileManager.default.createDirectoryIfNotExists(atPath: stateFolder) {
            return false
        }

        let imageFolder: String?
        if autoSave {
            imageFolder = AppConfig.shared.sharedAutoThumbnailFolderPath
        } else {
            imageFolder = nil
        }

        if RetroArchX.shared().saveState(to: stateFolder, imageFolder: imageFolder, name: rawName) {
            let item = RetroRomGameStateItem(rawName: rawName, coreId: currentCoreItem.coreId, showName: showName, romKey: romKey, sha256: sha256, createAt: Date())
            if !Retro​Rom​Persistence.shared.insertGameStateItem(item) {
                deleteGameStateItem(item)
                return false
            } else {
                return true
            }
        } else {
            return false
        }
    }

    @discardableResult
    func deleteGameStateItem(_ romKey: String) -> Bool {
        let items = Retro​Rom​Persistence.shared.getGameStateItems(romKey: romKey) ?? []
        var result = true
        for item in items {
            if !deleteGameStateItem(item) {
                result = false
            }
        }
        return result
    }

    @discardableResult
    func deleteFileTag(_ tag: RetroRomFileTag) -> Bool {
        guard Retro​Rom​Persistence.shared.deleteFileTag(id: tag.id) else {
            return false
        }

        fileTagCache.removeValue(forKey: tag.id)

        for (_, v) in fileItemCache {
            v.removeFileTag(id: tag.id)
        }

        NotificationCenter.default.post(name: .fileTagDeleted, object: tag)

        return true
    }

    func getAllFileTags() -> [RetroRomFileTag] {
        guard let tagIds = Retro​Rom​Persistence.shared.getAllFileTagIDs() else {
            return []
        }

        return fileTags(in: tagIds, order: true)
    }

    func getRomFileArrayByTag() -> [Int: [RetroRomFileItem]] {
        var result = [Int: [RetroRomFileItem]]()
        guard let tagFileKeys = Retro​Rom​Persistence.shared.getAllTagFileKeys() else {
            return result
        }

        for (k, v) in tagFileKeys {
            let keys = v.split(separator: ",").map({ String($0) })
            let items = retroRomFileItems(in: Set(keys))
            if items.count > 0 {
                result[k] = items
            }
        }

        return result
    }

    func getUntagFileItems() -> [RetroRomFileItem] {
        guard let keys = Retro​Rom​Persistence.shared.getUntagFileItemKeys() else {
            return []
        }

        return retroRomFileItems(in: keys)
    }

    func getRomFileArrayByCore() -> [String: [RetroRomFileItem]] {
        guard let keys = Retro​Rom​Persistence.shared.getAllFileItemKeys() else {
            return [:]
        }
        let noneKey = RetroRomFileItemWrapper.uncategorizedKey
        var result = [String: [RetroRomFileItem]]()
        let items = retroRomFileItems(in: keys)
        result[noneKey] = []

        for item in items {
            let cores = item.getSupportedCoresByExtension()
            if cores.count > 0 {
                for core in cores {
                    if result[core.coreId] != nil {
                        result[core.coreId]?.append(item)
                    } else {
                        result[core.coreId] = [item]
                    }
                }
            } else if item.inheritedPreferCore == nil {
                result[noneKey]?.append(item)
            }

            if let coreId = item.inheritedPreferCore, !(result[coreId]?.contains(item) ?? false) {
                if result[coreId] != nil {
                    result[coreId]?.append(item)
                } else {
                    result[coreId] = [item]
                }
            }
        }

        return result
    }

    func storeFileTag(_ tag: RetroRomFileTag) -> Bool {
        if Retro​Rom​Persistence.shared.storeFileTag(tag) {
            fileTagCache[tag.id] = tag
            return true
        } else {
            return false
        }
    }

    func deleteFolderItem(_ key: String) -> Bool {
        if Retro​Rom​Persistence.shared.deleteFolderItem(key) {
            folderItemCache.removeValue(forKey: key)
            return true
        } else {
            return false
        }
    }

    func deleteFileItem(_ key: String) -> Bool {
        if Retro​Rom​Persistence.shared.deleteFileItem(key) {
            fileItemCache.removeValue(forKey: key)
            return true
        } else {
            return false
        }
    }
}

extension RetroRomFileManager {
    // v1.0 -> v1.1.0~
    func performDataMigrationIfNeeded() {
        let fileManager = FileManager.default
        let legacyDataRoot = fileManager.documentFolder + "/data"

        guard fileManager.fileExists(atPath: legacyDataRoot) else { return }
        if isSymbolicLink(at: legacyDataRoot) { return }

        // 定义迁移映射关系：[旧子目录 : 新子目录]
        let migrationMap: [String: String] = [
            legacyDataRoot + "/states": AppConfig.shared.statesFolder,
            legacyDataRoot + "/database": (AppConfig.shared.romDatabasePath as NSString).deletingLastPathComponent,
            legacyDataRoot + "/roms": AppConfig.shared.romFolderPath,
            legacyDataRoot + "/auto_snapshots": AppConfig.shared.sharedAutoThumbnailFolderPath
        ]

        for (oldDir, newDir) in migrationMap {
            migrateSubFolderContent(from: oldDir, to: newDir)
        }

        // 检查 legacyDataRoot 是否已经搬空，如果空了再删，如果不空说明有用户自定义数据，留着
        if let contents = try? fileManager.contentsOfDirectory(atPath: legacyDataRoot), contents.isEmpty {
            try? fileManager.removeItem(atPath: legacyDataRoot)
        }
    }

    private func isSymbolicLink(at path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    // 核心：逐个文件移动，不破坏目录结构
    private func migrateSubFolderContent(from oldDir: String, to newDir: String) {
        let fileManager = FileManager.default
        guard fileManager.pathIsDirectory(oldDir) else { return }
        if isSymbolicLink(at: oldDir) { return }
        if normalizedPath(oldDir) == normalizedPath(newDir) { return }

        do {
            let files = try fileManager.contentsOfDirectory(atPath: oldDir)
            for fileName in files {
                let oldPath = oldDir + "/" + fileName
                let newPath = newDir + "/" + fileName

                if !fileManager.fileExists(atPath: newPath) {
                    // 使用 moveItem，因为同一个沙盒内这是移动指针，极快且省空间
                    try fileManager.moveItem(atPath: oldPath, toPath: newPath)
                } else {
                    // 如果目标已存在（说明之前迁移过一半中断了），安全起见可以 removeItem 旧的
                    try? fileManager.removeItem(atPath: oldPath)
                }
            }
            // 尝试删除已经搬空的旧子目录
            try? fileManager.removeItem(atPath: oldDir)
        } catch {
            print("Migration Error at \(oldDir): \(error)")
        }
    }
}
