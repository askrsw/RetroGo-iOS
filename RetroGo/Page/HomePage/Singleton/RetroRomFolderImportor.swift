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

    private let rootUrl: URL
    private let rootParent: String
    private let destinationRootPath: String

    private let indicatorView = RetroRomActivityView(mainTitle: Bundle.localizedString(forKey: "homepage_import_importing"))
    private let procSemphore = DispatchSemaphore(value: 0)
    private var conflictPolicy = ConflictPolicy.skip

    private var folderItems: [String: RetroRomFolderItem] = [:]
    private var folderItemPaths: [String] = []
    private var skipedFolders: [String] = []
    private var fileItems: [String: RetroRomFileItem] = [:]
    private var fileItemPaths: [String] = []
    private var skipedFiles: [String] = []
    private var reusedFolders: [RetroRomFolderItem] = []
    private var rootKey: String?

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

        guard makeRootFolderItem() else {
            return
        }

        let fileManager = FileManager.default
        let rootPath = rootUrl.path(percentEncoded: false)
        let supportedExtensions = RetroArchX.shared().allExtensionsSet
        if let enumerator = fileManager.enumerator(atPath: rootPath) {
            for case let filePath as String in enumerator {
                if filePath.hasPrefix(".DS_Store") || filePath.hasSuffix(".DS_Store") {
                    continue
                }

                if skipedFolders.contains(where: { filePath.hasPrefix($0) }) {
                    continue
                }

                let fileUrl = rootUrl.appendingPathComponent(filePath)
                let ext = fileUrl.pathExtension.lowercased()
                if !supportedExtensions.contains(ext) {
                    continue
                }
                if fileManager.urlIsDirectory(fileUrl) {
                    if !makeSubFolderItem(filePath) {
                        return
                    }
                } else if fileManager.urlIsFile(fileUrl) {
                    if !makeFileItem(filePath, fileUrl: fileUrl) {
                        return
                    }
                }
            }

            saveFolerAndFiles()
        } else {
            return errorProcess(.enumeratorBuildFailed)
        }
    }
}

extension RetroRomFolderImportor {
    private func postProcess() {
        if success {
            let files = fileItemPaths.map({ fileItems[$0]! })
            let fileKeys = files.map({ $0.key })
            RetroRomHomePageState.shared.lastImportDate = startDate
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .romCountChanged, object: nil)
                NotificationCenter.default.post(name: .retroFolderImported, object: self.rootKey, userInfo: ["fileKeys": fileKeys])
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

            let fullPath = destinationRootPath + file
            do {
                var isDir: ObjCBool = false
                let exists = fileManager.fileExists(atPath: fullPath, isDirectory: &isDir)
                if exists {
                    if isDir.boolValue {
                        continue
                    } else {
                        throw NSError(domain: "RetroRomError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Path occupied by a file"])
                    }
                }
                let src = rootUrl.deletingLastPathComponent().appendingPathComponent(file).path(percentEncoded: false)
                try fileManager.copyItem(atPath: src, toPath: fullPath)
                importedCount += 1
            } catch {
                errorProcess(.fileCopyFailed(path: file))
                deleteFolderFiles()
                return
            }
        }

        let folders = folderItemPaths.map({ folderItems[$0]! })
        let files = fileItemPaths.map({ fileItems[$0]! })
        if !RetroRomFileManager.shared.storeRomFiles(files, folders: folders) {
            deleteFolderFiles()
            errorProcess(.saveToDatabaseFailed)
        } else {
            let rootRawName = rootUrl.lastPathComponent
            if let rootFolderItem = folderItems[rootRawName] {
                RetroRomFileManager.shared.folderItem(key: rootParent)?.addSubItemKeys(newFolderKeys: [rootFolderItem.key], newFileKeys: [])
            }
            for folder in reusedFolders {
                folder.updateSubItemKeys()
            }
            if importedCount == 0 {
                let message = Bundle.localizedString(forKey: "homepage_import_finished")
                let title = Bundle.localizedString(forKey: "info")
                indicatorView.infoMessage(message, title: title, canDismiss: true)
            } else if importedCount == 1 {
                success = true
                let message = Bundle.localizedString(forKey: "homepage_import_completed")
                let title = Bundle.localizedString(forKey: "homepage_import_success")
                indicatorView.successMessage(message, title: title, canDismiss: true)
            } else {
                success = true
                let formatter = Bundle.localizedString(forKey: "homepage_import_completed_s")
                let message = String(format: formatter, importedCount)
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
            guard let key = RetroRomFileManager.shared.getUniqueKey() else {
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
        let p = "\(rootUrl.lastPathComponent)/\(folderPath)"
        let formatter = Bundle.localizedString(forKey: "homepage_import_folder_checking")
        let message = String(format: formatter, p)
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
            guard let key = RetroRomFileManager.shared.getUniqueKey() else {
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
            guard let rootKey = RetroRomFileManager.shared.getUniqueKey() else {
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
            let path = "\(rootRawName)/\(folderParentPath)"
            return (path: path, name: folderName)
        } else {
            return (path: rootRawName, name: folderPath)
        }
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
