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

    private let urls: [URL]
    private let rootParent: String
    private let destinationRootPath: String

    private let indicatorView = RetroRomActivityView(mainTitle: Bundle.localizedString(forKey: "homepage_import_importing"))
    private let procSemphore = DispatchSemaphore(value: 0)
    private var conflictPolicy = ConflictPolicy.skip
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

        for url in urls {
            guard url.startAccessingSecurityScopedResource() else {
                continue
            }

            let success = makeFileItem(url)
            url.stopAccessingSecurityScopedResource()
            if !success {
                return
            }
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

    private func saveFiles() {
        let fileManager = FileManager.default
        var errorOccured = false
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else {
                continue
            }

            do {
                defer { url.stopAccessingSecurityScopedResource() }

                let fileName = url.lastPathComponent
                if fileItems.contains(where: { $0.rawName == fileName }) {
                    let formatter = Bundle.localizedString(forKey: "homepage_import_file_copying")
                    let message = String(format: formatter, fileName)
                    let title = Bundle.localizedString(forKey: "homepage_import_importing")
                    indicatorView.activeMessage(message, title: title)

                    let dstPath = destinationRootPath + fileName
                    do {
                        try fileManager.copyItem(atPath: url.path(percentEncoded: false), toPath: dstPath)
                    } catch {
                        errorProcess(.fileCopyFailed(path: fileName))
                        errorOccured = true
                    }
                }
            }

            if errorOccured {
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

    private func deleteFiles() {
        let fileManager = FileManager.default
        for item in fileItems {
            let dstPath = destinationRootPath + item.rawName
            try? fileManager.removeItem(atPath: dstPath)
        }
    }

    private func makeFileItem(_ url: URL) -> Bool {
        let formatter = Bundle.localizedString(forKey: "homepage_import_file_checking")
        let message = String(format: formatter, url.lastPathComponent)
        let title = Bundle.localizedString(forKey: "homepage_import_importing")
        indicatorView.activeMessage(message, title: title)

        if checkFileExists(url) {
            procSemphore.wait()
            if conflictPolicy == .cancel {
                let title = Bundle.localizedString(forKey: "info")
                let message = Bundle.localizedString(forKey: "homepage_import_cancelled")
                indicatorView.infoMessage(message, title: title, canDismiss: true)
                return false
            } else if conflictPolicy == .skip {
                let formatter = Bundle.localizedString(forKey: "homepage_import_file_skipped")
                let message = String(format: formatter, url.lastPathComponent)
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

            let rawName = url.lastPathComponent
            let parent  = rootParent
            let sha256 = try (url as NSURL).computeSHA256String()
            let resources = try url.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = resources.fileSize ?? 0
            let item = RetroRomFileItem(key: key, rawName: rawName, parent: parent, createAt: Date(), updateAt: Date(), fileSize: fileSize, sha256: sha256)
            fileItems.append(item)
            return true
        } catch {
            errorProcess(.romFileReadFailed(error: error.localizedDescription))
            return false
        }
    }

    private func checkFileExists(_ url: URL) -> Bool {
        let fileName = url.lastPathComponent
        let fullPath = destinationRootPath + fileName
        if FileManager.default.fileExists(atPath: fullPath) {
            DispatchQueue.main.async {
                let title = Bundle.localizedString(forKey: "homepage_import_file_exists")
                let message: String
                if FileManager.default.pathIsDirectory(fullPath) {
                    let msgFormatter = Bundle.localizedString(forKey: "homepage_import_exist_same_name_folder_with_file")
                    message = String(format: msgFormatter, fileName, fileName)
                } else {
                    let msgFormatter = Bundle.localizedString(forKey: "homepage_import_file_exists_path")
                    message = String(format: msgFormatter, fileName)
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
