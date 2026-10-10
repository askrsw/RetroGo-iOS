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

/// Names a new control layout and says who uses it. Neither switch on means
/// the layout is only saved, to be picked from the list later.
final class GameOverlayLayoutSaveViewController: UITableViewController {
    struct Result {
        let name: String
        let useForGame: Bool
        let applyToPlatform: Bool
    }

    private let session: GameOverlayLayoutSession
    private let showsGameOption: Bool
    private let onSave: (Result) -> Bool

    /// Called once the sheet is gone, saved or not.
    var onDismiss: (() -> Void)?

    private let nameField = UITextField()
    private var useForGame = true
    private var applyToPlatform = false

    private enum Row {
        case name, useForGame, applyToPlatform
    }

    private var sections: [[Row]] {
        // Without a game (opened outside a game) only the platform choice makes sense.
        let usage: [Row] = showsGameOption ? [.useForGame, .applyToPlatform] : [.applyToPlatform]
        return [[.name], usage]
    }

    /// `onSave` returns false when saving failed, keeping the sheet open.
    init(session: GameOverlayLayoutSession, showsGameOption: Bool, onSave: @escaping (Result) -> Bool) {
        self.session = session
        self.showsGameOption = showsGameOption
        self.onSave = onSave
        super.init(style: .insetGrouped)
        useForGame = showsGameOption
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
            cell.accessoryView = makeSwitch(isOn: useForGame) { [weak self] isOn in
                self?.useForGame = isOn
                self?.refreshPlatformSwitch()
            }
        case .applyToPlatform:
            if let platform = session.platformTitle {
                content.text = String(format: Bundle.localizedString(forKey: "overlay_layout_apply_to_platform"), platform)
            } else {
                content.text = Bundle.localizedString(forKey: "overlay_layout_apply_to_platform_generic")
            }
            cell.accessoryView = makeSwitch(isOn: applyToPlatform) { [weak self] isOn in
                self?.applyToPlatform = isOn
            }
            (cell.accessoryView as? UISwitch)?.isEnabled = useForGame || !showsGameOption
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return isNameTaken ? Bundle.localizedString(forKey: "overlay_layout_name_taken") : nil
        }
        return Bundle.localizedString(forKey: "overlay_layout_apply_to_platform_footer")
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

    private func refreshPlatformSwitch() {
        guard showsGameOption else { return }
        if !useForGame {
            applyToPlatform = false
        }
        guard let row = sections[1].firstIndex(of: .applyToPlatform),
              let cell = tableView.cellForRow(at: IndexPath(row: row, section: 1)),
              let toggle = cell.accessoryView as? UISwitch else { return }
        toggle.isEnabled = useForGame
        toggle.setOn(applyToPlatform, animated: true)
    }

    private func makeSwitch(isOn: Bool, onChange: @escaping (Bool) -> Void) -> UISwitch {
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.onTintColor = .mainColor
        toggle.addAction(UIAction { [weak toggle] _ in
            guard let toggle else { return }
            onChange(toggle.isOn)
        }, for: .valueChanged)
        return toggle
    }

    private func save() {
        // Commits text still being composed (pinyin, suggestions) before reading the name.
        view.endEditing(true)
        guard !trimmedName.isEmpty, !isNameTaken else { return }
        let result = Result(name: trimmedName,
                            useForGame: showsGameOption && useForGame,
                            applyToPlatform: applyToPlatform)
        guard onSave(result) else {
            let alert = UIAlertController(title: nil, message: Bundle.localizedString(forKey: "overlay_layout_save_failed"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default))
            present(alert, animated: true)
            return
        }
        dismiss(animated: true)
    }
}
