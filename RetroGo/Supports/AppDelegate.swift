//
//  AppDelegate.swift
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
import IQKeyboardManagerSwift

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        performDataMigrationIfNeeded()

        let _ = RetroArchX.shared()
        let _ = RetroRomFileManager.shared

        configKeyboardManager()
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

extension AppDelegate {
    private func configKeyboardManager() {
        IQKeyboardManager.shared.isDebuggingEnabled = false
        IQKeyboardManager.shared.isEnabled = true
    }

    private func performDataMigrationIfNeeded() {
        let fileManager = FileManager.default
        let legacyDataRoot = fileManager.documentFolder + "/data"

        guard fileManager.fileExists(atPath: legacyDataRoot) else { return }

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

    // 核心：逐个文件移动，不破坏目录结构
    private func migrateSubFolderContent(from oldDir: String, to newDir: String) {
        let fileManager = FileManager.default
        guard fileManager.pathIsDirectory(oldDir) else { return }

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

extension UIApplication {
    var sceneDelegate: SceneDelegate? {
        return self.connectedScenes
            .first { $0.activationState == .foregroundActive }
            .flatMap { $0.delegate as? SceneDelegate }
    }
}
