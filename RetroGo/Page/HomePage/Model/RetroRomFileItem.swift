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
import ObjcHelper
import RACoordinator

final class RetroRomFileItem: RetroRomBaseItem {
    let fileSize: Int
    let sha256: String?
    private(set) var lastPlayAt: Date?
    private(set) var playTime: Int

    private(set) var tagIdArray: [Int]

    init(key: String, rawName: String, showName: String? = nil, parent: String, createAt: Date, updateAt: Date, preferCore: String? = nil, preferIcon: String? = nil, fileSize: Int, sha256: String?, lastPlayAt: Date? = nil,  playTime: Int = 0, tagIdArray: [Int] = []) {
        self.fileSize   = fileSize
        self.sha256     = sha256
        self.lastPlayAt = lastPlayAt
        self.playTime   = playTime
        self.tagIdArray = tagIdArray
        super.init(key: key, rawName: rawName, showName: showName, parent: parent, createAt: createAt, updateAt: updateAt, preferCore: preferCore, preferIcon: preferIcon)
    }

    override var lastPlayDate: Date? {
        lastPlayAt
    }

    override var playedTime: Int? {
        playTime
    }

    override var thumbnail: UIImage? {
        let path = AppConfig.shared.sharedAutoThumnailFolderPath + "auto_\(sha256 ?? "").png"
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

    override func delete(path: String, indicatorView: RetroRomActivityView) -> Bool {
        let title = Bundle.localizedString(forKey: "homepage_delete_deleting")
        let filePath = (path.count > 0 ? path + "/" : "") + itemName
        let message = Bundle.localizedString(forKey: "homepage_delete_file") + filePath
        indicatorView.activeMessage(message, title: title)

        RetroRomFileManager.shared.deleteGameStateItem(key)

        if RetroRomFileManager.shared.deleteFileItem(key) {
            parentFolderItem?.removeSubFileItemKey(key)
            let thumbnailPath = AppConfig.shared.sharedAutoThumnailFolderPath + key + ".jpg"
            try? FileManager.default.removeItem(atPath: thumbnailPath)
            if let fullPath = self.fullPath {
                do {
                    try FileManager.default.removeItem(atPath: fullPath)
                } catch {
                    print("Failed to delete rom file: \(rawName) for item: \(itemName)")
                }
            }
            return true
        } else {
            let message = String(format: Bundle.localizedString(forKey: "homepage_delete_item_failed"), filePath)
            indicatorView.errorMessage(message, title: Bundle.localizedString(forKey: "error"), canDismiss: true)
            return false
        }
    }

    override func assignCore(_ core: EmuCoreInfoItem) -> Bool {
        let oldCore = inheritedPreferCore
        if super.assignCore(core) {
            let new = core.coreId
            if oldCore != new {
                let ext = (rawName as NSString).pathExtension.lowercased()
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
            suffix = (rawName as NSString).pathExtension.lowercased()
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
