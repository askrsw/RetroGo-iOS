//
//  RetroRomBaseItem.swift
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

enum RetroRomType {
    case none
    case folder, file
}

class RetroRomBaseItem: NSObject, RetroRomArraySortFunction {
    let key: String
    private(set) var rawName: String
    private(set) var showName: String?
    private(set) var parent: String
    let createAt: Date
    private(set) var updateAt: Date
    private(set) var preferCore:String?
    private(set) var preferIcon: String?

    @objc
    dynamic var pulseText: Bool = false

    @objc
    dynamic var pulseImage: Bool = false

    init(key: String, rawName: String, showName: String?, parent: String, createAt: Date, updateAt: Date, preferCore: String?, preferIcon: String?) {
        self.key      = key
        self.rawName  = rawName
        self.showName = showName
        self.parent   = parent
        self.createAt = createAt
        self.updateAt = updateAt
        self.preferCore = preferCore
        self.preferIcon = preferIcon
    }

    var playedTime: Int? {
        nil
    }

    var isFile: Bool {
        self is RetroRomFileItem
    }

    var isFolder: Bool {
        self is RetroRomFolderItem
    }

    var itemName: String {
        if let item = self as? RetroRomFolderItem, item.isRoot {
            return Bundle.localizedString(forKey: "homepage_root_folder")
        } else {
            return showName ?? rawName
        }
    }

    var itemPageTitle: String {
        showName ?? rawName
    }

    private var _latinFileName: String?
    var latinFileName: String {
        if _latinFileName == nil {
            let name = NSMutableString(string: itemName) as CFMutableString

            // 将阿拉伯语字符转换为拉丁字母
            CFStringTransform(name, nil, kCFStringTransformToLatin, false)

            // 将字符串转换为小写
            CFStringTransform(name, nil, kCFStringTransformStripDiacritics, false)

            _latinFileName = (name as String).lowercased()
        }
        return _latinFileName!
    }

    var retroRomType: RetroRomType {
        if self.isFolder {
            return .folder
        } else if self.isFile {
            return .file
        } else {
            return .none
        }
    }

    var thumbnail: UIImage? {
        nil
    }

    var lastPlayDate: Date? {
        nil
    }

    var parentFolderItem: RetroRomFolderItem? {
        RetroRomFileManager.shared.folderItem(key: parent)
    }

    var fullPath: String? {
        if let folder = self as? RetroRomFolderItem, folder.isRoot {
            return AppConfig.shared.romFolderPath
        } else if let parentFolder = parentFolderItem {
            if let parentPath = parentFolder.fullPath {
                return parentPath + rawName + (isFolder ? "/" : "")
            } else {
                return nil
            }
        } else {
            return nil
        }
    }

    var  inheritedPreferCore: String? {
        if let core = preferCore {
            return core
        } else if key == "root" {
            return nil
        } else {
            return parentFolderItem?.inheritedPreferCore
        }
    }

    var exists: Bool {
        if let fullPath = fullPath {
            return FileManager.default.fileExists(atPath: fullPath)
        } else {
            return false
        }
    }

    var createAtFullString: String {
        getDateFullString(createAt)
    }

    var createAtSimpleString: String {
        getDateSimpleString(createAt)
    }

    func updateShowName(_ name: String) -> Bool {
        if Retro​Rom​Persistence.shared.updateShowName(name, key: key, isFolder: isFolder) {
            showName = name
            pulseText = !pulseText
            return true
        } else {
            return false
        }
    }

    func delete(path: String, indicatorView: RetroRomActivityView) -> Bool {
        false
    }

    func moveToFolder(_ folder: String) -> Bool {
        if Retro​Rom​Persistence.shared.updateItemParent(folder, key: key, isFolder: isFolder) {
            let parentFolderItem = self.parentFolderItem
            if self.isFile {
                parentFolderItem?.removeSubFileItemKey(key)
            } else if self.isFolder {
                parentFolderItem?.removeSubFolderItemKey(key)
            }
            parent = folder
            return true
        } else {
            return false
        }
    }

