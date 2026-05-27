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

    /// 专属串行队列，所有 importRdb 调用均在此队列上执行。
    /// 串行保证多平台并发 ODR 回调不会同时写 SQLite；
    /// 独立于主线程和 RAGameRDBManager 的 sqlitequeue，避免死锁。
    private let importQueue = DispatchQueue(label: "com.retrogo.odr.import", qos: .utility)

    @objc
    private(set) dynamic var rdbReady = false

    private override init() {
        super.init()
        loadRDB()
    }

    // MARK: - Load

    private func loadRDB() {
        // initialize 的 completion 在主线程触发（ObjC 内部 dispatch_async 到 main_queue）。
        // 立即跳出到 importQueue，避免在主线程上执行 isPlatformImported 的
        // dispatch_sync 阻塞 UI，以及避免在主线程上触发耗时的 rdb 导入流程。
        RAGameRDBManager.shared().initialize(AppConfig.shared.gameRdbDatabasePath) { [weak self] in
            guard let self else { return }
            self.importQueue.async {
                self.importMissingPlatforms()
            }
        }
    }

    // MARK: - Missing platform check

    /// 运行在 importQueue（串行）上。
    /// isPlatformImported 内部 dispatch_sync 到 d_dbQueue，
    /// 从 importQueue 发起不会死锁（两个不同的队列）。
    private func importMissingPlatforms() {
        let missing = rdb.filter { _, rdbName in
            !RAGameRDBManager.shared().isPlatformImported(rdbName)
        }

        // 所有平台均已导入，直接就绪
        guard !missing.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.rdbReady = true
            }
            return
        }

        // 用 DispatchGroup 追踪所有平台的导入完成情况（含失败），
        // 全部结束后才将 rdbReady 置为 true
        let group = DispatchGroup()

        for (tag, rdbName) in missing {
            group.enter()
            requestAndImport(tag: tag, rdbName: rdbName) {
                group.leave()
            }
        }

        // 所有平台导入流程（无论成败）全部结束后通知主线程
        group.notify(queue: .main) { [weak self] in
            NSLog("[ODR] ✅ 所有平台导入流程结束，rdbReady = true")
            self?.rdbReady = true
        }
    }

    // MARK: - Per-platform ODR request

    /// `completion` 在每个平台的导入流程结束（成功或失败）后调用，
    /// 保证 DispatchGroup 的 leave 能在所有路径上被触发到。
    private func requestAndImport(tag: String, rdbName: String, completion: @escaping () -> Void) {
        let request = NSBundleResourceRequest(tags: [tag])
        request.loadingPriority = NSBundleResourceRequestLoadingPriorityUrgent

        // 持有引用，防止提前释放
        lock.lock()
        activeRequests[tag] = request
        lock.unlock()

        // beginAccessingResources 的 completion 在 OS 内部未知队列上回调。
        // importRdb 内部会 dispatch_async 到 d_dbQueue，任意队列调用均安全；
        // completion 最终由 d_dbQueue 回调到主线程，group.leave() 在主线程执行。
        request.beginAccessingResources { [weak self] error in
            guard let self else {
                completion()
                return
            }

            if let error {
                NSLog("[ODR] ❌ %@ 资源请求失败: %@", tag, error.localizedDescription)
                self.releaseRequest(tag: tag)
                completion()
                return
            }

            // 在 Bundle 中定位 .rdb 文件（只读元数据，ODR 回调队列上可以做）
            guard let rdbURL = Bundle.main.url(forResource: rdbName, withExtension: "rdb") else {
                NSLog("[ODR] ❌ Bundle 中找不到 %@.rdb（tag=%@）", rdbName, tag)
                request.endAccessingResources()
                self.releaseRequest(tag: tag)
                completion()
                return
            }


            RAGameRDBManager.shared().importRdb(atPath: rdbURL.path) { importedCount, importError in
                if let importError {
                    NSLog("[ODR] ❌ %@ 导入失败: %@", rdbName, importError.localizedDescription)
                } else {
                    NSLog("[ODR] ✅ %@ 导入完成，写入游戏 %d 条", rdbName, importedCount)
                }

                // 数据已落盘 SQLite，释放 ODR 资源
                request.endAccessingResources()
                self.releaseRequest(tag: tag)
                completion()
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
