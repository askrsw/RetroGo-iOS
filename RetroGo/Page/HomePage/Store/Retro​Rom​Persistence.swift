//
//  Retro​Rom​Persistence.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/3.
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
import Foundation
import ObjcHelper

final class Retro​Rom​Persistence {
    static let shared = Retro​Rom​Persistence()
    private init() {
        _ = Retro​Rom​Persistence.sqlite
    }

    // MARK: - Rom File and Rom Folder Stuff

    func deleteFolderItem(_ key: String) -> Bool {
        do {
            let db = Self.sqlite
            let alice = Self.romFolderTable.filter(Self.key == key)
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
            let db = Self.sqlite
            let alice1 = Self.romGameFileTable.filter(Self.key == key)
            let alice2 = Self.romGameTable.filter(Self.key == key)
            try db.transaction {
                try db.run(alice1.delete())
                try db.run(alice2.delete())
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

    func getFolderCount() -> Int? {
        do {
            let db = Self.sqlite
            let alice = Self.romFolderTable.where(Self.key != "root")
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
            let count = try db.scalar(Self.romGameTable.count)
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

    func getFileItems(parent: String) -> [RetroRomFileItem]? {
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
                    preferCore: row[Self.preferCore],
                    preferIcon: row[Self.preferIcon],
                    fileSize: row[Self.fileSize],
                    sha256: row[Self.sha256],
                    lastPlayAt: row[Self.lastPlayAt],
                    playTime: row[Self.playTime],
                    tagIdArray: parseTagIds(row[Self.tagIdsText]),
                    fileGroupType: row[Self.fileGroupType],
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

    func getFileItems(in keys: [String]) -> [RetroRomFileItem]? {
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
                        preferCore: row[Self.preferCore],
                        preferIcon: row[Self.preferIcon],
                        fileSize: row[Self.fileSize],
                        sha256: row[Self.sha256],
                        lastPlayAt: row[Self.lastPlayAt],
                        playTime: row[Self.playTime],
                        tagIdArray: parseTagIds(row[Self.tagIdsText]),
                        fileGroupType: row[Self.fileGroupType],
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

    func getFolderItems(parent: String) -> [RetroRomFolderItem]? {
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

    func getFolderItems(in keys: [String]) -> [RetroRomFolderItem]? {
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

    func getFileItem(key: String) -> RetroRomFileItem? {
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
                    preferCore: row[Self.preferCore],
                    preferIcon: row[Self.preferIcon],
                    fileSize: row[Self.fileSize],
                    sha256: row[Self.sha256],
                    lastPlayAt: row[Self.lastPlayAt],
                    playTime: row[Self.playTime],
                    tagIdArray: parseTagIds(row[Self.tagIdsText]),
                    fileGroupType: row[Self.fileGroupType],
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

    func getUntagFileItemKeys() -> Set<String>? {
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

    func getAllFileItemKeys() -> Set<String>? {
        do {
            let db = Self.sqlite
            let alice = Self.romGameTable.select(Self.key)
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

    func getFolderItem(key: String) -> RetroRomFolderItem? {
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

    func getFolderItem(parent: String, rawName: String) -> RetroRomFolderItem? {
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
            let alice1 = Self.romFolderTable.where(Self.parent == folderKey).select(Self.key)
            var subFolderKeys = Set<String>()
            for row in try db.prepare(alice1) {
                let key = row[Self.key]
                subFolderKeys.insert(key)
            }
            if folderKey == "root" {
                subFolderKeys.remove("root")
            }
            let alice2 = Self.romGameTable.where(Self.parent == folderKey).select(Self.key)
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

    func storeRomFiles(_ files: [RetroRomFileItem], folders: [RetroRomFolderItem]) -> Bool {
        do {
            let db = Self.sqlite
            try db.transaction {
                for folder in folders {
                    try db.run(folder.insert)
                }
                for file in files {
                    try db.run(file.insert)
                    for sub in file.subItems {
                        try db.run(sub.insert)
                    }
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
                alice = Self.romFolderTable.filter(Self.key == key)
            } else {
                alice = Self.romGameTable.filter(Self.key == key)
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
                alice = Self.romFolderTable.filter(Self.key == key)
            } else {
                alice = Self.romGameTable.filter(Self.key == key)
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
            let alice = Self.romGameTable.filter(Self.key == key)
            let update = alice.update(
                Self.lastPlayAt <- date
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
            let alice = Self.romGameTable.filter(Self.key == key)
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
            let alice = Self.romGameTable.filter(Self.key == key)
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
            let alice = Self.romFolderTable.filter(Self.key == key)
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
                let query1 = Self.romFolderTable.filter(Self.key == key).limit(1)
                if (try db.pluck(query1)) != nil {
                    continue
                }

                let query2 = Self.romGameTable.filter(Self.key == key).limit(1)
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
            let alice = Self.romStateTable.filter(Self.coreId == coreId && Self.sha256 == sha256 && Self.rawName == fileName)
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
                alice = Self.romStateTable.filter(Self.coreId == coreId && Self.sha256 == sha256).order(Self.createAt.desc)
            } else if let coreId = coreId {
                alice = Self.romStateTable.filter(Self.coreId == coreId).order(Self.createAt.desc)
            } else if let sha256 = sha256 {
                alice = Self.romStateTable.filter(Self.sha256 == sha256).order(Self.createAt.desc)
            } else {
                alice = Self.romStateTable.order(Self.createAt.desc)
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
                alice = Self.romStateTable.filter(Self.romKey == romKey).order(Self.createAt.desc)
            } else {
                alice = Self.romStateTable.filter(Self.romKey == romKey)
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
            let alice = Self.romStateTable.filter(Self.coreId == coreId && Self.sha256 == sha256 && Self.rawName == fileName)
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
            let alice = Self.romTagTable.order(Self.id)
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

    func getAllFileTagIDs() -> [Int]? {
        do {
            let db = Self.sqlite
            let alice = Self.romTagTable.order(Self.id)
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
            let alice = Self.romGameTagTable.filter(Self.key == romKey).order(Self.id)
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
                    let alice = Self.romGameTagTable.filter(Self.key == romKey && removedTags.contains(Self.id))
                    try db.run(alice.delete())
                }
                if !addedTags.isEmpty {
                    let insertStatements = addedTags.map { id in
                        Self.romGameTagTable.insert(or: .replace,
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
            let alice = Self.romTagTable.filter(Self.id == id)
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
                let query = Self.romTagTable.where(chunk.contains(Self.id))

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
            if let maxV = try db.scalar(Self.romTagTable.select(Self.id.max)) {
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

    func updateFileTag(id: Int, title: String?, color: Int?) -> Bool {
        do {
            let db = Self.sqlite
            let alice = Self.romTagTable.where(Self.id == id)
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
            let alice = Self.romTagTable.where(Self.id == id)
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
            let sql = "SELECT id, GROUP_CONCAT(key) AS file_keys FROM romgametag GROUP BY id"
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

extension Retro​Rom​Persistence {
    static let key        = SQLite.Expression<String>("key")
    static let parent     = SQLite.Expression<String>("parent")
    static let path       = SQLite.Expression<String>("path")
    static let rawName    = SQLite.Expression<String>("raw_name")
    static let showName   = SQLite.Expression<String?>("show_name")
    static let createAt   = SQLite.Expression<Date>("create_at")
    static let updateAt   = SQLite.Expression<Date>("update_at")
    static let fileSize   = SQLite.Expression<Int>("file_size")
    static let sha256     = SQLite.Expression<String?>("sha256")
    static let lastPlayAt = SQLite.Expression<Date?>("last_play_at")
    static let playTime   = SQLite.Expression<Int>("play_time")
    static let coreId     = SQLite.Expression<String>("core_id")
    static let romKey     = SQLite.Expression<String?>("rom_key")
    static let id         = SQLite.Expression<Int>("id")
    static let title      = SQLite.Expression<String?>("title")
    static let colorArgb  = SQLite.Expression<Int?>("color_argb")
    static let tagIdsText = SQLite.Expression<String?>("tag_ids_text")
    static let folderChildrenText = SQLite.Expression<String?>("folder_children")
    static let fileChildrenText = SQLite.Expression<String?>("file_children")
    static let fileKeys   = SQLite.Expression<String?>("file_keys")
    static let preferCore = SQLite.Expression<String?>("prefer_core")
    static let preferIcon = SQLite.Expression<String?>("prefer_icon")
    static let isHidden   = SQLite.Expression<Bool>("is_hidden")

    static let entryFileKey    = SQLite.Expression<String>("entry_file_key")
    static let fileGroupType   = SQLite.Expression<RetroRomFileGroupType>("file_group_type")
    static let fileRole        = SQLite.Expression<RetroRomFileSubRole>("file_role")
    static let sortIndex       = SQLite.Expression<Int>("sort_index")

    static let romFolderTable   = SQLite.Table("romfolder")
    static let romGameTable     = SQLite.Table("romgame")
    static let romGameFileTable = SQLite.Table("romgamefile")
    static let romTagTable      = SQLite.Table("romtag")
    static let romGameTagTable  = SQLite.Table("romgametag")
    static let romStateTable    = SQLite.Table("romstate")

    static let romTagInfoView   = SQLite.View("romtaginfoview")
    static let folderChildrenInfoView = SQLite.View("folderchildreninfoview")

    static let sqlite = { () -> Connection in
        let romInfoPath = AppConfig.shared.romDatabasePath
        do {
            let db = try Connection(romInfoPath, readonly: false)
            try db.execute("PRAGMA journal_mode = WAL;")
            try db.execute("PRAGMA foreign_keys = ON;")

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
                    try databaseV3(db: db)
                    return true
                case 1:
                    try migrationV1ToV2(db: db)
                    try migrationV2ToV3(db: db)
                    return true
                case 2:
                    try migrationV2ToV3(db: db)
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
}

extension RetroRomFolderItem {
    var insert: SQLite.Insert {
        Retro​Rom​Persistence.romFolderTable.insert(
            Retro​Rom​Persistence.key      <- key,
            Retro​Rom​Persistence.rawName  <- rawName,
            Retro​Rom​Persistence.showName <- showName,
            Retro​Rom​Persistence.parent   <- parent,
            Retro​Rom​Persistence.createAt <- createAt,
            Retro​Rom​Persistence.updateAt <- updateAt,
            Retro​Rom​Persistence.preferCore <- preferCore,
            Retro​Rom​Persistence.preferIcon <- preferIcon,
        )
    }
}

extension RetroRomFileSubItem {
    var insert: SQLite.Insert {
        Retro​Rom​Persistence.romGameFileTable.insert(
            Retro​Rom​Persistence.key <- key,
            Retro​Rom​Persistence.rawName <- rawName,
            Retro​Rom​Persistence.fileRole <- fileRole,
            Retro​Rom​Persistence.sha256 <- sha256,
            Retro​Rom​Persistence.fileSize <- fileSize,
            Retro​Rom​Persistence.sortIndex <- sortIndex
        )
    }
}

extension RetroRomFileItem {
    var insert: SQLite.Insert {
        Retro​Rom​Persistence.romGameTable.insert(
            Retro​Rom​Persistence.key        <- key,
            Retro​Rom​Persistence.entryFileKey <- rawName,
            Retro​Rom​Persistence.showName   <- showName,
            Retro​Rom​Persistence.parent     <- parent,
            Retro​Rom​Persistence.createAt   <- createAt,
            Retro​Rom​Persistence.updateAt   <- updateAt,
            Retro​Rom​Persistence.sha256     <- sha256,
            Retro​Rom​Persistence.lastPlayAt <- lastPlayAt,
            Retro​Rom​Persistence.playTime   <- playTime,
            Retro​Rom​Persistence.preferCore <- preferCore,
            Retro​Rom​Persistence.preferIcon <- preferIcon,
            Retro​Rom​Persistence.fileGroupType <- fileGroupType,
        )
    }
}

extension RetroRomGameStateItem {
    var insert: SQLite.Insert {
        Retro​Rom​Persistence.romStateTable.insert(or: .replace,
            Retro​Rom​Persistence.rawName  <- rawName,
            Retro​Rom​Persistence.coreId   <- coreId,
            Retro​Rom​Persistence.showName <- showName,
            Retro​Rom​Persistence.romKey   <- romKey,
            Retro​Rom​Persistence.sha256   <- sha256,
            Retro​Rom​Persistence.createAt <- createAt,
        )
    }
}

extension RetroRomFileTag {
    var insert: SQLite.Insert {
        Retro​Rom​Persistence.romTagTable.insert(or: .replace,
            Retro​Rom​Persistence.id <- id,
            Retro​Rom​Persistence.title <- title,
            Retro​Rom​Persistence.colorArgb <- color,
            Retro​Rom​Persistence.createAt <- createAt,
            Retro​Rom​Persistence.isHidden <- isHidden,
        )
    }
}
