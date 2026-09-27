//
//  MameCheatLibraryViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/9/27.
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
import SnapKit
import ObjcHelper
import UniformTypeIdentifiers

/// Status of the imported MAME cheat collection, with import/delete. Opened from the MAME
/// core page, and from the in-game cheat list when nothing has been imported yet.
final class MameCheatLibraryViewController: UIViewController {
    private enum Row {
        case status
        case sourceFile
        case importedAt
        case importCollection
        case download
        case delete
    }

    private var sections: [[Row]] = []
    private lazy var tableView = configUI()
    /// Called after a successful import (the in-game list reloads its guide).
    var onImport: (() -> Void)?

    /// Pushes the page, or presents it in its own navigation controller.
    static func show(from viewController: UIViewController, onImport: (() -> Void)? = nil) {
        let page = MameCheatLibraryViewController()
        page.onImport = onImport
        if let navigationController = viewController.navigationController {
            navigationController.pushViewController(page, animated: true)
        } else {
            let navigation = UINavigationController(rootViewController: page)
            page.navigationItem.leftBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "xmark"), style: .plain, target: page, action: #selector(closeAction))
            viewController.present(navigation, animated: true)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let title = Bundle.localizedString(forKey: "mame_cheat_library_title")
        navigationItem.title = title
        navigationItem.titleView = Self.makeIconTitleView(title, icon: IconRender.shared.settingsIcon(
            symbol: "star.circle", background: .cheatIconColor, size: CGSize(width: 28, height: 28)))
        navigationItem.largeTitleDisplayMode = .never
        _ = tableView
        reload()
    }

    private func configUI() -> UITableView {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.tintColor = .mainColor
        table.register(RGSectionFooterView.self, forHeaderFooterViewReuseIdentifier: RGSectionFooterView.className)
        view.addSubview(table)
        table.snp.makeConstraints { $0.edges.equalToSuperview() }
        return table
    }

    private func reload() {
        let info = MameCheatLibrary.shared.info
        if info != nil {
            sections = [[.status, .sourceFile, .importedAt], [.importCollection, .download], [.delete]]
        } else {
            sections = [[.status], [.importCollection, .download]]
        }
        tableView.reloadData()
    }

    @objc private func closeAction() {
        dismiss(animated: true)
    }

    // MARK: - Actions

    private func pickCollection() {
        var types: [UTType] = [.zip]
        if let sevenZip = UTType(filenameExtension: "7z") { types.insert(sevenZip, at: 0) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func importCollection(at url: URL) {
        let title = Bundle.localizedString(forKey: "mame_cheat_import_title")
        let activity = RetroRomActivityView(mainTitle: title)
        activity.install()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try MameCheatLibrary.shared.importCollection(at: url) { message in
                    activity.activeMessage(message, title: title)
                }
            }
            try? FileManager.default.removeItem(at: url)
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    let message = String(format: Bundle.localizedString(forKey: "mame_cheat_import_done"), info.setCount)
                    activity.successMessage(message, title: title, canDismiss: true)
                    self?.onImport?()
                case .failure(let error):
                    activity.errorMessage(error.localizedDescription, title: title, canDismiss: true)
                }
                self?.reload()
            }
        }
    }

    private func confirmDelete(from indexPath: IndexPath) {
        let alert = UIAlertController(title: Bundle.localizedString(forKey: "mame_cheat_delete_title"),
                                      message: Bundle.localizedString(forKey: "mame_cheat_delete_message"),
                                      preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "delete"), style: .destructive) { [weak self] _ in
            MameCheatLibrary.shared.deleteLibrary()
            self?.reload()
        })
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel))
        if let popover = alert.popoverPresentationController, let cell = tableView.cellForRow(at: indexPath) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }
        present(alert, animated: true)
    }
}

extension MameCheatLibraryViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        var content = UIListContentConfiguration.valueCell()
        let info = MameCheatLibrary.shared.info
        switch sections[indexPath.section][indexPath.row] {
        case .status:
            content.text = Bundle.localizedString(forKey: "mame_cheat_library_status")
            content.secondaryText = info.map {
                String(format: Bundle.localizedString(forKey: "mame_cheat_library_games"), $0.setCount)
            } ?? Bundle.localizedString(forKey: "mame_cheat_library_not_imported")
            cell.selectionStyle = .none
        case .sourceFile:
            content.text = Bundle.localizedString(forKey: "mame_cheat_library_source_file")
            content.secondaryText = info?.sourceFileName ?? "-"
            cell.selectionStyle = .none
        case .importedAt:
            content.text = Bundle.localizedString(forKey: "mame_cheat_library_imported_at")
            content.secondaryText = info?.importedAt.map {
                DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short)
            } ?? "-"
            cell.selectionStyle = .none
        case .importCollection:
            content = UIListContentConfiguration.cell()
            content.text = Bundle.localizedString(forKey: info == nil ? "mame_cheat_import_action" : "mame_cheat_reimport_action")
            content.image = UIImage(systemName: "square.and.arrow.down")
            content.textProperties.color = .mainColor
        case .download:
            content = UIListContentConfiguration.cell()
            content.text = Bundle.localizedString(forKey: "mame_cheat_download_action")
            content.image = UIImage(systemName: "safari")
            content.textProperties.color = .mainColor
        case .delete:
            content = UIListContentConfiguration.cell()
            content.text = Bundle.localizedString(forKey: "mame_cheat_delete_title")
            content.image = UIImage(systemName: "trash")
            content.imageProperties.tintColor = .systemRed
            content.textProperties.color = .systemRed
        }
        cell.contentConfiguration = content
        return cell
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == 1 else { return nil }
        let footer = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionFooterView.className) as? RGSectionFooterView
        footer?.text = String(format: Bundle.localizedString(forKey: "mame_cheat_library_footer"),
                              MameCheatLibrary.sourceName, MameCheatLibrary.sourceURL.host ?? "")
        return footer
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section][indexPath.row] {
        case .importCollection:
            Vibration.selection.vibrate()
            pickCollection()
        case .download:
            UIApplication.shared.open(MameCheatLibrary.sourceURL)
        case .delete:
            confirmDelete(from: indexPath)
        default:
            break
        }
    }
}

extension MameCheatLibraryViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        importCollection(at: url)
    }
}
