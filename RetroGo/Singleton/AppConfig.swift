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

    /// Private app data; exposed through a Documents symlink in Debug builds only.
    var dataFolder: String { FileManager.default.applicationSupportFolder + "/data/" }

    var shaderFolder: String { dataFolder + "shaders/" }
    var shaderImportsFolder: String { shaderFolder + "imports/" }
    var shaderNoticesURL: URL {
        bundledShaderFolder.appendingPathComponent("notices", isDirectory: true)
            .appendingPathComponent("notices.\(Bundle.currentSimpleLanguageKey()).html")
    }
    /// Bump manually when the Shader compiler, compile options or cache format becomes incompatible.
    var shaderCacheVersion: Int { 1 }
    var shaderCacheFolder: String { shaderFolder + "cache/spirv/v\(shaderCacheVersion)/" }
    var shaderCacheByteLimit: Int { 256 * 1024 * 1024 }
    var bundledShaderFolder: URL {
        Bundle.main.bundleURL.appendingPathComponent("Data/shaders", isDirectory: true)
    }
    var bundledShaderSourceFolder: URL {
        bundledShaderFolder.appendingPathComponent("shaders_slang", isDirectory: true)
    }
    var bundledShaderCatalogURL: URL { bundledShaderFolder.appendingPathComponent("catalog.json") }

    private(set) lazy var statesFolder = { () -> String in
        let folder = FileManager.default.applicationSupportFolder + "/data/states/"
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
        let folder = FileManager.default.applicationSupportFolder + "/data/database/"
        if FileManager.default.createDirectoryIfNotExists(atPath: folder) {
            return folder + "roms.db"
        } else {
            fatalError()
        }
    }()

    private(set) lazy var gameRdbDatabasePath = { () -> String in
        let folder = FileManager.default.applicationSupportFolder + "/data/database/"
        if FileManager.default.createDirectoryIfNotExists(atPath: folder) {
            return folder + "gamerdb.db"
        } else {
            fatalError()
        }
    }()

    private(set) lazy var mameRomSetDatabasePath = { () -> String in
        let folder = FileManager.default.applicationSupportFolder + "/data/database/"
        if FileManager.default.createDirectoryIfNotExists(atPath: folder) {
            return folder + "mame_romset.db"
        } else {
            fatalError()
        }
    }()

    /// MAME cheat XMLs imported from Pugsy's cheat.7z (see MameCheatLibrary).
    private(set) lazy var mameCheatDatabasePath = { () -> String in
        let folder = FileManager.default.applicationSupportFolder + "/data/database/"
        if FileManager.default.createDirectoryIfNotExists(atPath: folder) {
            return folder + "mame_cheat.db"
        } else {
            fatalError()
        }
    }()

    /// Originals of MAME sets replaced by a repair, kept until the user clears them.
    private(set) lazy var mameRepairBackupFolder = { () -> String in
        let folder = FileManager.default.applicationSupportFolder + "/data/romset_backup/"
        if FileManager.default.createDirectoryIfNotExists(atPath: folder) {
            return folder
        } else {
            fatalError()
        }
    }()

    private(set) lazy var romFolderPath = { () -> String in
        let folder = FileManager.default.applicationSupportFolder + "/data/roms/"
        if FileManager.default.createDirectoryIfNotExists(atPath: folder) {
            return folder
        } else {
            fatalError()
        }
    }()

    private(set) lazy var sharedAutoThumbnailFolderPath = { () -> String in
        let folder = FileManager.default.applicationSupportFolder + "/data/auto_snapshots/"
        if FileManager.default.createDirectoryIfNotExists(atPath: folder) {
            return folder
        } else {
            fatalError()
        }
    }()
}
