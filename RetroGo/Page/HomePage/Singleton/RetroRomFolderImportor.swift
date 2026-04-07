//
//  RetroRomFolderImportor.swift
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

enum RetroRomImportMessage {
    case enumeratorBuildFailed
    case uniqueKeyCreationFailed
    case parentFolderDoesNotExist(path: String)
    case romFileReadFailed(error: String)
    case folderCreationFailed(path: String)
    case fileCopyFailed(path: String)
    case saveToDatabaseFailed
}

final class RetroRomFolderImportor: Thread {
    enum ConflictPolicy {
        case skip, merge, cancel
    }

    enum IncompletePolicy {
        case skip, cancel
    }

    private let rootUrl: URL
    private let rootParent: String
    private let destinationRootPath: String

    private let indicatorView = RetroRomActivityView(mainTitle: Bundle.localizedString(forKey: "homepage_import_importing"))
    private lazy var groupBuilder = RetroRomImportGroupBuilder(indicatorView: indicatorView)
    private let procSemphore = DispatchSemaphore(value: 0)
    private var conflictPolicy = ConflictPolicy.skip
    private var incompletePolicy = IncompletePolicy.skip

    private var folderItems: [String: RetroRomFolderItem] = [:]
    private var folderItemPaths: [String] = []
    private var skipedFolders: [String] = []
    private var fileItems: [String: RetroRomFileItem] = [:]
    private var fileItemPaths: [String] = []
    private var fileCopyPlans: [String: [(source: String, destination: String)]] = [:]
    private var skipedFiles: [String] = []
    private var reusedFolders: [RetroRomFolderItem] = []
    private var rootKey: String?
    private var flattenRootFolder = false
    private var incompleteGroups: [RetroRomImportGroupBuilder.IncompleteGroup] = []

    private let startDate: Date = Date()
    private var success = false

    init?(rootUrl: URL, rootParent: String) {
        self.rootUrl = rootUrl
        self.rootParent = rootParent

        let parentFolder = RetroRomFileManager.shared.folderItem(key: rootParent)
        guard let dstRootPath = parentFolder?.fullPath else {
            return nil
        }
        self.destinationRootPath = dstRootPath

        super.init()
    }

    override func start() {
        success  = false
        indicatorView.install()
        super.start()
    }

    override func main() {
        defer { postProcess() }

        guard rootUrl.startAccessingSecurityScopedResource() else {
            return
        }
        defer { rootUrl.stopAccessingSecurityScopedResource() }

        do {
            let sourceFiles = try collectSourceFiles()
            let analysis = try groupBuilder.analyzeGroups(from: sourceFiles)
            let groups = filterImportableGroups(analysis.groups)
            incompleteGroups = filterIncompleteGroups(analysis.incompleteGroups)
            if !handleIncompleteGroups(incompleteGroups) {
                let title = Bundle.localizedString(forKey: "info")
                let message = Bundle.localizedString(forKey: "homepage_import_cancelled")
                indicatorView.infoMessage(message, title: title, canDismiss: true)
                return
            }
            let effectiveSourceFiles = sourceFilesForGroups(groups, fileMap: analysis.map)
            let absorbedDirectories = determineAbsorbedDirectories(groups: groups, sourceFiles: effectiveSourceFiles)
            flattenRootFolder = shouldFlattenRootFolder(groups: groups, absorbedDirectories: absorbedDirectories)
            guard buildFolderItems(groups: groups, absorbedDirectories: absorbedDirectories) else {
                return
            }
            guard buildGroupedFileItems(groups: groups, fileMap: analysis.map, absorbedDirectories: absorbedDirectories) else {
                return
            }
            saveFolerAndFiles()
        } catch {
            errorProcess(.romFileReadFailed(error: error.localizedDescription))
        }
    }
}

extension RetroRomFolderImportor {
    private func collectSourceFiles() throws -> [RetroRomImportGroupBuilder.SourceFile] {
        let fileManager = FileManager.default
        let rootPath = rootUrl.path(percentEncoded: false)
        guard let enumerator = fileManager.enumerator(atPath: rootPath) else {
            throw NSError(domain: "RetroRomError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to enumerate folder"])
        }

        var files: [RetroRomImportGroupBuilder.SourceFile] = []
        for case let filePath as String in enumerator {
            if filePath.hasPrefix(".DS_Store") || filePath.hasSuffix(".DS_Store") {
                continue
            }

            let fileUrl = rootUrl.appendingPathComponent(filePath)
            if !fileManager.urlIsFile(fileUrl) {
                continue
            }
            let displayPath = "\(rootUrl.lastPathComponent)/\(filePath)"
            let formatter = Bundle.localizedString(forKey: "homepage_import_file_checking")
            let message = String(format: formatter, displayPath)
            let title = Bundle.localizedString(forKey: "homepage_import_importing")
            indicatorView.activeMessage(message, title: title)

            let source = try RetroRomImportGroupBuilder.SourceFile(relativePath: filePath, url: fileUrl)
            files.append(source)
        }
        return files.sorted {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
    }

