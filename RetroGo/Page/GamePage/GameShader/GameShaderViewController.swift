//
//  GameShaderViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/19.
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
import UniformTypeIdentifiers
import ObjcHelper

enum GameShaderAppearance {
    static var background: UIColor { .secondarySystemBackground }
    static var card: UIColor { .tertiarySystemBackground }

    static func configureSheet(_ navigation: UINavigationController) {
        navigation.overrideUserInterfaceStyle = .dark
        navigation.view.backgroundColor = background
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = background
        appearance.shadowColor = .clear
        navigation.navigationBar.standardAppearance = appearance
        navigation.navigationBar.scrollEdgeAppearance = appearance
        navigation.navigationBar.compactAppearance = appearance
        guard let sheet = navigation.sheetPresentationController else { return }
        sheet.detents = [.medium()]
        sheet.selectedDetentIdentifier = .medium
        sheet.prefersGrabberVisible = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        if #available(iOS 26.1, *) {
            sheet.backgroundEffect = UIColorEffect(color: background)
        }
    }

    static func registerSections(in table: UITableView) {
        table.register(RGSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: RGSectionHeaderView.className)
        table.register(RGSectionFooterView.self, forHeaderFooterViewReuseIdentifier: RGSectionFooterView.className)
        table.estimatedSectionHeaderHeight = 40
        table.estimatedSectionFooterHeight = 44
    }
}

/// Owns the complete in-game flow, including orientation restoration after dismissal.
final class GameShaderNavigationController: UINavigationController {
    weak var gamePage: GamePageViewController?
    var onClose: (() -> Void)?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        let close = onClose
        onClose = nil
        close?()
        gamePage?.endShaderPresentation()
    }
}

final class GameShaderViewController: UITableViewController, UIDocumentPickerDelegate {
    private enum Group: String {
        case featured = "builtins", imported = "imported_shaders"
        var title: String { shaderText(rawValue) }
    }
    private enum Row {
        case inherit, off, current, group(Group), preset(GameShaderPreset), folder(GameShaderFolder), emptyFolder, importFolder, notices
    }
    private enum Deletion {
        case package(id: String, title: String)
        case preset(GameShaderPreset)
    }
    private let session: GameShaderSession
    private let modal: Bool
    private var folder: GameShaderFolder?
    private weak var flowRoot: GameShaderViewController?
    private var importedFolders: [GameShaderFolder]?
    private var collapsed: Set<Group> = [.imported]
    private var rows: [[Row]] = []
    private var headings: [String?] = []
    private var finished = false
    private var importing = false
    private var selectionTask: Task<Void, Never>?
    private var selectionRequest = UUID()

    init(session: GameShaderSession, modal: Bool, folder: GameShaderFolder? = nil, root: GameShaderViewController? = nil) {
        self.session = session
        self.modal = modal
        self.folder = folder
        self.flowRoot = root
        super.init(style: .insetGrouped)
        isModalInPresentation = true
        overrideUserInterfaceStyle = .dark
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = folder?.title ?? shaderText("title")
        view.backgroundColor = GameShaderAppearance.background
        tableView.tintColor = .mainColor
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
        GameShaderAppearance.registerSections(in: tableView)
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: shaderText("save"), style: .done, target: self, action: #selector(save))
        if modal, folder == nil {
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: shaderText("cancel"), style: .plain, target: self, action: #selector(cancel))
        }
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.accessibilityViewIsModal = modal
        UIAccessibility.post(notification: .screenChanged, argument: tableView)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true {
            stopPreparation()
            if !finished, folder == nil || navigationController?.isBeingDismissed == true {
                try? session.cancel()
                finished = true
            }
        }
    }

