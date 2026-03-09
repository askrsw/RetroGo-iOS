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

import SQLite
import ObjcHelper
import Foundation
import RACoordinator

final class RetroRomFileManager {
    static let shared = RetroRomFileManager()
    private init() {
        _ = RetroRomFileManager.sqlite
    }

    private var folderItemCache = Dictionary<String, RetroRomFolderItem>()
    private var fileItemCache   = Dictionary<String, RetroRomFileItem>()
    private var fileTagCache    = Dictionary<Int, RetroRomFileTag>()

    func folderItem(key: String) -> RetroRomFolderItem? {
        if let item = folderItemCache[key] {
            return item
        } else {
            if let item = getFolderItem(key: key) {
                folderItemCache[key] = item
                return item
            } else {
                return nil
            }
        }
    }

    func folderItem(parent: String, rawName: String) -> RetroRomFolderItem? {
        if let item = getFolderItem(parent: parent, rawName: rawName) {
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
            if let item = getFileItem(key: key) {
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
            if let tag = getFileTag(id: id) {
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
            let fetched = getFileTags(in: lacked) ?? []
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
        let files = getFileItems(parent: parent)
        let folders = getFolderItems(parent: parent)
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
            let fetched = getFileItems(in: lacked) ?? []
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
            let fetched = getFolderItems(in: lacked) ?? []
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
        let ret1 = deleteGameState(coreId: item.coreId, sha256: item.sha256, fileName: item.rawName)
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
            imageFolder = AppConfig.shared.sharedAutoThumnailFolderPath
        } else {
            imageFolder = nil
        }

        if RetroArchX.shared().saveState(to: stateFolder, imageFolder: imageFolder, name: rawName) {
            let item = RetroRomGameStateItem(rawName: rawName, coreId: currentCoreItem.coreId, showName: showName, romKey: romKey, sha256: sha256, createAt: Date())
            if !insertGameStateItem(item) {
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
        let items = getGameStateItems(romKey: romKey) ?? []
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
        guard deleteFileTag(id: tag.id) else {
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
        guard let tagIds = getAllFileTagIDs() else {
            return []
        }

        return fileTags(in: tagIds, order: true)
    }

    func getRomFileArrayByTag() -> [Int: [RetroRomFileItem]] {
        var result = [Int: [RetroRomFileItem]]()
        guard let tagFileKeys = getAllTagFileKeys() else {
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
        guard let keys = getUntagFileItemKeys() else {
            return []
        }

        return retroRomFileItems(in: keys)
    }

    func getRomFileArrayByCore() -> [String: [RetroRomFileItem]] {
        guard let keys = getAllFileItemKeys() else {
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
            } else if item.preferCore == nil {
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
}

extension RetroRomFileManager {

    // MARK: - Rom File and Rom Folder Stuff

    func deleteFolderItem(_ key: String) -> Bool {
        do {
            folderItemCache.removeValue(forKey: key)

            let db = Self.sqlite
            let alice = Self.folderInfoTable.filter(Self.key == key)
            try db.run(alice.delete())
            return true
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return false
        #endif
        }
    }

    func deleteFileItem(_ key: String) -> Bool {
        do {
            fileItemCache.removeValue(forKey: key)

            let db = Self.sqlite
            let alice = Self.romInfoTable.filter(Self.key == key)
            try db.run(alice.delete())
            return true
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return false
        #endif
        }
    }

    func getFolderCount() -> Int? {
        do {
            let db = Self.sqlite
            let alice = Self.folderInfoTable.where(Self.key != "root")
            let count = try db.scalar(alice.count)
            return count
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return nil
        #endif
        }
    }

    func getRomFileCount() -> Int? {
        do {
            let db = Self.sqlite
            let alice = Self.romInfoTable
            let count = try db.scalar(alice.count)
            return count
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return nil
        #endif
        }
    }

    private func getFileItems(parent: String) -> [RetroRomFileItem]? {
        do {
            let db = Self.sqlite
            let alice = Self.romTagInfoView.where(Self.parent == parent)
            var items: [RetroRomFileItem] = []
            for row in try db.prepare(alice) {
                let item = RetroRomFileItem(
                    key: row[Self.key],
                    rawName: row[Self.rawName],
                    showName: row[Self.showName],
                    parent: row[Self.parent],
                    createAt: row[Self.createAt],
                    updateAt: row[Self.updateAt],
                    preferSystem: row[Self.preferSystem],
                    preferCore: row[Self.preferCore],
                    preferIcon: row[Self.preferIcon],
                    fileSize: row[Self.fileSize],
                    sha256: row[Self.sha256],
                    lastPlayAt: row[Self.lastPlayAt],
                    playTime: row[Self.playTime],
                    tagIdArray: parseTagIds(row[Self.tagIdsText]),
                )
                items.append(item)
            }
            return items
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return nil
        #endif
        }
    }

    private func getFileItems(in keys: [String]) -> [RetroRomFileItem]? {
        guard !keys.isEmpty else { return [] }

        // 1. 设置合理的步长。200 是一个兼顾性能与解析开销的黄金值
        let chunkSize = 200
        var allItems: [RetroRomFileItem] = []

        do {
            let db = Self.sqlite

            // 2. 将 keys 按照步长切分
            for i in stride(from: 0, to: keys.count, by: chunkSize) {
                let end = min(i + chunkSize, keys.count)
                let chunk = Array(keys[i..<end])

                // 3. 构建当前批次的查询语句
                let query = Self.romTagInfoView.where(chunk.contains(Self.key))

                // 4. 执行当前批次的查询并填充数据
                for row in try db.prepare(query) {
                    let item = RetroRomFileItem(
                        key: row[Self.key],
                        rawName: row[Self.rawName],
                        showName: row[Self.showName],
                        parent: row[Self.parent],
                        createAt: row[Self.createAt],
                        updateAt: row[Self.updateAt],
                        preferSystem: row[Self.preferSystem],
                        preferCore: row[Self.preferCore],
                        preferIcon: row[Self.preferIcon],
                        fileSize: row[Self.fileSize],
                        sha256: row[Self.sha256],
                        lastPlayAt: row[Self.lastPlayAt],
                        playTime: row[Self.playTime],
                        tagIdArray: parseTagIds(row[Self.tagIdsText]),
                    )
                    allItems.append(item)
                }
            }
            return allItems
        } catch {
            #if DEBUG
                fatalError("SQLite 查询失败: \(error)")
            #else
                return nil
            #endif
        }
    }

    // 辅助方法：解析标签字符串
    private func parseTagIds(_ text: String?) -> [Int] {
        guard let text = text, !text.isEmpty else { return [] }
        return text.split(separator: ",").compactMap { Int($0) }
    }

    private func parseSubFileKeys(_ text: String?) -> Set<String> {
        guard let text = text, !text.isEmpty else { return [] }
        let array = text.split(separator: "|").map { String($0) }
        return Set(array)
    }

    private func parseSubFolderKeys(_ text: String?) -> Set<String> {
        guard let text = text, !text.isEmpty else { return [] }
        let array = text.split(separator: "|").map { String($0) }
        return Set(array)
    }

    private func getFolderItems(parent: String) -> [RetroRomFolderItem]? {
        do {
            let db = Self.sqlite
            let alice = Self.folderChildrenInfoView.where(Self.parent == parent && Self.key != "root")
            var items: [RetroRomFolderItem] = []
            for row in try db.prepare(alice) {
                let item = RetroRomFolderItem(
                    key: row[Self.key],
                    rawName: row[Self.rawName],
                    showName: row[Self.showName],
                    parent: row[Self.parent],
                    createAt: row[Self.createAt],
                    updateAt: row[Self.updateAt],
                    preferSystem: row[Self.preferSystem],
                    preferCore: row[Self.preferCore],
                    preferIcon: row[Self.preferIcon],
                    subFolderKeys: parseSubFolderKeys(row[Self.folderChildrenText]),
                    subFileKeys: parseSubFileKeys(row[Self.fileChildrenText]),
                )
                items.append(item)
            }
            return items
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return nil
        #endif
        }
    }

    private func getFolderItems(in keys: [String]) -> [RetroRomFolderItem]? {
        guard !keys.isEmpty else { return [] }

        // 1. 设置合理的步长。200 是一个兼顾性能与解析开销的黄金值
        let chunkSize = 200
        var allItems: [RetroRomFolderItem] = []

        do {
            let db = Self.sqlite

            // 2. 将 keys 按照步长切分
            for i in stride(from: 0, to: keys.count, by: chunkSize) {
                let end = min(i + chunkSize, keys.count)
                let chunk = Array(keys[i..<end])

                // 3. 构建当前批次的查询语句
                let query = Self.folderChildrenInfoView.where(chunk.contains(Self.key))

                // 4. 执行当前批次的查询并填充数据
                for row in try db.prepare(query) {
                    let item = RetroRomFolderItem(
                        key: row[Self.key],
                        rawName: row[Self.rawName],
                        showName: row[Self.showName],
                        parent: row[Self.parent],
                        createAt: row[Self.createAt],
                        updateAt: row[Self.updateAt],
                        preferSystem: row[Self.preferSystem],
                        preferCore: row[Self.preferCore],
                        preferIcon: row[Self.preferIcon],
                        subFolderKeys: parseSubFolderKeys(row[Self.folderChildrenText]),
                        subFileKeys: parseSubFileKeys(row[Self.fileChildrenText])
                    )
                    allItems.append(item)
                }
            }
            return allItems
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return nil
        #endif
        }
    }

    private func getFileItem(key: String) -> RetroRomFileItem? {
        do {
            let db = Self.sqlite
            let alice = Self.romTagInfoView.where(Self.key == key)
            for row in try db.prepare(alice) {
                let item = RetroRomFileItem(
                    key: row[Self.key],
                    rawName: row[Self.rawName],
                    showName: row[Self.showName],
                    parent: row[Self.parent],
                    createAt: row[Self.createAt],
                    updateAt: row[Self.updateAt],
                    preferSystem: row[Self.preferSystem],
                    preferCore: row[Self.preferCore],
                    preferIcon: row[Self.preferIcon],
                    fileSize: row[Self.fileSize],
                    sha256: row[Self.sha256],
                    lastPlayAt: row[Self.lastPlayAt],
                    playTime: row[Self.playTime],
                    tagIdArray: parseTagIds(row[Self.tagIdsText]),
                )
                return item
            }
            return nil
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return nil
        #endif
        }
    }

    private func getUntagFileItemKeys() -> Set<String>? {
        do {
            let db = Self.sqlite
            let alice = Self.romTagInfoView.where(Self.tagIdsText == nil).select(Self.key)
            var keys = Set<String>()
            for row in try db.prepare(alice) {
                let key = row[Self.key]
                keys.insert(key)
            }
            return keys
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return nil
        #endif
        }
    }

    private func getAllFileItemKeys() -> Set<String>? {
        do {
            let db = Self.sqlite
            let alice = Self.romInfoTable.select(Self.key)
            var keys: Set<String> = []
            for row in try db.prepare(alice) {
                let key = row[Self.key]
                keys.insert(key)
            }
            return keys
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return nil
        #endif
        }
    }

    private func getFolderItem(key: String) -> RetroRomFolderItem? {
        do {
            let db = Self.sqlite
            let alice = Self.folderChildrenInfoView.where(Self.key == key)
            for row in try db.prepare(alice) {
                let item = RetroRomFolderItem(
                    key: row[Self.key],
                    rawName: row[Self.rawName],
                    showName: row[Self.showName],
                    parent: row[Self.parent],
                    createAt: row[Self.createAt],
                    updateAt: row[Self.updateAt],
                    preferSystem: row[Self.preferSystem],
                    preferCore: row[Self.preferCore],
                    preferIcon: row[Self.preferIcon],
                    subFolderKeys: parseSubFolderKeys(row[Self.folderChildrenText]),
                    subFileKeys: parseSubFileKeys(row[Self.fileChildrenText]),
                )
                return item
            }
            return nil
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return nil
        #endif
        }
    }

    private func getFolderItem(parent: String, rawName: String) -> RetroRomFolderItem? {
        do {
            let db = Self.sqlite
            let alice = Self.folderChildrenInfoView.where(Self.parent == parent && Self.rawName == rawName).limit(1)
            for row in try db.prepare(alice) {
                let item = RetroRomFolderItem(
                    key: row[Self.key],
                    rawName: row[Self.rawName],
                    showName: row[Self.showName],
                    parent: row[Self.parent],
                    createAt: row[Self.createAt],
                    updateAt: row[Self.updateAt],
                    preferSystem: row[Self.preferSystem],
                    preferCore: row[Self.preferCore],
                    preferIcon: row[Self.preferIcon],
                    subFolderKeys: parseSubFolderKeys(row[Self.folderChildrenText]),
                    subFileKeys: parseSubFileKeys(row[Self.fileChildrenText]),
                )
                return item
            }
            return nil
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return nil
        #endif
        }
    }

    func getFolderSubItemKeys(_ folderKey: String) -> (folderKeys: Set<String>, fileKeys: Set<String>)? {
        do {
            let db = Self.sqlite
            let alice1 = Self.folderInfoTable.where(Self.parent == folderKey)
            var subFolderKeys = Set<String>()
            for row in try db.prepare(alice1) {
                let key = row[Self.key]
                subFolderKeys.insert(key)
            }
            if folderKey == "root" {
                subFolderKeys.remove("root")
            }
            let alice2 = Self.romInfoTable.where(Self.parent == folderKey)
            var subFileKeys = Set<String>()
            for row in try db.prepare(alice2) {
                let key = row[Self.key]
                subFileKeys.insert(key)
            }
            return (subFolderKeys, subFileKeys)
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return nil
        #endif
        }
    }

    func storeRomFiles(_ files:[RetroRomFileItem], folders: [RetroRomFolderItem]) -> Bool {
        do {
            let db = Self.sqlite
            try db.transaction {
                for folder in folders {
                    try db.run(folder.insert)
                }
                for file in files {
                    try db.run(file.insert)
                }
            }
            return true
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return false
        #endif
        }
    }

    func updateShowName(_ name: String, key: String, isFolder: Bool) -> Bool {
        do {
            let db = Self.sqlite
            let alice: SQLite.Table
            if isFolder {
                alice = Self.folderInfoTable.filter(Self.key == key)
            } else {
                alice = Self.romInfoTable.filter(Self.key == key)
            }
            let update = alice.update(
                Self.showName <- name
            )
            try db.run(update)
            return true
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return false
        #endif
        }
    }

    func updateItemParent(_ parent: String, key: String, isFolder: Bool) -> Bool {
        do {
            let db = Self.sqlite
            let alice: SQLite.Table
            if isFolder {
                alice = Self.folderInfoTable.filter(Self.key == key)
            } else {
                alice = Self.romInfoTable.filter(Self.key == key)
            }
            let update = alice.update(
                Self.parent <- parent
            )
            try db.run(update)
            return true
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return false
        #endif
        }
    }

    func updateLastPlayAt(key: String, date: Date) -> Bool {
        do {
            let db = Self.sqlite
            let alice = Self.romInfoTable.filter(Self.key == key)
            let update = alice.update(
                Self.lastPlayAt <- Date()
            )
            try db.run(update)
            return true
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return false
        #endif
        }
    }

    func updatePlayTime(key: String, seconds: Int) -> Bool {
        do {
            let db = Self.sqlite
            let alice = Self.romInfoTable.filter(Self.key == key)
            let update = alice.update(
                Self.playTime <- seconds
            )
            try db.run(update)
            return true
        } catch  {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return false
        #endif
        }
    }

    func updateFilePreferCore(key: String, core: String?) -> Bool {
        do {
            let db = Self.sqlite
            let alice = Self.romInfoTable.filter(Self.key == key)
            let update = alice.update(
                Self.preferCore <- core
            )
            try db.run(update)
            return true
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return false
        #endif
        }
    }

    func updateFolderPreferCore(key: String, core: String?) -> Bool {
        do {
            let db = Self.sqlite
            let alice = Self.folderInfoTable.filter(Self.key == key)
            let update = alice.update(
                Self.preferCore <- core
            )
            try db.run(update)
            return true
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return false
        #endif
        }
    }

    func getUniqueKey(_ folder: RetroRomFolderItem? = nil) -> String? {
        do {
            let db = Self.sqlite
            let fileManager = FileManager.default
            while true {
                let key = NSString.randomString(10, caseInsensitive: false)
                let query1 = Self.folderInfoTable.filter(Self.key == key).limit(1)
                if (try db.pluck(query1)) != nil {
                    continue
                }

                let query2 = Self.romInfoTable.filter(Self.key == key).limit(1)
                if (try db.pluck(query2)) != nil {
                    continue
                }

                if let folder = folder, let path = folder.fullPath {
                    let folderPath = path + key
                    if fileManager.fileExists(atPath: folderPath) {
                        continue
                    }
                }

                return key
            }
        } catch {
    #if DEBUG
        let errMsg = "\(error)"
        fatalError(errMsg)
    #else
        return nil
    #endif
        }
    }

    // MARK: - Game State Stuff

    func insertGameStateItem(_ item: RetroRomGameStateItem) -> Bool {
        do {
            let db = Self.sqlite
            try db.run(item.insert)
            return true
        } catch {
        #if DEBUG
            fatalError("\(error.localizedDescription)")
        #else
            return false
        #endif
        }
    }

    func deleteGameState(coreId: String, sha256: String?, fileName: String) -> Bool {
        do {
            let db = Self.sqlite
            let alice = Self.stateInfoTable.filter(Self.coreId == coreId && Self.sha256 == sha256 && Self.rawName == fileName)
            try db.run(alice.delete())
            return true
        } catch {
        #if DEBUG
            fatalError("\(error.localizedDescription)")
        #else
            return false
        #endif
        }
    }

    func getGameStateItems(coreId: String? = nil, sha256: String? = nil) -> [RetroRomGameStateItem]? {
        do {
            let db = Self.sqlite
            let alice: SQLite.Table
            if let coreId = coreId, let sha256 = sha256 {
                alice = Self.stateInfoTable.filter(Self.coreId == coreId && Self.sha256 == sha256).order(Self.createAt.desc)
            } else if let coreId = coreId {
                alice = Self.stateInfoTable.filter(Self.coreId == coreId).order(Self.createAt.desc)
            } else if let sha256 = sha256 {
                alice = Self.stateInfoTable.filter(Self.sha256 == sha256).order(Self.createAt.desc)
            } else {
                alice = Self.stateInfoTable.order(Self.createAt.desc)
            }
            var items: [RetroRomGameStateItem] = []
            for row in try db.prepare(alice) {
                let item = RetroRomGameStateItem(
                    rawName: row[Self.rawName],
                    coreId: row[Self.coreId],
                    showName: row[Self.showName],
                    romKey: row[Self.romKey],
                    sha256: row[Self.sha256],
                    createAt: row[Self.createAt],
                )
                items.append(item)
            }
            return items
        } catch {
        #if DEBUG
            fatalError("\(error.localizedDescription)")
        #else
            return nil
        #endif
        }
    }

    func getGameStateItems(romKey: String, order: Bool = false) -> [RetroRomGameStateItem]? {
        do {
            let db = Self.sqlite
            let alice: SQLite.Table
            if order {
                alice = Self.stateInfoTable.filter(Self.romKey == romKey).order(Self.createAt.desc)
            } else {
                alice = Self.stateInfoTable.filter(Self.romKey == romKey)
            }
            var items: [RetroRomGameStateItem] = []
            for row in try db.prepare(alice) {
                let item = RetroRomGameStateItem(
                    rawName: row[Self.rawName],
                    coreId: row[Self.coreId],
                    showName: row[Self.showName],
                    romKey: row[Self.romKey],
                    sha256: row[Self.sha256],
                    createAt: row[Self.createAt],
                )
                items.append(item)
            }
            return items
        } catch {
        #if DEBUG
            fatalError("\(error.localizedDescription)")
        #else
            return nil
        #endif
        }
    }

    func updateGameStateShowName(_ showName: String, coreId: String, sha256: String?, fileName: String) -> Bool {
        do {
            let db = Self.sqlite
            let alice = Self.stateInfoTable.filter(Self.coreId == coreId && Self.sha256 == sha256 && Self.rawName == fileName)
            try db.run(alice.update(Self.showName <- showName))
            return true
        } catch {
        #if DEBUG
            fatalError("\(error.localizedDescription)")
        #else
            return false
        #endif
        }
    }

    // MARK: - File Tag Stuff

    private func getAllFileTagsFromDatabase() -> [RetroRomFileTag]? {
        do {
            let db = Self.sqlite
            let alice = Self.tagInfoTable.order(Self.id)
            var tags: [RetroRomFileTag] = []
            for row in try db.prepare(alice) {
                let tag = RetroRomFileTag(
                    id: row[Self.id],
                    title: row[Self.title],
                    color: row[Self.colorArgb],
                    createAt: row[Self.createAt],
                    isHidden: row[Self.isHidden],
                )
                tags.append(tag)
            }
            return tags
        } catch {
        #if DEBUG
            fatalError("\(error.localizedDescription)")
        #else
            return nil
        #endif
        }
    }

    private func getAllFileTagIDs() -> [Int]? {
        do {
            let db = Self.sqlite
            let alice = Self.tagInfoTable.order(Self.id)
            var tags: [Int] = []
            for row in try db.prepare(alice) {
                tags.append(row[Self.id])
            }
            return tags
        } catch {
        #if DEBUG
            fatalError("\(error.localizedDescription)")
        #else
            return nil
        #endif
        }
    }

    func getRomFileTagIdArray(romKey: String) -> [Int]? {
        do {
            let db = Self.sqlite
            let alice = Self.romTagInfoTable.filter(Self.key == romKey).order(Self.id)
            var ids: [Int] = []
            for row in try db.prepare(alice) {
                let id = row[Self.id]
                ids.append(id)
            }
            return ids
        } catch {
        #if DEBUG
            fatalError("\(error.localizedDescription)")
        #else
            return nil
        #endif
        }
    }

    func updateRetroFileTags(romKey: String, addedTags: Set<Int>, removedTags: Set<Int>) -> Bool {
        do {
            let db = Self.sqlite
            try db.transaction {
                if !removedTags.isEmpty {
                    let alice = Self.romTagInfoTable.filter(Self.key == romKey && removedTags.contains(Self.id))
                    try db.run(alice.delete())
                }
                if !addedTags.isEmpty {
                    let insertStatements = addedTags.map { id in
                        Self.romTagInfoTable.insert(or: .replace,
                            Self.key <- romKey,
                            Self.id <- id,
                            Self.createAt <- Date()
                        )
                    }
                    for insert in insertStatements {
                        try db.run(insert)
                    }
                }
            }
            return true
        } catch {
        #if DEBUG
            fatalError("\(error.localizedDescription)")
        #else
            return false
        #endif
        }
    }

    func getFileTag(id: Int) -> RetroRomFileTag? {
        do {
            let db = Self.sqlite
            let alice = Self.tagInfoTable.filter(Self.id == id)
            for row in try db.prepare(alice) {
                let tag = RetroRomFileTag(
                    id: row[Self.id],
                    title: row[Self.title],
                    color: row[Self.colorArgb],
                    createAt: row[Self.createAt],
                    isHidden: row[Self.isHidden],
                )
                return tag
            }
            return nil
        } catch {
        #if DEBUG
            fatalError("\(error.localizedDescription)")
        #else
            return nil
        #endif
        }
    }

    func getFileTags(in idArray: [Int]) -> [RetroRomFileTag]? {
        guard !idArray.isEmpty else { return [] }

        // 1. 设置合理的步长。200 是一个兼顾性能与解析开销的黄金值
        let chunkSize = 200
        var allTags: [RetroRomFileTag] = []

        do {
            let db = Self.sqlite

            // 2. 将 keys 按照步长切分
            for i in stride(from: 0, to: idArray.count, by: chunkSize) {
                let end = min(i + chunkSize, idArray.count)
                let chunk = Array(idArray[i..<end])

                // 3. 构建当前批次的查询语句
                let query = Self.tagInfoTable.where(chunk.contains(Self.id))

                // 4. 执行当前批次的查询并填充数据
                for row in try db.prepare(query) {
                    let tag = RetroRomFileTag(
                        id: row[Self.id],
                        title: row[Self.title],
                        color: row[Self.colorArgb],
                        createAt: row[Self.createAt],
                        isHidden: row[Self.isHidden],
                    )
                    allTags.append(tag)
                }
            }

            return allTags
        } catch {
        #if DEBUG
            fatalError("\(error.localizedDescription)")
        #else
            return nil
        #endif
        }
    }

    func getUniqueFileTagId() -> Int? {
        do {
            let db = Self.sqlite
            if let maxV = try db.scalar(Self.tagInfoTable.select(Self.id.max)) {
                if maxV < RetroRomFileTag.kUserTagIdStart {
                    return RetroRomFileTag.kUserTagIdStart + 1
                } else {
                    return maxV + 1
                }
            } else {
                return RetroRomFileTag.kUserTagIdStart + 1
            }
        } catch {
        #if DEBUG
            fatalError("\(error.localizedDescription)")
        #else
            return nil
        #endif
        }
    }

    func storeFileTag(_ tag: RetroRomFileTag) -> Bool {
        do {
            let db = Self.sqlite
            try db.run(tag.insert)
            fileTagCache[tag.id] = tag
            return true
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return false
        #endif
        }
    }

    func updateFiltTag(id: Int, title: String?, color: Int?) -> Bool {
        do {
            let db = Self.sqlite
            let alice = Self.tagInfoTable.where(Self.id == id)
            try db.run(alice.update(
                Self.title <- title,
                Self.colorArgb <- color
            ))
            return true
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return false
        #endif
        }
    }

    func deleteFileTag(id: Int) -> Bool {
        do {
            let db = Self.sqlite
            let alice = Self.tagInfoTable.where(Self.id == id)
            try db.run(alice.delete())
            return true
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return false
        #endif
        }
    }

    func getAllTagFileKeys() -> [Int: String]? {
        do {
            let db = Self.sqlite
            let sql = "SELECT id, GROUP_CONCAT(key) AS file_keys FROM romtaginfo GROUP BY id"
            var result: [Int: String] = [:]
            for row in try db.prepare(sql) {
                let rawID    = row[0] as? Int64
                let fileKeys = row[1] as? String
                if let rawID = rawID, let keys = fileKeys {
                    result[Int(rawID)] = keys
                }
            }
            return result
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return nil
        #endif
        }
    }
}

extension RetroRomFileManager {
    fileprivate static let key        = SQLite.Expression<String>("key")
    fileprivate static let parent     = SQLite.Expression<String>("parent")
    fileprivate static let path       = SQLite.Expression<String>("path")
    fileprivate static let rawName    = SQLite.Expression<String>("raw_name")
    fileprivate static let showName   = SQLite.Expression<String?>("show_name")
    fileprivate static let createAt   = SQLite.Expression<Date>("create_at")
    fileprivate static let updateAt   = SQLite.Expression<Date>("update_at")
    fileprivate static let fileSize   = SQLite.Expression<Int>("file_size")
    fileprivate static let sha256     = SQLite.Expression<String?>("sha256")
    fileprivate static let lastPlayAt = SQLite.Expression<Date?>("last_play_at")
    fileprivate static let playTime   = SQLite.Expression<Int>("play_time")
    fileprivate static let coreId     = SQLite.Expression<String>("core_id")
    fileprivate static let romKey     = SQLite.Expression<String?>("rom_key")
    fileprivate static let id         = SQLite.Expression<Int>("id")
    fileprivate static let title      = SQLite.Expression<String?>("title")
    fileprivate static let colorArgb  = SQLite.Expression<Int?>("color_argb")
    fileprivate static let tagIdsText = SQLite.Expression<String?>("tag_ids_text")
    fileprivate static let folderChildrenText = SQLite.Expression<String?>("folder_children")
    fileprivate static let fileChildrenText = SQLite.Expression<String?>("file_children")
    fileprivate static let fileKeys   = SQLite.Expression<String?>("file_keys")
    fileprivate static let preferSystem = SQLite.Expression<String?>("prefer_system")
    fileprivate static let preferCore = SQLite.Expression<String?>("prefer_core")
    fileprivate static let preferIcon = SQLite.Expression<String?>("prefer_icon")
    fileprivate static let isHidden   = SQLite.Expression<Bool>("is_hidden")

    fileprivate static let folderInfoTable = SQLite.Table("folderinfo")
    fileprivate static let romInfoTable    = SQLite.Table("rominfo")
    fileprivate static let stateInfoTable  = SQLite.Table("stateinfo")
    fileprivate static let tagInfoTable    = SQLite.Table("taginfo")
    fileprivate static let romTagInfoTable = SQLite.Table("romtaginfo")

    fileprivate static let romTagInfoView  = SQLite.View("romtaginfoview")
    fileprivate static let folderChildrenInfoView = SQLite.View("folderchildreninfoview")

    private static let sqlite = { () -> Connection in
        let romInfoPath = AppConfig.shared.romDatabasePath
        do {
            let db = try Connection(romInfoPath, readonly: false)
            try db.execute("PRAGMA journal_mode = WAL;")
            try db.execute("PRAGMA foreign_keys = ON;")

            // 2. 设置等待时间，防止繁忙时立刻崩溃
            db.busyTimeout = 5.0

            if createTable(db: db) == false {
            #if DEBUG
                fatalError()
            #endif
            }
            return db
        } catch {
            let errMsg = "\(error)"
            fatalError(errMsg)
        }
    }()

    private static func createTable(db: Connection) -> Bool {
        do {
            guard let version = try db.scalar("PRAGMA user_version") as? Int64 else {
                return false
            }

            switch version {
                case 0:
                    try datablseV1(db: db)
                    try db.run("PRAGMA user_version = \(1)")
                    return true
                default:
                    return true
            }
        } catch {
        #if DEBUG
            let errMsg = "\(error)"
            fatalError(errMsg)
        #else
            return false
        #endif
        }
    }

    private static func datablseV1(db: Connection) throws {
        try db.run(Self.folderInfoTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
            t.column(Self.key, primaryKey: true)
            t.column(Self.rawName)
            t.column(Self.showName)
            t.column(Self.parent)
            t.column(Self.createAt)
            t.column(Self.updateAt)
            t.column(Self.preferSystem)
            t.column(Self.preferCore)
            t.column(Self.preferIcon)

            t.foreignKey(Self.parent, references: Self.folderInfoTable, Self.key, delete: .restrict)
        }))
        try db.run(Self.folderInfoTable.createIndex(Self.parent, unique: false, ifNotExists: true))

        try db.run(Self.romInfoTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
            t.column(Self.key, primaryKey: true)
            t.column(Self.rawName)
            t.column(Self.showName)
            t.column(Self.parent)
            t.column(Self.createAt)
            t.column(Self.updateAt)
            t.column(Self.fileSize)
            t.column(Self.sha256)
            t.column(Self.lastPlayAt)
            t.column(Self.playTime)
            t.column(Self.preferSystem)
            t.column(Self.preferCore)
            t.column(Self.preferIcon)

            t.foreignKey(Self.parent, references: Self.folderInfoTable, Self.key, delete: .restrict)
        }))
        try db.run(Self.romInfoTable.createIndex(Self.parent, unique: false, ifNotExists: true))

        try db.run(Self.folderInfoTable.insert(or: .replace,
            Self.key <- "root",
            Self.rawName <- "root",
            Self.showName <- "Retro Go",
            Self.parent <- "root",
            Self.createAt <- Date(),
            Self.updateAt <- Date(),
            Self.preferSystem <- nil,
            Self.preferCore <- nil,
            Self.preferIcon <- nil,
        ))

        try db.run(Self.stateInfoTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
            t.column(Self.rawName)
            t.column(Self.coreId)
            t.column(Self.showName)
            t.column(Self.romKey)
            t.column(Self.sha256)
            t.column(Self.createAt)
            t.foreignKey(Self.romKey, references: Self.romInfoTable, Self.key, delete: .restrict)
            t.primaryKey(Self.rawName, Self.coreId)
        }))
        try db.run(Self.stateInfoTable.createIndex(Self.rawName, ifNotExists: true))
        try db.run(Self.stateInfoTable.createIndex(Self.createAt, ifNotExists: true))

        try db.run(Self.tagInfoTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
            t.column(Self.id, primaryKey: true)
            t.column(Self.title)
            t.column(Self.colorArgb)
            t.column(Self.createAt)
            t.column(Self.isHidden, defaultValue: false)
        }))

        for i in 1 ..< 8 {
            try db.run(
                Self.tagInfoTable.insert(or: .replace,
                    Self.id <- i,
                    Self.title <- nil,
                    Self.colorArgb <- nil,
                    Self.createAt <- Date()
                )
            )
        }

        try db.run(Self.romTagInfoTable.create(temporary: false, ifNotExists: true, withoutRowid: true, block: { t in
            t.column(Self.key)
            t.column(Self.id)
            t.column(Self.createAt)
            t.primaryKey(Self.key, Self.id)
            t.foreignKey(Self.key, references: Self.romInfoTable, Self.key, delete: .cascade)
            t.foreignKey(Self.id, references: Self.tagInfoTable, Self.id, delete: .cascade)
        }))
        try db.run(Self.romTagInfoTable.createIndex(Self.key, ifNotExists: true))
        try db.run(Self.romTagInfoTable.createIndex(Self.id, ifNotExists: true))

        let romTagInfoViewSql = """
            CREATE VIEW IF NOT EXISTS romtaginfoview AS
                SELECT 
                    rominfo.key AS key,
                    rominfo.raw_name AS raw_name,
                    rominfo.show_name AS show_name,
                    rominfo.parent AS parent,
                    rominfo.create_at AS create_at,
                    rominfo.update_at AS update_at,
                    rominfo.file_size AS file_size,
                    rominfo.sha256 AS sha256,
                    rominfo.last_play_at AS last_play_at,
                    rominfo.play_time AS play_time,
                    rominfo.prefer_system AS prefer_system,
                    rominfo.prefer_core AS prefer_core,
                    rominfo.prefer_icon AS prefer_icon,
                    GROUP_CONCAT(romtaginfo.id) AS tag_ids_text
                FROM rominfo
                LEFT JOIN romtaginfo ON rominfo.key = romtaginfo.key
                GROUP BY rominfo.key;
            """
        try db.run(romTagInfoViewSql)

        let folderChildrenInfoViewSql = """
            CREATE VIEW IF NOT EXISTS folderchildreninfoview AS
                SELECT 
                    folderinfo.key AS key,
                    folderinfo.raw_name AS raw_name,
                    folderinfo.show_name AS show_name,
                    folderinfo.parent AS parent,
                    folderinfo.create_at AS create_at,
                    folderinfo.update_at AS update_at,
                    folderinfo.prefer_system AS prefer_system,
                    folderinfo.prefer_core AS prefer_core,
                    folderinfo.prefer_icon AS prefer_icon,
                    GROUP_CONCAT(folders.key, '|') AS folder_children,
                    GROUP_CONCAT(roms.key, '|') AS file_children
                FROM folderinfo
                LEFT JOIN folderinfo AS folders ON folders.parent = folderinfo.key AND folders.key != 'root'
                LEFT JOIN rominfo AS roms ON roms.parent = folderinfo.key
                GROUP BY folderinfo.key;
            """
        try db.run(folderChildrenInfoViewSql)

        try db.run("PRAGMA user_version = \(1)")
    }
}