    private func filterImportableGroups(_ groups: [RetroRomImportGroupBuilder.Group]) -> [RetroRomImportGroupBuilder.Group] {
        let supportedExtensions = RetroArchX.shared().allExtensionsSet
        return groups.filter { group in
            if group.type != .single {
                return true
            }
            let ext = groupBuilder.fileExtension(of: group.entryPath)
            return supportedExtensions.contains(ext)
        }
    }

    private func filterIncompleteGroups(_ groups: [RetroRomImportGroupBuilder.IncompleteGroup]) -> [RetroRomImportGroupBuilder.IncompleteGroup] {
        let supportedExtensions = RetroArchX.shared().allExtensionsSet
        return groups.filter { group in
            if group.type != .single {
                return true
            }
            let ext = groupBuilder.fileExtension(of: group.entryPath)
            return supportedExtensions.contains(ext)
        }
    }

    private func handleIncompleteGroups(_ groups: [RetroRomImportGroupBuilder.IncompleteGroup]) -> Bool {
        guard !groups.isEmpty else {
            return true
        }
        promptIncompleteGroups(groups)
        procSemphore.wait()
        return incompletePolicy != .cancel
    }

    private func promptIncompleteGroups(_ groups: [RetroRomImportGroupBuilder.IncompleteGroup]) {
        DispatchQueue.main.async {
            let details = groups.map { group -> String in
                if group.missingPaths.isEmpty {
                    return "• \(group.entryPath)"
                }
                let missing = group.missingPaths.joined(separator: "\n   - ")
                return "• \(group.entryPath)\n   - \(missing)"
            }.joined(separator: "\n\n")
            let format = Bundle.localizedString(forKey: "homepage_import_incomplete_groups_message")
            let message = NSString.localizedStringWithFormat(format as NSString, details) as String
            let title = Bundle.localizedString(forKey: "homepage_import_incomplete_groups_title")
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel) { [unowned self] _ in
                self.incompletePolicy = .cancel
                self.procSemphore.signal()
            }
            alert.addAction(cancelAction)
            let skipAction = UIAlertAction(title: Bundle.localizedString(forKey: "skip"), style: .default) { [unowned self] _ in
                self.incompletePolicy = .skip
                self.procSemphore.signal()
            }
            alert.addAction(skipAction)
            UIViewController.currentActive()?.present(alert, animated: true)
        }
    }

    private func sourceFilesForGroups(_ groups: [RetroRomImportGroupBuilder.Group], fileMap: [String: RetroRomImportGroupBuilder.SourceFile]) -> [RetroRomImportGroupBuilder.SourceFile] {
        let effectivePaths = Set(groups.flatMap(\.memberPaths))
        return effectivePaths.compactMap { fileMap[$0] }.sorted {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
    }

    private func determineAbsorbedDirectories(groups: [RetroRomImportGroupBuilder.Group], sourceFiles: [RetroRomImportGroupBuilder.SourceFile]) -> [String: String] {
        let allPaths = Set(sourceFiles.map(\.relativePath))
        var absorbed: [String: String] = [:]

        for group in groups {
            let candidateDirectory = commonDirectory(for: group.memberPaths)
            let scopedFiles = files(in: candidateDirectory, from: allPaths)
            let memberSet = Set(group.memberPaths)
            guard !candidateDirectory.isEmpty || groups.count == 1 else {
                continue
            }
            guard !scopedFiles.isEmpty, scopedFiles.isSubset(of: memberSet) else {
                continue
            }

            let overlappingGroups = groups.filter { other in
                Set(other.memberPaths).isSubset(of: scopedFiles)
            }
            if overlappingGroups.count == 1 {
                absorbed[group.entryPath] = candidateDirectory
            }
        }

        if absorbed.isEmpty, groups.count == 1, let group = groups.first {
            let memberSet = Set(group.memberPaths)
            if memberSet == allPaths {
                absorbed[group.entryPath] = ""
            }
        }

        return absorbed
    }

    private func shouldFlattenRootFolder(groups: [RetroRomImportGroupBuilder.Group], absorbedDirectories: [String: String]) -> Bool {
        guard groups.count == 1, let group = groups.first else {
            return false
        }

        if group.type == .single {
            return parentDirectory(of: group.entryPath).isEmpty
        }

        return absorbedDirectories[group.entryPath] == ""
    }

    private func buildFolderItems(groups: [RetroRomImportGroupBuilder.Group], absorbedDirectories: [String: String]) -> Bool {
        let requiredRelativeDirectories = requiredFolderDirectories(groups: groups, absorbedDirectories: absorbedDirectories)
        let sortedDirectories = requiredRelativeDirectories.sorted {
            let lhsDepth = $0.isEmpty ? 0 : $0.components(separatedBy: "/").count
            let rhsDepth = $1.isEmpty ? 0 : $1.components(separatedBy: "/").count
            if lhsDepth != rhsDepth {
                return lhsDepth < rhsDepth
            }
            return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        for directory in sortedDirectories {
            if shouldSkipDirectory(directory) {
                skipedFolders.append(directory)
                continue
            }
            if directory.isEmpty {
                if flattenRootFolder {
                    continue
                }
                if !makeRootFolderItem() {
                    return false
                }
            } else if !makeSubFolderItem(directory) {
                return false
            }
        }
        return true
    }

    private func buildGroupedFileItems(groups: [RetroRomImportGroupBuilder.Group], fileMap: [String: RetroRomImportGroupBuilder.SourceFile], absorbedDirectories: [String: String]) -> Bool {
        for group in groups {
            if shouldSkipGroup(group, absorbedDirectory: absorbedDirectories[group.entryPath]) {
                continue
            }
            showGroupProgress(group.entryPath)
            do {
                if let target = try makeGroupedFileItem(group: group, fileMap: fileMap, absorbedDirectory: absorbedDirectories[group.entryPath]) {
                    if checkFileExists(target) {
                        procSemphore.wait()
                        if conflictPolicy == .cancel {
                            let title = Bundle.localizedString(forKey: "info")
                            let message = Bundle.localizedString(forKey: "homepage_import_cancelled")
                            indicatorView.infoMessage(message, title: title, canDismiss: true)
                            return false
                        } else if conflictPolicy == .skip {
                            removePendingFile(at: target)
                            skipedFiles.append(target)
                            continue
                        }
                    }
                }
            } catch {
                errorProcess(.romFileReadFailed(error: error.localizedDescription))
                return false
            }
        }
        return true
    }

    private func makeGroupedFileItem(group: RetroRomImportGroupBuilder.Group, fileMap: [String: RetroRomImportGroupBuilder.SourceFile], absorbedDirectory: String?) throws -> String? {
        let parentRelativeDirectory: String
        let displayName: String?
        let itemRawName: String
        let sourceBaseDirectory: String

        if flattenRootFolder, groupsAtRootContainOnly(group: group, absorbedDirectory: absorbedDirectory) {
            parentRelativeDirectory = ""
            displayName = rootUrl.lastPathComponent
            itemRawName = lastPathComponent(of: group.entryPath)
            sourceBaseDirectory = absorbedDirectory ?? parentDirectory(of: group.entryPath)
        } else if let absorbedDirectory {
            parentRelativeDirectory = parentDirectory(of: absorbedDirectory)
            let folderName = lastPathComponent(of: absorbedDirectory.isEmpty ? rootUrl.lastPathComponent : absorbedDirectory)
            displayName = folderName
            itemRawName = lastPathComponent(of: group.entryPath)
            sourceBaseDirectory = absorbedDirectory
        } else if group.type == .single {
            parentRelativeDirectory = parentDirectory(of: group.entryPath)
            displayName = nil
            itemRawName = lastPathComponent(of: group.entryPath)
            sourceBaseDirectory = parentRelativeDirectory
        } else {
            parentRelativeDirectory = parentDirectory(of: group.entryPath)
            displayName = nil
            itemRawName = lastPathComponent(of: group.entryPath)
            sourceBaseDirectory = parentRelativeDirectory
        }

        let parentKey: String
        if parentRelativeDirectory.isEmpty {
            if flattenRootFolder {
                parentKey = rootParent
            } else if let rootFolder = folderItems[rootUrl.lastPathComponent] {
                parentKey = rootFolder.key
            } else {
                parentKey = rootParent
            }
        } else {
            let parentPath = targetFolderPath(for: parentRelativeDirectory)
            guard let parentItem = folderItems[parentPath] else {
                errorProcess(.parentFolderDoesNotExist(path: parentPath))
                return nil
            }
            parentKey = parentItem.key
        }

        guard let key = Retro​Rom​Persistence.shared.getUniqueKey() else {
            errorProcess(.uniqueKeyCreationFailed)
            return nil
        }

        var subItems: [RetroRomFileSubItem] = []
        subItems.reserveCapacity(group.memberPaths.count)

        for (index, memberPath) in group.memberPaths.enumerated() {
            guard let file = fileMap[memberPath] else {
                throw NSError(domain: "RetroRomError", code: 2, userInfo: [NSLocalizedDescriptionKey: memberPath])
            }
            let relativeName = relativeMemberPath(memberPath, baseDirectory: sourceBaseDirectory)
            let item = RetroRomFileSubItem(
                key: key,
                rawName: relativeName,
                fileRole: groupBuilder.subRole(for: memberPath, entryPath: group.entryPath, groupType: group.type),
                sha256: try file.sha256(),
                fileSize: file.fileSize,
                sortIndex: index
            )
            subItems.append(item)
        }

        let totalFileSize = subItems.reduce(0) { $0 + $1.fileSize }
        guard let entrySubItem = subItems.first(where: { $0.fileRole == .entry }) else {
            throw NSError(domain: "RetroRomError", code: 3, userInfo: [NSLocalizedDescriptionKey: group.entryPath])
        }
        let sha256 = try groupBuilder.contentSHA256(for: group, entrySubItem: entrySubItem, subItems: subItems)
        let item = RetroRomFileItem(
            key: key,
            rawName: itemRawName,
            showName: displayName,
            parent: parentKey,
            createAt: Date(),
            updateAt: Date(),
            fileSize: totalFileSize,
            sha256: sha256,
            fileGroupType: group.type,
            subItems: subItems
        )

        let targetPath = targetFilePath(for: item, parentRelativeDirectory: parentRelativeDirectory)
        fileItems[targetPath] = item
        fileItemPaths.append(targetPath)
        fileCopyPlans[targetPath] = makeCopyPlan(for: item, group: group, targetPath: targetPath, sourceBaseDirectory: sourceBaseDirectory)
        return targetPath
    }

    private func requiredFolderDirectories(groups: [RetroRomImportGroupBuilder.Group], absorbedDirectories: [String: String]) -> Set<String> {
        var directories: Set<String> = []
        for group in groups {
            let parentRelativeDirectory: String
            if flattenRootFolder, groupsAtRootContainOnly(group: group, absorbedDirectory: absorbedDirectories[group.entryPath]) {
                parentRelativeDirectory = ""
            } else if let absorbedDirectory = absorbedDirectories[group.entryPath] {
                parentRelativeDirectory = parentDirectory(of: absorbedDirectory)
            } else {
                parentRelativeDirectory = parentDirectory(of: group.entryPath)
            }

            var current = parentRelativeDirectory
            while true {
                directories.insert(current)
                if current.isEmpty {
                    break
                }
                current = parentDirectory(of: current)
            }
        }
        return directories
    }

    private func makeCopyPlan(for item: RetroRomFileItem, group: RetroRomImportGroupBuilder.Group, targetPath: String, sourceBaseDirectory: String) -> [(source: String, destination: String)] {
        if item.fileGroupType == .single {
            return [(source: group.entryPath, destination: targetPath)]
        }

        return item.subItems.map { subItem in
            let source = joinRelativePath(base: sourceBaseDirectory, component: subItem.rawName)
            let destination = targetPath + subItem.rawName
            return (source: source, destination: destination)
        }
    }

    private func showGroupProgress(_ path: String) {
        let formatter = Bundle.localizedString(forKey: "homepage_import_file_checking")
        let message = String(format: formatter, "\(rootUrl.lastPathComponent)/\(path)")
        let title = Bundle.localizedString(forKey: "homepage_import_importing")
        indicatorView.activeMessage(message, title: title)
    }

    private func files(in directory: String, from allPaths: Set<String>) -> Set<String> {
        if directory.isEmpty {
            return allPaths
        }
        let prefix = directory + "/"
        return Set(allPaths.filter { $0 == directory || $0.hasPrefix(prefix) })
    }

    private func commonDirectory(for paths: [String]) -> String {
        guard var components = paths.first?.components(separatedBy: "/").dropLast().map({ $0 }) else {
            return ""
        }
        for path in paths.dropFirst() {
            let pathComponents = path.components(separatedBy: "/").dropLast().map({ $0 })
            var shared: [String] = []
            for (lhs, rhs) in zip(components, pathComponents) where lhs == rhs {
                shared.append(lhs)
            }
            components = shared
            if components.isEmpty {
                break
            }
        }
        return components.joined(separator: "/")
    }

    private func relativeMemberPath(_ path: String, baseDirectory: String) -> String {
        guard !baseDirectory.isEmpty else {
            return path
        }
        let prefix = baseDirectory + "/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return lastPathComponent(of: path)
    }

    private func parentDirectory(of path: String) -> String {
        let directory = (path as NSString).deletingLastPathComponent
        return directory == "." ? "" : directory
    }

    private func lastPathComponent(of path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private func joinRelativePath(base: String, component: String) -> String {
        guard !base.isEmpty else {
            return component
        }
        guard !component.isEmpty else {
            return base
        }
        return "\(base)/\(component)"
    }

    private func targetFolderPath(for relativeDirectory: String) -> String {
        if relativeDirectory.isEmpty {
            if flattenRootFolder {
                return ""
            }
            return rootUrl.lastPathComponent
        }
        if flattenRootFolder {
            return relativeDirectory
        }
        return "\(rootUrl.lastPathComponent)/\(relativeDirectory)"
    }

    private func targetFilePath(for item: RetroRomFileItem, parentRelativeDirectory: String) -> String {
        let parentPath = targetFolderPath(for: parentRelativeDirectory)
        if item.fileGroupType == .single {
            return parentPath.isEmpty ? item.rawName : "\(parentPath)/\(item.rawName)"
        }
        return parentPath.isEmpty ? "\(item.baseName)/" : "\(parentPath)/\(item.baseName)/"
    }

    private func postProcess() {
        if success {
            let files = fileItemPaths.map({ fileItems[$0]! })
            let newFileKeys = files.map({ $0.key })
            RetroRomHomePageState.shared.lastImportDate = startDate
            if self.rootKey != nil {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .romCountChanged, object: nil)
                    NotificationCenter.default.post(name: .retroFolderImported, object: self.rootKey, userInfo: ["fileKeys": newFileKeys])
                }
            } else if files.count > 0 {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .romCountChanged, object: nil)
                    NotificationCenter.default.post(name: .retroFileImported, object: newFileKeys)
                }
            }
        }
    }

    private func saveFolerAndFiles() {
        let fileManager = FileManager.default
        for folder in folderItemPaths {
            let fullPath = destinationRootPath + folder
            do {
                try fileManager.createDirectory(atPath: fullPath, withIntermediateDirectories: false)
            } catch {
                errorProcess(.folderCreationFailed(path: folder))
                deleteFolderFiles()
                return
            }
        }

        var importedCount = 0
        for file in fileItemPaths {
            let formatter = Bundle.localizedString(forKey: "homepage_import_file_copying")
            let message = String(format: formatter, file)
            let title = Bundle.localizedString(forKey: "homepage_import_importing")
            indicatorView.activeMessage(message, title: title)

            do {
                guard let item = fileItems[file], let plans = fileCopyPlans[file] else {
                    throw NSError(domain: "RetroRomError", code: 1, userInfo: [NSLocalizedDescriptionKey: file])
                }

                if item.fileGroupType == .single {
                    let destination = destinationRootPath + file
                    let source = rootUrl.appendingPathComponent(plans[0].source).path(percentEncoded: false)
                    try fileManager.copyItem(atPath: source, toPath: destination)
                } else {
                    let containerPath = destinationRootPath + file
                    try fileManager.createDirectory(atPath: containerPath, withIntermediateDirectories: true)
                    for plan in plans {
                        let source = rootUrl.appendingPathComponent(plan.source).path(percentEncoded: false)
                        let destination = destinationRootPath + plan.destination
                        let parentPath = (destination as NSString).deletingLastPathComponent
                        if !parentPath.isEmpty {
                            try fileManager.createDirectory(atPath: parentPath, withIntermediateDirectories: true)
                        }
                        if !fileManager.fileExists(atPath: destination) {
                            try fileManager.copyItem(atPath: source, toPath: destination)
                        }
                    }
                }
                importedCount += 1
            } catch {
                errorProcess(.fileCopyFailed(path: file))
                deleteFolderFiles()
                return
            }
        }

        let folders = folderItemPaths.map({ folderItems[$0]! })
        let files = fileItemPaths.map({ fileItems[$0]! })
        if !Retro​Rom​Persistence.shared.storeRomFiles(files, folders: folders) {
            deleteFolderFiles()
            errorProcess(.saveToDatabaseFailed)
        } else {
            let rootRawName = rootUrl.lastPathComponent
            if folderItemPaths.contains(rootRawName), let rootFolderItem = folderItems[rootRawName] {
                RetroRomFileManager.shared.folderItem(key: rootParent)?.addSubItemKeys(newFolderKeys: [rootFolderItem.key], newFileKeys: [])
            } else if folderItems[rootRawName] == nil {
                let fileKeys = files.map({ $0.key })
                if fileKeys.count > 0 {
                    RetroRomFileManager.shared.folderItem(key: rootParent)?.addSubItemKeys(newFolderKeys: [], newFileKeys: fileKeys)
                }
            }
            for folder in reusedFolders {
                folder.updateSubItemKeys()
            }
            if importedCount == 0 {
                let message = Bundle.localizedString(forKey: "homepage_import_finished")
                let title = Bundle.localizedString(forKey: "info")
                indicatorView.infoMessage(message, title: title, canDismiss: true)
            } else {
                success = true
                let format = Bundle.localizedString(forKey: "homepage_import_completed")
                let message = NSString.localizedStringWithFormat(format as NSString, importedCount) as String
                let title = Bundle.localizedString(forKey: "homepage_import_success")
                indicatorView.successMessage(message, title: title, canDismiss: true)
            }
        }
    }

    private func deleteFolderFiles() {
        let fileManager = FileManager.default

        // 1. 删除本次拷贝过去的文件
        for file in fileItemPaths {
            let fullPath = destinationRootPath + file
            try? fileManager.removeItem(atPath: fullPath)
        }

        // 2. 删除本次新建的文件夹（必须从深到浅删除）
        for folderPath in folderItemPaths.reversed() {
            // 核心判断：如果这个路径是“重用”的，说明是合并模式下的旧文件夹，不能删
            // 需要通过路径匹配来找到对应的 item 是否在 reusedFolders 中
            let isReused = reusedFolders.contains { item in
                // 这里假设你的 folderItems 存储的是全路径 key
                return folderItems[folderPath]?.key == item.key
            }

            if !isReused {
                let fullPath = destinationRootPath + folderPath
                try? fileManager.removeItem(atPath: fullPath)
            }
        }
    }

    private func makeFileItem(_ filePath: String, fileUrl: URL) -> Bool {
        let p = "\(rootUrl.lastPathComponent)/\(filePath)"
        let formatter = Bundle.localizedString(forKey: "homepage_import_file_checking")
        let message = String(format: formatter, p)
        let title = Bundle.localizedString(forKey: "homepage_import_importing")
        indicatorView.activeMessage(message, title: title)
        if checkFileExists(p) {
            procSemphore.wait()
            if conflictPolicy == .cancel {
                let title = Bundle.localizedString(forKey: "info")
                let message = Bundle.localizedString(forKey: "homepage_import_cancelled")
                indicatorView.infoMessage(message, title: title, canDismiss: true)
                return false
            } else if conflictPolicy == .skip {
                skipedFiles.append(filePath)
                let formatter = Bundle.localizedString(forKey: "homepage_import_file_skipped")
                let message = String(format: formatter, p)
                let title = Bundle.localizedString(forKey: "info")
                indicatorView.infoMessage(message, title: title, canDismiss: false)
                return true
            }
        }

        do {
            guard let key = Retro​Rom​Persistence.shared.getUniqueKey() else {
                errorProcess(.uniqueKeyCreationFailed)
                return false
            }

            let pathAndName = getPathAndName(filePath)
            guard let parentItem = folderItems[pathAndName.path] else {
                errorProcess(.parentFolderDoesNotExist(path: pathAndName.path))
                return false
            }
            let rawName = pathAndName.name
            let parent  = parentItem.key
            let sha256 = try (fileUrl as NSURL).computeSHA256String()
            let resources = try fileUrl.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = resources.fileSize ?? 0
            let item = RetroRomFileItem(key: key, rawName: rawName, parent: parent, createAt: Date(), updateAt: Date(), fileSize: fileSize, sha256: sha256)
            fileItems[p] = item
            fileItemPaths.append(p)
            return true
        } catch {
            errorProcess(.romFileReadFailed(error: error.localizedDescription))
            return false
        }
    }

    private func checkFileExists(_ path: String) -> Bool {
        let fullPath = destinationRootPath + path
        if FileManager.default.fileExists(atPath: fullPath) {
            DispatchQueue.main.async {
                let title = Bundle.localizedString(forKey: "homepage_import_file_exists")
                let msgFormatter = Bundle.localizedString(forKey: "homepage_import_file_exists_path")
                let message = String(format: msgFormatter, path)
                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                let cancelAction = UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel) { [unowned self] _ in
                    self.conflictPolicy = .cancel
                    self.procSemphore.signal()
                }
                alert.addAction(cancelAction)
                let skipAction = UIAlertAction(title: Bundle.localizedString(forKey: "skip"), style: .default) { [unowned self] _ in
                    self.conflictPolicy = .skip
                    self.procSemphore.signal()
                }
                alert.addAction(skipAction)

                UIViewController.currentActive()?.present(alert, animated: true)
            }
            return true
        } else {
            return false
        }
    }

    private func makeSubFolderItem(_ folderPath: String) -> Bool {
        let p = targetFolderPath(for: folderPath)
        let displayPath = "\(rootUrl.lastPathComponent)/\(folderPath)"
        let formatter = Bundle.localizedString(forKey: "homepage_import_folder_checking")
        let message = String(format: formatter, displayPath)
        let title = Bundle.localizedString(forKey: "homepage_import_importing")
        indicatorView.activeMessage(message, title: title)
        if checkFolderExists(p) {
            procSemphore.wait()
            if conflictPolicy == .cancel {
                let title = Bundle.localizedString(forKey: "info")
                let message = Bundle.localizedString(forKey: "homepage_import_cancelled")
                indicatorView.infoMessage(message, title: title, canDismiss: true)
                return false
            } else if conflictPolicy == .skip {
                let formatter = Bundle.localizedString(forKey: "homepage_import_folder_skipped")
                let message = String(format: formatter, p)
                let title = Bundle.localizedString(forKey: "info")
                indicatorView.infoMessage(message, title: title, canDismiss: false)
                skipedFolders.append(folderPath)
                return true
            } else {
                let pathAndName = getPathAndName(folderPath)
                guard let parentItem = folderItems[pathAndName.path] else {
                    errorProcess(.parentFolderDoesNotExist(path: pathAndName.path))
                    return false
                }
                if let item = RetroRomFileManager.shared.folderItem(parent: parentItem.key, rawName: pathAndName.name) {
                    folderItems[p] = item
                    reusedFolders.append(item)
                    return true
                } else {
                    errorProcess(.parentFolderDoesNotExist(path: folderPath))
                    return false
                }
            }
        } else {
            guard let key = Retro​Rom​Persistence.shared.getUniqueKey() else {
                errorProcess(.uniqueKeyCreationFailed)
                return false
            }

            let pathAndName = getPathAndName(folderPath)
            guard let parentItem = folderItems[pathAndName.path] else {
                errorProcess(.parentFolderDoesNotExist(path: pathAndName.path))
                return false
            }

            let item = RetroRomFolderItem(key: key, rawName: pathAndName.name, parent: parentItem.key, createAt: Date(), updateAt: Date())
            folderItems[p] = item
            folderItemPaths.append(p)
            return true
        }
    }

    private func makeRootFolderItem() -> Bool {
        let rootRawName = rootUrl.lastPathComponent
        let formatter = Bundle.localizedString(forKey: "homepage_import_folder_checking")
        let message = String(format: formatter, rootRawName)
        let title = Bundle.localizedString(forKey: "homepage_import_importing")
        defer {
            self.rootKey = folderItems[rootRawName]?.key
        }
        indicatorView.activeMessage(message, title: title)
        if checkFolderExists(rootRawName) {
            procSemphore.wait()
            if conflictPolicy == .cancel {
                let title = Bundle.localizedString(forKey: "info")
                let message = Bundle.localizedString(forKey: "homepage_import_cancelled")
                indicatorView.infoMessage(message, title: title, canDismiss: true)
                return false
            } else if conflictPolicy == .skip {
                let title = Bundle.localizedString(forKey: "info")
                let formatter = Bundle.localizedString(forKey: "homepage_import_folder_skipped_finish")
                let message = String(format: formatter, rootRawName)
                indicatorView.infoMessage(message, title: title, canDismiss: true)
                return false
            }
            if let item = RetroRomFileManager.shared.folderItem(parent: rootParent, rawName: rootRawName) {
                folderItems[rootRawName] = item
                reusedFolders.append(item)
                return true
            } else {
                errorProcess(.parentFolderDoesNotExist(path: rootRawName))
                return false
            }
        } else {
            guard let rootKey = Retro​Rom​Persistence.shared.getUniqueKey() else {
                errorProcess(.uniqueKeyCreationFailed)
                return false
            }
            let item = RetroRomFolderItem(key: rootKey, rawName: rootRawName, parent: rootParent, createAt: Date(), updateAt: Date())
            folderItems[rootRawName] = item
            folderItemPaths.append(rootRawName)
            return true
        }
    }

    private func getPathAndName(_ folderPath: String) -> (path: String, name: String) {
        let rootRawName = rootUrl.lastPathComponent
        let pathString  = NSMutableString(string: folderPath)
        let lastSlashRange = pathString.range(of: "/", options: .backwards)
        if lastSlashRange.location != NSNotFound {
            let folderName = pathString.substring(from: lastSlashRange.location + 1)
            let folderParentPath = pathString.substring(to: lastSlashRange.location)
            let path = flattenRootFolder ? folderParentPath : "\(rootRawName)/\(folderParentPath)"
            return (path: path, name: folderName)
        } else {
            return (path: flattenRootFolder ? "" : rootRawName, name: folderPath)
        }
    }

    private func groupsAtRootContainOnly(group: RetroRomImportGroupBuilder.Group, absorbedDirectory: String?) -> Bool {
        if group.type == .single {
            return parentDirectory(of: group.entryPath).isEmpty
        }

        return absorbedDirectory == ""
    }

    private func shouldSkipDirectory(_ directory: String) -> Bool {
        guard !directory.isEmpty else {
            return false
        }
        return skipedFolders.contains(where: { skipped in
            !skipped.isEmpty && (directory == skipped || directory.hasPrefix(skipped + "/"))
        })
    }

    private func shouldSkipGroup(_ group: RetroRomImportGroupBuilder.Group, absorbedDirectory: String?) -> Bool {
        let directoryToCheck: String
        if let absorbedDirectory {
            directoryToCheck = absorbedDirectory
        } else {
            directoryToCheck = parentDirectory(of: group.entryPath)
        }

        if shouldSkipDirectory(directoryToCheck) {
            return true
        }

        let prospectivePath: String
        if flattenRootFolder, groupsAtRootContainOnly(group: group, absorbedDirectory: absorbedDirectory) {
            prospectivePath = group.type == .single ? lastPathComponent(of: group.entryPath) : ((lastPathComponent(of: group.entryPath) as NSString).deletingPathExtension + "/")
        } else if let absorbedDirectory {
            let parentRelativeDirectory = parentDirectory(of: absorbedDirectory)
            let baseName = (lastPathComponent(of: group.entryPath) as NSString).deletingPathExtension
            let parentPath = targetFolderPath(for: parentRelativeDirectory)
            prospectivePath = parentPath.isEmpty ? "\(baseName)/" : "\(parentPath)/\(baseName)/"
        } else if group.type == .single {
            let parentRelativeDirectory = parentDirectory(of: group.entryPath)
            let parentPath = targetFolderPath(for: parentRelativeDirectory)
            let fileName = lastPathComponent(of: group.entryPath)
            prospectivePath = parentPath.isEmpty ? fileName : "\(parentPath)/\(fileName)"
        } else {
            let parentRelativeDirectory = parentDirectory(of: group.entryPath)
            let parentPath = targetFolderPath(for: parentRelativeDirectory)
            let baseName = (lastPathComponent(of: group.entryPath) as NSString).deletingPathExtension
            prospectivePath = parentPath.isEmpty ? "\(baseName)/" : "\(parentPath)/\(baseName)/"
        }

        return skipedFiles.contains(prospectivePath)
    }

    private func removePendingFile(at targetPath: String) {
        fileItems.removeValue(forKey: targetPath)
        fileCopyPlans.removeValue(forKey: targetPath)
        fileItemPaths.removeAll { $0 == targetPath }
    }

    private func checkFolderExists(_ path: String) -> Bool {
        let fullPath = destinationRootPath + path
        if FileManager.default.fileExists(atPath: fullPath) {
            DispatchQueue.main.async {
                let title = Bundle.localizedString(forKey: "homepage_import_folder_exists")
                let message: String
                let canMerge: Bool
                if FileManager.default.pathIsFile(fullPath) {
                    let msgFormatter = Bundle.localizedString(forKey: "homepage_import_exist_same_name_file_with_folder")
                    let fileName = path.split(separator: "/").last!
                    message = String(format: msgFormatter, String(fileName), path)
                    canMerge = false
                } else {
                    let msgFormatter = Bundle.localizedString(forKey: "homepage_import_folder_exists_path")
                    message = String(format: msgFormatter, path)
                    canMerge = true
                }
                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                let cancelAction = UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel) { [unowned self] _ in
                    self.conflictPolicy = .cancel
                    self.procSemphore.signal()
                }
                alert.addAction(cancelAction)
                let skipAction = UIAlertAction(title: Bundle.localizedString(forKey: "skip"), style: .default) { [unowned self] _ in
                    self.conflictPolicy = .skip
                    self.procSemphore.signal()
                }
                alert.addAction(skipAction)
                if canMerge {
                    let mergeAction = UIAlertAction(title: Bundle.localizedString(forKey: "homepage_import_folder_merge"), style: .default) { [unowned self] _ in
                        self.conflictPolicy = .merge
                        self.procSemphore.signal()
                    }
                    alert.addAction(mergeAction)
                }

                UIViewController.currentActive()?.present(alert, animated: true)
            }
            return true
        } else {
            return false
        }
    }

    private func errorProcess(_ error: RetroRomImportMessage) {
        let title = Bundle.localizedString(forKey: "error")
        let message: String
        switch error {
            case .enumeratorBuildFailed:
                message = Bundle.localizedString(forKey: "homepage_import_error_enumerator_build_failed")
            case .uniqueKeyCreationFailed:
                message = Bundle.localizedString(forKey: "homepage_import_error_unique_key_create_failed")
            case .parentFolderDoesNotExist(path: let path):
                let formatter = Bundle.localizedString(forKey: "homepage_import_error_parent_folder_not_exist")
                message = String(format: formatter, path)
            case .romFileReadFailed(error: let error):
                let formatter = Bundle.localizedString(forKey: "homepage_import_error_rom_file_read_failed")
                message = String(format: formatter, error)
            case .folderCreationFailed(path: let path):
                let formatter = Bundle.localizedString(forKey: "homepage_import_error_folder_create_failed")
                message = String(format: formatter, path)
            case .fileCopyFailed(path: let path):
                let formatter = Bundle.localizedString(forKey: "homepage_import_error_file_copy_failed")
                message = String(format: formatter, path)
            case .saveToDatabaseFailed:
                message = Bundle.localizedString(forKey: "homepage_import_error_database_save_failed")
        }
        indicatorView.errorMessage(message, title: title, canDismiss: true)
    }
}