    private func reload() {
        do {
            if let folder {
                rows = [folder.count == 0 ? [.emptyFolder] : folder.folders.map { .folder($0) } + folder.presets.map { .preset($0) }]
                headings = [nil]
                tableView.reloadData()
                return
            }
            let builtins = try GameShaderCatalog.builtins()
            if importedFolders == nil { importedFolders = GameShaderFolder.packages(try GameShaderCatalog.importedPackages()) }
            rows = [[.inherit, .off, .current]]
            rows.append([.group(.featured)] + (collapsed.contains(.featured) ? [] : builtins.map { .preset($0) }))
            rows.append([.group(.imported)] + (collapsed.contains(.imported) ? [] : (importedFolders ?? []).map { .folder($0) }) + [.importFolder])
            rows.append([.notices])
            headings = Array(repeating: nil, count: rows.count)
            tableView.reloadData()
        } catch { showError(error) }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows[section].count }
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let text = headings[section] else { return nil }
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionHeaderView.className) as! RGSectionHeaderView
        header.text = text
        return header
    }
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        headings[section] != nil ? UITableView.automaticDimension : (section == 0 ? .leastNormalMagnitude : 12)
    }
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard let text = footerText(section) else { return nil }
        let footer = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionFooterView.className) as! RGSectionFooterView
        footer.text = text
        return footer
    }
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        footerText(section) != nil ? UITableView.automaticDimension : 28
    }
    private func footerText(_ section: Int) -> String? {
        if case .group(.imported)? = rows[section].first,
           !collapsed.contains(.imported), importedFolders?.isEmpty == false {
            return shaderText("delete_folder_footer")
        }
        guard section == 0 else { return nil }
        let scope: String
        switch session.settings.scope {
        case .game: scope = "scope_game_footer"
        case .core: scope = "scope_core_footer"
        case .global: scope = "scope_global_footer"
        }
        var text = shaderText(scope)
        // Compatibility is presentation-only; the runtime remains responsible for applying presets.
        let driver = session.isLive ? GameShaderRuntime.shared.driver : session.settings.getVideoDriver()
        if !["vulkan", "metal"].contains(driver.lowercased()), (try? session.selected.preset) != nil {
            text += "\n" + shaderText("compatibility")
        }
        if let folder, !folder.presets.isEmpty {
            text += "\n\n" + shaderText("delete_preset_footer")
        }
        return text
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.section][indexPath.row]
        let isCurrent: Bool
        if case .current = row { isCurrent = true } else { isCurrent = false }
        let cell = UITableViewCell(style: isCurrent ? .subtitle : .value1, reuseIdentifier: nil)
        cell.backgroundColor = GameShaderAppearance.card
        cell.textLabel?.numberOfLines = 1
        cell.textLabel?.setContentCompressionResistancePriority(.required, for: .horizontal)
        cell.detailTextLabel?.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cell.detailTextLabel?.lineBreakMode = .byTruncatingTail
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.font = .boldSystemFont(ofSize: UIFont.labelFontSize)
        var checked = false
        switch row {
        case .inherit:
            cell.textLabel?.text = shaderText(session.settings.scope == .global ? "default" : "inherit")
            let inherited = try? GameShaderStore.resolved(session.settings, replacing: .some(nil))
            cell.detailTextLabel?.text = inherited?.preset?.title ?? shaderText("off")
            checked = session.draft == nil
        case .off:
            cell.textLabel?.text = shaderText("off")
            checked = session.draft == .off
        case .current:
            let preset = try? session.selected.preset
            cell.textLabel?.text = shaderText("current") + " · " + (preset?.title ?? shaderText("off"))
            cell.detailTextLabel?.font = .preferredFont(forTextStyle: .footnote)
            cell.detailTextLabel?.numberOfLines = 2
            cell.detailTextLabel?.text = preset.map { sourceTitle($0) }
            cell.selectionStyle = preset == nil ? .none : .default
            if let preset { cell.accessoryView = configurationAccessory(for: preset, checked: false) }
        case .group(let group):
            cell.textLabel?.text = group.title
            cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
            let chevron = UIImageView(image: UIImage(systemName: collapsed.contains(group) ? "chevron.right" : "chevron.down"))
            chevron.tintColor = .secondaryLabel
            cell.accessoryView = chevron
            cell.accessibilityValue = Bundle.localizedString(forKey: collapsed.contains(group) ? "coreoption_collapsed" : "coreoption_expanded")
        case .preset(let preset):
            cell.textLabel?.text = preset.title
            cell.imageView?.image = UIImage(systemName: "camera.filters")
            cell.imageView?.tintColor = .mainColor
            checked = session.draft?.preset?.id == preset.id
            if checked {
                cell.accessoryView = configurationAccessory(for: preset)
            }
        case .folder(let folder):
            cell.textLabel?.text = folder.title
            cell.imageView?.image = UIImage(systemName: "folder")
            cell.imageView?.tintColor = .mainColor
            cell.detailTextLabel?.text = String(folder.count)
            cell.accessoryType = .disclosureIndicator
        case .emptyFolder:
            cell.textLabel?.text = shaderText("empty_import_folder")
            cell.textLabel?.textColor = .secondaryLabel
            cell.selectionStyle = .none
        case .importFolder:
            cell.textLabel?.text = shaderText("import_folder")
            cell.imageView?.image = UIImage(systemName: "folder.badge.plus")
        case .notices:
            cell.textLabel?.text = shaderText("notices")
            cell.accessoryType = .disclosureIndicator
        }
        if checked {
            cell.accessibilityTraits.insert(.selected)
            if cell.accessoryView == nil { cell.accessoryType = .checkmark }
        }
        return cell
    }

    private func sourceTitle(_ preset: GameShaderPreset) -> String {
        if preset.imported {
            let relative = preset.path.split(separator: "/").dropFirst().dropLast().joined(separator: " / ")
            return shaderText("imported_shaders") + (relative.isEmpty ? "" : " / " + relative)
        }
        return shaderText("builtins")
    }

    private func configurationAccessory(for preset: GameShaderPreset, checked: Bool = true) -> UIView {
        let check = UIImageView(image: UIImage(systemName: "checkmark"))
        check.tintColor = .mainColor
        check.contentMode = .scaleAspectFit
        check.isAccessibilityElement = false
        let button = UIButton(type: .system)
        button.tintColor = .mainColor
        button.setImage(UIImage(systemName: "slider.horizontal.3"), for: .normal)
        button.accessibilityLabel = String(format: shaderText("configure_preset"), preset.title)
        button.addAction(UIAction { [weak self] _ in
            Vibration.selection.vibrate()
            self?.configurePreset(preset)
        }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: checked ? [check, button] : [button])
        stack.alignment = .center
        stack.spacing = 8
        check.widthAnchor.constraint(equalToConstant: 20).isActive = true
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        stack.frame = CGRect(x: 0, y: 0, width: checked ? 72 : 44, height: 44)
        return stack
    }

    /// Also handles a stale accessory tap after selection changed, without resetting edited parameters.
    private func configurePreset(_ preset: GameShaderPreset) {
        let selected = try? session.selected.preset
        let selection = selected?.id == preset.id
            ? session.draft : GameShaderSelection(preset: preset)
        prepare(selection, configure: true)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        Vibration.selection.vibrate()
        switch rows[indexPath.section][indexPath.row] {
        case .inherit: prepare(nil)
        case .off: prepare(.off)
        case .current:
            if let preset = try? session.selected.preset { configurePreset(preset) }
        case .group(let group):
            if collapsed.contains(group) { collapsed.remove(group) } else { collapsed.insert(group) }
            reload()
        case .notices:
            navigationController?.pushViewController(GameShaderNoticesViewController(), animated: true)
        case .preset(let preset):
            // Tapping the current row keeps any parameter edits in the draft.
            prepare(session.draft?.preset?.id == preset.id ? session.draft : GameShaderSelection(preset: preset))
        case .folder(let folder):
            stopPreparation()
            let child = GameShaderViewController(session: session, modal: modal, folder: folder, root: flowRoot ?? self)
            navigationController?.pushViewController(child, animated: true)
        case .emptyFolder: break
        case .importFolder:
            guard selectionTask == nil else { return }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
            picker.delegate = self
            present(picker, animated: true)
        }
    }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch rows[indexPath.section][indexPath.row] {
        case .current: return (try? session.selected.preset) != nil
        case .emptyFolder: return false
        default: return true
        }
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !importing, selectionTask == nil else { return nil }
        let deletion: Deletion
        switch rows[indexPath.section][indexPath.row] {
        case .folder(let folder) where self.folder == nil:
            guard let id = folder.packageID else { return nil }
            deletion = .package(id: id, title: folder.title)
        case .preset(let preset) where preset.imported:
            deletion = .preset(preset)
        default: return nil
        }
        let action = UIContextualAction(style: .destructive, title: shaderText("delete")) { [weak self] _, _, completion in
            completion(false)
            guard let self, !importing, selectionTask == nil else { return }
            Vibration.selection.vibrate()
            confirmDeletion(deletion)
        }
        let configuration = UISwipeActionsConfiguration(actions: [action])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    private func confirmDeletion(_ deletion: Deletion) {
        let title: String
        let message: String
        switch deletion {
        case .package(_, let name):
            title = String(format: shaderText("delete_folder_title"), name)
            message = shaderText("delete_folder_message")
        case .preset(let preset):
            title = String(format: shaderText("delete_preset_title"), preset.title)
            message = shaderText("delete_preset_message")
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: shaderText("cancel"), style: .cancel) { _ in Vibration.selection.vibrate() })
        alert.addAction(UIAlertAction(title: shaderText("delete"), style: .destructive) { [weak self] _ in
            Vibration.selection.vibrate()
            self?.deleteImport(deletion)
        })
        present(alert, animated: true)
    }

    private func deleteImport(_ deletion: Deletion) {
        do {
            switch deletion {
            case .package(let id, _):
                try GameShaderCatalog.deleteImportedPackage(id)
            case .preset(let preset):
                try GameShaderCatalog.deleteImportedPreset(preset)
                // Keep every open folder, including an emptied one, in sync when navigating back.
                for case let controller as GameShaderViewController in navigationController?.viewControllers ?? [self] {
                    controller.folder = controller.folder?.removing(preset)
                }
            }
            (flowRoot ?? self).importedFolders = nil
            defer { reload() }
            try session.importsDidChange()
        } catch { showError(error) }
    }

    private func prepare(_ selection: GameShaderSelection?, configure: Bool = false) {
        stopPreparation()
        let request = UUID()
        selectionRequest = request
        setPreparing(true)
        selectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await session.choosePrepared(selection)
                guard request == selectionRequest, !Task.isCancelled else { return }
                selectionTask = nil
                setPreparing(false)
                reload()
                if configure { openParameters() }
            } catch {
                guard request == selectionRequest, !Task.isCancelled else { return }
                selectionTask = nil
                setPreparing(false)
                if !(error is CancellationError) { showError(error) }
            }
        }
    }

    private func setPreparing(_ preparing: Bool) {
        navigationItem.rightBarButtonItem?.isEnabled = !preparing && !importing
        if preparing {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            let label = UILabel()
            label.text = shaderText("preparing")
            label.font = .preferredFont(forTextStyle: .headline)
            let stack = UIStackView(arrangedSubviews: [spinner, label])
            stack.spacing = 8
            navigationItem.titleView = stack
        } else { navigationItem.titleView = nil }
    }

    private func stopPreparation() {
        selectionRequest = UUID()
        selectionTask?.cancel()
        selectionTask = nil
        setPreparing(false)
    }

    private func openParameters() {
        navigationController?.pushViewController(GameShaderParameterViewController(session: session), animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !importing, let url = urls.first else { return }
        importing = true
        navigationItem.leftBarButtonItem?.isEnabled = false
        navigationItem.rightBarButtonItem?.isEnabled = false
        let title = shaderText("import_title")
        let activity = RetroRomActivityView(mainTitle: title)
        activity.install()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try GameShaderCatalog.importFolder(url) { activity.activeMessage($0, title: title) }
            }
            DispatchQueue.main.async {
                self?.importing = false
                self?.navigationItem.leftBarButtonItem?.isEnabled = true
                self?.navigationItem.rightBarButtonItem?.isEnabled = true
                switch result {
                case .success(let report):
                    if !report.presets.isEmpty { self?.collapsed.remove(.imported) }
                    self?.importedFolders = nil
                    self?.reload()
                    var message = String(format: shaderText("import_summary"), report.presets.count, report.skipped.count)
                    if !report.skipped.isEmpty {
                        message += "\n\n" + report.skipped.prefix(2).map { "\(URL(fileURLWithPath: $0.preset).lastPathComponent)\n\($0.reason)" }.joined(separator: "\n\n")
                        if report.skipped.count > 2 {
                            message += "\n\n" + String(format: shaderText("import_more"), report.skipped.count - 2)
                        }
                        message += "\n\n" + shaderText("import_report")
                        if report.presets.isEmpty {
                            activity.errorMessage(message, title: title, canDismiss: true)
                        } else {
                            activity.infoMessage(message, title: title, canDismiss: true)
                        }
                    } else {
                        activity.successMessage(message, title: title, canDismiss: true)
                    }
                case .failure(let error):
                    activity.errorMessage(error.localizedDescription, title: title, canDismiss: true)
                }
            }
        }
    }

    @objc private func save() {
        guard selectionTask == nil else { return }
        Vibration.selection.vibrate()
        do { try session.commit(); finished = true; flowRoot?.finished = true; close() }
        catch { showError(error) }
    }
    @objc private func cancel() {
        Vibration.selection.vibrate()
        stopPreparation()
        do { try session.cancel(); finished = true; flowRoot?.finished = true; close() }
        catch { showError(error) }
    }
    private func close() {
        if modal { dismiss(animated: true) }
        else if let root = flowRoot, let navigationController,
                let index = navigationController.viewControllers.firstIndex(where: { $0 === root }), index > 0 {
            navigationController.popToViewController(navigationController.viewControllers[index - 1], animated: true)
        } else { navigationController?.popViewController(animated: true) }
    }
    private func showError(_ error: Error) {
        let alert = UIAlertController(title: shaderText("title"), message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: shaderText("ok"), style: .default) { _ in Vibration.selection.vibrate() })
        present(alert, animated: true)
    }
}
