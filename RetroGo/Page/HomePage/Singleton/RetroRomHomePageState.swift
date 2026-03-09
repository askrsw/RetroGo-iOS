//
//  RetroRomHomePageState.swift
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

import Defaults
import Foundation
import ObjcHelper

final class RetroRomHomePageState {
    static let shared = RetroRomHomePageState()

    private init() {
        self.homeFileSortType = {
            let v: Int = Defaults[.homeFileSortType] ?? 0
            return RetroRomFileSortType(rawValue: v) ?? .fileNameAsc
        }()

        self.homeCurrentFolder = Defaults[.homeCurrentFolder] ?? "root"
        self.homeBrowserType = {
            let v: Int = Defaults[.homeBrowserType] ?? 0
            return RetroRomFileBrowserType(rawValue: v) ?? .icon
        }()
        self.homeOrganizeType = {
            let v: Int = Defaults[.homeOrganizeType] ?? 0
            return RetroRomFileOrganizeType(rawValue: v) ?? .byFolder
        }()
    }

    // MARK: - Runtime State (Requires File Sync)

    var homeFileSortType: RetroRomFileSortType {
        didSet {
            Defaults[.homeFileSortType] = homeFileSortType.rawValue
        }
    }

    var homeCurrentFolder: String {
        didSet {
            Defaults[.homeCurrentFolder] = homeCurrentFolder
        }
    }

    var homeCurrentFolderItem: RetroRomFolderItem {
        if let item = RetroRomFileManager.shared.folderItem(key: homeCurrentFolder) {
            return item
        } else {
            homeCurrentFolder = "root"
            return RetroRomFileManager.shared.folderItem(key: homeCurrentFolder)!
        }
    }

    var homeBrowserType: RetroRomFileBrowserType {
        didSet {
            Defaults[.homeBrowserType] = homeBrowserType.rawValue
        }
    }

    var homeOrganizeType: RetroRomFileOrganizeType {
        didSet {
            Defaults[.homeOrganizeType] = homeOrganizeType.rawValue
        }
    }

    var lastImportDate: Date?

    // MARK: - Runtime State (No File Sync Required)

    var couldShowItemMenu: Bool = true

    var browserMeta: RetroRomFileBrowserMeta {
        switch homeBrowserType {
            case .icon:
                return .iconView(organize: homeOrganizeType, folderKey: homeCurrentFolder)
            case .list:
                return .listView(organize: homeOrganizeType, folderKey: homeCurrentFolder)
            case .tree:
                return .treeView
        }
    }
}
