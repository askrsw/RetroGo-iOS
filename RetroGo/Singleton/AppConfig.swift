//
//  AppConfig.swift
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

final class AppConfig {
    static let shared = AppConfig()
    private init() { }

    private(set) lazy var statesDatabasePath = { () -> String in
        let folder = FileManager.default.documentFolder + "/data/database/"
        if FileManager.default.createDirectoryIfNotExists(atPath: folder) {
            return folder + "states.db"
        } else {
            fatalError()
        }
    }()

    private(set) lazy var statesFolder = { () -> String in
        let folder = FileManager.default.documentFolder + "/data/states/"
        if FileManager.default.createDirectoryIfNotExists(atPath: folder) {
            return folder
        } else {
            fatalError()
        }
    }()

    private(set) lazy var snapshotFolder = { () -> String in
        let folder = FileManager.default.documentFolder + "/snapshots/"
        if FileManager.default.createDirectoryIfNotExists(atPath: folder) {
            return folder
        } else {
            fatalError()
        }
    }()

    private(set) lazy var romDatabasePath = { () -> String in
        let folder = FileManager.default.documentFolder + "/data/database/"
        if FileManager.default.createDirectoryIfNotExists(atPath: folder) {
            return folder + "roms.db"
        } else {
            fatalError()
        }
    }()

    private(set) lazy var romFolderPath = { () -> String in
        let folder = FileManager.default.documentFolder + "/data/roms/"
        if FileManager.default.createDirectoryIfNotExists(atPath: folder) {
            return folder
        } else {
            fatalError()
        }
    }()

    private(set) lazy var sharedAutoThumnailFolderPath = { () -> String in
        let folder = FileManager.default.documentFolder + "/data/auto_snapshots/"
        if FileManager.default.createDirectoryIfNotExists(atPath: folder) {
            return folder
        } else {
            fatalError()
        }
    }()
}
