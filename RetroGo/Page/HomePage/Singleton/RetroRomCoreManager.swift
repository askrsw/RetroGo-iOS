//
//  RetroRomCoreManager.swift
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
import RACoordinator

final class RetroRomCoreManager {
    static let shared = RetroRomCoreManager()
    private init() { }

    var allCores: [EmuCoreInfoItem] {
        RetroArchX.shared().allCores
    }

    private(set) lazy var cores: [String: EmuCoreInfoItem] = Dictionary(uniqueKeysWithValues: allCores.map { ($0.coreId, $0) })
    private(set) lazy var systems: [String: [EmuCoreInfoItem]] = Dictionary(grouping: allCores, by: { $0.systemID ?? "none" })

    // 每个核心独特的文件扩展名
    private(set) lazy var coreUnqueExtensions: [String: Set<String>] = { [unowned self] in
        var result: [String: Set<String>] = [:]
        let allExtensions = cores.mapValues { Set($0.extensions ?? []) }
        for (key, exts) in allExtensions {
            // 计算所有其他 core 的扩展名集合
            let otherExts = allExtensions
                .filter { $0.key != key }
                .reduce(into: Set<String>()) { $0.formUnion($1.value) }
            // 当前 core 独有的扩展名
            let unique = exts.subtracting(otherExts)
            result[key] = unique
        }
        return result
    }()

    // 每个系统独特的文件扩展名
    private(set) lazy var systemUnqueExtensions: [String: Set<String>] = { [unowned self] in
        var result: [String: Set<String>] = [:]
        // 每个 systemID 下所有扩展名集合
        let systemExtensions = systems.mapValues { cores in
            Set(cores.flatMap { $0.extensions ?? [] })
        }
        for (systemID, exts) in systemExtensions {
            // 其他 systemID 的所有扩展名集合
            let otherExts = systemExtensions
                .filter { $0.key != systemID }
                .reduce(into: Set<String>()) { $0.formUnion($1.value) }
            // 当前 systemID 独有的扩展名
            let unique = exts.subtracting(otherExts)
            result[systemID] = unique
        }
        return result
    }()

    // Core Info 中注册的可以打开某个类型文件的核心数组
    private(set) lazy var extensionCores: [String: [EmuCoreInfoItem]] = { [unowned self] in
        var result: [String: [EmuCoreInfoItem]] = [:]

        // 1. 建立基础映射
        for core in cores.values {
            guard let extensions = core.extensions else { continue }
            for ext in extensions {
                let lowExt = ext.lowercased()
                // 使用 default 值简化插入逻辑
                result[lowExt, default: []].append(core)
            }
        }

        // 2. 按照 displayName 对每个扩展名下的数组进行升序排序
        // 使用 mapValues 能够保持 Key 不变，仅处理 Value
        let sortedResult = result.mapValues { coreList in
            coreList.sorted {
                let name1 = $0.displayName
                let name2 = $1.displayName
                return name1.localizedStandardCompare(name2) == .orderedAscending
            }
        }

        return sortedResult
    }()

    private var extensionOpenCores: [String: [EmuCoreInfoItem]] = [:]

    func getExtOpenCores(ext: String) -> [EmuCoreInfoItem] {
        if let array = extensionOpenCores[ext] {
            return array
        } else {
            guard var cores = Self.shared.extensionCores[ext] else {
                extensionOpenCores[ext] = []
                return []
            }

            var notUniqueCores: Set<EmuCoreInfoItem> = []
            for core in cores {
                if let systemID = core.systemID , let extsSet = systemUnqueExtensions[systemID] {
                    if !extsSet.contains(ext) {
                        notUniqueCores.insert(core)
                    }
                }
            }
            cores.removeAll(where: { notUniqueCores.contains($0 )})
            extensionOpenCores[ext] = cores
            return cores
        }
    }

    func core(_ key: String) -> EmuCoreInfoItem? {
        if key == RetroRomFileItemWrapper.uncategorizedKey {
            return .noneCore()
        }

        return cores[key]
    }

    func getRunningCore(_ item: RetroRomFileItem) -> EmuCoreInfoItem? {
        guard let romPath = item.fullPath else { return nil }

        if let coreId = item.inheritedPreferCore, let core = core(coreId), core != .noneCore() {
            return core
        }

        let ext = (romPath as NSString).pathExtension.lowercased()
        let cores = getExtOpenCores(ext: ext)
        return cores.first
    }

    func getRunningCore(_ url: URL) -> EmuCoreInfoItem? {
        let ext = url.pathExtension.lowercased()
        let cores = getExtOpenCores(ext: ext)
        return cores.first
    }
}