    func assignCore(_ core: EmuCoreInfoItem) -> Bool {
        guard preferCore != core.coreId else { return true }

        let result: Bool
        if isFolder {
            result = Retro​Rom​Persistence.shared.updateFolderPreferCore(key: key, core: core.coreId)
        } else if isFile {
            result = Retro​Rom​Persistence.shared.updateFilePreferCore(key: key, core: core.coreId)
        } else {
            result = false
        }
        
        if result {
            preferCore = core.coreId
            return true
        } else {
            return false
        }
    }

    func isDescendant(of folderKey: String) -> Bool {
        var tmpKey = parent
        while tmpKey != "root" {
            if tmpKey == folderKey {
                return true
            }

            if let k = RetroRomFileManager.shared.folderItem(key: tmpKey)?.parent {
                tmpKey = k
            } else {
                break
            }
        }
        return false
    }
}

extension RetroRomBaseItem {
    func getDateFullString(_ date: Date) -> String {
        switch Bundle.currentSimpleLanguageKey() {
            case "zh":
                return DateFormatter.cnFull().string(from: date)
            case "en":
                return DateFormatter.enFull().string(from: date)
            default:
                return DateFormatter.enFull().string(from: date)
        }
    }

    func getDateSimpleString(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return DateFormatter.hhColonMm().string(from: date)
        }

        if Calendar.current.isDateInYesterday(date) {
            return "\(Bundle.localizedString(forKey: "homepage_yesterday"))"
        }

        let languageKey = Bundle.currentSimpleLanguageKey()
        let isDayBeforeYesterday = (Calendar.current as NSCalendar).isDateInDay(beforeYesterday: date)
        if languageKey == "zh" && isDayBeforeYesterday {
            return "\(Bundle.localizedString(forKey: "homepage_beforeyesterday"))"
        }

        switch languageKey {
            case "zh":
                return DateFormatter.cnSimple().string(from: date)
            case "en":
                return DateFormatter.enSimple().string(from: date)
            default:
                return DateFormatter.enSimple().string(from: date)
        }
    }
}

protocol RetroRomArraySortFunction {
    var itemName: String { get }
    var latinFileName: String { get }
    var createAt: Date { get }
    var lastPlayDate: Date? { get }
    var isFile: Bool { get }
    var playedTime: Int? { get }
}

extension Array where Element: RetroRomArraySortFunction {
    mutating func sortByFileNameAsc() {
        self.sort { item1, item2 in
            let isItem1FirstCharAlphabet = item1.itemName.isFirstCharacterASCII
            let isItem2FirstCharAlphabet = item2.itemName.isFirstCharacterASCII
            if isItem1FirstCharAlphabet && !isItem2FirstCharAlphabet {
                return true
            } else if !isItem1FirstCharAlphabet && isItem2FirstCharAlphabet {
                return false
            } else {
                return item1.latinFileName < item2.latinFileName
            }
        }
    }

    mutating func sortByFileNameAscFolderFirst() {
        self.sort { item1, item2 in
            if (!item1.isFile && !item2.isFile) || (item1.isFile && item2.isFile) {
                let isItem1FirstCharAlphabet = item1.itemName.isFirstCharacterASCII
                let isItem2FirstCharAlphabet = item2.itemName.isFirstCharacterASCII
                if isItem1FirstCharAlphabet && !isItem2FirstCharAlphabet {
                    return true
                } else if !isItem1FirstCharAlphabet && isItem2FirstCharAlphabet {
                    return false
                } else {
                    return item1.latinFileName < item2.latinFileName
                }
            } else if !item1.isFile {
                return true
            } else {
                return false
            }
        }
    }

