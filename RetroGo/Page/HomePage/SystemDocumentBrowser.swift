//
//  SystemDocumentBrowser.swift
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
import RACoordinator

final class SystemDocumentBrowser: UIDocumentBrowserViewController {

    // https://betterprogramming.pub/how-to-fix-greyed-icons-on-ios-document-browser-and-picker-8dea8a76d6e7
    init() {
        let supportedExtensions = RetroArchX.shared().allSupportedExtensions
        super.init(forOpening: supportedExtensions)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.tintColor = .accent

        allowsDocumentCreation = false
        defaultDocumentAspectRatio = 256.0 / 240
        shouldShowFileExtensions = true
        allowsPickingMultipleItems = false
        delegate = self

        additionalTrailingNavigationBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "gear"), style: .plain, target: self, action: #selector(settingsAction)),
        ]
    }
}

extension SystemDocumentBrowser {
    @objc
    private func settingsAction() {
        let controller = AppSettingViewController()
        let naviController = UINavigationController(rootViewController: controller)
        present(naviController, animated: true)
    }
}

extension SystemDocumentBrowser: UIDocumentBrowserViewControllerDelegate {
    func documentBrowser(_ controller: UIDocumentBrowserViewController, didPickDocumentURLs documentURLs: [URL]) {
        guard RetroArchX.shared().initialized, let url = documentURLs.first else {
            return
        }

        if let core = RetroRomCoreManager.shared.getRunningCore(url) {
            RetroArchX.playGame(romUrl: url, core: core)
        } else {
            let controller = RetroRomCoreSelectViewController(action: .runRomWithUrl(url: url))
            let navController = UINavigationController(rootViewController: controller)
            present(navController, animated: true)
        }
    }

    func documentBrowser(_ controller: UIDocumentBrowserViewController, didImportDocumentAt sourceURL: URL, toDestinationURL destinationURL: URL) { }

    func documentBrowser(_ controller: UIDocumentBrowserViewController, failedToImportDocumentAt documentURL: URL, error: Error?) { }

    func documentBrowser(_ controller: UIDocumentBrowserViewController, didRequestDocumentCreationWithHandler importHandler: @escaping (URL?, UIDocumentBrowserViewController.ImportMode) -> Void) { }
}
