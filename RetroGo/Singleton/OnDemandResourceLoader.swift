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

extension Notification.Name {
    /// Posted (on main) when an ODR resource finishes installing or is deleted.
    /// `object` = the resource id (String).
    static let odrResourceStateDidChange = Notification.Name("RetroGoODRResourceStateDidChange")
}

/// One downloadable On-Demand Resource = a prebuilt file shipped as an ODR tag
/// (the game DB, the cheat library, the game-name localization DB, and — later —
/// large filter/shader config packs). Every fact is hardcoded in
/// `OnDemandResourceLoader.resources`; adding a new resource is one entry.
struct ODRResource: Hashable {
    /// Stable id (also the UserDefaults / notification key suffix).
    let id: String
    /// On-Demand Resource tag (set in the Xcode resource's ODR tags).
    let odrTag: String
    /// Resource name + extension inside the app bundle.
    let bundleResource: String
    let bundleExtension: String
    /// File name written into the app's database folder.
    let installedFileName: String
    /// Hardcoded approximate byte size, for display before any download.
    let approxByteSize: Int64
    /// Snapshot version. Bump when repacking the prebuilt file so installed
    /// users re-copy the newer one. (Independent of the SQLite schema version.)
    let bundledVersion: Int
    /// Required = auto-downloaded on launch and not user-deletable (the game DB).
    /// Optional = user downloads / deletes it from the resource management page.
    let isRequired: Bool
    /// Localized string keys (Localizable.strings: odr_*_title / odr_*_desc).
    let titleKey: String
    let descKey: String

    var installedVersionKey: String { "RetroGoODRInstalledVersion_\(id)" }