    mutating func sortByFileNameDesc() {
        self.sort { item1, item2 in
            let isItem1FirstCharAlphabet = item1.itemName.isFirstCharacterASCII
            let isItem2FirstCharAlphabet = item2.itemName.isFirstCharacterASCII
            if isItem1FirstCharAlphabet && !isItem2FirstCharAlphabet {
                return false
            } else if !isItem1FirstCharAlphabet && isItem2FirstCharAlphabet {
                return true
            } else {
                return item1.latinFileName >= item2.latinFileName
            }
        }
    }

    mutating func sortByFileNameDescFolderFirst() {
        self.sort { item1, item2 in
            if (!item1.isFile && !item2.isFile) || (item1.isFile && item2.isFile) {
                let isItem1FirstCharAlphabet = item1.itemName.isFirstCharacterASCII
                let isItem2FirstCharAlphabet = item2.itemName.isFirstCharacterASCII
                if isItem1FirstCharAlphabet && !isItem2FirstCharAlphabet {
                    return false
                } else if !isItem1FirstCharAlphabet && isItem2FirstCharAlphabet {
                    return true
                } else {
                    return item1.latinFileName >= item2.latinFileName
                }
            } else if !item1.isFile {
                return true
            } else {
                return false
            }
        }
    }

    mutating func sortByCreateDateAsc() {
        self.sort { $0.createAt < $1.createAt }
    }

    mutating func sortByCreateDateAscFolderFirst() {
        self.sort { item1, item2 in
            if (!item1.isFile && !item2.isFile) || (item1.isFile && item2.isFile) {
                return item1.createAt < item2.createAt
            } else if !item1.isFile {
                return true
            } else {
                return false
            }
        }
    }

    mutating func sortByCreateDateDesc() {
        self.sort { $0.createAt >= $1.createAt }
    }

    mutating func sortByCreateDateDescFolderFirst() {
        self.sort { item1, item2 in
            if (!item1.isFile && !item2.isFile) || (item1.isFile && item2.isFile) {
                return item1.createAt >= item2.createAt
            } else if !item1.isFile {
                return true
            } else {
                return false
            }
        }
    }

    mutating func sortByLastPlayAt() {
        self.sort { item1, item2 in
            if item1.isFile && item2.isFile {
                if let date1 = item1.lastPlayDate, let date2 = item2.lastPlayDate {
                    return date1 > date2
                } else if item1.lastPlayDate != nil {
                    return true
                } else if item2.lastPlayDate != nil {
                    return false
                } else {
                    return item1.latinFileName < item2.latinFileName
                }
            } else if item1.isFile {
                return true
            } else if item2.isFile {
                return false
            } else {
                return item1.latinFileName < item2.latinFileName
            }
        }
    }

    mutating func sortByLastPlayAtFolderFirst() {
        self.sort { item1, item2 in
            if item1.isFile && item2.isFile {
                if let date1 = item1.lastPlayDate, let date2 = item2.lastPlayDate {
                    return date1 > date2
                } else if item1.lastPlayDate != nil {
                    return true
                } else if item2.lastPlayDate != nil {
                    return false
                } else {
                    return item1.latinFileName < item2.latinFileName
                }
            } else if !item1.isFile {
                return true
            } else if !item2.isFile {
                return false
            } else {
                return item1.latinFileName < item2.latinFileName
            }
        }
    }

    mutating func sortByPlayTime() {
        self.sort { item1, item2 in
            if let time1 = item1.playedTime, let time2 = item2.playedTime {
                return time1 > time2
            } else if item1.isFile {
                return true
            } else if item2.isFile {
                return false
            } else {
                return item1.latinFileName < item2.latinFileName
            }
        }
    }

    mutating func sortByPlayTimeFolderFirst() {
        self.sort { item1, item2 in
            if let time1 = item1.playedTime, let time2 = item2.playedTime {
                return time1 > time2
            } else if !item1.isFile {
                return true
            } else if !item2.isFile {
                return false
            } else {
                return item1.latinFileName < item2.latinFileName
            }
        }
    }
}

extension String {
    fileprivate var isFirstCharacterASCII: Bool {
        guard let first = self.first else { return false }
        return first.isASCII
    }
}
