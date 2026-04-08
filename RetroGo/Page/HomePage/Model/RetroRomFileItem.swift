//
//  RetroRomFileItem.swift
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
import SQLite
import ObjcHelper
import RACoordinator

enum RetroRomFileGroupType: String, Value {
    case single = "single"
    case cue = "cue"
    case mds = "mds"
    case m3u = "m3u"
    case gdi = "gdi"
    case ccd = "ccd"

    // 1. Define the underlying storage data type (String corresponds to String.Datatype, which is TEXT in SQLite)
    static var declaredDatatype: String {
        return String.declaredDatatype
    }

    // 2. Read from Database: Convert the stored String back into the enum type
    static func fromDatatypeValue(_ datatypeValue: String) -> RetroRomFileGroupType {
        // Fallback to .single if the value in the database is invalid or unrecognized
        return RetroRomFileGroupType(rawValue: datatypeValue) ?? .single
    }

    // 3. Write to Database: Convert the enum instance into its String rawValue for storage
    var datatypeValue: String {
        return rawValue
    }
}

enum RetroRomFileSubRole: String, Value {
    case entry
    case resource
    case disc
    case track
    case descriptor

    static var declaredDatatype: String {
        return String.declaredDatatype
    }

    static func fromDatatypeValue(_ datatypeValue: String) -> RetroRomFileSubRole {
        return RetroRomFileSubRole(rawValue: datatypeValue) ?? .entry
    }

    var datatypeValue: String {
        return rawValue
    }
}

final class RetroRomFileSubItem {
    let key: String
    let rawName: String
    let fileRole: RetroRomFileSubRole
    let sha256: String
    let fileSize: Int
    let sortIndex: Int

    init(key: String, rawName: String, fileRole: RetroRomFileSubRole, sha256: String, fileSize: Int, sortIndex: Int) {
        self.key = key
        self.rawName = rawName
        self.fileRole = fileRole
        self.sha256 = sha256
        self.fileSize = fileSize
        self.sortIndex = sortIndex
    }
}

final class RetroRomFileItem: RetroRomBaseItem {
    let fileSize: Int
    let sha256: String?
    private(set) var lastPlayAt: Date?
    private(set) var playTime: Int
    private(set) var tagIdArray: [Int]
    private(set) var fileGroupType: RetroRomFileGroupType
    private(set) var subItems: [RetroRomFileSubItem]

    init(key: String, rawName: String, showName: String? = nil, parent: String, createAt: Date, updateAt: Date, preferCore: String? = nil, preferIcon: String? = nil, fileSize: Int, sha256: String?, lastPlayAt: Date? = nil,  playTime: Int = 0, tagIdArray: [Int] = [], fileGroupType: RetroRomFileGroupType = .single, subItems: [RetroRomFileSubItem] = []) {
        self.fileSize   = fileSize
        self.sha256     = sha256
        self.lastPlayAt = lastPlayAt
        self.playTime   = playTime
        self.tagIdArray = tagIdArray
        self.fileGroupType = fileGroupType
        self.subItems = subItems
        super.init(key: key, rawName: rawName, showName: showName, parent: parent, createAt: createAt, updateAt: updateAt, preferCore: preferCore, preferIcon: preferIcon)
    }

    override var lastPlayDate: Date? {
        lastPlayAt
    }

    override var playedTime: Int? {
        playTime
    }

    override var thumbnail: UIImage? {
        let path = AppConfig.shared.sharedAutoThumbnailFolderPath + "auto_\(sha256 ?? "").png"
        return UIImage(contentsOfFile: path)
    }

    var lastPlayAtFullString: String {
        guard let date = lastPlayAt else {
            return "-"
        }

        return getDateFullString(date)
    }

    var lastPlayAtSimpleString: String {
        if let date = lastPlayAt {
            return getDateSimpleString(date)
        } else {
            return "-"
        }
    }

