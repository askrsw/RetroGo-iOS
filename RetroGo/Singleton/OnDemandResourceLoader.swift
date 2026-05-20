//
//  OnDemandResourceLoader.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/20.
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
import RACoordinator

final class OnDemandResourceLoader: NSObject {

    static let shared = OnDemandResourceLoader()

    // ODR tag → rdb 文件名（不含扩展名，与 Xcode ODR tag 一一对应）
    let rdb: [String: String] = [
        "rdb-DOS":    "DOS",
        "rdb-FDS":    "Nintendo - Family Computer Disk System",
        "rdb-GB":     "Nintendo - Game Boy",
        "rdb-GBA":    "Nintendo - Game Boy Advance",
        "rdb-GBC":    "Nintendo - Game Boy Color",
        "rdb-MAME":   "MAME",
        "rdb-N64":    "Nintendo - Nintendo 64",
        "rdb-NDS":    "Nintendo - Nintendo DS",
        "rdb-NES":    "Nintendo - Nintendo Entertainment System",
        "rdb-PS":     "Sony - PlayStation",
        "rdb-PSP":    "Sony - PlayStation Portable",
        "rdb-Saturn": "Sega - Saturn",
        "rdb-SNES":   "Nintendo - Super Nintendo Entertainment System",
    ]

    // 持有进行中的 NSBundleResourceRequest，防止 ARC 提前释放
    private var activeRequests: [String: NSBundleResourceRequest] = [:]
    private let lock = NSLock()

    @objc
    private(set) dynamic var rdbReady = false

    private override init() {
        super.init()
        loadRDB()
    }

    // MARK: - Load

    private func loadRDB() {
        // Step 1: 初始化 SQLite DB；completion 在主线程触发，DB 已就绪
        RAGameRDBManager.shared().initialize(AppConfig.shared.gameRdbDatabasePath) { [weak self] in
            self?.importMissingPlatforms()

            self?.rdbReady = true
        }
    }

    // MARK: - Missing platform check

    private func importMissingPlatforms() {
        // 过滤出尚未导入的平台（isPlatformImported 内部走 dispatch_sync，此处在主线程调用安全）
        let missing = rdb.filter { _, rdbName in
            !RAGameRDBManager.shared().isPlatformImported(rdbName)
        }

        guard !missing.isEmpty else { return }

        for (tag, rdbName) in missing {
            requestAndImport(tag: tag, rdbName: rdbName)
        }
    }

    // MARK: - Per-platform ODR request

    private func requestAndImport(tag: String, rdbName: String) {
        let request = NSBundleResourceRequest(tags: [tag])
        request.loadingPriority = NSBundleResourceRequestLoadingPriorityUrgent

        // 持有引用，防止提前释放
        lock.lock()
        activeRequests[tag] = request
        lock.unlock()

        request.beginAccessingResources { [weak self] error in
            guard let self else { return }

            if let error {
                NSLog("[ODR] ❌ %@ 资源请求失败: %@", tag, error.localizedDescription)
                self.releaseRequest(tag: tag)
                return
            }

            // 在 Bundle 中定位 .rdb 文件
            guard let rdbURL = Bundle.main.url(forResource: rdbName, withExtension: "rdb") else {
                NSLog("[ODR] ❌ Bundle 中找不到 %@.rdb（tag=%@）", rdbName, tag)
                request.endAccessingResources()
                self.releaseRequest(tag: tag)
                return
            }

            // 导入到 SQLite；completion 在主线程
            RAGameRDBManager.shared().importRdb(atPath: rdbURL.path) { importedCount, importError in
                if let importError {
                    NSLog("[ODR] ❌ %@ 导入失败: %@", rdbName, importError.localizedDescription)
                } else {
                    NSLog("[ODR] ✅ %@ 导入完成，写入游戏 %d 条", rdbName, importedCount)
                }

                // 数据已落盘 SQLite，释放 ODR 资源
                request.endAccessingResources()
                self.releaseRequest(tag: tag)
            }
        }
    }

    // MARK: - Helpers

    private func releaseRequest(tag: String) {
        lock.lock()
        activeRequests.removeValue(forKey: tag)
        lock.unlock()
    }
}
