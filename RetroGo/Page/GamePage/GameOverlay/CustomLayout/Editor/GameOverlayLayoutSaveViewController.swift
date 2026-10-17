//
//  GameOverlayLayoutSaveViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/8.
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

/// Names a new layout and selects one application scope.
final class GameOverlayLayoutSaveViewController: UITableViewController {
    struct Result {
        let name: String
        let useForGame: Bool
        let applyToPlatform: Bool
        let applyToDriver: Bool
    }

    private let session: GameOverlayLayoutSession
    private let showsGameOption: Bool
    private let onSave: (Result) -> Bool

    /// Called once the sheet is gone, saved or not.
    var onDismiss: (() -> Void)?

    private let nameField = UITextField()
    private var selectedScope: Row = .useForGame

    private enum Row {
        case name, saveOnly, useForGame, applyToDriver, applyToPlatform
    }

    private var sections: [[Row]] {
        // Without a game (opened outside a game) only the platform choice makes sense.
        var usage: [Row] = [.saveOnly]
        if showsGameOption { usage.append(.useForGame) }
        if showsGameOption, session.driverIdentifier != nil { usage.append(.applyToDriver) }
        usage.append(.applyToPlatform)
        return [[.name], usage]
    }

    /// `onSave` returns false when saving failed, keeping the sheet open.
    init(session: GameOverlayLayoutSession, showsGameOption: Bool, onSave: @escaping (Result) -> Bool) {
        self.session = session
        self.showsGameOption = showsGameOption
        self.onSave = onSave
        super.init(style: .insetGrouped)
        selectedScope = showsGameOption ? .useForGame : .saveOnly
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Bundle.localizedString(forKey: "overlay_layout_save_title")
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: Bundle.localizedString(forKey: "overlay_layout_save"),
            primaryAction: UIAction { [weak self] _ in self?.save() }
        )
        navigationItem.rightBarButtonItem?.style = .done

        nameField.text = session.suggestedName(prefix: Bundle.localizedString(forKey: "overlay_layout_name_prefix"))
        nameField.placeholder = Bundle.localizedString(forKey: "overlay_layout_name_placeholder")
        nameField.clearButtonMode = .whileEditing
        nameField.autocorrectionType = .no
        nameField.returnKeyType = .done
        nameField.addAction(UIAction { [weak self] _ in self?.updateSaveState() }, for: .editingChanged)
        nameField.addAction(UIAction { [weak self] _ in self?.save() }, for: .editingDidEndOnExit)
        updateSaveState()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if navigationController?.isBeingDismissed ?? isBeingDismissed {
            onDismiss?()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        nameField.becomeFirstResponder()
        nameField.selectAll(nil)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        var content = cell.defaultContentConfiguration()
        switch sections[indexPath.section][indexPath.row] {
        case .name:
            cell.contentView.addSubview(nameField)
            nameField.snp.makeConstraints { make in
                make.leading.trailing.equalTo(cell.contentView.layoutMarginsGuide)
                make.top.bottom.equalToSuperview()
                make.height.greaterThanOrEqualTo(44)
            }
            return cell
        case .useForGame:
            content.text = Bundle.localizedString(forKey: "overlay_layout_use_for_game")
        case .saveOnly:
            content.text = Bundle.localizedString(forKey: "overlay_layout_save_only")
        case .applyToDriver:
            content.text = String(format: Bundle.localizedString(forKey: "overlay_layout_apply_to_driver"), session.driverIdentifier ?? "")
        case .applyToPlatform:
            if let platform = session.platformTitle {
                content.text = String(format: Bundle.localizedString(forKey: "overlay_layout_apply_to_platform"), platform)
            } else {
                content.text = Bundle.localizedString(forKey: "overlay_layout_apply_to_platform_generic")
            }
        }
        cell.selectionStyle = .default
        cell.tintColor = .mainColor
        cell.accessoryType = sections[indexPath.section][indexPath.row] == selectedScope ? .checkmark : .none
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        selectedScope = sections[indexPath.section][indexPath.row]
        tableView.reloadSections(IndexSet(integer: 1), with: .none)
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return isNameTaken ? Bundle.localizedString(forKey: "overlay_layout_name_taken") : nil
        }
        return Bundle.localizedString(forKey: session.driverIdentifier == nil ? "overlay_layout_apply_to_platform_footer" : "overlay_layout_driver_footer")
    }

    private var trimmedName: String {
        (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isNameTaken: Bool {
        !trimmedName.isEmpty && session.isNameTaken(trimmedName)
    }

    private func updateSaveState() {
        let wasTaken = tableView.footerView(forSection: 0)?.textLabel?.text != nil
        navigationItem.rightBarButtonItem?.isEnabled = !trimmedName.isEmpty && !isNameTaken
        if wasTaken != isNameTaken {
            UIView.performWithoutAnimation {
                tableView.beginUpdates()
                tableView.footerView(forSection: 0)?.textLabel?.text = isNameTaken ? Bundle.localizedString(forKey: "overlay_layout_name_taken") : nil
                tableView.footerView(forSection: 0)?.sizeToFit()
                tableView.endUpdates()
            }
        }
    }

    private func save() {
        guard presentedViewController == nil else { return }
        // Commits text still being composed (pinyin, suggestions) before reading the name.
        view.endEditing(true)
        guard !trimmedName.isEmpty, !isNameTaken else { return }
        let result = Result(name: trimmedName,
                            useForGame: selectedScope == .useForGame,
                            applyToPlatform: selectedScope == .applyToPlatform,
                            applyToDriver: selectedScope == .applyToDriver)
        completeSave(result)
    }

    private func completeSave(_ result: Result) {
        guard onSave(result) else {
            let alert = UIAlertController(title: nil, message: Bundle.localizedString(forKey: "overlay_layout_save_failed"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default))
            present(alert, animated: true)
            return
        }
        dismiss(animated: true)
    }
}