    var playTimeString: String {
        switch playTime {
            case 0:
                return "-"
            case 1 ..< 60:
                return "\(playTime) \(Bundle.localizedString(forKey: "homepage_second"))"
            case 60 ..< 3600:
                let m = playTime / 60
                return "\(m) \(Bundle.localizedString(forKey: "homepage_minute"))"
            default:
                let h = playTime / 3600
                let m = (playTime - h * 3600) / 60
                if m == 0 {
                    return "\(h) \(Bundle.localizedString(forKey: "homepage_hour"))"
                } else {
                    return "\(h) \(Bundle.localizedString(forKey: "homepage_hour")) \(m) \(Bundle.localizedString(forKey: "homepage_minute"))"
                }
        }
    }

    var fileSizeString: String? {
        formatFileSize(fileSize)
    }

    override var baseName: String {
        if fileGroupType == .single {
            return super.baseName
        } else {
            return ((rawName as NSString).lastPathComponent as NSString).deletingPathExtension
        }
    }

    override var fullPath: String? {
        guard let parentPath = parentFolderItem?.fullPath else {
            return nil
        }

        if fileGroupType == .single {
            return parentPath + rawName
        } else {
            return "\(parentPath)\(baseName)/"
        }
    }

    var entryPath: String? {
        guard let fullPath else {
            return nil
        }

        if fileGroupType == .single {
            return fullPath
        } else {
            let entryName = subItems.first(where: { $0.fileRole == .entry })?.rawName ?? rawName
            return fullPath + entryName
        }
    }

    override func delete(path: String, indicatorView: RetroRomActivityView) -> Bool {
        let title = Bundle.localizedString(forKey: "homepage_delete_deleting")
        let filePath = (path.count > 0 ? path + "/" : "") + itemName
        let message = Bundle.localizedString(forKey: "homepage_delete_file") + filePath
        indicatorView.activeMessage(message, title: title)

        if !RetroRomFileManager.shared.deleteGameStateItem(key) {
            let message = String(format: Bundle.localizedString(forKey: "homepage_delete_item_failed"), filePath)
            indicatorView.errorMessage(message, title: Bundle.localizedString(forKey: "error"), canDismiss: true)
            return false
        }

        guard let fullPath = self.fullPath else {
            let message = String(format: Bundle.localizedString(forKey: "homepage_delete_item_failed"), filePath)
            indicatorView.errorMessage(message, title: Bundle.localizedString(forKey: "error"), canDismiss: true)
            return false
        }

        do {
            try FileManager.default.removeItem(atPath: fullPath)
        } catch {
            print("Failed to delete rom file: \(rawName) for item: \(itemName), error: \(error)")
            let message = String(format: Bundle.localizedString(forKey: "homepage_delete_item_failed"), filePath)
            indicatorView.errorMessage(message, title: Bundle.localizedString(forKey: "error"), canDismiss: true)
            return false
        }

        if !RetroRomFileManager.shared.deleteFileItem(key) {
            let message = String(format: Bundle.localizedString(forKey: "homepage_delete_item_failed"), filePath)
            indicatorView.errorMessage(message, title: Bundle.localizedString(forKey: "error"), canDismiss: true)
            return false
        }

        parentFolderItem?.removeSubFileItemKey(key)
        let thumbnailPath = AppConfig.shared.sharedAutoThumbnailFolderPath + key + ".jpg"
        try? FileManager.default.removeItem(atPath: thumbnailPath)
        return true
    }

    override func assignCore(_ core: EmuCoreInfoItem) -> Bool {
        let oldCore = inheritedPreferCore
        if super.assignCore(core) {
            let new = core.coreId
            if oldCore != new {
                let ext = entryFileExtension
                let coresFromExt = RetroRomCoreManager.shared.getExtOpenCores(ext: ext)
                var info: [String: String] = [:]
                if let old = oldCore, !coresFromExt.contains(where: { $0.coreId == old }) {
                    info["old"] = old
                }
                if !coresFromExt.contains(where: { $0.coreId == new }) {
                    info["new"] = new
                }
                if info.count > 0 {
                    NotificationCenter.default.post(name: .fileCoreAssigned, object: self, userInfo: info)
                }
            }
            return true
        } else {
            return false
        }
    }

    func updateLastPlayAt() {
        let now = Date()
        if Retro​Rom​Persistence.shared.updateLastPlayAt(key: key, date: now) {
            lastPlayAt = now
            pulseText = !pulseText
        }
    }