    static func == (l: ODRResource, r: ODRResource) -> Bool { l.id == r.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Install / download state of an ODR resource.
enum ODRResourceState {
    case ready                    // installed and up to date
    case notDownloaded
    case downloading(Double)      // fractionCompleted 0…1
}

final class OnDemandResourceLoader: NSObject {

    static let shared = OnDemandResourceLoader()

    // MARK: - Hardcoded resource catalog

    /// The full set of On-Demand Resources. Order = display order.
    static let resources: [ODRResource] = [
        ODRResource(
            id: "gamerdb", odrTag: "game-db",
            bundleResource: "gamerdb", bundleExtension: "sqlite",
            installedFileName: "gamerdb.db",
            approxByteSize: 71_794_688, bundledVersion: 1,
            isRequired: true,
            titleKey: "odr_gamerdb_title", descKey: "odr_gamerdb_desc"),
        ODRResource(
            id: "gameloc", odrTag: "gameloc-db",
            bundleResource: "gameloc", bundleExtension: "sqlite",
            installedFileName: "gameloc.sqlite",
            approxByteSize: 9_457_664, bundledVersion: 1,
            isRequired: true,   // required: small, and language is easily toggled
            titleKey: "odr_gameloc_title", descKey: "odr_gameloc_desc"),
        ODRResource(
            id: "cheat", odrTag: "cheat-db",
            bundleResource: "cheat", bundleExtension: "sqlite",
            installedFileName: "cheat.sqlite",
            approxByteSize: 130_015_232, bundledVersion: 1,
            isRequired: false,
            titleKey: "odr_cheat_title", descKey: "odr_cheat_desc"),
    ]

    static func resource(id: String) -> ODRResource? {
        resources.first { $0.id == id }
    }

    // MARK: - State

    /// `true` once the (required) game database is open and queryable.
    @objc private(set) dynamic var rdbReady = false

    /// Live requests keyed by resource id (kept alive while downloading) + their
    /// progress observers. Touched only on the main thread.
    private var activeRequests: [String: NSBundleResourceRequest] = [:]
    private var progressObservers: [String: NSKeyValueObservation] = [:]

    /// Serial queue for file copy / version bookkeeping — never the main thread.
    private let importQueue = DispatchQueue(label: "com.retrogo.odr.install", qos: .utility)

    private var databaseFolder: String {
        (AppConfig.shared.gameRdbDatabasePath as NSString).deletingLastPathComponent + "/"
    }

    func targetPath(_ r: ODRResource) -> String { databaseFolder + r.installedFileName }

    private override init() {
        super.init()
        importQueue.async { [weak self] in self?.ensureRequiredThenOpenGameDB() }
    }

    // MARK: - Public API (resource management page)

    func state(for r: ODRResource) -> ODRResourceState {
        if let req = activeRequests[r.id] {
            return .downloading(req.progress.fractionCompleted)
        }
        let installed = UserDefaults.standard.integer(forKey: r.installedVersionKey)
        if installed >= r.bundledVersion,
           FileManager.default.fileExists(atPath: targetPath(r)) {
            return .ready
        }
        return .notDownloaded
    }

    /// Begin (or resume) downloading + installing a resource. `progress` and
    /// `completion` are delivered on the main thread. The ODR download runs while
    /// the app is in the foreground holding the request (not a true background
    /// task — keep the progress UI up).
    func startDownload(_ r: ODRResource,
                       progress: @escaping (Double) -> Void,
                       completion: @escaping (Bool, Error?) -> Void) {
        assert(Thread.isMainThread)
        if case .ready = state(for: r) { completion(true, nil); return }
        if activeRequests[r.id] != nil { return }     // already downloading

        let request = NSBundleResourceRequest(tags: [r.odrTag])
        request.loadingPriority = NSBundleResourceRequestLoadingPriorityUrgent
        activeRequests[r.id] = request
        progressObservers[r.id] = request.progress.observe(\.fractionCompleted) { p, _ in
            DispatchQueue.main.async { progress(p.fractionCompleted) }
        }

        request.beginAccessingResources { [weak self] error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.cleanup(r.id)
                    completion(false, error)
                }
                return
            }
            self.importQueue.async {
                let ok = self.installFromBundle(r)
                if ok {
                    UserDefaults.standard.set(r.bundledVersion, forKey: r.installedVersionKey)
                }
                request.endAccessingResources()
                DispatchQueue.main.async {
                    self.cleanup(r.id)
                    if ok {
                        NotificationCenter.default.post(name: .odrResourceStateDidChange, object: r.id)
                    }
                    completion(ok, ok ? nil : NSError(
                        domain: "OnDemandResourceLoader", code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "install failed"]))
                }
            }
        }
    }

    /// Delete an optional resource's installed file to reclaim space. Required
    /// resources can't be deleted. Returns `true` if anything was removed.
    @discardableResult
    func delete(_ r: ODRResource) -> Bool {
        guard !r.isRequired else { return false }
        let fm = FileManager.default
        var removed = false
        for suffix in ["", "-wal", "-shm"] {
            let p = targetPath(r) + suffix
            if fm.fileExists(atPath: p), (try? fm.removeItem(atPath: p)) != nil {
                removed = true
            }
        }
        UserDefaults.standard.removeObject(forKey: r.installedVersionKey)
        if removed {
            NotificationCenter.default.post(name: .odrResourceStateDidChange, object: r.id)
        }
        return removed
    }

    private func cleanup(_ id: String) {
        progressObservers[id]?.invalidate()
        progressObservers[id] = nil
        activeRequests[id] = nil
    }

    // MARK: - Launch: ensure required resources, then open the game DB

    /// Auto-installs every required resource (the game DB + the localization DB)
    /// the first time / after a repack, then opens the game DB (`rdbReady`).
    private func ensureRequiredThenOpenGameDB() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for r in Self.resources where r.isRequired {
                self.ensureInstalled(r) { [weak self] in
                    // Open the game DB once gamerdb is in place. Open regardless
                    // of download success: worst case we open an empty/old DB so
                    // the UI still works and launch is never blocked.
                    if r.id == "gamerdb" {
                        self?.importQueue.async { self?.openGameDatabase() }
                    }
                }
            }
        }
    }

    /// Main-thread. Ensure a resource is installed (download if needed), then
    /// call `completion` (also on main).
    private func ensureInstalled(_ r: ODRResource, completion: @escaping () -> Void) {
        if case .ready = state(for: r) { completion(); return }
        startDownload(r, progress: { _ in }) { _, _ in completion() }
    }

    /// Open the game SQLite. The prebuilt DB's user_version is aligned with
    /// `RAGameRDBManager.currentDBVersion`, so initialize skips DDL and just opens.
    private func openGameDatabase() {
        let path = AppConfig.shared.gameRdbDatabasePath
        if let loc = Self.resource(id: "gameloc") {
            RAGameLocalizationManager.shared().initialize(targetPath(loc), completion: nil)
        }
        RAGameRDBManager.shared().initialize(path) { [weak self] in
            self?.rdbReady = true
            NSLog("[ODR] ✅ 游戏数据库就绪，rdbReady = true")
        }
    }

    /// Copy the bundled prebuilt file over the install path, clearing any old
    /// file + its WAL/SHM sidecars first. Runs on importQueue.
    private func installFromBundle(_ r: ODRResource) -> Bool {
        guard let srcURL = Bundle.main.url(forResource: r.bundleResource,
                                           withExtension: r.bundleExtension) else {
            NSLog("[ODR] ❌ Bundle 中找不到资源 %@.%@", r.bundleResource, r.bundleExtension)
            return false
        }
        let fm = FileManager.default
        let dst = URL(fileURLWithPath: targetPath(r))
        do {
            for suffix in ["", "-wal", "-shm"] {
                let p = targetPath(r) + suffix
                if fm.fileExists(atPath: p) { try fm.removeItem(atPath: p) }
            }
            try fm.createDirectory(at: dst.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try fm.copyItem(at: srcURL, to: dst)
            NSLog("[ODR] ✅ 预制资源已安装 → %@", targetPath(r))
            return true
        } catch {
            NSLog("[ODR] ❌ 安装资源失败 (%@): %@", r.id, error.localizedDescription)
            return false
        }
    }
}