extension RetroRomFolderItem {
    var insert: SQLite.Insert {
        RetroRomFileManager.folderInfoTable.insert(
            RetroRomFileManager.key      <- key,
            RetroRomFileManager.rawName  <- rawName,
            RetroRomFileManager.showName <- showName,
            RetroRomFileManager.parent   <- parent,
            RetroRomFileManager.createAt <- createAt,
            RetroRomFileManager.updateAt <- updateAt,
            RetroRomFileManager.preferSystem <- preferSystem,
            RetroRomFileManager.preferCore <- preferCore,
            RetroRomFileManager.preferIcon <- preferIcon,
        )
    }
}

extension RetroRomFileItem {
    var insert: SQLite.Insert {
        RetroRomFileManager.romInfoTable.insert(
            RetroRomFileManager.key        <- key,
            RetroRomFileManager.rawName    <- rawName,
            RetroRomFileManager.showName   <- showName,
            RetroRomFileManager.parent     <- parent,
            RetroRomFileManager.createAt   <- createAt,
            RetroRomFileManager.updateAt   <- updateAt,
            RetroRomFileManager.fileSize   <- fileSize,
            RetroRomFileManager.sha256     <- sha256,
            RetroRomFileManager.lastPlayAt <- lastPlayAt,
            RetroRomFileManager.playTime   <- playTime,
            RetroRomFileManager.preferSystem <- preferSystem,
            RetroRomFileManager.preferCore <- preferCore,
            RetroRomFileManager.preferIcon <- preferIcon,
        )
    }
}

extension RetroRomGameStateItem {
    var insert: SQLite.Insert {
        RetroRomFileManager.stateInfoTable.insert(or: .replace,
            RetroRomFileManager.rawName  <- rawName,
            RetroRomFileManager.coreId   <- coreId,
            RetroRomFileManager.showName <- showName,
            RetroRomFileManager.romKey   <- romKey,
            RetroRomFileManager.sha256   <- sha256,
            RetroRomFileManager.createAt <- createAt,
        )
    }
}

extension RetroRomFileTag {
    var insert: SQLite.Insert {
        RetroRomFileManager.tagInfoTable.insert(or: .replace,
            RetroRomFileManager.id <- id,
            RetroRomFileManager.title <- title,
            RetroRomFileManager.colorArgb <- color,
            RetroRomFileManager.createAt <- createAt,
            RetroRomFileManager.isHidden <- isHidden,
        )
    }
}