    func updatePlayTime(seconds: Int) {
        if Retro​Rom​Persistence.shared.updatePlayTime(key: key, seconds: playTime + seconds) {
            playTime += seconds
            pulseText = !pulseText
        }
    }

    @discardableResult
    func updateFileTags(_ newTags: Set<Int>, oldTags: Set<Int>) -> Bool {
        let added = newTags.subtracting(oldTags)
        let removed = oldTags.subtracting(newTags)

        if added.count > 0 || removed.count > 0 {
            let ret = Retro​Rom​Persistence.shared.updateRetroFileTags(romKey: key, addedTags: added, removedTags: removed)
            tagIdArray = Array(newTags).sorted()
            pulseText = !pulseText
            NotificationCenter.default.post(name: .fileTagFileChanged, object: self, userInfo: ["added": added, "removed": removed])
            return ret
        } else {
            return true
        }
    }

    func removeFileTag(id: Int) {
        if tagIdArray.contains(id) {
            tagIdArray.removeAll(where: { $0 == id })
            pulseText = !pulseText
        }
    }

    func getSupportedCoresByExtension() -> [EmuCoreInfoItem] {
        let suffix: String
        if let str = (showName as? NSString)?.pathExtension, str.count > 0 {
            suffix = str.lowercased()
        } else {
            suffix = entryFileExtension
        }
        return RetroRomCoreManager.shared.getExtOpenCores(ext: suffix)
    }

    func getSupportedCores() -> [EmuCoreInfoItem] {
        let cores = getSupportedCoresByExtension()
        if let c = inheritedPreferCore, !cores.contains(where: { $0.coreId == c }), let core = RetroRomCoreManager.shared.core(c) {
            return [core] + cores
        } else {
            return cores
        }
    }
}

extension RetroRomFileItem {
    private var entryFileExtension: String {
        if fileGroupType == .single {
            return (rawName as NSString).pathExtension.lowercased()
        }
        return (subItems.first(where: { $0.fileRole == .entry })?.rawName as? NSString)?.pathExtension.lowercased() ?? (rawName as NSString).pathExtension.lowercased()
    }

    private func formatFileSize(_ size: Int) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var fileSize = Double(size)
        var unitIndex = 0

        while fileSize >= 1024 && unitIndex < units.count - 1 {
            fileSize /= 1024
            unitIndex += 1
        }

        return String(format: "%.2f %@", fileSize, units[unitIndex])
    }
}

final class RetroRomFileItemWrapper: Hashable {
    static let uncategorizedKey = "0"

    let index: Int64
    let item: RetroRomFileItem
    let tag: RetroRomFileTag?
    let core: EmuCoreInfoItem?

    init(item: RetroRomFileItem, tag: RetroRomFileTag?) {
        self.index = RetroRomFileItemWrapper.indexQueue.sync {
            let current = RetroRomFileItemWrapper.index
            RetroRomFileItemWrapper.index += 1
            return current
        }
        self.item = item
        self.tag  = tag
        self.core = nil
    }

    init(item: RetroRomFileItem, core: EmuCoreInfoItem?) {
        self.index = RetroRomFileItemWrapper.indexQueue.sync {
            let current = RetroRomFileItemWrapper.index
            RetroRomFileItemWrapper.index += 1
            return current
        }
        self.item = item
        self.core = core
        self.tag  = nil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(index)
    }

    static func == (lhs: RetroRomFileItemWrapper, rhs: RetroRomFileItemWrapper) -> Bool {
        lhs.index == rhs.index
    }

    private static var index: Int64 = 1
    private static let indexQueue = DispatchQueue(label: "com.haharsw.pudge.file_wraper.index_quene")
}

extension RetroRomFileItemWrapper: RetroRomArraySortFunction {
    var itemName: String {
        item.itemName
    }

    var latinFileName: String {
        item.latinFileName
    }

    var createAt: Date {
        item.createAt
    }

    var lastPlayDate: Date? {
        item.lastPlayDate
    }

    var isFile: Bool {
        item.isFile
    }

    var playedTime: Int? {
        item.playedTime
    }
}