#if DEBUG
// MARK: - DEBUG：从 Bundle 内的 .rdb 离线生成预制库

extension OnDemandResourceLoader {

    /// 用于离线导出的 13 个 .rdb 资源名（Bundle 资源名，不含扩展名）。
    static let debugRdbNames: [String] = [
        "DOS",
        "Nintendo - Family Computer Disk System",
        "Nintendo - Game Boy",
        "Nintendo - Game Boy Advance",
        "Nintendo - Game Boy Color",
        "MAME",
        "Nintendo - Nintendo 64",
        "Nintendo - Nintendo DS",
        "Nintendo - Nintendo Entertainment System",
        "Sony - PlayStation",
        "Sony - PlayStation Portable",
        "Sega - Saturn",
        "Nintendo - Super Nintendo Entertainment System",
    ]

    /// DEBUG：把 Bundle 内的 .rdb 合并构建成成品预制库，
    /// 落地到 <Documents>/gamerdb.sqlite，并把路径回调出来供从模拟器容器取出。
    func debugExportCombinedDatabase(completion: @escaping (String?, Error?) -> Void) {
        // Resources/Data 是蓝色 folder reference，保留层级打进包，
        // 故 rdb 运行时位于 <bundle>/Data/rdb/，必须带 subdirectory 才能定位。
        let rdbPaths: [String] = OnDemandResourceLoader.debugRdbNames.compactMap {
            Bundle.main.url(forResource: $0,
                            withExtension: "rdb",
                            subdirectory: "Data/rdb")?.path
        }
        guard !rdbPaths.isEmpty else {
            completion(nil, NSError(domain: "OnDemandResourceLoader", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey:
                                                "Bundle 内找不到任何 .rdb 文件，请确认它们仍包含在 Debug target 的资源中"]))
            return
        }

        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory,
                                                       .userDomainMask, true).first!
        let dest = (docs as NSString).appendingPathComponent("gamerdb.sqlite")

        RAGameRDBManager.shared().exportCombinedDatabase(toPath: dest,
                                                         fromRdbPaths: rdbPaths) { total, error in
            if let error {
                completion(nil, error)
            } else {
                NSLog("[ODR][DEBUG] ✅ 导出完成，共 %ld 条游戏 → %@", total, dest)
                completion(dest, nil)
            }
        }
    }
}
#endif
