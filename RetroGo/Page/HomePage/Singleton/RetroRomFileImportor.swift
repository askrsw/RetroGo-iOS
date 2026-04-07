//
//  RetroRomFileImportor.swift
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

final class RetroRomFileImportor: Thread {
    enum ConflictPolicy {
        case skip, cancel
    }

    enum IncompletePolicy {
        case skip, cancel
    }

    private let urls: [URL]
    private let rootParent: String
    private let destinationRootPath: String

    private let indicatorView = RetroRomActivityView(mainTitle: Bundle.localizedString(forKey: "homepage_import_importing"))
    private let procSemphore = DispatchSemaphore(value: 0)
    private var conflictPolicy = ConflictPolicy.skip
    private var incompletePolicy = IncompletePolicy.skip
    private var sourceFiles: [RetroRomImportGroupBuilder.SourceFile] = []
    private var sourceFileMap: [String: RetroRomImportGroupBuilder.SourceFile] = [:]
    private var fileItems: [RetroRomFileItem] = []

    private let startDate: Date = Date()
    private var success = false

    init?(urls: [URL], rootParent: String) {
        self.urls = urls
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

        if !buildFileItems() {
            return
        }

        saveFiles()
    }
}

extension RetroRomFileImportor {
    private func postProcess() {
        if success {
            let newFileKeys = fileItems.map({ $0.key })
            RetroRomHomePageState.shared.lastImportDate = startDate
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .romCountChanged, object: nil)
                NotificationCenter.default.post(name: .retroFileImported, object: newFileKeys)
            }
        }
    }

    private func buildFileItems() -> Bool {
        do {
            let builder = RetroRomImportGroupBuilder(indicatorView: indicatorView)
            sourceFiles.removeAll(keepingCapacity: true)
            sourceFileMap.removeAll(keepingCapacity: true)

            sourceFiles = try collectSelectedSourceFiles()
            sourceFileMap = Dictionary(uniqueKeysWithValues: sourceFiles.map { ($0.relativePath, $0) })
            let analysis = try builder.analyzeGroups(from: sourceFiles)
            if !handleIncompleteGroups(analysis.incompleteGroups) {
                let title = Bundle.localizedString(forKey: "info")
                let message = Bundle.localizedString(forKey: "homepage_import_cancelled")
                indicatorView.infoMessage(message, title: title, canDismiss: true)
                return false
            }

            fileItems = try builder.buildFileItems(groups: analysis.groups, map: analysis.map, parent: rootParent) {
                Retro​Rom​Persistence.shared.getUniqueKey()
            }

            var filteredItems: [RetroRomFileItem] = []
            for item in fileItems {
                if checkFileExists(item) {
                    procSemphore.wait()
                    if conflictPolicy == .cancel {
                        let title = Bundle.localizedString(forKey: "info")
                        let message = Bundle.localizedString(forKey: "homepage_import_cancelled")
                        indicatorView.infoMessage(message, title: title, canDismiss: true)
                        return false
                    } else if conflictPolicy == .skip {
                        let formatter = Bundle.localizedString(forKey: "homepage_import_file_skipped")
                        let message = String(format: formatter, item.itemName)
                        let title = Bundle.localizedString(forKey: "info")
                        indicatorView.infoMessage(message, title: title, canDismiss: false)
                        continue
                    }
                }
                filteredItems.append(item)
            }
            fileItems = filteredItems
            return true
        } catch RetroRomImportGroupBuilder.BuildError.keyCreationFailed {
            errorProcess(.uniqueKeyCreationFailed)
            return false
        } catch RetroRomImportGroupBuilder.BuildError.missingEntryFile(let path), RetroRomImportGroupBuilder.BuildError.missingMemberFile(let path) {
            errorProcess(.romFileReadFailed(error: path))
            return false
        } catch RetroRomImportGroupBuilder.BuildError.duplicatedRelativePath(let path) {
            errorProcess(.romFileReadFailed(error: path))
            return false
        } catch {
            errorProcess(.romFileReadFailed(error: error.localizedDescription))
            return false
        }
    }

    private func saveFiles() {
        var errorOccured = false
        for item in fileItems {
            if !copyFileItem(item) {
                errorOccured = true
                break
            }
        }

        if !errorOccured {
            if !Retro​Rom​Persistence.shared.storeRomFiles(fileItems, folders: []) {
                errorProcess(.saveToDatabaseFailed)
                deleteFiles()
                return
            }
        }

        if errorOccured {
            deleteFiles()
        } else {
            let importedCount = fileItems.count
            let fileKeys = fileItems.map({ $0.key })
            RetroRomFileManager.shared.folderItem(key: rootParent)?.addSubItemKeys(newFolderKeys: [], newFileKeys: fileKeys)
            if importedCount == 0 {
                let message = Bundle.localizedString(forKey: "homepage_import_finished")
                let title = Bundle.localizedString(forKey: "info")
                indicatorView.infoMessage(message, title: title, canDismiss: true)
            } else {
                success = true
                let message = Bundle.localizedString(forKey: "homepage_import_completed", count: importedCount)
                let title = Bundle.localizedString(forKey: "homepage_import_success")
                indicatorView.successMessage(message, title: title, canDismiss: true)
            }
        }
    }

    private func copyFileItem(_ item: RetroRomFileItem) -> Bool {
        let fileManager = FileManager.default
        let formatter = Bundle.localizedString(forKey: "homepage_import_file_copying")
        let message = String(format: formatter, item.itemName)
        let title = Bundle.localizedString(forKey: "homepage_import_importing")
        indicatorView.activeMessage(message, title: title)

        do {
            if item.fileGroupType == .single {
                guard let source = sourceFileMap[item.rawName] else {
                    throw NSError(domain: "RetroRomError", code: 1, userInfo: [NSLocalizedDescriptionKey: item.rawName])
                }
                let dstPath = destinationRootPath + item.rawName
                try copySourceFile(source, toPath: dstPath)
            } else {
                guard let containerPath = item.fullPath else {
                    throw NSError(domain: "RetroRomError", code: 2, userInfo: [NSLocalizedDescriptionKey: item.itemName])
                }
                try fileManager.createDirectory(atPath: containerPath, withIntermediateDirectories: true)
                for sub in item.subItems {
                    guard let source = sourceFileMap[sub.rawName] else {
                        throw NSError(domain: "RetroRomError", code: 3, userInfo: [NSLocalizedDescriptionKey: sub.rawName])
                    }
                    let dstPath = containerPath + sub.rawName
                    let parentPath = (dstPath as NSString).deletingLastPathComponent
                    if !parentPath.isEmpty {
                        try fileManager.createDirectory(atPath: parentPath, withIntermediateDirectories: true)
                    }
                    try copySourceFile(source, toPath: dstPath)
                }
            }
            return true
        } catch {
            errorProcess(.fileCopyFailed(path: item.itemName))
            return false
        }
    }

    private func deleteFiles() {
        let fileManager = FileManager.default
        for item in fileItems {
            if let path = item.fullPath {
                try? fileManager.removeItem(atPath: path)
            }
        }
    }

    private func collectSelectedSourceFiles() throws -> [RetroRomImportGroupBuilder.SourceFile] {
        var files: [RetroRomImportGroupBuilder.SourceFile] = []
        files.reserveCapacity(urls.count)

        for url in urls.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            let formatter = Bundle.localizedString(forKey: "homepage_import_file_checking")
            let message = String(format: formatter, url.lastPathComponent)
            indicatorView.activeMessage(message, title: Bundle.localizedString(forKey: "homepage_import_importing"))
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "RetroRomError", code: 4, userInfo: [NSLocalizedDescriptionKey: url.lastPathComponent])
            }
            do {
                let source = try RetroRomImportGroupBuilder.SourceFile(relativePath: url.lastPathComponent, url: url)
                files.append(source)
            } catch {
                url.stopAccessingSecurityScopedResource()
                throw error
            }
            url.stopAccessingSecurityScopedResource()
        }
        return files
    }

    private func copySourceFile(_ source: RetroRomImportGroupBuilder.SourceFile, toPath destinationPath: String) throws {
        let shouldStopAccessing = source.url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                source.url.stopAccessingSecurityScopedResource()
            }
        }
        try FileManager.default.copyItem(atPath: source.url.path(percentEncoded: false), toPath: destinationPath)
    }

    private func handleIncompleteGroups(_ incompleteGroups: [RetroRomImportGroupBuilder.IncompleteGroup]) -> Bool {
        guard !incompleteGroups.isEmpty else {
            return true
        }
        promptIncompleteGroups(incompleteGroups)
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
            let format = Bundle.localizedString(forKey: "homepage_import_incomplete_files_message")
            let message = NSString.localizedStringWithFormat(format as NSString, details) as String
            let title = Bundle.localizedString(forKey: "homepage_import_incomplete_files_title")
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

    private func checkFileExists(_ item: RetroRomFileItem) -> Bool {
        let targetPath: String
        if item.fileGroupType == .single {
            targetPath = destinationRootPath + item.rawName
        } else {
            targetPath = destinationRootPath + item.baseName
        }
        if FileManager.default.fileExists(atPath: targetPath) {
            DispatchQueue.main.async {
                let title = Bundle.localizedString(forKey: "homepage_import_file_exists")
                let message: String
                if FileManager.default.pathIsDirectory(targetPath) {
                    let msgFormatter = Bundle.localizedString(forKey: "homepage_import_exist_same_name_folder_with_file")
                    message = String(format: msgFormatter, item.itemName, item.itemName)
                } else {
                    let msgFormatter = Bundle.localizedString(forKey: "homepage_import_file_exists_path")
                    message = String(format: msgFormatter, item.itemName)
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
