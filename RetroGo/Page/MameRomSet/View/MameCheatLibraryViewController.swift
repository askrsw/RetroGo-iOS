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
import XMLTextRenderKit

/// Status of the imported MAME cheat collection, with import/delete. Opened from the MAME
/// core page, and from the in-game cheat list when nothing has been imported yet.
final class MameCheatLibraryViewController: UIViewController {
    private enum Row {
        case status
        case release
        case sourceFile
        case importedAt
        case notes
        case importCollection
        case guide
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
        NotificationCenter.default.addObserver(self, selector: #selector(libraryDidChange), name: .mameCheatLibraryDidChange, object: nil)
        reload()
    }

    @objc private func libraryDidChange() {
        reload()
        onImport?()
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
        if let info = MameCheatLibrary.shared.info {
            var status: [Row] = [.status]
            if info.releaseMameVersion != nil { status.append(.release) }
            status += [.sourceFile, .importedAt]
            if info.hasNotes { status.append(.notes) }
            sections = [status, [.importCollection, .guide, .download], [.delete]]
        } else {
            sections = [[.status], [.importCollection, .guide, .download]]
        }
        tableView.reloadData()
    }

    @objc private func closeAction() {
        dismiss(animated: true)
    }

    // MARK: - Actions

    /// cheat.txt from the release zip: Pugsy's instructions and the contributor credits.
    private func showNotes() {
        guard let notes = MameCheatLibrary.shared.notesText() else { return }
        let page = UIViewController()
        page.view.backgroundColor = .systemBackground
        page.navigationItem.title = Bundle.localizedString(forKey: "mame_cheat_library_notes")
        let textView = UITextView()
        textView.isEditable = false
        textView.text = notes
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 24, right: 12)
        textView.dataDetectorTypes = .link
        page.view.addSubview(textView)
        textView.snp.makeConstraints { $0.edges.equalToSuperview() }
        navigationController?.pushViewController(page, animated: true)
    }

    private func confirmDelete(from indexPath: IndexPath) {
        let alert = UIAlertController(title: Bundle.localizedString(forKey: "mame_cheat_delete_title"),
                                      message: Bundle.localizedString(forKey: "mame_cheat_delete_message"),
                                      preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "delete"), style: .destructive) {  _ in
            MameCheatLibrary.shared.deleteLibrary()
            NotificationCenter.default.post(name: .mameCheatLibraryDidChange, object: nil)
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
        case .release:
            content.text = Bundle.localizedString(forKey: "mame_cheat_library_release")
            content.secondaryText = info.map { info in
                [info.releaseMameVersion.map { "MAME \($0)" }, info.releaseDate].compactMap { $0 }.joined(separator: " · ")
            }
            cell.selectionStyle = .none
        case .notes:
            content.text = Bundle.localizedString(forKey: "mame_cheat_library_notes")
            cell.accessoryType = .disclosureIndicator
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
        case .guide:
            content = UIListContentConfiguration.cell()
            content.text = Bundle.localizedString(forKey: "mame_cheat_guide_action")
            content.image = UIImage(systemName: "questionmark.circle")
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
            MameCheatImporter.pickAndImport(from: self)
        case .guide:
            Vibration.selection.vibrate()
            Self.showGuide(from: self)
        case .download:
            UIApplication.shared.open(MameCheatLibrary.sourceURL)
        case .delete:
            confirmDelete(from: indexPath)
        case .notes:
            showNotes()
        default:
            break
        }
    }
}

/// Picks cheat.7z or Pugsy's release zip and imports it, with progress; used by the library
/// page and the guide's "import" command. Posts `mameCheatLibraryDidChange` on success.
final class MameCheatImporter: NSObject, UIDocumentPickerDelegate {
    /// Keeps the importer alive while the picker is up.
    private static var active: MameCheatImporter?

    static func pickAndImport(from viewController: UIViewController) {
        var types: [UTType] = [.zip]
        if let sevenZip = UTType(filenameExtension: "7z") { types.insert(sevenZip, at: 0) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        let importer = MameCheatImporter()
        picker.delegate = importer
        picker.allowsMultipleSelection = false
        active = importer
        viewController.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        Self.active = nil
        guard let url = urls.first else { return }
        Self.importCollection(at: url)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Self.active = nil
    }

    private static func importCollection(at url: URL) {
        let title = Bundle.localizedString(forKey: "mame_cheat_import_title")
        let activity = RetroRomActivityView(mainTitle: title)
        activity.install()
        DispatchQueue.global(qos: .userInitiated).async {
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
                    NotificationCenter.default.post(name: .mameCheatLibraryDidChange, object: nil)
                case .failure(let error):
                    activity.errorMessage(error.localizedDescription, title: title, canDismiss: true)
                }
            }
        }
    }
}

extension Notification.Name {
    /// The imported MAME cheat collection was replaced or deleted.
    static let mameCheatLibraryDidChange = Notification.Name("RetroGoMameCheatLibraryDidChange")
}

// MARK: - Guide

extension MameCheatLibraryViewController {
    /// `<command key="importCollection">` in the guide XML.
    static let importCommand = "importCollection"

    /// The guide XML in the app language.
    static var guideURL: URL? {
        let language = Bundle.currentSimpleLanguageKey()
        return Bundle.main.url(forResource: "mame_cheat_guide", withExtension: "xml", subdirectory: "Data/xmls/\(language)")
            ?? Bundle.main.url(forResource: "mame_cheat_guide", withExtension: "xml", subdirectory: "Data/xmls/en")
    }

    /// Step-by-step guide with screenshots: download the collection in Safari, import the zip.
    static func showGuide(from viewController: UIViewController) {
        guard let url = guideURL else { return }
        let config = XMLRenderConfig()
        config.mainColor = .mainColor
        let title = Bundle.localizedString(forKey: "mame_cheat_guide_title")
        let icon = IconRender.shared.settingsIcon(symbol: "questionmark.circle.fill", background: .cheatIconColor, size: CGSize(width: 22, height: 22))
        weak var weakGuide: UIViewController?
        let guide = XMLTextViewController(xmlUrl: url, title: title, icon: icon, config: config, commandHandlers: [
            importCommand: {
                guard let guide = weakGuide else { return }
                Vibration.selection.vibrate()
                MameCheatImporter.pickAndImport(from: guide)
            }
        ], imageInteractionHandler: { [weak viewController] tap in
            guard let presenter = viewController?.navigationController ?? viewController else { return }
            presenter.present(MameGuideImageViewController(image: tap.image), animated: true)
        }, usesDynamicType: true)
        weakGuide = guide
        if let navigationController = viewController.navigationController {
            navigationController.pushViewController(guide, animated: true)
        } else {
            let navigation = UINavigationController(rootViewController: guide)
            guide.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak navigation] _ in
                navigation?.dismiss(animated: true)
            })
            viewController.present(navigation, animated: true)
        }
    }
}

/// A screenshot of the guide at full size: pinch to zoom, tap to close.
final class MameGuideImageViewController: UIViewController, UIScrollViewDelegate {
    private let image: UIImage
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()

    init(image: UIImage) {
        self.image = image
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.92)
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        scrollView.addSubview(imageView)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
        view.accessibilityViewIsModal = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if scrollView.zoomScale == 1 {
            imageView.frame = CGRect(origin: .zero, size: scrollView.bounds.size)
            scrollView.contentSize = scrollView.bounds.size
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    override func accessibilityPerformEscape() -> Bool {
        close()
        return true
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}
